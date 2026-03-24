import uuid
from decimal import Decimal

from sqlalchemy import CHAR, Column, Numeric, UniqueConstraint
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class BudgetSettings(TimestampedModel, table=True):
    """Per-user monthly budget configuration."""

    __tablename__ = "budget_settings"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_budget_settings_user_id"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")
    currency: str = Field(
        default="EUR",
        sa_column=Column(CHAR(3), nullable=False, default="EUR"),
    )
    monthly_income: Decimal | None = Field(
        default=None,
        sa_column=Column(Numeric(12, 2), nullable=True),
    )


class BudgetCategoryLimit(TimestampedModel, table=True):
    """Monthly budget cap for one top-level category."""

    __tablename__ = "budget_category_limits"
    __table_args__ = (
        UniqueConstraint(
            "budget_settings_id",
            "category_id",
            name="uq_budget_category_limits_budget_category",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    budget_settings_id: uuid.UUID = Field(
        index=True,
        nullable=False,
        foreign_key="budget_settings.id",
    )
    category_id: uuid.UUID = Field(
        index=True,
        nullable=False,
        foreign_key="categories.id",
    )
    limit_amount: Decimal = Field(
        sa_column=Column(Numeric(12, 2), nullable=False),
    )
