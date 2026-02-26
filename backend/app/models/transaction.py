import datetime
import uuid
from decimal import Decimal

from sqlalchemy import CHAR, Column, DateTime, Index, Numeric, String
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.enums import TransactionSource
from app.models.timestamps import TimestampedModel


class TransactionBase(SQLModel):
    """Base financial transaction attributes shared by API and ORM models."""

    occurred_at: datetime.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True, index=True),
    )
    amount_total: Decimal | None = Field(
        default=None,
        sa_column=Column(Numeric(12, 2), nullable=True),
    )

    currency: str = Field(
        default="EUR",
        sa_column=Column(CHAR(3), nullable=False, default="EUR"),
    )
    merchant_id: uuid.UUID | None = Field(default=None, index=True, foreign_key="merchants.id")
    merchant_name: str | None = Field(default=None, max_length=255)
    category_id: uuid.UUID | None = Field(default=None, index=True, foreign_key="categories.id")
    source: TransactionSource = Field(
        default=TransactionSource.RECEIPT,
        sa_column=Column(
            SAEnum(TransactionSource, name="transaction_source", native_enum=False),
            nullable=False,
            default=TransactionSource.RECEIPT,
        ),
    )
    status: str = Field(
        default="DRAFT",
        sa_column=Column(String(16), nullable=False, default="DRAFT"),
    )


class Transaction(TransactionBase, TimestampedModel, table=True):
    """Financial ledger record generated from receipts, manual input, or imports.

    Status values are currently stored as strings and should remain in the
    `DRAFT` / `CONFIRMED` value set for compatibility.
    """

    __tablename__ = "transactions"
    __table_args__ = (Index("ix_transactions_user_occurred_at", "user_id", "occurred_at"),)

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")
    receipt_id: uuid.UUID | None = Field(
        default=None, index=True, unique=True, foreign_key="receipts.id"
    )
