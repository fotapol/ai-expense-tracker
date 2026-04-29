"""Category API endpoints for fetching and managing taxonomy data."""

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy import or_
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory
from app.models.users.user import User
from app.services.billing import CategoryUsage, resolve_category_usage
from app.services.taxonomy import (
    collect_disable_target_ids,
    disable_category_ids_for_user,
    get_user_disabled_category_ids,
    restore_category_ids_for_user,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["categories"])


class CategoryCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    code: str | None = None  # Auto-generated from name if not provided
    parent_id: uuid.UUID | None = None
    icon: str | None = Field(default=None, max_length=50)
    color: str | None = Field(default=None, max_length=50)


class CategoryUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    parent_id: uuid.UUID | None = None
    icon: str | None = Field(default=None, max_length=50)
    color: str | None = Field(default=None, max_length=50)


def _normalize_code(value: str) -> str:
    return "_".join(value.strip().upper().split())


def _to_response(cat: Category, *, is_disabled: bool = False) -> dict:
    return {
        "id": str(cat.id),
        "code": cat.code,
        "name": cat.name,
        "is_default": cat.user_id is None,
        "is_custom": cat.is_custom,
        "is_disabled": is_disabled,
        "parent_id": str(cat.parent_id) if cat.parent_id else None,
        "icon": cat.icon,
        "color": cat.color,
    }


def _category_limit_detail(*, code: str, usage: CategoryUsage) -> dict:
    is_subcategory = code == "free_plan_subcategory_limit_reached"
    used = usage.subcategories_used if is_subcategory else usage.categories_used
    limit = usage.subcategories_limit if is_subcategory else usage.categories_limit
    return {
        "code": code,
        "message": (
            f"Free plan allows up to {limit} active custom "
            f"{'subcategories' if is_subcategory else 'categories'}."
        ),
        "used": used,
        "limit": limit,
        "remaining": 0,
    }


def _raise_category_limit_error(*, code: str, usage: CategoryUsage) -> None:
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail=_category_limit_detail(code=code, usage=usage),
    )


def _assert_can_activate_custom_category(
    session: Session,
    current_user: User,
    *,
    parent_id: uuid.UUID | None,
) -> None:
    usage = resolve_category_usage(session, current_user.id)
    if usage.is_unlimited:
        return

    if parent_id is None:
        if usage.categories_limit is not None and usage.categories_used >= usage.categories_limit:
            _raise_category_limit_error(
                code="free_plan_category_limit_reached",
                usage=usage,
            )
        return

    if (
        usage.subcategories_limit is not None
        and usage.subcategories_used >= usage.subcategories_limit
    ):
        _raise_category_limit_error(
            code="free_plan_subcategory_limit_reached",
            usage=usage,
        )


def _resolve_parent_or_400(
    session: Session,
    current_user: User,
    parent_id: uuid.UUID,
) -> Category:
    disabled_subquery = select(UserHiddenCategory.category_id).where(
        UserHiddenCategory.user_id == current_user.id
    )
    parent = session.exec(
        select(Category).where(
            Category.id == parent_id,
            Category.scope == CategoryScope.ITEM,
            Category.is_active,
            Category.parent_id.is_(None),  # top-level only
            Category.id.notin_(disabled_subquery),
            or_(Category.user_id.is_(None), Category.user_id == current_user.id),
        )
    ).first()
    if parent is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid parent category. Parent must be an active top-level ITEM category.",
        )
    return parent


# ---------------------------------------------------------------------------
# LIST
# ---------------------------------------------------------------------------


@router.get("/categories")
@limiter.limit("60/minute")
async def list_categories(
    request: Request,
    include_disabled: bool = False,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List all available categories (global + user-specific)."""
    categories = session.exec(
        select(Category)
        .where(
            Category.is_active,
            Category.scope == CategoryScope.ITEM,
            or_(Category.user_id.is_(None), Category.user_id == current_user.id),
        )
        .order_by(Category.parent_id, Category.name)
    ).all()

    # Prefer user-specific category over global category with the same code.
    effective_by_code: dict[tuple[str, uuid.UUID | None], Category] = {}
    for cat in categories:
        key = (cat.code, cat.parent_id)
        existing = effective_by_code.get(key)
        if existing is None:
            effective_by_code[key] = cat
            continue
        if existing.user_id is None and cat.user_id == current_user.id:
            effective_by_code[key] = cat

    disabled_ids = get_user_disabled_category_ids(session, current_user.id)

    effective_categories = list(effective_by_code.values())
    if not include_disabled:
        effective_categories = [cat for cat in effective_categories if cat.id not in disabled_ids]
    effective_categories.sort(
        key=lambda c: (
            c.id in disabled_ids,
            c.parent_id is not None,
            c.name.lower(),
        )
    )
    return [_to_response(cat, is_disabled=cat.id in disabled_ids) for cat in effective_categories]


# ---------------------------------------------------------------------------
# CREATE
# ---------------------------------------------------------------------------


@router.post("/categories", status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
async def create_category(
    payload: CategoryCreateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create a new user-defined category."""
    if payload.parent_id is not None:
        _resolve_parent_or_400(session, current_user, payload.parent_id)

    code = _normalize_code(payload.code or payload.name)

    # Allow collisions with global codes. Disallow duplicate code per user.
    existing = session.exec(
        select(Category).where(
            Category.scope == CategoryScope.ITEM,
            Category.code == code,
            Category.user_id == current_user.id,
        )
    ).first()
    if existing:
        if not existing.is_active:
            _assert_can_activate_custom_category(
                session,
                current_user,
                parent_id=payload.parent_id,
            )
            existing.name = payload.name.strip()
            existing.parent_id = payload.parent_id
            existing.icon = payload.icon
            existing.color = payload.color
            existing.is_active = True
            existing.is_custom = True
            session.add(existing)
            session.commit()
            session.refresh(existing)
            return _to_response(existing)
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"You already have a category with code '{code}'.",
        )

    _assert_can_activate_custom_category(
        session,
        current_user,
        parent_id=payload.parent_id,
    )

    cat = Category(
        scope=CategoryScope.ITEM,
        code=code,
        name=payload.name.strip(),
        parent_id=payload.parent_id,
        icon=payload.icon,
        color=payload.color,
        user_id=current_user.id,
        is_custom=True,
    )
    session.add(cat)
    session.commit()
    session.refresh(cat)

    return _to_response(cat)


# ---------------------------------------------------------------------------
# UPDATE
# ---------------------------------------------------------------------------


@router.put("/categories/{category_id}")
@limiter.limit("30/minute")
async def update_category(
    category_id: uuid.UUID,
    payload: CategoryUpdateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Update a category's name."""
    cat = session.exec(
        select(Category).where(Category.id == category_id, Category.user_id == current_user.id)
    ).first()

    if cat is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found.")

    if payload.name is not None:
        cat.name = payload.name.strip()
    if "parent_id" in payload.model_fields_set:
        next_parent_id = payload.parent_id
        if next_parent_id == cat.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A category cannot be its own parent.",
            )
        if next_parent_id is not None:
            _resolve_parent_or_400(session, current_user, next_parent_id)
        if cat.is_active and (cat.parent_id is None) != (next_parent_id is None):
            _assert_can_activate_custom_category(
                session,
                current_user,
                parent_id=next_parent_id,
            )
        cat.parent_id = next_parent_id
    if payload.icon is not None:
        cat.icon = payload.icon
    if payload.color is not None:
        cat.color = payload.color

    session.add(cat)
    session.commit()
    session.refresh(cat)

    return _to_response(cat)


# ---------------------------------------------------------------------------
# DELETE (soft)
# ---------------------------------------------------------------------------


@router.delete("/categories/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("30/minute")
async def delete_category(
    category_id: uuid.UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Soft-delete a custom category, or hide a built-in category."""
    visible_category = session.exec(
        select(Category).where(
            Category.id == category_id,
            Category.scope == CategoryScope.ITEM,
            or_(Category.user_id.is_(None), Category.user_id == current_user.id),
        )
    ).first()
    if visible_category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found.")
    if visible_category.user_id is None:
        disable_category_ids_for_user(
            session,
            user_id=current_user.id,
            category_ids=collect_disable_target_ids(session, visible_category),
        )
        return None

    cat = visible_category

    has_active_children = session.exec(
        select(Category.id).where(Category.parent_id == cat.id, Category.is_active)
    ).first()
    if has_active_children is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Cannot delete a category that still has active subcategories.",
        )

    cat.is_active = False
    session.add(cat)
    session.commit()

    return None


# ---------------------------------------------------------------------------
# RESTORE (un-hide)
# ---------------------------------------------------------------------------


@router.post("/categories/{category_id}/restore", status_code=status.HTTP_200_OK)
@limiter.limit("20/minute")
async def restore_category(
    category_id: uuid.UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Restore a previously hidden built-in category for the current user."""
    category = session.exec(
        select(Category).where(
            Category.id == category_id,
            Category.scope == CategoryScope.ITEM,
            Category.user_id.is_(None),
        )
    ).first()
    if category is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Built-in category not found.",
        )

    restored_count = restore_category_ids_for_user(
        session,
        user_id=current_user.id,
        category_ids=collect_disable_target_ids(session, category),
    )
    if restored_count == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category is not hidden, or doesn't exist.",
        )

    return {"message": "Category restored successfully."}
