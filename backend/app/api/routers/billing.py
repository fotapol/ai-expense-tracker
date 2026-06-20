"""Subscription and entitlement API routes."""

from __future__ import annotations

import datetime as dt
import logging
import os

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlmodel import Session
from starlette.responses import JSONResponse

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.users.user import User
from app.schemas.billing import (
    CategoryUsageRead,
    DevSubscriptionActionRequest,
    DevSubscriptionActionResponse,
    MeEntitlementsResponse,
    MeSubscriptionResponse,
    ReceiptScanUsageRead,
    RevenueCatSyncResponse,
    SubscriptionRead,
)
from app.services.billing import (
    SubscriptionSyncService,
    build_manual_subscription_event,
    process_revenuecat_webhook,
    resolve_category_usage,
    resolve_effective_entitlements,
    resolve_effective_subscription,
    resolve_receipt_scan_usage,
    subscription_grants_premium_access,
    sync_revenuecat_subscription_for_user,
)

router = APIRouter(prefix="/v1", tags=["billing"])
dev_router = APIRouter(prefix="/internal/dev/billing", tags=["billing-dev"])
logger = logging.getLogger(__name__)


def _is_truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def _current_app_environment() -> str:
    return (
        (os.environ.get("APP_ENV") or os.environ.get("ENVIRONMENT") or "development")
        .strip()
        .lower()
    )


def _is_local_or_development_environment() -> bool:
    return _current_app_environment() in {"local", "development", "dev", "test"}


def _dev_billing_routes_enabled() -> bool:
    # Require a non-empty secret before enabling dev endpoints; an empty
    # secret would let any caller with an empty header bypass the key check.
    secret = os.environ.get("DEV_BILLING_INTERNAL_SECRET", "").strip()
    if not secret:
        return False
    return _is_local_or_development_environment() and _is_truthy(
        os.environ.get("ENABLE_DEV_BILLING_ENDPOINTS")
    )


def should_include_dev_billing_router() -> bool:
    """Return whether dev billing routes should be mounted for this environment."""

    return _dev_billing_routes_enabled()


def _build_usage_payload(
    *,
    used: int,
    limit: int | None,
    remaining: int | None,
    is_unlimited: bool,
    period_start_at: dt.datetime,
    period_end_at: dt.datetime,
) -> ReceiptScanUsageRead:
    return ReceiptScanUsageRead(
        used=used,
        limit=limit,
        remaining=remaining,
        is_unlimited=is_unlimited,
        period_start_at=period_start_at,
        period_end_at=period_end_at,
    )


def _build_category_usage_payload(category_usage) -> CategoryUsageRead:
    return CategoryUsageRead(
        categories_used=category_usage.categories_used,
        categories_limit=category_usage.categories_limit,
        categories_remaining=category_usage.categories_remaining,
        subcategories_used=category_usage.subcategories_used,
        subcategories_limit=category_usage.subcategories_limit,
        subcategories_remaining=category_usage.subcategories_remaining,
        is_unlimited=category_usage.is_unlimited,
    )


def _serialize_subscription_or_none(subscription) -> SubscriptionRead | None:
    if subscription is None:
        return None
    try:
        return SubscriptionRead.model_validate(subscription)
    except Exception:
        logger.exception(
            "Failed to serialize subscription payload for user %s.",
            getattr(subscription, "user_id", None),
        )
        return None


def _assert_dev_billing_enabled() -> None:
    if _dev_billing_routes_enabled():
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail=(
            "Dev billing endpoint is disabled. Set APP_ENV=development "
            "and ENABLE_DEV_BILLING_ENDPOINTS=true, then restart backend."
        ),
    )


def _assert_dev_billing_access(request: Request, current_user: User) -> None:
    if not current_user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access is required for dev billing endpoints.",
        )

    expected_secret = os.environ.get("DEV_BILLING_INTERNAL_SECRET", "").strip()
    if not expected_secret:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Development billing secret is not configured.",
        )
    provided_secret = (request.headers.get("X-Internal-Dev-Key") or "").strip()
    if not provided_secret or provided_secret != expected_secret:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Missing or invalid internal dev key.",
        )


@router.get("/me/subscription", response_model=MeSubscriptionResponse)
@limiter.limit("60/minute")
async def get_me_subscription(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return normalized effective subscription state for current user."""

    current_time = dt.datetime.now(dt.UTC)
    usage = resolve_receipt_scan_usage(session, current_user.id, now=current_time)
    category_usage = resolve_category_usage(session, current_user.id, now=current_time)
    usage_payload = _build_usage_payload(
        used=usage.used,
        limit=usage.limit,
        remaining=usage.remaining,
        is_unlimited=usage.is_unlimited,
        period_start_at=usage.period_start_at,
        period_end_at=usage.period_end_at,
    )
    category_usage_payload = _build_category_usage_payload(category_usage)
    effective_subscription = resolve_effective_subscription(
        session, current_user.id, now=current_time
    )
    if effective_subscription is None:
        return MeSubscriptionResponse(
            has_active_subscription=False,
            subscription=None,
            receipt_scan_usage=usage_payload,
            category_usage=category_usage_payload,
        )

    return MeSubscriptionResponse(
        has_active_subscription=subscription_grants_premium_access(
            status=effective_subscription.status,
            expires_at=effective_subscription.expires_at,
            now=current_time,
        ),
        subscription=_serialize_subscription_or_none(effective_subscription),
        receipt_scan_usage=usage_payload,
        category_usage=category_usage_payload,
    )


@router.post("/billing/revenuecat/sync", response_model=RevenueCatSyncResponse)
@limiter.limit("30/minute")
async def sync_revenuecat_subscription(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Synchronize current user's subscription state from RevenueCat."""

    try:
        subscription = await sync_revenuecat_subscription_for_user(
            session=session,
            current_user=current_user,
        )
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception(
            "Unexpected RevenueCat sync failure for user %s.",
            current_user.id,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Subscription sync failed unexpectedly.",
        ) from exc
    feature_codes = sorted(resolve_effective_entitlements(session, current_user.id))
    current_time = dt.datetime.now(dt.UTC)
    usage = resolve_receipt_scan_usage(session, current_user.id, now=current_time)
    category_usage = resolve_category_usage(session, current_user.id, now=current_time)
    has_active_subscription = (
        subscription_grants_premium_access(
            status=subscription.status,
            expires_at=subscription.expires_at,
            now=current_time,
        )
        if subscription is not None
        else False
    )
    return RevenueCatSyncResponse(
        has_active_subscription=has_active_subscription,
        subscription=_serialize_subscription_or_none(subscription),
        feature_codes=feature_codes,
        receipt_scan_usage=_build_usage_payload(
            used=usage.used,
            limit=usage.limit,
            remaining=usage.remaining,
            is_unlimited=usage.is_unlimited,
            period_start_at=usage.period_start_at,
            period_end_at=usage.period_end_at,
        ),
        category_usage=_build_category_usage_payload(category_usage),
    )


@router.post("/billing/revenuecat/webhook", include_in_schema=False)
async def revenuecat_webhook(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
):
    """Handle RevenueCat webhook deliveries with auth validation and idempotency."""

    try:
        payload = await request.json()
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="RevenueCat webhook payload must be valid JSON.",
        ) from exc

    result = await process_revenuecat_webhook(
        session=session,
        payload=payload if isinstance(payload, dict) else {},
        headers=request.headers,
    )
    status_code = int(result.pop("status_code", status.HTTP_200_OK))
    return JSONResponse(status_code=status_code, content=result)


@router.get("/me/entitlements", response_model=MeEntitlementsResponse)
@limiter.limit("60/minute")
async def get_me_entitlements(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return active user-scope feature codes for the current user."""
    feature_codes = sorted(resolve_effective_entitlements(session, current_user.id))
    return MeEntitlementsResponse(feature_codes=feature_codes)


@dev_router.post(
    "/subscriptions/manual",
    response_model=DevSubscriptionActionResponse,
)
@limiter.limit("30/minute")
async def apply_manual_subscription_action(
    payload: DevSubscriptionActionRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Apply a dev-only manual subscription action for a target user."""

    _assert_dev_billing_enabled()
    _assert_dev_billing_access(request, current_user)

    service = SubscriptionSyncService(session)
    normalized_event = build_manual_subscription_event(
        action=payload.action,
        target_user_id=payload.target_user_id,
        actor_user_id=current_user.id,
        reason=payload.reason,
        product_id=payload.product_id,
        expires_at=payload.expires_at,
    )
    subscription = service.apply_normalized_event(normalized_event)
    if payload.action in {"expire", "revoke"}:
        event_time = subscription.latest_event_at or dt.datetime.now(dt.UTC)
        service.apply_terminal_state_to_other_provider_rows(
            user_id=payload.target_user_id,
            product_id=payload.product_id,
            terminal_status=subscription.status,
            terminal_expires_at=subscription.expires_at,
            latest_event_at=event_time,
            exclude_subscription_id=subscription.id,
            metadata_patch={
                "dev_override_action": payload.action,
                "dev_override_actor_user_id": str(current_user.id),
                "dev_override_applied_at": event_time.isoformat(),
            },
        )
    feature_codes = sorted(resolve_effective_entitlements(session, payload.target_user_id))
    current_time = dt.datetime.now(dt.UTC)
    has_active_subscription = subscription_grants_premium_access(
        status=subscription.status,
        expires_at=subscription.expires_at,
        now=current_time,
    )

    return DevSubscriptionActionResponse(
        target_user_id=payload.target_user_id,
        has_active_subscription=has_active_subscription,
        subscription=_serialize_subscription_or_none(subscription),
        feature_codes=feature_codes,
    )
