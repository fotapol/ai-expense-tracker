"""Category API endpoints for fetching and managing taxonomy data."""

import logging
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.taxonomy.category import Category
from app.models.shared.enums import CategoryScope
from app.models.users.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["categories"])


class CategoryCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    code: str | None = None  # Auto-generated from name if not provided


class CategoryUpdateRequest(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)


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
        .where(Category.is_active == True, Category.scope == CategoryScope.ITEM)
        .order_by(Category.name)
    ).all()

    return [
        {
            "id": str(cat.id),
            "code": cat.code,
            "name": cat.name,
            "is_default": cat.code in _DEFAULT_CODES,
        }
        for cat in categories
    ]


_DEFAULT_CODES = {
    "FOOD", "CLOTHING", "TRANSPORT", "UTILITIES", "HEALTH",
    "ENTERTAINMENT", "HOME", "ELECTRONICS", "EDUCATION",
    "PERSONAL_CARE", "OTHER", "UNCATEGORIZED",
}


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
    code = payload.code or payload.name.strip().upper().replace(" ", "_")

    # Check for duplicates
    existing = session.exec(
        select(Category).where(
            Category.scope == CategoryScope.ITEM,
            Category.code == code,
        )
    ).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Category with code '{code}' already exists.",
        )

    cat = Category(
        scope=CategoryScope.ITEM,
        code=code,
        name=payload.name.strip(),
    )
    session.add(cat)
    session.commit()
    session.refresh(cat)

    return {"id": str(cat.id), "code": cat.code, "name": cat.name}


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
        select(Category).where(Category.id == category_id)
    ).first()

    if cat is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found.")

    if payload.name is not None:
        cat.name = payload.name.strip()

    session.add(cat)
    session.commit()
    session.refresh(cat)

    return {"id": str(cat.id), "code": cat.code, "name": cat.name}


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
    """Soft-delete (deactivate) a category."""
    cat = session.exec(
        select(Category).where(Category.id == category_id)
    ).first()

    if cat is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found.")

    cat.is_active = False
    session.add(cat)
    session.commit()

    return None
