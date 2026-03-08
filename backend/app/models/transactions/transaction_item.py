import uuid
from decimal import Decimal

from sqlalchemy import Column, Numeric, String, UniqueConstraint
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class TransactionItem(TimestampedModel, table=True):
    """Line item within a transaction with mandatory item-level category assignment.

    If extraction cannot classify an item, assign category code `UNCATEGORIZED`
    under ITEM scope and persist that category's UUID in `category_id`.
    """

    __tablename__ = "transaction_items"
    __table_args__ = (
        UniqueConstraint(
            "transaction_id", "line_no", name="uq_transaction_items_transaction_line_no"
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    transaction_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="transactions.id")

    line_no: int = Field(nullable=False)

    description: str = Field(sa_column=Column(String(500), nullable=False))
    description_lang: str | None = Field(default=None, max_length=16, index=True)

    qty: Decimal | None = Field(default=None, sa_column=Column(Numeric(12, 3), nullable=True))
    unit: str | None = Field(default=None, max_length=32)

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

    is_adjustment: bool = Field(default=False, nullable=False)
    category_id: uuid.UUID = Field(nullable=False, index=True, foreign_key="categories.id")

    raw_line: str | None = Field(default=None, max_length=1000)
