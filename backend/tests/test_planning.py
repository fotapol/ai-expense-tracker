"""Tests for budget planning and bill reminder routes."""

from __future__ import annotations

import asyncio
import datetime as dt
import uuid
from decimal import Decimal

import pytest
from fastapi import HTTPException
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine
from starlette.requests import Request

from app.api.routers import planning
from app.models.planning.bill_reminder import BillReminder
from app.models.planning.budget import BudgetCategoryLimit, BudgetSettings
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory
from app.models.users.user import User
from app.schemas.planning import (
    BillReminderCreate,
    BillReminderMarkPaid,
    BillReminderSkip,
    BudgetCategoryLimitInput,
    BudgetPlanUpsert,
)


def _build_session() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(
        engine,
        tables=[
            User.__table__,
            Category.__table__,
            UserHiddenCategory.__table__,
            BudgetSettings.__table__,
            BudgetCategoryLimit.__table__,
            BillReminder.__table__,
        ],
    )
    return Session(engine)


def _make_user(email: str) -> User:
    suffix = uuid.uuid4().hex[:8]
    return User(
        email=email,
        auth_provider="firebase",
        auth_subject=f"uid-{suffix}",
    )


def _make_top_level_category(code: str, name: str) -> Category:
    return Category(
        scope=CategoryScope.ITEM,
        code=code,
        name=name,
        parent_id=None,
        user_id=None,
        is_custom=False,
        is_active=True,
    )


def _run(coro):
    return asyncio.run(coro)


def _request() -> Request:
    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/",
            "headers": [],
        }
    )


def _unlimited(func):
    return getattr(func, "__wrapped__", func)


def test_budget_plan_is_scoped_to_current_user() -> None:
    session = _build_session()
    user_one = _make_user("user1@example.com")
    user_two = _make_user("user2@example.com")
    groceries = _make_top_level_category("GROCERIES", "Groceries")
    session.add(user_one)
    session.add(user_two)
    session.add(groceries)
    session.commit()

    saved = _run(
        _unlimited(planning.put_budget_plan)(
            payload=BudgetPlanUpsert(
                monthly_income=Decimal("5000.00"),
                currency="USD",
                category_limits=[
                    BudgetCategoryLimitInput(
                        category_id=groceries.id,
                        limit_amount=Decimal("650.00"),
                    )
                ],
            ),
            request=_request(),
            session=session,
            current_user=user_one,
        )
    )
    user_one_budget = _run(
        _unlimited(planning.get_budget_plan)(
            request=_request(),
            session=session,
            current_user=user_one,
        )
    )
    user_two_budget = _run(
        _unlimited(planning.get_budget_plan)(
            request=_request(),
            session=session,
            current_user=user_two,
        )
    )

    assert saved.currency == "USD"
    assert saved.monthly_income == Decimal("5000.00")
    assert len(saved.category_limits) == 1
    assert saved.category_limits[0].category_id == groceries.id
    assert saved.category_limits[0].limit_amount == Decimal("650.00")
    assert user_one_budget == saved
    assert user_two_budget.currency == user_two.default_currency
    assert user_two_budget.monthly_income is None
    assert user_two_budget.category_limits == []


def test_budget_plan_rejects_duplicate_category_limits() -> None:
    session = _build_session()
    user = _make_user("user@example.com")
    housing = _make_top_level_category("HOUSING", "Housing")
    session.add(user)
    session.add(housing)
    session.commit()

    with pytest.raises(HTTPException) as exc_info:
        _run(
            _unlimited(planning.put_budget_plan)(
                payload=BudgetPlanUpsert(
                    monthly_income=Decimal("4200.00"),
                    currency="EUR",
                    category_limits=[
                        BudgetCategoryLimitInput(
                            category_id=housing.id,
                            limit_amount=Decimal("1000.00"),
                        ),
                        BudgetCategoryLimitInput(
                            category_id=housing.id,
                            limit_amount=Decimal("1200.00"),
                        ),
                    ],
                ),
                request=_request(),
                session=session,
                current_user=user,
            )
        )

    assert exc_info.value.status_code == 400
    assert "one budget limit" in str(exc_info.value.detail).lower()


def test_bill_reminders_are_scoped_to_current_user() -> None:
    session = _build_session()
    user_one = _make_user("bills1@example.com")
    user_two = _make_user("bills2@example.com")
    session.add(user_one)
    session.add(user_two)
    session.commit()

    created = _run(
        _unlimited(planning.create_bill_reminder)(
            payload=BillReminderCreate(
                name="Internet",
                amount=Decimal("79.99"),
                currency="USD",
                first_due_date=dt.date(2026, 3, 25),
                remind_days_before=3,
                is_active=True,
            ),
            request=_request(),
            session=session,
            current_user=user_one,
        )
    )
    session.add(
        BillReminder(
            user_id=user_two.id,
            name="Rent",
            amount=Decimal("1500.00"),
            currency="USD",
            first_due_date=dt.date(2026, 3, 1),
            remind_days_before=5,
            is_active=True,
        )
    )
    session.commit()

    user_one_bills = _run(
        _unlimited(planning.list_bill_reminders)(
            request=_request(),
            session=session,
            current_user=user_one,
        )
    )
    user_two_bills = _run(
        _unlimited(planning.list_bill_reminders)(
            request=_request(),
            session=session,
            current_user=user_two,
        )
    )

    assert created.user_id == user_one.id
    assert [bill.name for bill in user_one_bills] == ["Internet"]
    assert [bill.name for bill in user_two_bills] == ["Rent"]


def test_mark_bill_paid_is_idempotent_and_monotonic() -> None:
    session = _build_session()
    user = _make_user("paid@example.com")
    reminder = BillReminder(
        user_id=user.id,
        name="Gym Membership",
        amount=Decimal("49.99"),
        currency="USD",
        first_due_date=dt.date(2026, 1, 15),
        remind_days_before=3,
        is_active=True,
    )
    session.add(user)
    session.add(reminder)
    session.commit()
    session.refresh(reminder)

    march_paid = _run(
        _unlimited(planning.mark_bill_reminder_paid)(
            bill_id=reminder.id,
            payload=BillReminderMarkPaid(due_date=dt.date(2026, 3, 15)),
            request=_request(),
            session=session,
            current_user=user,
        )
    )
    february_paid = _run(
        _unlimited(planning.mark_bill_reminder_paid)(
            bill_id=reminder.id,
            payload=BillReminderMarkPaid(due_date=dt.date(2026, 2, 15)),
            request=_request(),
            session=session,
            current_user=user,
        )
    )
    repeated_march_paid = _run(
        _unlimited(planning.mark_bill_reminder_paid)(
            bill_id=reminder.id,
            payload=BillReminderMarkPaid(due_date=dt.date(2026, 3, 15)),
            request=_request(),
            session=session,
            current_user=user,
        )
    )

    assert march_paid.last_paid_due_date == dt.date(2026, 3, 15)
    assert march_paid.last_paid_at is not None
    assert february_paid.last_paid_due_date == dt.date(2026, 3, 15)
    assert february_paid.last_paid_at == march_paid.last_paid_at
    assert repeated_march_paid.last_paid_due_date == dt.date(2026, 3, 15)
    assert repeated_march_paid.last_paid_at == march_paid.last_paid_at


def test_mark_bill_paid_accepts_daily_recurrence_dates() -> None:
    session = _build_session()
    user = _make_user("daily@example.com")
    reminder = BillReminder(
        user_id=user.id,
        name="Medicine",
        amount=Decimal("10.00"),
        currency="EUR",
        recurrence="daily",
        first_due_date=dt.date(2026, 3, 20),
        remind_days_before=1,
        is_active=True,
    )
    session.add(user)
    session.add(reminder)
    session.commit()
    session.refresh(reminder)

    paid = _run(
        _unlimited(planning.mark_bill_reminder_paid)(
            bill_id=reminder.id,
            payload=BillReminderMarkPaid(due_date=dt.date(2026, 3, 24)),
            request=_request(),
            session=session,
            current_user=user,
        )
    )

    assert paid.last_paid_due_date == dt.date(2026, 3, 24)
    assert paid.last_paid_at is not None


def test_mark_bill_paid_clamps_yearly_leap_day_schedule() -> None:
    session = _build_session()
    user = _make_user("yearly@example.com")
    reminder = BillReminder(
        user_id=user.id,
        name="Insurance",
        amount=Decimal("100.00"),
        currency="EUR",
        recurrence="yearly",
        first_due_date=dt.date(2024, 2, 29),
        remind_days_before=14,
        is_active=True,
    )
    session.add(user)
    session.add(reminder)
    session.commit()
    session.refresh(reminder)

    paid = _run(
        _unlimited(planning.mark_bill_reminder_paid)(
            bill_id=reminder.id,
            payload=BillReminderMarkPaid(due_date=dt.date(2026, 2, 28)),
            request=_request(),
            session=session,
            current_user=user,
        )
    )

    assert paid.last_paid_due_date == dt.date(2026, 2, 28)
    assert paid.last_paid_at is not None


def test_bill_reminder_create_accepts_weekly_and_one_time_recurrence() -> None:
    session = _build_session()
    user = _make_user("recurrence@example.com")
    session.add(user)
    session.commit()

    weekly = _run(
        _unlimited(planning.create_bill_reminder)(
            payload=BillReminderCreate(
                name="Cleaning",
                amount=Decimal("30.00"),
                currency="EUR",
                recurrence="weekly",
                first_due_date=dt.date(2026, 4, 7),
                remind_days_before=2,
                is_active=True,
            ),
            request=_request(),
            session=session,
            current_user=user,
        )
    )
    one_time = _run(
        _unlimited(planning.create_bill_reminder)(
            payload=BillReminderCreate(
                name="One-time fee",
                amount=Decimal("15.00"),
                currency="EUR",
                recurrence="none",
                first_due_date=dt.date(2026, 4, 9),
                remind_days_before=0,
                is_active=True,
            ),
            request=_request(),
            session=session,
            current_user=user,
        )
    )

    assert weekly.recurrence == "weekly"
    assert one_time.recurrence == "none"


def test_skip_bill_reminder_updates_last_skipped_due_date_only() -> None:
    session = _build_session()
    user = _make_user("skip@example.com")
    reminder = BillReminder(
        user_id=user.id,
        name="Internet",
        amount=Decimal("50.00"),
        currency="USD",
        recurrence="weekly",
        first_due_date=dt.date(2026, 4, 1),
        remind_days_before=2,
        is_active=True,
    )
    session.add(user)
    session.add(reminder)
    session.commit()
    session.refresh(reminder)

    skipped = _run(
        _unlimited(planning.skip_bill_reminder_occurrence)(
            bill_id=reminder.id,
            payload=BillReminderSkip(due_date=dt.date(2026, 4, 8)),
            request=_request(),
            session=session,
            current_user=user,
        )
    )

    assert skipped.last_skipped_due_date == dt.date(2026, 4, 8)
    assert skipped.last_paid_due_date is None


def test_delete_bill_reminder_keeps_paid_history_entries_in_list() -> None:
    session = _build_session()
    user = _make_user("history@example.com")
    paid_reminder = BillReminder(
        user_id=user.id,
        name="Gym",
        amount=Decimal("45.00"),
        currency="USD",
        recurrence="monthly",
        first_due_date=dt.date(2026, 1, 10),
        last_paid_due_date=dt.date(2026, 4, 10),
        remind_days_before=3,
        is_active=True,
    )
    unpaid_reminder = BillReminder(
        user_id=user.id,
        name="Parking",
        amount=Decimal("25.00"),
        currency="USD",
        recurrence="monthly",
        first_due_date=dt.date(2026, 1, 12),
        remind_days_before=3,
        is_active=True,
    )
    session.add(user)
    session.add(paid_reminder)
    session.add(unpaid_reminder)
    session.commit()
    session.refresh(paid_reminder)
    session.refresh(unpaid_reminder)

    _run(
        _unlimited(planning.delete_bill_reminder)(
            bill_id=paid_reminder.id,
            request=_request(),
            session=session,
            current_user=user,
        )
    )
    _run(
        _unlimited(planning.delete_bill_reminder)(
            bill_id=unpaid_reminder.id,
            request=_request(),
            session=session,
            current_user=user,
        )
    )

    visible = _run(
        _unlimited(planning.list_bill_reminders)(
            request=_request(),
            session=session,
            current_user=user,
        )
    )

    assert [bill.name for bill in visible] == ["Gym"]
    assert visible[0].is_active is False
    assert visible[0].last_paid_due_date == dt.date(2026, 4, 10)
