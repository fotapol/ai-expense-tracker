from __future__ import annotations

import datetime as dt
import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.models.billing.webhook_event import BillingWebhookEvent
from app.services.billing import webhooks


class _Session:
    def __init__(self) -> None:
        self.events: list[BillingWebhookEvent] = []
        self.commit_calls = 0
        self.rollback_calls = 0

    def add(self, obj) -> None:
        if isinstance(obj, BillingWebhookEvent) and obj not in self.events:
            self.events.append(obj)

    def commit(self) -> None:
        self.commit_calls += 1

    def refresh(self, _obj) -> None:
        return None

    def rollback(self) -> None:
        self.rollback_calls += 1


def _payload(
    *,
    event_id: str = "evt_123",
    event_type: str = "RENEWAL",
    app_user_id: str = "firebase-user-1",
) -> dict:
    return {
        "event": {
            "id": event_id,
            "type": event_type,
            "app_user_id": app_user_id,
            "aliases": [],
            "event_timestamp_ms": int(dt.datetime.now(dt.UTC).timestamp() * 1000),
        }
    }


def _load_existing_event(session: _Session, *, provider: str, event_id: str):
    for event in session.events:
        if event.provider == provider and event.event_id == event_id:
            return event
    return None


def test_validate_revenuecat_webhook_auth_requires_matching_secret(monkeypatch) -> None:
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH_SECRET", "expected-secret")
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH_HEADER", "Authorization")

    with pytest.raises(HTTPException) as exc_info:
        webhooks.validate_revenuecat_webhook_auth(headers={"Authorization": "wrong-secret"})

    assert exc_info.value.status_code == 403


@pytest.mark.anyio
async def test_process_revenuecat_webhook_processes_once_and_then_deduplicates(monkeypatch) -> None:
    session = _Session()

    async def _fake_sync(*, session, user_id, app_user_id):
        assert app_user_id == "firebase-user-1"
        return SimpleNamespace(id=user_id)

    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH_SECRET", "expected-secret")
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH_HEADER", "Authorization")
    monkeypatch.setattr(webhooks, "_load_existing_event", _load_existing_event)
    monkeypatch.setattr(
        webhooks,
        "_resolve_user_by_auth_subjects",
        lambda _session, *, auth_subjects: SimpleNamespace(
            id=uuid.uuid4(),
            auth_subject=auth_subjects[0],
        ),
    )
    monkeypatch.setattr(webhooks, "sync_revenuecat_subscription", _fake_sync)

    first = await webhooks.process_revenuecat_webhook(
        session=session,
        payload=_payload(),
        headers={"Authorization": "expected-secret"},
    )
    second = await webhooks.process_revenuecat_webhook(
        session=session,
        payload=_payload(),
        headers={"Authorization": "expected-secret"},
    )

    assert first["status"] == "processed"
    assert second["status"] == "duplicate"
    assert len(session.events) == 1
    assert session.events[0].status == "processed"
    assert session.events[0].processed_at is not None


@pytest.mark.anyio
async def test_process_revenuecat_webhook_ignores_unknown_user(monkeypatch) -> None:
    session = _Session()

    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH_SECRET", "expected-secret")
    monkeypatch.setenv("REVENUECAT_WEBHOOK_AUTH_HEADER", "Authorization")
    monkeypatch.setattr(webhooks, "_load_existing_event", _load_existing_event)
    monkeypatch.setattr(
        webhooks,
        "_resolve_user_by_auth_subjects",
        lambda _session, *, auth_subjects: None,
    )

    result = await webhooks.process_revenuecat_webhook(
        session=session,
        payload=_payload(app_user_id="missing-user"),
        headers={"Authorization": "expected-secret"},
    )

    assert result["status"] == "ignored"
    assert len(session.events) == 1
    assert session.events[0].status == "ignored"
    assert "No local user matched" in (session.events[0].last_error or "")
