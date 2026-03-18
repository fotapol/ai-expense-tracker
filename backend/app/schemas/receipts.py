"""Receipt ingestion and extraction read/write schemas."""

import datetime as dt
from typing import Any
from uuid import UUID

from pydantic import Field

from app.models.shared.enums import ReceiptStatus
from app.schemas.extraction import ExtractedReceiptData
from app.schemas.shared import Cost6DP, SchemaBase, UUIDTimestampSchema


class ReceiptCreateRequest(SchemaBase):
    """Client payload for initiating a receipt upload.

    The server generates ``storage_bucket`` and ``storage_key``
    internally — clients only provide content metadata.
    """

    mime_type: str = Field(min_length=1, max_length=100)
    original_filename: str | None = Field(default=None, max_length=255)
    size_bytes: int | None = Field(default=None, ge=0)
    sha256: str | None = Field(default=None, min_length=64, max_length=64)


class ReceiptCreateResponse(SchemaBase):
    """Returned after creating a receipt — contains the presigned upload URL."""

    receipt_id: UUID
    storage_bucket: str
    storage_key: str
    upload_url: str
    required_headers: dict[str, str]


class ReceiptConfirmResponse(SchemaBase):
    """Returned after confirming a receipt upload."""

    receipt_id: UUID
    status: ReceiptStatus


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
    transaction_id: UUID | None = None


class ReceiptViewUrlResponse(SchemaBase):
    """Short-lived receipt file URL for previewing the uploaded artifact."""

    receipt_id: UUID
    view_url: str
    mime_type: str
    original_filename: str


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
