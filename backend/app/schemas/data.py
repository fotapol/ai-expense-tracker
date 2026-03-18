"""Data import and export schemas."""

import datetime as dt
from uuid import UUID

from pydantic import Field

from app.schemas.shared import SchemaBase


class CategoryExportData(SchemaBase):
    """Exportable category data."""

    id: UUID
    parent_id: UUID | None = None
    name: str = Field(max_length=64)
    code: str = Field(max_length=64)
    is_active: bool = True
    scope: str = Field(max_length=32)


class TransactionItemExportData(SchemaBase):
    """Exportable transaction item data."""

    id: UUID
    line_no: int
    description: str | None = None
    description_lang: str | None = None
    qty: float | None = None
    unit: str | None = None
    unit_price: float | None = None
    amount: float
    amount_before_discount: float | None = None
    discount_amount: float | None = None
    is_adjustment: bool = False
    category_id: UUID | None = None


class TransactionExportData(SchemaBase):
    """Exportable transaction data including line items."""

    id: UUID
    title: str | None = None
    merchant_name: str | None = None
    occurred_at: dt.datetime
    amount_total: float
    currency: str = Field(max_length=3)
    category_id: UUID | None = None
    notes: str | None = None
    # M-6: preserve owner attribution for export/import round-trips
    owner_user_id: UUID | None = None
    items: list[TransactionItemExportData] = Field(default_factory=list)


class DataExportPayload(SchemaBase):
    """Complete data export payload."""

    version: int = 1
    exported_at: dt.datetime
    categories: list[CategoryExportData] = Field(default_factory=list)
    transactions: list[TransactionExportData] = Field(default_factory=list)

class DataImportPayload(SchemaBase):
    """Payload to import data."""

    version: int | None = None
    exported_at: dt.datetime | None = None
    categories: list[CategoryExportData] = Field(default_factory=list)
    transactions: list[TransactionExportData] = Field(default_factory=list)
