import datetime
import uuid
from decimal import Decimal

from sqlalchemy import Column, DateTime, Enum as SAEnum, Numeric, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class ReceiptExtraction(SQLModel, table=True):
    """Structured extraction result produced by an LLM.

    Stores both the validated structured JSON (matching your Pydantic schema)
    and the raw provider response for debugging.
    """

    __tablename__ = "receipt_extractions"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    receipt_id: uuid.UUID = Field(
        nullable=False, unique=True, index=True, foreign_key="receipts.id"
    )

    provider: str = Field(max_length=64, nullable=False)
    model_name: str = Field(max_length=128, nullable=False)

    structured_json: dict = Field(sa_column=Column(JSONB, nullable=False))
    raw_json: dict | None = Field(default=None, sa_column=Column(JSONB, nullable=True))

    latency_ms: int | None = Field(default=None)
    cost_usd: Decimal | None = Field(
        default=None, sa_column=Column(Numeric(12, 6), nullable=True)
    )
    prompt_version: str | None = Field(default=None, max_length=64)

    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
