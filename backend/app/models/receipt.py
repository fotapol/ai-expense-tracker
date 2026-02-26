import datetime
import uuid

from sqlalchemy import Column, DateTime
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.enums import ReceiptStatus
from app.models.timestamps import TimestampedModel


class ReceiptBase(SQLModel):
    """Base metadata fields for an uploaded receipt file in object storage."""

    storage_bucket: str = Field(max_length=128, nullable=False)
    storage_key: str = Field(max_length=512, nullable=False)
    mime_type: str = Field(max_length=100, nullable=False)
    original_filename: str = Field(max_length=255, nullable=False)
    sha256: str = Field(max_length=64, nullable=False, index=True)
    size_bytes: int = Field(nullable=False)

    page_count: int | None = Field(default=None)
    uploaded_at: datetime.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True, index=True),
    )
    failure_reason: str | None = Field(default=None, max_length=1000)
    processing_attempt: int = Field(default=0, nullable=False)


class Receipt(ReceiptBase, TimestampedModel, table=True):
    """Stored receipt object tracked through asynchronous extraction lifecycle."""

    __tablename__ = "receipts"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(nullable=False, index=True, foreign_key="users.id")

    status: ReceiptStatus = Field(
        default=ReceiptStatus.CREATED,
        sa_column=Column(
            SAEnum(ReceiptStatus, name="receipt_status", native_enum=False),
            nullable=False,
            default=ReceiptStatus.CREATED,
        ),
    )
