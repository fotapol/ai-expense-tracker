"""Usage helpers for free-plan custom category limits."""

from __future__ import annotations

import datetime as dt
import uuid
from dataclasses import dataclass

from sqlalchemy import func
from sqlmodel import Session, select

from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.services.billing.entitlements import user_has_feature
from app.services.billing.features import (
    FREE_PLAN_CUSTOM_CATEGORY_LIMIT,
    FREE_PLAN_CUSTOM_SUBCATEGORY_LIMIT,
    PREMIUM_CATEGORIES_UNLIMITED,
)


@dataclass(slots=True, frozen=True)
class CategoryUsage:
    """Current custom category usage snapshot for one user."""

    categories_used: int
    categories_limit: int | None
    categories_remaining: int | None
    subcategories_used: int
    subcategories_limit: int | None
    subcategories_remaining: int | None
    is_unlimited: bool


def count_user_active_custom_categories(
    session: Session,
    user_id: uuid.UUID,
    *,
    parented: bool,
) -> int:
    """Count active custom user categories by level."""

    parent_filter = Category.parent_id.is_not(None) if parented else Category.parent_id.is_(None)
    count = session.exec(
        select(func.count())
        .select_from(Category)
        .where(
            Category.scope == CategoryScope.ITEM,
            Category.user_id == user_id,
            Category.is_custom,
            Category.is_active,
            parent_filter,
        )
    ).one()
    return int(count or 0)


def resolve_category_usage(
    session: Session,
    user_id: uuid.UUID,
    *,
    now: dt.datetime | None = None,
) -> CategoryUsage:
    """Resolve category usage from entitlements + persisted categories."""

    categories_used = count_user_active_custom_categories(
        session,
        user_id,
        parented=False,
    )
    subcategories_used = count_user_active_custom_categories(
        session,
        user_id,
        parented=True,
    )
    is_unlimited = user_has_feature(
        session,
        user_id,
        PREMIUM_CATEGORIES_UNLIMITED,
        now=now,
    )
    if is_unlimited:
        return CategoryUsage(
            categories_used=categories_used,
            categories_limit=None,
            categories_remaining=None,
            subcategories_used=subcategories_used,
            subcategories_limit=None,
            subcategories_remaining=None,
            is_unlimited=True,
        )

    return CategoryUsage(
        categories_used=categories_used,
        categories_limit=FREE_PLAN_CUSTOM_CATEGORY_LIMIT,
        categories_remaining=max(FREE_PLAN_CUSTOM_CATEGORY_LIMIT - categories_used, 0),
        subcategories_used=subcategories_used,
        subcategories_limit=FREE_PLAN_CUSTOM_SUBCATEGORY_LIMIT,
        subcategories_remaining=max(
            FREE_PLAN_CUSTOM_SUBCATEGORY_LIMIT - subcategories_used,
            0,
        ),
        is_unlimited=False,
    )
