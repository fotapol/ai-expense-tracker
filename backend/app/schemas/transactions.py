"""Transaction and transaction-item API schemas."""

import datetime as dt
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator

from app.models.shared.enums import TransactionSource
from app.schemas.shared import (
    Amount2DP,
    CurrencyCode,
    PaginationParams,
    Quantity3DP,
    SchemaBase,
    UnitPrice4DP,
    UUIDTimestampSchema,
    normalize_currency_code,
    quantize_amount,
    quantize_quantity,
    quantize_unit_price,
)

TransactionStatus = Literal["DRAFT", "CONFIRMED"]


class TransactionItemCreate(SchemaBase):
    """Payload for adding an item line to a transaction."""

    line_no: int = Field(ge=1)
    description: str = Field(min_length=1, max_length=500)
    qty: Quantity3DP | None = None
    unit: str | None = Field(default=None, max_length=32)
    unit_price: UnitPrice4DP | None = None
    amount: Amount2DP
    amount_before_discount: Amount2DP | None = None
    discount_amount: Amount2DP | None = None
    is_adjustment: bool = False
    category_id: UUID
    raw_line: str | None = Field(default=None, max_length=1000)

    @field_validator("qty")
    @classmethod
    def normalize_qty(cls, value: Decimal | None) -> Decimal | None:
        """Quantize quantity when provided."""

        if value is None:
            return None
        return quantize_quantity(value)

    @field_validator("unit_price")
    @classmethod
    def normalize_unit_price(cls, value: Decimal | None) -> Decimal | None:
        """Quantize unit price when provided."""

        if value is None:
            return None
        return quantize_unit_price(value)

    @field_validator("amount", "amount_before_discount", "discount_amount")
    @classmethod
    def normalize_amounts(cls, value: Decimal | None) -> Decimal | None:
        """Quantize amount fields when provided."""

        if value is None:
            return None
        return quantize_amount(value)


class TransactionItemRead(UUIDTimestampSchema):
    """Read model for persisted transaction item lines."""

    transaction_id: UUID
    line_no: int
    description: str
    qty: Quantity3DP | None
    unit: str | None
    unit_price: UnitPrice4DP | None
    amount: Amount2DP
    amount_before_discount: Amount2DP | None
    discount_amount: Amount2DP | None
    is_adjustment: bool
    category_id: UUID
    raw_line: str | None


class TransactionItemUpdate(SchemaBase):
    """Update payload for a single transaction line item."""
    id: UUID | None = Field(default=None, description="Provide ID to update existing item, omit to create new.")
    description: str | None = None
    qty: Quantity3DP | None = None
    unit: str | None = None
    unit_price: UnitPrice4DP | None = None
    amount: Amount2DP | None = None
    amount_before_discount: Amount2DP | None = None
    discount_amount: Amount2DP | None = None
    is_adjustment: bool | None = None
    category_id: UUID | None = None


class TransactionCreateManual(SchemaBase):
    """Payload for creating a manual transaction entry."""

    occurred_at: dt.datetime | None = None
    amount_total: Amount2DP
    currency: CurrencyCode = "EUR"
    merchant_id: UUID | None = None
    merchant_name: str | None = Field(default=None, max_length=255)
    category_id: UUID | None = None
    source: TransactionSource = TransactionSource.MANUAL
    status: TransactionStatus = "DRAFT"
    items: list[TransactionItemCreate] = Field(default_factory=list)

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        """Normalize currency code casing."""

        return normalize_currency_code(value)

    @field_validator("amount_total")
    @classmethod
    def normalize_total(cls, value: Decimal) -> Decimal:
        """Quantize transaction total."""

        return quantize_amount(value)


class TransactionRead(UUIDTimestampSchema):
    """Read model for transaction records."""

    user_id: UUID
    receipt_id: UUID | None
    occurred_at: dt.datetime | None
    amount_total: Amount2DP | None
    currency: CurrencyCode
    merchant_id: UUID | None
    merchant_name: str | None
    category_id: UUID | None
    source: TransactionSource
    status: TransactionStatus
    items: list[TransactionItemRead] = Field(default_factory=list)


class TransactionUpdateRequest(SchemaBase):
    """Payload to update an extracted transaction and its items."""
    occurred_at: dt.datetime | None = None
    amount_total: Amount2DP | None = None
    currency: CurrencyCode | None = None
    merchant_name: str | None = None
    category_id: UUID | None = None
    status: TransactionStatus | None = None

    items: list[TransactionItemUpdate] | None = Field(
        default=None, 
        description="If provided, fully replaces or updates the line items."
    )


class TransactionListFilter(PaginationParams):
    """Filter parameters for listing transactions."""

    user_id: UUID | None = None
    from_occurred_at: dt.datetime | None = None
    to_occurred_at: dt.datetime | None = None
    merchant_id: UUID | None = None
    category_id: UUID | None = None
    merchant_name_search: str | None = None  # Text search on merchant_name
    label_id: UUID | None = None
    status: TransactionStatus | None = None
    source: TransactionSource | None = None
    currency: CurrencyCode | None = None

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str | None) -> str | None:
        """Normalize optional currency code casing."""

        if value is None:
            return None
        return normalize_currency_code(value)


class TransactionConfirm(SchemaBase):
    """Payload used to confirm a draft transaction."""

    status: Literal["CONFIRMED"] = "CONFIRMED"
