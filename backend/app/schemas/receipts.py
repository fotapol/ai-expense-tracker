"""Receipt ingestion and extraction read/write schemas."""

import datetime as dt
from typing import Any
from uuid import UUID

from pydantic import Field

from app.models.shared.enums import ReceiptStatus
from app.schemas.extraction import ExtractedReceiptData
from app.schemas.shared import Cost6DP, SchemaBase, UUIDTimestampSchema


class ReceiptCreate(SchemaBase):
    """Payload for creating receipt metadata before extraction starts."""

    storage_bucket: str = Field(min_length=1, max_length=128)
    storage_key: str = Field(min_length=1, max_length=512)
    mime_type: str = Field(min_length=1, max_length=100)
    original_filename: str = Field(min_length=1, max_length=255)
    sha256: str = Field(min_length=64, max_length=64)
    size_bytes: int = Field(ge=0)
    page_count: int | None = Field(default=None, ge=1)
    uploaded_at: dt.datetime | None = None


class ReceiptRead(UUIDTimestampSchema):
    """Read model for receipt metadata and processing status."""

    user_id: UUID
    status: ReceiptStatus
    storage_bucket: str
    storage_key: str
    mime_type: str
    original_filename: str
    sha256: str
    size_bytes: int
    page_count: int | None
    uploaded_at: dt.datetime | None
    failure_reason: str | None
    processing_attempt: int


class ReceiptStatusUpdate(SchemaBase):
    """Payload for changing receipt processing state."""

    status: ReceiptStatus
    failure_reason: str | None = Field(default=None, max_length=1000)
    processing_attempt: int | None = Field(default=None, ge=0)
    uploaded_at: dt.datetime | None = None


class ReceiptExtractionRead(UUIDTimestampSchema):
    """Read model for extraction metadata and parsed structured output."""

    receipt_id: UUID
    provider: str
    model_name: str
    structured_json: ExtractedReceiptData | dict[str, Any]
    raw_json: dict[str, Any] | None
    prompt_version: str | None
    cost_usd: Cost6DP | None
    latency_ms: int | None
