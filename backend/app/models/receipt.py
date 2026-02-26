import datetime
import uuid
from enum import Enum

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class ReceiptStatus(str, Enum):
    """High-level receipt processing status."""

    CREATED = "CREATED"
    UPLOADED = "UPLOADED"
    PROCESSING = "PROCESSING"
    DONE = "DONE"
    FAILED = "FAILED"


class ReceiptBase(SQLModel):
    """Shared fields for Receipt models.

    Receipt represents a stored file (image/PDF) and its processing lifecycle,
    not a financial record.
    """

    storage_bucket: str | None = Field(default=None, max_length=128)
    storage_key: str | None = Field(default=None, max_length=512)
    mime_type: str | None = Field(default=None, max_length=100)
    original_filename: str | None = Field(default=None, max_length=255)

    page_count: int | None = Field(default=None)
    size_bytes: int | None = Field(default=None)

    failure_reason: str | None = Field(default=None, max_length=500)
    processing_attempt: int = Field(default=0)


class Receipt(ReceiptBase, table=True):
    """Receipt file metadata and processing state.

    Receipt tracks the uploaded file location in object storage (MinIO/S3) and
    the async processing status (LLM extraction job).
    """

    __tablename__ = "receipts"

    id: uuid.UUID | None = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False)

    status: ReceiptStatus = Field(
        default=ReceiptStatus.CREATED,
        sa_column=Column(SAEnum(ReceiptStatus, name="receipt_status", native_enum=False), nullable=False),
    )

    sha256: str | None = Field(default=None, max_length=64, index=True)
    uploaded_at: datetime.datetime | None = Field(
        default=None, sa_column=Column(DateTime(timezone=True), nullable=True)
    )

    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
    updated_at: datetime.datetime = Field(
        sa_column=Column(
            DateTime(timezone=True), default=func.now(), onupdate=func.now(), nullable=False
        )
    )
