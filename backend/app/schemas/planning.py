"""Budget and bill reminder API schemas."""

from __future__ import annotations

import datetime as dt
from typing import Annotated
from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.shared import (
    Amount2DP,
    CurrencyCode,
    SchemaBase,
    UUIDTimestampSchema,
    normalize_currency_code,
    quantize_amount,
)

BillReminderRecurrence = Annotated[str, Field(min_length=5, max_length=7)]
_ALLOWED_BILL_RECURRENCES = {"daily", "monthly", "yearly"}


class BudgetCategoryLimitInput(SchemaBase):
    """One top-level category limit within a monthly budget."""

    category_id: UUID
    limit_amount: Amount2DP

    @field_validator("limit_amount")
    @classmethod
    def normalize_limit_amount(cls, value):
        return quantize_amount(value)


class BudgetPlanUpsert(SchemaBase):
    """Replace the current user's budget configuration."""

    monthly_income: Amount2DP | None = None
    currency: CurrencyCode
    category_limits: list[BudgetCategoryLimitInput] = Field(default_factory=list)

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        return normalize_currency_code(value)

    @field_validator("monthly_income")
    @classmethod
    def normalize_monthly_income(cls, value):
        if value is None:
            return None
        return quantize_amount(value)


class BudgetPlanRead(SchemaBase):
    """Current user's budget configuration."""

    monthly_income: Amount2DP | None = None
    currency: CurrencyCode
    category_limits: list[BudgetCategoryLimitInput] = Field(default_factory=list)


class BillReminderCreate(SchemaBase):
    """Payload for creating a recurring bill reminder."""

    name: str = Field(min_length=1, max_length=120)
    amount: Amount2DP
    currency: CurrencyCode
    recurrence: BillReminderRecurrence = "monthly"
    first_due_date: dt.date
    remind_days_before: int = Field(default=3, ge=0, le=30)
    is_active: bool = True

    @field_validator("name")
    @classmethod
    def normalize_name(cls, value: str) -> str:
        return value.strip()

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        return normalize_currency_code(value)

    @field_validator("recurrence")
    @classmethod
    def normalize_recurrence(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in _ALLOWED_BILL_RECURRENCES:
            raise ValueError("Recurrence must be daily, monthly, or yearly.")
        return normalized

    @field_validator("amount")
    @classmethod
    def normalize_amount(cls, value):
        return quantize_amount(value)


class BillReminderRead(UUIDTimestampSchema):
    """Read model for a recurring bill reminder."""

    user_id: UUID
    name: str
    amount: Amount2DP
    currency: CurrencyCode
    recurrence: BillReminderRecurrence
    first_due_date: dt.date
    last_paid_due_date: dt.date | None = None
    remind_days_before: int
    is_active: bool


class BillReminderMarkPaid(SchemaBase):
    """Mark one reminder cycle as paid."""

    due_date: dt.date
