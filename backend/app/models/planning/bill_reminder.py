import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import CHAR, Column, Date, Index, Numeric, String
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class BillReminder(TimestampedModel, table=True):
    """Per-user recurring monthly bill reminder."""

    __tablename__ = "bill_reminders"
    __table_args__ = (
        Index("ix_bill_reminders_user_active", "user_id", "is_active"),
        Index("ix_bill_reminders_user_first_due_date", "user_id", "first_due_date"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")
    name: str = Field(sa_column=Column(String(120), nullable=False))
    amount: Decimal = Field(sa_column=Column(Numeric(12, 2), nullable=False))
    currency: str = Field(
        default="EUR",
        sa_column=Column(CHAR(3), nullable=False, default="EUR"),
    )
    first_due_date: dt.date = Field(
        sa_column=Column(Date(), nullable=False),
    )
    last_paid_due_date: dt.date | None = Field(
        default=None,
        sa_column=Column(Date(), nullable=True),
    )
    remind_days_before: int = Field(default=3, nullable=False)
    is_active: bool = Field(default=True, nullable=False)
