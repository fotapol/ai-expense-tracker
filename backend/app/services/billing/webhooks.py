"""RevenueCat webhook validation, idempotency, and sync orchestration."""

from __future__ import annotations

import datetime as dt
import logging
import secrets
from collections.abc import Mapping, Sequence
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.core.config import billing_settings
from app.core.metrics import record_revenuecat_webhook_event
from app.models.billing.webhook_event import BillingWebhookEvent
from app.models.users.user import User
from app.services.billing.revenuecat import sync_revenuecat_subscription

logger = logging.getLogger(__name__)


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def _as_mapping(value: Any) -> dict[str, Any]:
    if isinstance(value, Mapping):
        return dict(value)
    return {}


def _coerce_event(payload: Mapping[str, Any]) -> dict[str, Any]:
    event = payload.get("event")
    if isinstance(event, Mapping):
        return dict(event)
    return dict(payload)


def _clean_str(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip()


def _extract_app_user_candidates(event: Mapping[str, Any]) -> list[str]:
    candidates: list[str] = []
    for key in ("app_user_id", "original_app_user_id"):
        value = _clean_str(event.get(key))
        if value and value not in candidates:
            candidates.append(value)

    aliases = event.get("aliases")
    if isinstance(aliases, Sequence) and not isinstance(aliases, str):
        for raw_alias in aliases:
            alias = _clean_str(raw_alias)
            if alias and alias not in candidates:
                candidates.append(alias)
    return candidates


def _event_status_code(status_value: str) -> int:
    return status.HTTP_200_OK if status_value in {"processed", "duplicate", "ignored", "test"} else status.HTTP_202_ACCEPTED


def validate_revenuecat_webhook_auth(*, headers: Mapping[str, str]) -> None:
    expected_secret = billing_settings.REVENUECAT_WEBHOOK_AUTH_SECRET.strip()
    if not expected_secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="RevenueCat webhook authentication secret is not configured.",
        )

    header_name = billing_settings.REVENUECAT_WEBHOOK_AUTH_HEADER.strip() or "Authorization"
    provided_secret = ""
    for key, value in headers.items():
        if key.lower() == header_name.lower():
            provided_secret = value.strip()
            break
    if not provided_secret or not secrets.compare_digest(provided_secret, expected_secret):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid RevenueCat webhook credentials.",
        )


def _safe_event_type(event: Mapping[str, Any]) -> str:
    return _clean_str(event.get("type")) or "unknown"


def _safe_event_id(event: Mapping[str, Any]) -> str:
    return _clean_str(event.get("id")) or _clean_str(event.get("event_id"))


def _load_existing_event(session: Session, *, provider: str, event_id: str) -> BillingWebhookEvent | None:
    return session.exec(
        select(BillingWebhookEvent).where(
            BillingWebhookEvent.provider == provider,
            BillingWebhookEvent.event_id == event_id,
        )
    ).first()


def _resolve_user_by_auth_subjects(session: Session, *, auth_subjects: Sequence[str]) -> User | None:
    unique_subjects = [subject for subject in auth_subjects if subject]
    if not unique_subjects:
        return None
    return session.exec(select(User).where(User.auth_subject.in_(unique_subjects))).first()  # type: ignore[attr-defined]


async def process_revenuecat_webhook(
    *,
    session: Session,
    payload: Mapping[str, Any],
    headers: Mapping[str, str],
) -> dict[str, Any]:
    """Validate, deduplicate, and synchronize a RevenueCat webhook event."""

    validate_revenuecat_webhook_auth(headers=headers)

    event = _coerce_event(payload)
    event_type = _safe_event_type(event)
    event_id = _safe_event_id(event)
    if not event_id:
        record_revenuecat_webhook_event(event_type=event_type, outcome="invalid")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="RevenueCat webhook payload is missing an event id.",
        )

    app_user_candidates = _extract_app_user_candidates(event)
    primary_app_user_id = app_user_candidates[0] if app_user_candidates else None
    webhook_event = _load_existing_event(session, provider="revenuecat", event_id=event_id)
    if webhook_event is None:
        webhook_event = BillingWebhookEvent(
            provider="revenuecat",
            event_id=event_id,
            event_type=event_type,
            app_user_id=primary_app_user_id,
            status="received",
        )
        session.add(webhook_event)
        try:
            session.commit()
            session.refresh(webhook_event)
        except IntegrityError:
            session.rollback()
            webhook_event = _load_existing_event(session, provider="revenuecat", event_id=event_id)
            if webhook_event is None:
                raise
    else:
        webhook_event.delivery_attempts += 1
        if primary_app_user_id and not webhook_event.app_user_id:
            webhook_event.app_user_id = primary_app_user_id
        session.add(webhook_event)
        session.commit()
        session.refresh(webhook_event)

    if webhook_event.processed_at is not None or webhook_event.status in {"processed", "ignored", "test"}:
        record_revenuecat_webhook_event(event_type=event_type, outcome="duplicate")
        return {
            "status": "duplicate",
            "event_id": event_id,
            "event_type": event_type,
        }

    if event_type.upper() == "TEST":
        webhook_event.status = "test"
        webhook_event.processed_at = _utcnow()
        webhook_event.last_error = None
        session.add(webhook_event)
        session.commit()
        record_revenuecat_webhook_event(event_type=event_type, outcome="test")
        return {
            "status": "test",
            "event_id": event_id,
            "event_type": event_type,
        }

    user = _resolve_user_by_auth_subjects(session, auth_subjects=app_user_candidates)
    if user is None:
        webhook_event.status = "ignored"
        webhook_event.processed_at = _utcnow()
        webhook_event.last_error = "No local user matched RevenueCat app_user_id."
        session.add(webhook_event)
        session.commit()
        record_revenuecat_webhook_event(event_type=event_type, outcome="ignored")
        logger.info(
            "Ignoring RevenueCat webhook with no local user match.",
            extra={
                "service": "api",
                "event": "revenuecat_webhook_ignored",
                "provider": "revenuecat",
                "event_id": event_id,
                "event_type": event_type,
                "app_user_id": primary_app_user_id,
            },
        )
        return {
            "status": "ignored",
            "event_id": event_id,
            "event_type": event_type,
        }

    try:
        webhook_event.status = "processing"
        webhook_event.last_error = None
        session.add(webhook_event)
        session.commit()

        await sync_revenuecat_subscription(
            session=session,
            user_id=user.id,
            app_user_id=user.auth_subject,
        )
    except HTTPException as exc:
        session.rollback()
        webhook_event = _load_existing_event(session, provider="revenuecat", event_id=event_id)
        if webhook_event is not None:
            webhook_event.status = "failed"
            webhook_event.last_error = str(exc.detail)[:500]
            session.add(webhook_event)
            session.commit()
        record_revenuecat_webhook_event(event_type=event_type, outcome="failed")
        raise
    except Exception as exc:
        session.rollback()
        webhook_event = _load_existing_event(session, provider="revenuecat", event_id=event_id)
        if webhook_event is not None:
            webhook_event.status = "failed"
            webhook_event.last_error = str(exc)[:500]
            session.add(webhook_event)
            session.commit()
        record_revenuecat_webhook_event(event_type=event_type, outcome="failed")
        logger.exception(
            "Unexpected RevenueCat webhook processing failure.",
            extra={
                "service": "api",
                "event": "revenuecat_webhook_failed",
                "provider": "revenuecat",
                "event_id": event_id,
                "event_type": event_type,
                "user_id": str(user.id),
            },
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="RevenueCat webhook processing failed.",
        ) from exc

    webhook_event = _load_existing_event(session, provider="revenuecat", event_id=event_id)
    if webhook_event is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="RevenueCat webhook state was lost during processing.",
        )
    webhook_event.status = "processed"
    webhook_event.processed_at = _utcnow()
    webhook_event.last_error = None
    session.add(webhook_event)
    session.commit()
    record_revenuecat_webhook_event(event_type=event_type, outcome="processed")
    logger.info(
        "RevenueCat webhook processed successfully.",
        extra={
            "service": "api",
            "event": "revenuecat_webhook_processed",
            "provider": "revenuecat",
            "event_id": event_id,
            "event_type": event_type,
            "user_id": str(user.id),
        },
    )
    return {
        "status": "processed",
        "event_id": event_id,
        "event_type": event_type,
        "status_code": _event_status_code("processed"),
    }
