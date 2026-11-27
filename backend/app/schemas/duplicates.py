"""Duplicate review contracts; all amounts retain their original currency."""

import datetime as dt
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.models.shared.enums import TransactionSource
from app.schemas.shared import Amount2DP, SchemaBase, UUIDTimestampSchema


class DuplicateTransactionRead(UUIDTimestampSchema):
    receipt_id: UUID | None
    merchant_name: str | None
    occurred_at: dt.datetime | None
    amount_total: Amount2DP | None
    currency: str
    source: TransactionSource
    status: str
    item_count: int = 0


class DuplicatePairRead(SchemaBase):
    first: DuplicateTransactionRead
    second: DuplicateTransactionRead
    confidence: Literal["exact", "high", "possible"]
    reasons: list[
        Literal[
            "same_image",
            "same_total",
            "same_date",
            "nearby_dates",
            "similar_merchant",
            "matching_items",
        ]
    ]
    matching_item_count: int = 0


class DuplicatePageRead(SchemaBase):
    items: list[DuplicatePairRead]
    page: int
    page_size: int
    has_more: bool


class DuplicatePairRequest(SchemaBase):
    first_transaction_id: UUID
    second_transaction_id: UUID


class DuplicateResolveRequest(SchemaBase):
    keep_transaction_id: UUID
    discard_transaction_id: UUID
    keep_updated_at: dt.datetime
    discard_updated_at: dt.datetime


class DuplicateResolveRead(SchemaBase):
    kept_transaction_id: UUID
    deleted_transaction_id: UUID


class DuplicateListFilter(SchemaBase):
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)
    transaction_id: UUID | None = None
