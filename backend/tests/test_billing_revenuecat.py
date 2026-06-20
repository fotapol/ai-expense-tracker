import datetime as dt
import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.models.shared.enums import SubscriptionStatus
from app.services.billing.revenuecat import (
    RevenueCatProvider,
    sync_revenuecat_subscription_for_user,
)


def _payload_with_entitlement(
    *,
    expires_date: str,
    purchase_date: str = "2026-03-01T00:00:00Z",
    unsubscribe_detected_at: str | None = None,
    billing_issues_detected_at: str | None = None,
) -> dict:
    entitlement = {
        "product_identifier": "pro.monthly",
        "purchase_date": purchase_date,
        "expires_date": expires_date,
        "store_transaction_id": "txn-1",
    }
    if unsubscribe_detected_at is not None:
        entitlement["unsubscribe_detected_at"] = unsubscribe_detected_at
    if billing_issues_detected_at is not None:
        entitlement["billing_issues_detected_at"] = billing_issues_detected_at

    return {
        "request_date": "2026-03-10T10:00:00Z",
        "subscriber": {
            "original_app_user_id": "firebase-uid-1",
            "entitlements": {
                "personal_premium": entitlement,
            },
            "subscriptions": {
                "pro.monthly": {
                    "purchase_date": purchase_date,
                    "expires_date": expires_date,
                }
            },
        },
    }


def test_revenuecat_provider_maps_active_entitlement() -> None:
    provider = RevenueCatProvider(premium_entitlement_id="personal_premium")
    event = provider.normalize_event(
        user_id=uuid.uuid4(),
        payload=_payload_with_entitlement(expires_date="2099-03-10T10:00:00Z"),
    )
    assert event.status == SubscriptionStatus.ACTIVE
    assert event.product_id == "personal_premium"
    assert event.raw_payload is not None
    assert event.internal_metadata is None


def test_revenuecat_provider_maps_cancelled_with_future_expiry() -> None:
    provider = RevenueCatProvider(premium_entitlement_id="personal_premium")
    event = provider.normalize_event(
        user_id=uuid.uuid4(),
        payload=_payload_with_entitlement(
            expires_date="2099-03-10T10:00:00Z",
            unsubscribe_detected_at="2026-03-09T00:00:00Z",
        ),
    )
    assert event.status == SubscriptionStatus.CANCELLED


def test_revenuecat_provider_maps_grace_period() -> None:
    provider = RevenueCatProvider(premium_entitlement_id="personal_premium")
    event = provider.normalize_event(
        user_id=uuid.uuid4(),
        payload=_payload_with_entitlement(
            expires_date="2099-03-10T10:00:00Z",
            billing_issues_detected_at="2026-03-09T00:00:00Z",
        ),
    )
    assert event.status == SubscriptionStatus.GRACE_PERIOD


def test_revenuecat_provider_maps_expired_entitlement() -> None:
    provider = RevenueCatProvider(premium_entitlement_id="personal_premium")
    event = provider.normalize_event(
        user_id=uuid.uuid4(),
        payload=_payload_with_entitlement(expires_date="2020-03-10T10:00:00Z"),
    )
    assert event.status == SubscriptionStatus.EXPIRED


def test_revenuecat_provider_falls_back_to_subscription_entry_status_when_entitlement_missing() -> None:
    provider = RevenueCatProvider(premium_entitlement_id="different_entitlement_id")
    event = provider.normalize_event(
        user_id=uuid.uuid4(),
        payload={
            "request_date": "2026-03-10T10:00:00Z",
            "subscriber": {
                "original_app_user_id": "firebase-uid-1",
                "entitlements": {},
                "subscriptions": {
                    "pro.monthly": {
                        "purchase_date": "2026-03-01T00:00:00Z",
                        "expires_date": "2099-03-10T10:00:00Z",
                    }
                },
            },
        },
    )
    assert event.status == SubscriptionStatus.ACTIVE


def test_revenuecat_provider_normalize_events_emits_single_premium_row() -> None:
    provider = RevenueCatProvider(
        premium_entitlement_id="personal_premium",
        personal_product_ids={"individual_plan_monthly", "individual_plan_yearly"},
    )

    events = provider.normalize_events(
        user_id=uuid.uuid4(),
        payload={
            "request_date": "2026-03-10T10:00:00Z",
            "subscriber": {
                "original_app_user_id": "firebase-uid-1",
                "entitlements": {
                    "personal_premium": {
                        "product_identifier": "individual_plan_monthly",
                        "purchase_date": "2026-03-01T00:00:00Z",
                        "expires_date": "2099-03-10T10:00:00Z",
                        "store_transaction_id": "personal-txn-1",
                    },
                },
                "subscriptions": {
                    "individual_plan_monthly": {
                        "purchase_date": "2026-03-01T00:00:00Z",
                        "expires_date": "2099-03-10T10:00:00Z",
                    },
                },
            },
        },
    )

    assert [event.product_id for event in events] == ["personal_premium"]


@pytest.mark.anyio
async def test_sync_revenuecat_requires_secret_key(monkeypatch) -> None:
    monkeypatch.setenv("REVENUECAT_SECRET_API_KEY", "")
    with pytest.raises(HTTPException) as exc_info:
        await sync_revenuecat_subscription_for_user(
            session=object(),
            current_user=SimpleNamespace(id=uuid.uuid4(), auth_subject="uid-1"),
        )
    assert exc_info.value.status_code == 503


@pytest.mark.anyio
async def test_sync_revenuecat_uses_sync_service(monkeypatch) -> None:
    fake_subscription = SimpleNamespace(
        status=SubscriptionStatus.ACTIVE,
        expires_at=dt.datetime(2099, 1, 1, tzinfo=dt.UTC),
    )

    class FakeClient:
        def __init__(self, **kwargs):
            pass

        async def fetch_subscriber_payload(self, *, app_user_id: str):
            return _payload_with_entitlement(expires_date="2099-03-10T10:00:00Z")

    class FakeSyncService:
        def __init__(self, _session):
            pass

        def handle_provider_event(self, *, provider, user_id, payload):
            return fake_subscription

    monkeypatch.setenv("REVENUECAT_SECRET_API_KEY", "secret")
    monkeypatch.setattr("app.services.billing.revenuecat.RevenueCatClient", FakeClient)
    monkeypatch.setattr("app.services.billing.revenuecat.SubscriptionSyncService", FakeSyncService)

    result = await sync_revenuecat_subscription_for_user(
        session=object(),
        current_user=SimpleNamespace(id=uuid.uuid4(), auth_subject="uid-1"),
    )
    assert result is fake_subscription
