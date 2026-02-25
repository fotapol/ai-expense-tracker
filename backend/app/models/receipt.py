import datetime
import uuid
from enum import Enum

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class StatusEnum(Enum):
    CREATED=1
    UPLOADED=2
    PROCESSING=3
    DONE=4
    FAILED=5


class ReceiptBase(SQLModel):
    pass

class Receipt(ReceiptBase, table=True):
    id: uuid.UUID | None = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False)
    status: StatusEnum = Field(default=StatusEnum.CREATED)
    storage_bucket: str | None = Field(default=None)
    storage_key: str | None = Field(default=None)
    mime_type: str | None = Field(default=None, max_length=100)
    original_filename: str | None = Field(default=None, nullable=True)
    page_count: int | None = Field(default=None, nullable=True)
    size_bytes: int | None = Field(default=None, nullable=True)
    failure_reason: str | None = Field(default=None, nullable=True)
    processing_attempt: int = Field(default=0)
    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
    updated_at: datetime.datetime = Field(
        sa_column=Column(
            DateTime(timezone=True), default=func.now(), onupdate=func.now(), nullable=False
        )
    )
