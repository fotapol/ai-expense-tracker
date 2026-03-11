"""Provider abstraction contracts for billing integration boundaries."""

import datetime as dt
import uuid
from abc import ABC, abstractmethod
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from app.models.shared.enums import SubscriptionProvider, SubscriptionStatus


@dataclass(slots=True)
class NormalizedSubscriptionEvent:
    """Provider-agnostic subscription event payload."""

    user_id: uuid.UUID
    provider: SubscriptionProvider
    product_id: str
    status: SubscriptionStatus
    started_at: dt.datetime | None = None
    expires_at: dt.datetime | None = None
    auto_renew: bool | None = None
    external_customer_id: str | None = None
    external_subscription_id: str | None = None
    external_purchase_id: str | None = None
    latest_event_at: dt.datetime | None = None
    raw_payload: dict[str, Any] | None = None
    internal_metadata: dict[str, Any] | None = None


class BillingProvider(ABC):
    """Contract for provider-specific payload normalization."""

    provider: SubscriptionProvider

    @abstractmethod
    def normalize_event(
        self,
        *,
        user_id: uuid.UUID,
        payload: Mapping[str, Any],
    ) -> NormalizedSubscriptionEvent:
        """Translate provider payload into normalized subscription event."""


class BillingEventHandler(ABC):
    """Contract for ingesting normalized provider payloads."""

    @abstractmethod
    def handle_provider_event(
        self,
        *,
        provider: BillingProvider,
        user_id: uuid.UUID,
        payload: Mapping[str, Any],
    ):
        """Handle one provider payload and update normalized state."""
