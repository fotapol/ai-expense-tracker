"""Budget and bill reminder API schemas."""

from __future__ import annotations

import datetime as dt
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
    """Payload for creating a recurring monthly reminder."""

    name: str = Field(min_length=1, max_length=120)
    amount: Amount2DP
    currency: CurrencyCode
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

    @field_validator("amount")
    @classmethod
    def normalize_amount(cls, value):
        return quantize_amount(value)


class BillReminderRead(UUIDTimestampSchema):
    """Read model for a recurring monthly reminder."""

    user_id: UUID
    name: str
    amount: Amount2DP
    currency: CurrencyCode
    first_due_date: dt.date
    last_paid_due_date: dt.date | None = None
    remind_days_before: int
    is_active: bool


class BillReminderMarkPaid(SchemaBase):
    """Mark one monthly reminder cycle as paid."""

    due_date: dt.date
