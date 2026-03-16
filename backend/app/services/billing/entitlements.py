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
from app.services.billing.features import FAMILY_PREMIUM_PRODUCT_ID, feature_codes_for_product


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
    
    valid_expires = expires_at is None or expires_at > current_time

    if subscription_status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD} and valid_expires:
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
    household_id: uuid.UUID | None = None,
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
    touched = _sync_scope_entitlements(
        session=session,
        subscription=subscription,
        scope_type=EntitlementScopeType.USER,
        scope_id=subscription.user_id,
        feature_codes=feature_codes,
        decision=decision,
        current_time=current_time,
    )

    household_feature_codes = (
        feature_codes
        if subscription.product_id == FAMILY_PREMIUM_PRODUCT_ID and household_id is not None
        else set()
    )
    touched.extend(
        _sync_scope_entitlements(
            session=session,
            subscription=subscription,
            scope_type=EntitlementScopeType.HOUSEHOLD,
            scope_id=household_id,
            feature_codes=household_feature_codes,
            decision=decision,
            current_time=current_time,
        )
    )
    return touched


def _sync_scope_entitlements(
    *,
    session: Session,
    subscription: Subscription,
    scope_type: EntitlementScopeType,
    scope_id: uuid.UUID | None,
    feature_codes: set[str],
    decision: EntitlementDecision,
    current_time: dt.datetime,
) -> list[Entitlement]:
    existing_rows = session.exec(
        select(Entitlement).where(
            Entitlement.scope_type == scope_type,
            Entitlement.source_subscription_id == subscription.id,
        )
    ).all()
    entitlements_by_key = {
        (row.scope_id, row.feature_code): row for row in existing_rows
    }

    touched: list[Entitlement] = []
    active_keys: set[tuple[uuid.UUID, str]] = set()
    if decision.should_grant and scope_id is not None:
        starts_at = subscription.started_at or current_time
        for feature_code in sorted(feature_codes):
            key = (scope_id, feature_code)
            row = entitlements_by_key.get(key)
            if row is None:
                row = Entitlement(
                    scope_type=scope_type,
                    scope_id=scope_id,
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
            active_keys.add(key)

    for row in existing_rows:
        key = (row.scope_id, row.feature_code)
        if key in active_keys:
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
    """Resolve active user-scope feature codes for a user.

    .. note::
        This function only returns ``user``-scoped entitlements.
        Use :func:`resolve_effective_entitlements` to also include
        household-scoped entitlements from family plans.
    """

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


def resolve_effective_entitlements(
    session: Session,
    user_id: uuid.UUID,
    *,
    now: dt.datetime | None = None,
) -> set[str]:
    """Resolve all active feature codes for a user, including household-scope.

    Collects:
    1. Active ``user``-scoped entitlements for ``user_id``.
    2. Active ``household``-scoped entitlements for any household where
       the user has an ``active`` membership (family plan support).

    Returns the union of both sets.
    """
    from app.models.households.household_member import HouseholdMember
    from app.models.shared.enums import HouseholdMemberStatus

    current_time = now or _utcnow()

    # --- User-scope entitlements ----------------------------------------
    feature_codes = resolve_user_entitlements(session, user_id, now=current_time)

    # --- Household-scope entitlements ------------------------------------
    # Find all households where this user is an active member.
    active_household_ids = [
        row.household_id
        for row in session.exec(
            select(HouseholdMember).where(
                HouseholdMember.user_id == user_id,
                HouseholdMember.status == HouseholdMemberStatus.ACTIVE,
            )
        ).all()
    ]

    if active_household_ids:
        household_rows = session.exec(
            select(Entitlement.feature_code).where(
                Entitlement.scope_type == EntitlementScopeType.HOUSEHOLD,
                Entitlement.scope_id.in_(active_household_ids),  # type: ignore[attr-defined]
                Entitlement.status == EntitlementStatus.ACTIVE,
                Entitlement.starts_at <= current_time,
                or_(Entitlement.expires_at.is_(None), Entitlement.expires_at > current_time),
            )
        ).all()
        feature_codes = feature_codes | set(household_rows)

    return feature_codes


def user_has_feature(
    session: Session,
    user_id: uuid.UUID,
    feature_code: str,
    *,
    now: dt.datetime | None = None,
) -> bool:
    """Return ``True`` when the given feature code is currently active for the user.

    Checks both user-scope and household-scope entitlements.
    """

    return feature_code in resolve_effective_entitlements(session, user_id, now=now)
