"""Entitlement synchronization and feature-check utilities."""

from __future__ import annotations

import datetime as dt
import uuid
from dataclasses import dataclass

from sqlalchemy import or_
from sqlmodel import Session, select

from app.models.billing.entitlement import Entitlement
from app.models.billing.subscription import Subscription
from app.models.shared.enums import (
    EntitlementScopeType,
    EntitlementStatus,
    SubscriptionStatus,
)
from app.services.billing.features import feature_codes_for_product


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


@dataclass(slots=True, frozen=True)
class EntitlementDecision:
    """Decision output for one subscription-to-entitlement evaluation."""

    should_grant: bool
    terminal_status: EntitlementStatus | None
    terminal_expires_at: dt.datetime | None


def decide_entitlement_state(
    *,
    subscription_status: SubscriptionStatus,
    expires_at: dt.datetime | None,
    now: dt.datetime | None = None,
) -> EntitlementDecision:
    """Resolve whether a subscription state should grant premium entitlements."""

    current_time = now or _utcnow()
    if subscription_status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD}:
        return EntitlementDecision(
            should_grant=True,
            terminal_status=None,
            terminal_expires_at=expires_at,
        )
    if subscription_status == SubscriptionStatus.CANCELLED and expires_at and expires_at > current_time:
        return EntitlementDecision(
            should_grant=True,
            terminal_status=None,
            terminal_expires_at=expires_at,
        )

    terminal_status = (
        EntitlementStatus.REVOKED
        if subscription_status == SubscriptionStatus.REVOKED
        else EntitlementStatus.EXPIRED
    )
    if terminal_status == EntitlementStatus.REVOKED:
        terminal_expires_at = current_time
    elif expires_at is not None and expires_at <= current_time:
        terminal_expires_at = expires_at
    else:
        terminal_expires_at = current_time
    return EntitlementDecision(
        should_grant=False,
        terminal_status=terminal_status,
        terminal_expires_at=terminal_expires_at,
    )


def sync_subscription_entitlements(
    session: Session,
    subscription: Subscription,
    *,
    now: dt.datetime | None = None,
) -> list[Entitlement]:
    """Create or update entitlements for a subscription's current normalized state."""

    current_time = now or _utcnow()
    decision = decide_entitlement_state(
        subscription_status=subscription.status,
        expires_at=subscription.expires_at,
        now=current_time,
    )
    feature_codes = feature_codes_for_product(subscription.product_id)

    existing_rows = session.exec(
        select(Entitlement).where(
            Entitlement.scope_type == EntitlementScopeType.USER,
            Entitlement.scope_id == subscription.user_id,
            Entitlement.source_subscription_id == subscription.id,
        )
    ).all()
    entitlements_by_feature = {row.feature_code: row for row in existing_rows}

    touched: list[Entitlement] = []
    if decision.should_grant:
        starts_at = subscription.started_at or current_time
        for feature_code in sorted(feature_codes):
            row = entitlements_by_feature.get(feature_code)
            if row is None:
                row = Entitlement(
                    scope_type=EntitlementScopeType.USER,
                    scope_id=subscription.user_id,
                    feature_code=feature_code,
                    source_subscription_id=subscription.id,
                    starts_at=starts_at,
                    expires_at=subscription.expires_at,
                    status=EntitlementStatus.ACTIVE,
                )
            else:
                row.status = EntitlementStatus.ACTIVE
                row.starts_at = starts_at
                row.expires_at = subscription.expires_at
            session.add(row)
            touched.append(row)

    for feature_code, row in entitlements_by_feature.items():
        if feature_code in feature_codes and decision.should_grant:
            continue
        row.status = decision.terminal_status or EntitlementStatus.EXPIRED
        row.expires_at = decision.terminal_expires_at
        session.add(row)
        touched.append(row)

    return touched


def resolve_user_entitlements(
    session: Session,
    user_id: uuid.UUID,
    *,
    now: dt.datetime | None = None,
) -> set[str]:
    """Resolve active user-scope feature codes for a user."""

    current_time = now or _utcnow()
    rows = session.exec(
        select(Entitlement.feature_code).where(
            Entitlement.scope_type == EntitlementScopeType.USER,
            Entitlement.scope_id == user_id,
            Entitlement.status == EntitlementStatus.ACTIVE,
            Entitlement.starts_at <= current_time,
            or_(Entitlement.expires_at.is_(None), Entitlement.expires_at > current_time),
        )
    ).all()
    return set(rows)


def user_has_feature(
    session: Session,
    user_id: uuid.UUID,
    feature_code: str,
    *,
    now: dt.datetime | None = None,
) -> bool:
    """Return ``True`` when the given feature code is currently active for the user."""

    return feature_code in resolve_user_entitlements(session, user_id, now=now)
