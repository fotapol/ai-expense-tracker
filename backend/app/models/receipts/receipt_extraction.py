import uuid
from decimal import Decimal
from typing import Any

from sqlalchemy import Column, Numeric
from sqlalchemy.dialects.postgresql import JSONB
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class ReceiptExtraction(TimestampedModel, table=True):
    """LLM extraction payload where structured JSON is validated and raw JSON preserves original provider output.

    `structured_json` is the canonical machine-readable result consumed by the app,
    while `raw_json` stores the unnormalized upstream payload for audits and debugging.
    """

    __tablename__ = "receipt_extractions"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    receipt_id: uuid.UUID = Field(
        nullable=False, unique=True, index=True, foreign_key="receipts.id"
    )

    provider: str = Field(max_length=64, nullable=False)
    model_name: str = Field(max_length=128, nullable=False)

    structured_json: dict[str, Any] = Field(sa_column=Column(JSONB, nullable=False))
    raw_json: dict[str, Any] | None = Field(default=None, sa_column=Column(JSONB, nullable=True))

    latency_ms: int | None = Field(default=None)
    cost_usd: Decimal | None = Field(default=None, sa_column=Column(Numeric(12, 6), nullable=True))
    prompt_version: str | None = Field(default=None, max_length=64)
