"""Strict structured extraction schemas produced by the vision LLM."""

import datetime as dt
from decimal import Decimal
from typing import Annotated, Literal

from pydantic import Field, field_validator

from app.schemas.shared import (
    Amount2DP,
    CurrencyCode,
    Quantity3DP,
    SchemaBase,
    UnitPrice4DP,
    normalize_currency_code,
    quantize_amount,
    quantize_quantity,
    quantize_unit_price,
)


class ExtractedTransactionItem(SchemaBase):
    """Structured representation of an extracted receipt line item."""

    line_no: int | None = Field(default=None, ge=1)
    description: str = Field(min_length=1, max_length=500)
    qty: Quantity3DP | None = None
    unit: str | None = Field(default=None, max_length=32)
    unit_price: UnitPrice4DP | None = None
    amount: Amount2DP
    amount_before_discount: Amount2DP | None = None
    discount_amount: Amount2DP | None = None
    is_adjustment: bool = False
    raw_line: str | None = Field(default=None, max_length=1000)
    category_code: str | None = Field(default=None, max_length=64)

    @field_validator("qty")
    @classmethod
    def normalize_qty(cls, value: Decimal | None) -> Decimal | None:
        """Quantize quantity value when present."""

        if value is None:
            return None
        return quantize_quantity(value)

    @field_validator("unit_price")
    @classmethod
    def normalize_unit_price(cls, value: Decimal | None) -> Decimal | None:
        """Quantize unit price value when present."""

        if value is None:
            return None
        return quantize_unit_price(value)

    @field_validator("amount", "amount_before_discount", "discount_amount")
    @classmethod
    def normalize_amounts(cls, value: Decimal | None) -> Decimal | None:
        """Quantize amount fields when present."""

        if value is None:
            return None
        return quantize_amount(value)

    @field_validator("category_code")
    @classmethod
    def normalize_category_code(cls, value: str | None) -> str | None:
        """Normalize extracted category code text."""

        if value is None:
            return None
        return value.strip().upper()


class LineTotalMismatchWarning(SchemaBase):
    """Warning emitted when qty * unit_price is not equal to extracted line total."""

    type: Literal["LINE_TOTAL_MISMATCH"] = "LINE_TOTAL_MISMATCH"
    line_no: int = Field(ge=1)
    expected_amount: Amount2DP
    extracted_amount: Amount2DP
    difference: Amount2DP


class ReceiptTotalMismatchWarning(SchemaBase):
    """Warning emitted when sum of extracted item totals != receipt total."""

    type: Literal["RECEIPT_TOTAL_MISMATCH"] = "RECEIPT_TOTAL_MISMATCH"
    expected_total: Amount2DP
    extracted_total: Amount2DP
    difference: Amount2DP


ExtractionWarning = Annotated[
    LineTotalMismatchWarning | ReceiptTotalMismatchWarning,
    Field(discriminator="type"),
]


class ExtractedReceiptData(SchemaBase):
    """Canonical structured extraction object consumed by transaction creation logic."""

    merchant_name: str | None = Field(default=None, max_length=255)
    merchant_country: str | None = Field(default=None, min_length=2, max_length=2)
    occurred_at: dt.datetime | None = None
    currency: CurrencyCode = "EUR"
    amount_total: Amount2DP | None = None
    subtotal: Amount2DP | None = None
    tax_total: Amount2DP | None = None
    primary_category_code: str | None = Field(default=None, max_length=64)
    items: list[ExtractedTransactionItem] = Field(default_factory=list)
    warnings: list[ExtractionWarning] = Field(default_factory=list)
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        """Normalize currency code casing."""

        return normalize_currency_code(value)

    @field_validator("amount_total", "subtotal", "tax_total")
    @classmethod
    def normalize_totals(cls, value: Decimal | None) -> Decimal | None:
        """Quantize total-like amounts when present."""

        if value is None:
            return None
        return quantize_amount(value)

    @field_validator("primary_category_code")
    @classmethod
    def normalize_primary_category_code(cls, value: str | None) -> str | None:
        """Normalize extracted primary category code text."""

        if value is None:
            return None
        return value.strip().upper()
