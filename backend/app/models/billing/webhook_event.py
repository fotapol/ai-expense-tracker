"""Billing webhook delivery records for idempotency and operator visibility."""

from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import Column, DateTime, Index, Integer, String, UniqueConstraint
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class BillingWebhookEvent(TimestampedModel, table=True):
    """Persisted webhook event receipt and processing status."""

    __tablename__ = "billing_webhook_events"
    __table_args__ = (
        UniqueConstraint("provider", "event_id", name="uq_billing_webhook_events_provider_event"),
        Index("ix_billing_webhook_events_status", "status"),
        Index("ix_billing_webhook_events_app_user_id", "app_user_id"),
        Index("ix_billing_webhook_events_processed_at", "processed_at"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    provider: str = Field(sa_column=Column(String(32), nullable=False))
    event_id: str = Field(sa_column=Column(String(255), nullable=False))
    event_type: str = Field(sa_column=Column(String(128), nullable=False))
    app_user_id: str | None = Field(default=None, sa_column=Column(String(255), nullable=True))
    status: str = Field(sa_column=Column(String(64), nullable=False))
    delivery_attempts: int = Field(default=1, sa_column=Column(Integer, nullable=False, default=1))
    processed_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )
    last_error: str | None = Field(default=None, sa_column=Column(String(500), nullable=True))
