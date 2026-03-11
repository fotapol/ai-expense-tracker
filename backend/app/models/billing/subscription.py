"""Normalized subscription model used by backend entitlement logic."""

import datetime as dt
import uuid
from typing import Any

from sqlalchemy import Boolean, Column, DateTime, Index, String, UniqueConstraint
from sqlalchemy import Enum as SAEnum
from sqlalchemy.dialects.postgresql import JSONB
from sqlmodel import Field, SQLModel

from app.models.shared.enums import SubscriptionProvider, SubscriptionStatus
from app.models.shared.timestamps import TimestampedModel


class SubscriptionBase(SQLModel):
    """Provider-agnostic current-state subscription fields.

    ``expires_at`` is the timestamp until which premium entitlement remains valid.
    """

    provider: SubscriptionProvider = Field(
        sa_column=Column(
            SAEnum(SubscriptionProvider, name="subscription_provider", native_enum=False),
            nullable=False,
        ),
    )
    product_id: str = Field(sa_column=Column(String(128), nullable=False))
    status: SubscriptionStatus = Field(
        sa_column=Column(
            SAEnum(SubscriptionStatus, name="subscription_status", native_enum=False),
            nullable=False,
        ),
    )
    started_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )
    expires_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )
    auto_renew: bool | None = Field(
        default=None,
        sa_column=Column(Boolean, nullable=True),
    )
    external_customer_id: str | None = Field(
        default=None,
        sa_column=Column(String(255), nullable=True),
    )
    external_subscription_id: str | None = Field(
        default=None,
        sa_column=Column(String(255), nullable=True),
    )
    external_purchase_id: str | None = Field(
        default=None,
        sa_column=Column(String(255), nullable=True),
    )
    latest_event_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )
    raw_payload: dict[str, Any] | None = Field(
        default=None,
        sa_column=Column(JSONB, nullable=True),
    )
    internal_metadata: dict[str, Any] | None = Field(
        default=None,
        sa_column=Column(JSONB, nullable=True),
    )


class Subscription(SubscriptionBase, TimestampedModel, table=True):
    """Current normalized subscription state for a purchasing user."""

    __tablename__ = "subscriptions"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "provider",
            "product_id",
            name="uq_subscriptions_user_provider_product",
        ),
        Index("ix_subscriptions_user_status_expires_at", "user_id", "status", "expires_at"),
        Index("ix_subscriptions_user_latest_event_at", "user_id", "latest_event_at"),
        Index("ix_subscriptions_external_subscription_id", "external_subscription_id"),
        Index("ix_subscriptions_external_purchase_id", "external_purchase_id"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")
