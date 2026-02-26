import uuid
from decimal import Decimal
from datetime import datetime

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel, String, Numeric


class TransactionItem(SQLModel, table=True):
    """A line item from a receipt.

    Represents a purchased product/service row, including optional discount
    information when available on the receipt.
    """

    __tablename__ = "transaction_items"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    transaction_id: uuid.UUID = Field(
        index=True, nullable=False, foreign_key="transactions.id"
    )

    line_no: int = Field(nullable=False)

    description: str = Field(sa_column=Column(String(500), nullable=False))

    qty: Decimal | None = Field(
        default=None, sa_column=Column(Numeric(12, 3), nullable=True)
    )
    unit: str | None = Field(default=None, max_length=16)  # e.g., "kg", "l", "pcs"

    unit_price: Decimal | None = Field(
        default=None, sa_column=Column(Numeric(12, 4), nullable=True)
    )

    amount: Decimal = Field(sa_column=Column(Numeric(12, 2), nullable=False))

    amount_before_discount: Decimal | None = Field(
        default=None, sa_column=Column(Numeric(12, 2), nullable=True)
    )
    discount_amount: Decimal | None = Field(
        default=None, sa_column=Column(Numeric(12, 2), nullable=True)
    )

    is_adjustment: bool = Field(default=False)  # e.g., discount/coupon line as a separate row

    product_category_label: str | None = Field(
        default=None, max_length=128, index=True
    )

    raw_line: str | None = Field(default=None, max_length=800)

    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
