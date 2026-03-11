"""Schemas for subscription and entitlement API endpoints."""

import datetime as dt
from typing import Literal
from uuid import UUID

from pydantic import Field

from app.models.shared.enums import SubscriptionProvider, SubscriptionStatus
from app.schemas.shared import SchemaBase, UUIDTimestampSchema
from app.services.billing.features import PERSONAL_PREMIUM_PRODUCT_ID


class SubscriptionRead(UUIDTimestampSchema):
    """Normalized effective subscription payload for the API."""

    user_id: UUID
    provider: SubscriptionProvider
    product_id: str
    status: SubscriptionStatus
    started_at: dt.datetime | None
    expires_at: dt.datetime | None
    auto_renew: bool | None
    latest_event_at: dt.datetime | None
    external_customer_id: str | None
    external_subscription_id: str | None
    external_purchase_id: str | None


class ReceiptScanUsageRead(SchemaBase):
    """Receipt scan usage limits for the current plan."""

    used: int
    limit: int | None
    remaining: int | None
    is_unlimited: bool
    period_start_at: dt.datetime
    period_end_at: dt.datetime


class MeSubscriptionResponse(SchemaBase):
    """Current user subscription summary response."""

    has_active_subscription: bool
    subscription: SubscriptionRead | None
    receipt_scan_usage: ReceiptScanUsageRead


class MeEntitlementsResponse(SchemaBase):
    """Active feature-code list for current user."""

    feature_codes: list[str]


class DevSubscriptionActionRequest(SchemaBase):
    """Dev-only manual subscription simulation payload."""

    target_user_id: UUID
    action: Literal["activate", "expire", "revoke"]
    product_id: str = Field(default=PERSONAL_PREMIUM_PRODUCT_ID, min_length=1, max_length=128)
    expires_at: dt.datetime | None = None
    reason: str | None = Field(default=None, max_length=500)


class DevSubscriptionActionResponse(SchemaBase):
    """Dev-only manual subscription simulation response."""

    target_user_id: UUID
    has_active_subscription: bool
    subscription: SubscriptionRead | None
    feature_codes: list[str]


class RevenueCatSyncResponse(SchemaBase):
    """RevenueCat sync response after normalized subscription refresh."""

    has_active_subscription: bool
    subscription: SubscriptionRead | None
    feature_codes: list[str]
    receipt_scan_usage: ReceiptScanUsageRead
