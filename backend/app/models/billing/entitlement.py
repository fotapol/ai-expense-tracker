"""Entitlement rows used for feature access checks."""

import datetime as dt
import uuid

from sqlalchemy import Column, DateTime, Index, String
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.shared.enums import EntitlementScopeType, EntitlementStatus
from app.models.shared.timestamps import TimestampedModel


class EntitlementBase(SQLModel):
    """Feature-access record scoped to an actor such as a user."""

    scope_type: EntitlementScopeType = Field(
        sa_column=Column(
            SAEnum(EntitlementScopeType, name="entitlement_scope_type", native_enum=False),
            nullable=False,
        )
    )
    scope_id: uuid.UUID = Field(nullable=False)
    feature_code: str = Field(sa_column=Column(String(128), nullable=False))
    status: EntitlementStatus = Field(
        sa_column=Column(
            SAEnum(EntitlementStatus, name="entitlement_status", native_enum=False),
            nullable=False,
        )
    )
    starts_at: dt.datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
    expires_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )


class Entitlement(EntitlementBase, TimestampedModel, table=True):
    """Normalized entitlement state used as source of truth for premium checks."""

    __tablename__ = "entitlements"
    __table_args__ = (
        Index(
            "ix_entitlements_scope_status_window",
            "scope_type",
            "scope_id",
            "status",
            "starts_at",
            "expires_at",
        ),
        Index(
            "ix_entitlements_scope_feature_status",
            "scope_type",
            "scope_id",
            "feature_code",
            "status",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    source_subscription_id: uuid.UUID | None = Field(
        default=None,
        index=True,
        foreign_key="subscriptions.id",
    )
