"""RevenueCat client and normalization helpers for subscription sync."""

from __future__ import annotations

import datetime as dt
import os
import uuid
from collections.abc import Mapping
from typing import Any
from urllib.parse import quote

import httpx
from fastapi import HTTPException, status
from sqlmodel import Session

from app.models.shared.enums import SubscriptionProvider, SubscriptionStatus
from app.models.users.user import User
from app.services.billing.contracts import BillingProvider, NormalizedSubscriptionEvent
from app.services.billing.features import (
    FAMILY_PREMIUM_PRODUCT_ID,
    PERSONAL_PREMIUM_PRODUCT_ID,
)
from app.services.billing.subscriptions import SubscriptionSyncService


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _parse_datetime(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw:
        return None
    if raw.endswith("Z"):
        raw = f"{raw[:-1]}+00:00"
    try:
        parsed = dt.datetime.fromisoformat(raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.UTC)
    return parsed.astimezone(dt.UTC)


def _to_mapping(value: Any) -> dict[str, Any]:
    if isinstance(value, Mapping):
        return dict(value)
    return {}


def _get_env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


def _parse_csv_values(value: str) -> set[str]:
    return {
        part.strip().lower()
        for part in value.split(",")
        if part.strip()
    }


def _get_env_csv(name: str, default_values: set[str]) -> set[str]:
    raw = _get_env(name)
    if not raw:
        return {entry.strip().lower() for entry in default_values if entry.strip()}
    parsed = _parse_csv_values(raw)
    if not parsed:
        return {entry.strip().lower() for entry in default_values if entry.strip()}
    return parsed


def _resolve_latest_event_at(payload: Mapping[str, Any], now: dt.datetime) -> dt.datetime:
    request_date = _parse_datetime(payload.get("request_date"))
    if request_date is not None:
        return request_date
    subscriber = _to_mapping(payload.get("subscriber"))
    return (
        _parse_datetime(subscriber.get("last_seen"))
        or _parse_datetime(subscriber.get("first_seen"))
        or now
    )


def _select_latest_subscription_entry(subscriber: Mapping[str, Any]) -> tuple[str | None, dict[str, Any]]:
    subscriptions = _to_mapping(subscriber.get("subscriptions"))
    best_key: str | None = None
    best_entry: dict[str, Any] = {}
    best_expires = dt.datetime.min.replace(tzinfo=dt.UTC)
    best_purchase = dt.datetime.min.replace(tzinfo=dt.UTC)
    for product_key, raw_entry in subscriptions.items():
        entry = _to_mapping(raw_entry)
        expires_at = _parse_datetime(entry.get("expires_date")) or dt.datetime.min.replace(
            tzinfo=dt.UTC
        )
        purchase_at = _parse_datetime(entry.get("purchase_date")) or dt.datetime.min.replace(
            tzinfo=dt.UTC
        )
        if (expires_at, purchase_at, str(product_key)) >= (best_expires, best_purchase, str(best_key)):
            best_key = str(product_key)
            best_entry = entry
            best_expires = expires_at
            best_purchase = purchase_at
    return best_key, best_entry


def _resolve_entitlement_status(
    *,
    now: dt.datetime,
    expires_at: dt.datetime | None,
    billing_issues_detected_at: dt.datetime | None,
    unsubscribe_detected_at: dt.datetime | None,
) -> SubscriptionStatus:
    if expires_at is None or expires_at <= now:
        return SubscriptionStatus.EXPIRED
    if billing_issues_detected_at is not None:
        return SubscriptionStatus.GRACE_PERIOD
    if unsubscribe_detected_at is not None:
        return SubscriptionStatus.CANCELLED
    return SubscriptionStatus.ACTIVE


def _resolve_subscription_entry_status(
    *,
    now: dt.datetime,
    entry: Mapping[str, Any],
    expires_at: dt.datetime | None,
) -> SubscriptionStatus:
    billing_issues_detected_at = _parse_datetime(entry.get("billing_issues_detected_at"))
    unsubscribe_detected_at = _parse_datetime(entry.get("unsubscribe_detected_at"))
    return _resolve_entitlement_status(
        now=now,
        expires_at=expires_at,
        billing_issues_detected_at=billing_issues_detected_at,
        unsubscribe_detected_at=unsubscribe_detected_at,
    )


class RevenueCatProvider(BillingProvider):
    """Normalize RevenueCat customer payloads into current-state subscription events."""

    provider = SubscriptionProvider.REVENUECAT

    def __init__(
        self,
        *,
        premium_entitlement_id: str,
        family_premium_entitlement_id: str = FAMILY_PREMIUM_PRODUCT_ID,
        personal_product_ids: set[str] | None = None,
        family_product_ids: set[str] | None = None,
    ):
        self.premium_entitlement_id = premium_entitlement_id
        self.family_premium_entitlement_id = family_premium_entitlement_id
        self.personal_product_ids = {
            entry.strip().lower()
            for entry in (personal_product_ids or {PERSONAL_PREMIUM_PRODUCT_ID})
            if entry.strip()
        } | {PERSONAL_PREMIUM_PRODUCT_ID}
        self.family_product_ids = {
            entry.strip().lower()
            for entry in (family_product_ids or {FAMILY_PREMIUM_PRODUCT_ID})
            if entry.strip()
        } | {FAMILY_PREMIUM_PRODUCT_ID}

    def _normalize_product_id(self, external_product_id: str | None) -> str:
        normalized_external_product_id = (external_product_id or "").strip().lower()
        if normalized_external_product_id in self.family_product_ids:
            return FAMILY_PREMIUM_PRODUCT_ID
        if normalized_external_product_id in self.personal_product_ids:
            return PERSONAL_PREMIUM_PRODUCT_ID
        return PERSONAL_PREMIUM_PRODUCT_ID

    def normalize_event(
        self,
        *,
        user_id: uuid.UUID,
        payload: Mapping[str, Any],
    ) -> NormalizedSubscriptionEvent:
        now = _utcnow()
        subscriber = _to_mapping(payload.get("subscriber"))
        entitlements = _to_mapping(subscriber.get("entitlements"))
        personal_entitlement = _to_mapping(entitlements.get(self.premium_entitlement_id))
        family_entitlement = _to_mapping(entitlements.get(self.family_premium_entitlement_id))
        entitlement = family_entitlement or personal_entitlement

        latest_product_key, latest_subscription_entry = _select_latest_subscription_entry(subscriber)

        started_at = _parse_datetime(entitlement.get("purchase_date"))
        if started_at is None:
            started_at = _parse_datetime(latest_subscription_entry.get("purchase_date"))
        expires_at = _parse_datetime(entitlement.get("expires_date"))
        if expires_at is None:
            expires_at = _parse_datetime(latest_subscription_entry.get("expires_date"))
        billing_issues_detected_at = _parse_datetime(entitlement.get("billing_issues_detected_at"))
        unsubscribe_detected_at = _parse_datetime(entitlement.get("unsubscribe_detected_at"))
        if unsubscribe_detected_at is None:
            unsubscribe_detected_at = _parse_datetime(
                latest_subscription_entry.get("unsubscribe_detected_at")
            )

        if entitlement:
            status_value = _resolve_entitlement_status(
                now=now,
                expires_at=expires_at,
                billing_issues_detected_at=billing_issues_detected_at,
                unsubscribe_detected_at=unsubscribe_detected_at,
            )
        elif latest_subscription_entry:
            status_value = _resolve_subscription_entry_status(
                now=now,
                entry=latest_subscription_entry,
                expires_at=expires_at,
            )
        else:
            status_value = SubscriptionStatus.EXPIRED

        external_subscription_id = (
            entitlement.get("store_transaction_id")
            or latest_subscription_entry.get("store_transaction_id")
            or latest_subscription_entry.get("transaction_id")
        )
        external_purchase_id = (
            entitlement.get("product_identifier")
            or latest_subscription_entry.get("product_identifier")
            or latest_product_key
        )
        normalized_product_id = self._normalize_product_id(
            str(external_purchase_id).strip() if external_purchase_id else None
        )
        if family_entitlement:
            normalized_product_id = FAMILY_PREMIUM_PRODUCT_ID
        elif personal_entitlement:
            normalized_product_id = PERSONAL_PREMIUM_PRODUCT_ID

        auto_renew = None
        if status_value in {
            SubscriptionStatus.ACTIVE,
            SubscriptionStatus.GRACE_PERIOD,
            SubscriptionStatus.CANCELLED,
        }:
            auto_renew = status_value != SubscriptionStatus.CANCELLED

        return NormalizedSubscriptionEvent(
            user_id=user_id,
            provider=self.provider,
            product_id=normalized_product_id,
            status=status_value,
            started_at=started_at,
            expires_at=expires_at,
            auto_renew=auto_renew,
            external_customer_id=(
                subscriber.get("original_app_user_id")
                or subscriber.get("app_user_id")
                or None
            ),
            external_subscription_id=(
                str(external_subscription_id).strip() if external_subscription_id else None
            ),
            external_purchase_id=(
                str(external_purchase_id).strip() if external_purchase_id else None
            ),
            latest_event_at=_resolve_latest_event_at(payload, now),
            raw_payload=dict(payload),
            internal_metadata=None,
        )


class RevenueCatClient:
    """Thin HTTP client for RevenueCat v1 subscriber API."""

    def __init__(
        self,
        *,
        secret_api_key: str,
        base_url: str = "https://api.revenuecat.com",
        timeout_seconds: float = 8.0,
    ):
        self.secret_api_key = secret_api_key.strip()
        self.base_url = base_url.rstrip("/")
        self.timeout_seconds = timeout_seconds

    async def fetch_subscriber_payload(self, *, app_user_id: str) -> dict[str, Any]:
        if not self.secret_api_key:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="RevenueCat secret API key is not configured on backend.",
            )
        encoded_user_id = quote(app_user_id, safe="")
        url = f"{self.base_url}/v1/subscribers/{encoded_user_id}"
        headers = {
            "Authorization": f"Bearer {self.secret_api_key}",
            "Accept": "application/json",
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                response = await client.get(
                    url,
                    headers=headers,
                )
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"RevenueCat API error: {exc.response.status_code}.",
            ) from exc
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Failed to reach RevenueCat API.",
            ) from exc

        payload = response.json()
        if not isinstance(payload, Mapping):
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="RevenueCat API returned an invalid payload.",
            )
        return dict(payload)


async def sync_revenuecat_subscription_for_user(
    *,
    session: Session,
    current_user: User,
) -> Any:
    """Fetch RevenueCat state and synchronize normalized subscription + entitlements."""

    app_user_id = (current_user.auth_subject or "").strip()
    if not app_user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current user does not have a valid auth subject for RevenueCat sync.",
        )

    timeout_raw = _get_env("REVENUECAT_HTTP_TIMEOUT_SECONDS", "8")
    try:
        timeout_seconds = float(timeout_raw)
    except ValueError:
        timeout_seconds = 8.0
    client = RevenueCatClient(
        secret_api_key=_get_env("REVENUECAT_SECRET_API_KEY"),
        base_url=_get_env("REVENUECAT_API_BASE_URL", "https://api.revenuecat.com"),
        timeout_seconds=max(timeout_seconds, 1.0),
    )
    payload = await client.fetch_subscriber_payload(app_user_id=app_user_id)

    provider = RevenueCatProvider(
        premium_entitlement_id=_get_env(
            "REVENUECAT_PERSONAL_PREMIUM_ENTITLEMENT_ID",
            PERSONAL_PREMIUM_PRODUCT_ID,
        )
        or PERSONAL_PREMIUM_PRODUCT_ID,
        family_premium_entitlement_id=_get_env(
            "REVENUECAT_FAMILY_PREMIUM_ENTITLEMENT_ID",
            FAMILY_PREMIUM_PRODUCT_ID,
        )
        or FAMILY_PREMIUM_PRODUCT_ID,
        personal_product_ids=_get_env_csv(
            "REVENUECAT_PERSONAL_PRODUCT_IDS",
            {PERSONAL_PREMIUM_PRODUCT_ID},
        ),
        family_product_ids=_get_env_csv(
            "REVENUECAT_FAMILY_PRODUCT_IDS",
            {FAMILY_PREMIUM_PRODUCT_ID},
        ),
    )
    sync_service = SubscriptionSyncService(session)
    return sync_service.handle_provider_event(
        provider=provider,
        user_id=current_user.id,
        payload=payload,
    )
