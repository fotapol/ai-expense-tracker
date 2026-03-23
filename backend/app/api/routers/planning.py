"""Budget calculator and bill reminder API endpoints."""

from __future__ import annotations

import calendar
import datetime as dt
import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import or_
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.planning.bill_reminder import BillReminder
from app.models.planning.budget import BudgetCategoryLimit, BudgetSettings
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory
from app.models.users.user import User
from app.schemas.planning import (
    BillReminderCreate,
    BillReminderMarkPaid,
    BillReminderRead,
    BudgetCategoryLimitInput,
    BudgetPlanRead,
    BudgetPlanUpsert,
)

router = APIRouter(prefix="/v1", tags=["planning"])


def _visible_top_level_categories_by_id(
    session: Session,
    current_user: User,
    category_ids: set[uuid.UUID],
) -> dict[uuid.UUID, Category]:
    if not category_ids:
        return {}

    disabled_subquery = select(UserHiddenCategory.category_id).where(
        UserHiddenCategory.user_id == current_user.id,
    )
    categories = session.exec(
        select(Category).where(
            Category.id.in_(category_ids),
            Category.scope == CategoryScope.ITEM,
            Category.parent_id.is_(None),
            Category.is_active,
            Category.id.notin_(disabled_subquery),
            or_(Category.user_id.is_(None), Category.user_id == current_user.id),
        )
    ).all()
    return {category.id: category for category in categories}


def _build_budget_response(
    session: Session,
    current_user: User,
    settings: BudgetSettings | None,
) -> BudgetPlanRead:
    if settings is None:
        return BudgetPlanRead(
            monthly_income=None,
            currency=current_user.default_currency,
            category_limits=[],
        )

    limit_rows = session.exec(
        select(BudgetCategoryLimit).where(
            BudgetCategoryLimit.budget_settings_id == settings.id,
        )
    ).all()
    visible_categories = _visible_top_level_categories_by_id(
        session,
        current_user,
        {row.category_id for row in limit_rows},
    )
    category_limits = [
        BudgetCategoryLimitInput(
            category_id=row.category_id,
            limit_amount=row.limit_amount,
        )
        for row in limit_rows
        if row.category_id in visible_categories
    ]
    return BudgetPlanRead(
        monthly_income=settings.monthly_income,
        currency=settings.currency,
        category_limits=category_limits,
    )


def _validate_budget_payload(
    session: Session,
    current_user: User,
    payload: BudgetPlanUpsert,
) -> list[BudgetCategoryLimitInput]:
    seen_category_ids: set[uuid.UUID] = set()
    normalized_limits: list[BudgetCategoryLimitInput] = []
    for limit in payload.category_limits:
        if limit.category_id in seen_category_ids:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Each category can only have one budget limit.",
            )
        seen_category_ids.add(limit.category_id)
        normalized_limits.append(limit)

    visible_categories = _visible_top_level_categories_by_id(
        session,
        current_user,
        seen_category_ids,
    )
    if len(visible_categories) != len(seen_category_ids):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Budget limits must target active top-level categories.",
        )
    return normalized_limits


def _monthly_due_date(anchor: dt.date, year: int, month: int) -> dt.date:
    last_day = calendar.monthrange(year, month)[1]
    return dt.date(year, month, min(anchor.day, last_day))


@router.get("/planning/budget", response_model=BudgetPlanRead)
@limiter.limit("30/minute")
async def get_budget_plan(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return the current user's synced budget configuration."""

    settings = session.exec(
        select(BudgetSettings).where(BudgetSettings.user_id == current_user.id)
    ).first()
    return _build_budget_response(session, current_user, settings)


@router.put("/planning/budget", response_model=BudgetPlanRead)
@limiter.limit("20/minute")
async def put_budget_plan(
    payload: BudgetPlanUpsert,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Replace the current user's synced budget configuration."""

    normalized_limits = _validate_budget_payload(session, current_user, payload)
    settings = session.exec(
        select(BudgetSettings).where(BudgetSettings.user_id == current_user.id)
    ).first()
    if settings is None:
        settings = BudgetSettings(user_id=current_user.id)

    settings.currency = payload.currency
    settings.monthly_income = payload.monthly_income
    session.add(settings)
    session.flush()

    existing_limits = session.exec(
        select(BudgetCategoryLimit).where(
            BudgetCategoryLimit.budget_settings_id == settings.id,
        )
    ).all()
    for row in existing_limits:
        session.delete(row)
    session.flush()

    for limit in normalized_limits:
        session.add(
            BudgetCategoryLimit(
                budget_settings_id=settings.id,
                category_id=limit.category_id,
                limit_amount=Decimal(limit.limit_amount),
            )
        )

    session.commit()
    session.refresh(settings)
    return _build_budget_response(session, current_user, settings)


@router.get("/planning/bills", response_model=list[BillReminderRead])
@limiter.limit("30/minute")
async def list_bill_reminders(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List active recurring bill reminders for the current user."""

    return session.exec(
        select(BillReminder)
        .where(
            BillReminder.user_id == current_user.id,
            BillReminder.is_active,
        )
        .order_by(BillReminder.first_due_date, BillReminder.created_at)
    ).all()


@router.post(
    "/planning/bills",
    response_model=BillReminderRead,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("20/minute")
async def create_bill_reminder(
    payload: BillReminderCreate,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create a recurring monthly bill reminder for the current user."""

    reminder = BillReminder(
        user_id=current_user.id,
        name=payload.name,
        amount=Decimal(payload.amount),
        currency=payload.currency,
        first_due_date=payload.first_due_date,
        remind_days_before=payload.remind_days_before,
        is_active=payload.is_active,
    )
    session.add(reminder)
    session.commit()
    session.refresh(reminder)
    return reminder


@router.patch("/planning/bills/{bill_id}/mark-paid", response_model=BillReminderRead)
@limiter.limit("20/minute")
async def mark_bill_reminder_paid(
    bill_id: uuid.UUID,
    payload: BillReminderMarkPaid,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Mark one reminder cycle as paid if the payload is valid and newer."""

    reminder = session.exec(
        select(BillReminder).where(
            BillReminder.id == bill_id,
            BillReminder.user_id == current_user.id,
        )
    ).first()
    if reminder is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Bill reminder not found.",
        )

    if payload.due_date < reminder.first_due_date:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Paid due date cannot be before the first due date.",
        )

    expected_due_date = _monthly_due_date(
        reminder.first_due_date,
        payload.due_date.year,
        payload.due_date.month,
    )
    if payload.due_date != expected_due_date:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Paid due date must match the monthly reminder schedule.",
        )

    if (
        reminder.last_paid_due_date is None
        or payload.due_date > reminder.last_paid_due_date
    ):
        reminder.last_paid_due_date = payload.due_date
        session.add(reminder)
        session.commit()
        session.refresh(reminder)

    return reminder
