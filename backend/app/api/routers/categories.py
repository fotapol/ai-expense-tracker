"""Category API endpoints for fetching and managing taxonomy data."""

import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlmodel import Session, select
from sqlalchemy import or_

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory
from app.models.users.user import User

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


def _to_response(cat: Category) -> dict:
    return {
        "id": str(cat.id),
        "code": cat.code,
        "name": cat.name,
        "is_default": cat.user_id is None,
        "is_custom": cat.is_custom,
        "parent_id": str(cat.parent_id) if cat.parent_id else None,
        "icon": cat.icon,
        "color": cat.color,
    }


def _resolve_parent_or_400(
    session: Session,
    current_user: User,
    parent_id: uuid.UUID,
) -> Category:
    parent = session.exec(
        select(Category).where(
            Category.id == parent_id,
            Category.scope == CategoryScope.ITEM,
            Category.is_active == True,
            Category.parent_id == None,  # top-level only
            or_(Category.user_id == None, Category.user_id == current_user.id),
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
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List all available categories (global + user-specific)."""
    categories = session.exec(
        select(Category)
        .where(
            Category.is_active == True,
            Category.scope == CategoryScope.ITEM,
            or_(Category.user_id == None, Category.user_id == current_user.id),
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

    hidden_ids = set()
    if current_user:
        hidden_rows = session.exec(
            select(UserHiddenCategory.category_id).where(
                UserHiddenCategory.user_id == current_user.id
            )
        ).all()
        hidden_ids.update(hidden_rows)

    effective_categories = [
        cat for cat in effective_by_code.values() if cat.id not in hidden_ids
    ]
    effective_categories.sort(key=lambda c: (c.parent_id is not None, c.name.lower()))
    return [_to_response(cat) for cat in effective_categories]


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
    if payload.parent_id is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="parent_id is required for custom categories.",
        )
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
    if payload.parent_id is not None:
        if payload.parent_id == cat.id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A category cannot be its own parent.",
            )
        _resolve_parent_or_400(session, current_user, payload.parent_id)
        cat.parent_id = payload.parent_id
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
    from app.models.taxonomy.category_hidden import UserHiddenCategory
    visible_category = session.exec(
        select(Category).where(
            Category.id == category_id,
            Category.scope == CategoryScope.ITEM,
            or_(Category.user_id == None, Category.user_id == current_user.id),
        )
    ).first()
    if visible_category is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found.")
    if visible_category.user_id is None:
        # It's a built-in category. Instead of rejecting, mark it as hidden for this user.
        already_hidden = session.exec(
            select(UserHiddenCategory).where(
                UserHiddenCategory.user_id == current_user.id,
                UserHiddenCategory.category_id == visible_category.id,
            )
        ).first()

        if not already_hidden:
            hidden_cat = UserHiddenCategory(
                user_id=current_user.id,
                category_id=visible_category.id,
            )
            session.add(hidden_cat)
            session.commit()
            
        return None
        
    cat = visible_category

    has_active_children = session.exec(
        select(Category.id).where(Category.parent_id == cat.id, Category.is_active == True)
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
    from app.models.taxonomy.category_hidden import UserHiddenCategory

    hidden = session.exec(
        select(UserHiddenCategory).where(
            UserHiddenCategory.user_id == current_user.id,
            UserHiddenCategory.category_id == category_id,
        )
    ).first()

    if hidden is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category is not hidden, or doesn't exist.",
        )

    session.delete(hidden)
    session.commit()

    return {"message": "Category restored successfully."}
