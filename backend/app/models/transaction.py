import datetime
import uuid
from enum import Enum
from decimal import Decimal


from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel, Numeric, SAEnum


class TransactionSource(str, Enum):
    """How a transaction was created."""

    RECEIPT = "RECEIPT"
    MANUAL = "MANUAL"
    IMPORTED = "IMPORTED"


class TransactionBase(SQLModel):
    """Shared fields for Transaction models.

    Transaction is a financial record used for analytics and user-facing ledgers.
    """

    occurred_at: datetime.datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True), nullable=True)
    )

    currency: str = Field(default="EUR", max_length=3, nullable=False)
    merchant_name: str = Field(default=None, max_length=255, nullable=True, foreign_key="merchant.name")
    
    note: str | None = Field(default=None, max_length=500)


class Transaction(TransactionBase, table=True):
    """A single spending/income record.

    Typically created from a processed receipt (Receipt -> Extraction -> Transaction),
    but can also be created manually in the future.
    """

    __tablename__ = "transactions"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")
    receipt_id: uuid.UUID | None = Field(
        default=None, index=True, unique=True, foreign_key="receipts.id"
    )

    amount_total: Decimal | None = Field(
        default=None, sa_column=Column(Numeric(12, 2), nullable=True)
    )

    source: TransactionSource = Field(
        default=TransactionSource.RECEIPT,
        sa_column=Column(SAEnum(TransactionSource, name="transaction_source", native_enum=False), nullable=False),
    )

    status: str = Field(default="DRAFT", max_length=16, nullable=False)

    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
    updated_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), onupdate=func.now(), nullable=False)
    )
