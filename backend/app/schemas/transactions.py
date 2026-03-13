"""Transaction and transaction-item API schemas."""

import datetime as dt
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator

from app.models.shared.enums import TransactionSource
from app.schemas.extraction import ExtractionWarning
from app.schemas.shared import (
    Amount2DP,
    CurrencyCode,
    PaginationParams,
    Quantity3DP,
    SchemaBase,
    UnitPrice4DP,
    UUIDTimestampSchema,
    normalize_currency_code,
    normalize_language_code,
    quantize_amount,
    quantize_quantity,
    quantize_unit_price,
)

TransactionStatus = Literal["DRAFT", "CONFIRMED"]


class TransactionItemCreate(SchemaBase):
    """Payload for adding an item line to a transaction."""

    line_no: int = Field(ge=1)
    description: str = Field(min_length=1, max_length=500)
    description_lang: str | None = Field(default=None, max_length=16)
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

    @field_validator("description_lang")
    @classmethod
    def normalize_description_lang(cls, value: str | None) -> str | None:
        """Normalize source language code when provided."""

        if value is None:
            return None
        normalized = normalize_language_code(value)
        return normalized or None


class TransactionItemRead(UUIDTimestampSchema):
    """Read model for persisted transaction item lines."""

    transaction_id: UUID
    line_no: int
    description: str
    description_lang: str | None
    qty: Quantity3DP | None
    unit: str | None
    unit_price: UnitPrice4DP | None
    amount: Amount2DP
    amount_before_discount: Amount2DP | None
    discount_amount: Amount2DP | None
    is_adjustment: bool
    category_id: UUID
    raw_line: str | None
    display_amount: Amount2DP | None = None
    display_unit_price: UnitPrice4DP | None = None
    translated_description: str | None = None
    translation_language: str | None = None
    translation_source_language: str | None = None


class TransactionItemUpdate(SchemaBase):
    """Update payload for a single transaction line item."""
    id: UUID | None = Field(default=None, description="Provide ID to update existing item, omit to create new.")
    description: str | None = None
    description_lang: str | None = Field(default=None, max_length=16)
    qty: Quantity3DP | None = None
    unit: str | None = None
    unit_price: UnitPrice4DP | None = None
    amount: Amount2DP | None = None
    amount_before_discount: Amount2DP | None = None
    discount_amount: Amount2DP | None = None
    is_adjustment: bool | None = None
    category_id: UUID | None = None

    @field_validator("description_lang")
    @classmethod
    def normalize_description_lang(cls, value: str | None) -> str | None:
        """Normalize source language code when provided."""

        if value is None:
            return None
        normalized = normalize_language_code(value)
        return normalized or None


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
    # Expense attribution fields (optional — defaults are set by the router)
    household_id: UUID | None = None
    owner_user_id: UUID | None = None


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


class TransactionLabelRead(SchemaBase):
    """Read model for labels assigned to a transaction."""

    id: UUID
    name: str
    color: str | None = None


class TransactionUserSnippetRead(SchemaBase):
    """Minimal user identity block for transaction attribution."""

    user_id: UUID
    display_name: str | None = None
    email: str | None = None
    avatar_url: str | None = None


class TransactionHouseholdSnippetRead(SchemaBase):
    """Minimal household identity block for transaction attribution."""

    household_id: UUID
    name: str | None = None


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
    category_name: str | None = None
    source: TransactionSource
    status: TransactionStatus
    items: list[TransactionItemRead] = Field(default_factory=list)
    display_currency: CurrencyCode | None = None
    display_amount_total: Amount2DP | None = None
    display_rate_date: dt.date | None = None
    display_rate_fallback: bool | None = None
    labels: list[TransactionLabelRead] = Field(default_factory=list)
    has_extraction_warnings: bool = False
    extraction_warnings: list[ExtractionWarning] = Field(default_factory=list)
    # Expense attribution fields
    household_id: UUID | None = None
    created_by_user_id: UUID | None = None
    owner_user_id: UUID | None = None
    household: TransactionHouseholdSnippetRead | None = None
    created_by_user: TransactionUserSnippetRead | None = None
    owner_user: TransactionUserSnippetRead | None = None


class TransactionUpdateRequest(SchemaBase):
    """Payload to update an extracted transaction and its items."""
    occurred_at: dt.datetime | None = None
    amount_total: Amount2DP | None = None
    currency: CurrencyCode | None = None
    merchant_name: str | None = None
    category_id: UUID | None = None
    status: TransactionStatus | None = None
    # Expense attribution fields (optional)
    household_id: UUID | None = None
    owner_user_id: UUID | None = None

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
    category_ids: str | None = None  # Comma-separated UUIDs
    subcategory_ids: str | None = None  # Comma-separated UUIDs
    merchant_name_search: str | None = None  # Text search on merchant_name
    label_id: UUID | None = None
    label_ids: str | None = None  # Comma-separated UUIDs for multi-select OR filter
    status: TransactionStatus | None = None
    source: TransactionSource | None = None
    currency: CurrencyCode | None = None
    target_currency: CurrencyCode | None = None
    item_language: str | None = Field(default=None, max_length=16)
    app_language: str | None = Field(default=None, max_length=16)

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str | None) -> str | None:
        """Normalize optional currency code casing."""

        if value is None:
            return None
        return normalize_currency_code(value)

    @field_validator("target_currency")
    @classmethod
    def normalize_target_currency(cls, value: str | None) -> str | None:
        """Normalize optional display currency code casing."""

        if value is None:
            return None
        return normalize_currency_code(value)

    @field_validator("item_language", "app_language")
    @classmethod
    def normalize_item_language(cls, value: str | None) -> str | None:
        """Normalize optional item translation language code."""

        if value is None:
            return None
        normalized = normalize_language_code(value)
        return normalized or None


class TransactionConfirm(SchemaBase):
    """Payload used to confirm a draft transaction."""

    status: Literal["CONFIRMED"] = "CONFIRMED"
