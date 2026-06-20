"""Subscription normalization, resolver, and synchronization services."""

from __future__ import annotations

import datetime as dt
import uuid
from collections.abc import Mapping, Sequence
from typing import Any, Literal

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models.billing.subscription import Subscription
from app.models.shared.enums import SubscriptionProvider, SubscriptionStatus
from app.services.billing.contracts import (
    BillingEventHandler,
    BillingProvider,
    NormalizedSubscriptionEvent,
)
from app.services.billing.entitlements import sync_subscription_entitlements
from app.services.billing.features import (
    PERSONAL_PREMIUM_PRODUCT_ID,
)

_MIN_TIMESTAMP = dt.datetime.min.replace(tzinfo=dt.UTC)


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def subscription_grants_premium_access(
    *,
    status: SubscriptionStatus,
    expires_at: dt.datetime | None,
    now: dt.datetime | None = None,
) -> bool:
    """Return whether the normalized subscription state grants premium entitlement."""

    current_time = now or _utcnow()
    if status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD}:
        return expires_at is None or expires_at > current_time
    return status == SubscriptionStatus.CANCELLED and expires_at is not None and expires_at > current_time


def subscription_priority_tier(
    *,
    status: SubscriptionStatus,
    expires_at: dt.datetime | None,
    now: dt.datetime | None = None,
) -> int:
    """Return deterministic resolver tier (3 is highest priority)."""

    current_time = now or _utcnow()
    valid_expires = expires_at is None or expires_at > current_time
    if status in {SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD} and valid_expires:
        return 3
    if status == SubscriptionStatus.CANCELLED and expires_at is not None and expires_at > current_time:
        return 3
    if status == SubscriptionStatus.PENDING:
        return 2
    if status in {SubscriptionStatus.EXPIRED, SubscriptionStatus.REVOKED, SubscriptionStatus.CANCELLED, SubscriptionStatus.ACTIVE, SubscriptionStatus.GRACE_PERIOD}:
        return 1
    return 0


def _descending_datetime_key(value: dt.datetime | None) -> tuple[bool, dt.datetime]:
    return (value is not None, value or _MIN_TIMESTAMP)


def _effective_row_sort_key(
    subscription: Subscription,
    *,
    now: dt.datetime | None = None,
) -> tuple[int, tuple[bool, dt.datetime], tuple[bool, dt.datetime], tuple[bool, dt.datetime], tuple[bool, dt.datetime], str]:
    current_time = now or _utcnow()
    return (
        subscription_priority_tier(
            status=subscription.status,
            expires_at=subscription.expires_at,
            now=current_time,
        ),
        _descending_datetime_key(subscription.expires_at),
        _descending_datetime_key(subscription.latest_event_at),
        _descending_datetime_key(subscription.updated_at),
        _descending_datetime_key(subscription.created_at),
        str(subscription.id),
    )


def select_effective_subscription(
    subscriptions: Sequence[Subscription],
    *,
    now: dt.datetime | None = None,
) -> Subscription | None:
    """Select the effective row for API reads using deterministic tier and tie-break rules."""

    current_time = now or _utcnow()
    candidates = [
        row
        for row in subscriptions
        if subscription_priority_tier(
            status=row.status,
            expires_at=row.expires_at,
            now=current_time,
        )
        > 0
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda row: _effective_row_sort_key(row, now=current_time))


def resolve_effective_subscription(
    session: Session,
    user_id: uuid.UUID,
    *,
    now: dt.datetime | None = None,
) -> Subscription | None:
    """Load all user subscriptions and resolve one deterministic effective row."""

    rows = session.exec(
        select(Subscription).where(Subscription.user_id == user_id)
    ).all()
    return select_effective_subscription(rows, now=now)


def build_manual_subscription_event(
    *,
    action: Literal["activate", "expire", "revoke"],
    target_user_id: uuid.UUID,
    actor_user_id: uuid.UUID,
    reason: str | None = None,
    product_id: str = PERSONAL_PREMIUM_PRODUCT_ID,
    expires_at: dt.datetime | None = None,
    now: dt.datetime | None = None,
) -> NormalizedSubscriptionEvent:
    """Build normalized event payload for manual/dev testing actions."""

    current_time = now or _utcnow()
    status = SubscriptionStatus.ACTIVE
    event_expires_at = expires_at
    if action == "activate":
        if event_expires_at is None:
            event_expires_at = current_time + dt.timedelta(days=30)
    elif action == "expire":
        status = SubscriptionStatus.EXPIRED
        event_expires_at = event_expires_at or current_time
    else:
        status = SubscriptionStatus.REVOKED
        event_expires_at = current_time

    metadata: dict[str, Any] = {
        "action": action,
        "actor_user_id": str(actor_user_id),
        "applied_at": current_time.isoformat(),
    }
    if reason:
        metadata["reason"] = reason

    return NormalizedSubscriptionEvent(
        user_id=target_user_id,
        provider=SubscriptionProvider.MANUAL,
        product_id=product_id,
        status=status,
        started_at=current_time if action == "activate" else None,
        expires_at=event_expires_at,
        auto_renew=False,
        latest_event_at=current_time,
        raw_payload=None,
        internal_metadata=metadata,
    )


class SubscriptionSyncService(BillingEventHandler):
    """Persists normalized subscriptions and keeps entitlements synchronized."""

    def __init__(self, session: Session):
        self.session = session

    def handle_provider_event(
        self,
        *,
        provider: BillingProvider,
        user_id: uuid.UUID,
        payload: Mapping[str, Any],
    ) -> Subscription | None:
        """Normalize provider payload and apply it to current subscription state."""

        normalized_events = provider.normalize_events(user_id=user_id, payload=payload)
        touched_rows: list[Subscription] = []
        latest_event_at = max(
            (
                event.latest_event_at
                for event in normalized_events
                if event.latest_event_at is not None
            ),
            default=_utcnow(),
        )

        for event in normalized_events:
            row = self._upsert_subscription_row(event)
            self._sync_row_entitlements(row, now=event.latest_event_at)
            touched_rows.append(row)

        expected_product_ids = getattr(provider, "expected_product_ids", None)
        if expected_product_ids:
            touched_rows.extend(
                self._expire_missing_provider_rows(
                    user_id=user_id,
                    provider=provider.provider,
                    expected_product_ids=set(expected_product_ids),
                    emitted_product_ids={event.product_id for event in normalized_events},
                    latest_event_at=latest_event_at,
                )
            )

        if touched_rows:
            self.session.commit()
            refreshed_ids: set[uuid.UUID] = set()
            for row in touched_rows:
                if row.id in refreshed_ids:
                    continue
                self.session.refresh(row)
                refreshed_ids.add(row.id)

        return resolve_effective_subscription(self.session, user_id)

    def apply_normalized_event(self, event: NormalizedSubscriptionEvent) -> Subscription:
        """Upsert current-state subscription row and synchronize its entitlements."""

        existing = self._upsert_subscription_row(event)
        self._sync_row_entitlements(existing, now=event.latest_event_at)
        self.session.commit()
        self.session.refresh(existing)
        return existing

    def _upsert_subscription_row(self, event: NormalizedSubscriptionEvent) -> Subscription:
        existing = self.session.exec(
            select(Subscription).where(
                Subscription.user_id == event.user_id,
                Subscription.provider == event.provider,
                Subscription.product_id == event.product_id,
            )
        ).first()
        if existing is None:
            existing = Subscription(
                user_id=event.user_id,
                provider=event.provider,
                product_id=event.product_id,
                status=event.status,
            )

        existing.status = event.status
        existing.started_at = event.started_at
        existing.expires_at = event.expires_at
        existing.auto_renew = event.auto_renew
        existing.external_customer_id = event.external_customer_id
        existing.external_subscription_id = event.external_subscription_id
        existing.external_purchase_id = event.external_purchase_id
        existing.latest_event_at = event.latest_event_at
        if event.raw_payload is not None:
            existing.raw_payload = event.raw_payload
        if event.internal_metadata is not None:
            existing.internal_metadata = event.internal_metadata

        self.session.add(existing)
        try:
            self.session.flush()
        except IntegrityError:
            self.session.rollback()
            existing = self.session.exec(
                select(Subscription).where(
                    Subscription.user_id == event.user_id,
                    Subscription.provider == event.provider,
                    Subscription.product_id == event.product_id,
                )
            ).first()
            if existing is None:
                raise

            existing.status = event.status
            existing.started_at = event.started_at
            existing.expires_at = event.expires_at
            existing.auto_renew = event.auto_renew
            existing.external_customer_id = event.external_customer_id
            existing.external_subscription_id = event.external_subscription_id
            existing.external_purchase_id = event.external_purchase_id
            existing.latest_event_at = event.latest_event_at
            if event.raw_payload is not None:
                existing.raw_payload = event.raw_payload
            if event.internal_metadata is not None:
                existing.internal_metadata = event.internal_metadata

            self.session.add(existing)
            self.session.flush()
        return existing

    def _sync_row_entitlements(
        self,
        subscription: Subscription,
        *,
        now: dt.datetime | None = None,
    ) -> None:
        sync_subscription_entitlements(
            self.session,
            subscription,
            now=now,
        )

    def _expire_missing_provider_rows(
        self,
        *,
        user_id: uuid.UUID,
        provider: SubscriptionProvider,
        expected_product_ids: set[str],
        emitted_product_ids: set[str],
        latest_event_at: dt.datetime,
    ) -> list[Subscription]:
        if not expected_product_ids:
            return []

        rows = self.session.exec(
            select(Subscription).where(
                Subscription.user_id == user_id,
                Subscription.provider == provider,
                Subscription.product_id.in_(expected_product_ids),  # type: ignore[attr-defined]
            )
        ).all()

        touched: list[Subscription] = []
        for row in rows:
            if row.product_id in emitted_product_ids:
                continue
            if row.status == SubscriptionStatus.EXPIRED and row.expires_at is not None and row.expires_at <= latest_event_at:
                continue
            row.status = SubscriptionStatus.EXPIRED
            if row.expires_at is None or row.expires_at > latest_event_at:
                row.expires_at = latest_event_at
            row.auto_renew = False
            row.latest_event_at = latest_event_at
            self.session.add(row)
            self._sync_row_entitlements(row, now=latest_event_at)
            touched.append(row)
        return touched

    def apply_terminal_state_to_other_provider_rows(
        self,
        *,
        user_id: uuid.UUID,
        product_id: str,
        terminal_status: SubscriptionStatus,
        terminal_expires_at: dt.datetime | None,
        latest_event_at: dt.datetime | None = None,
        exclude_subscription_id: uuid.UUID | None = None,
        metadata_patch: Mapping[str, Any] | None = None,
    ) -> list[Subscription]:
        """Force non-selected provider rows into terminal state for dev override flows."""

        if terminal_status not in {SubscriptionStatus.EXPIRED, SubscriptionStatus.REVOKED}:
            return []

        event_time = latest_event_at or _utcnow()
        target_expires_at = terminal_expires_at or event_time

        statement = select(Subscription).where(
            Subscription.user_id == user_id,
            Subscription.product_id == product_id,
        )
        rows = self.session.exec(statement).all()

        touched: list[Subscription] = []
        for row in rows:
            if exclude_subscription_id is not None and row.id == exclude_subscription_id:
                continue
            if row.status == terminal_status and row.expires_at is not None and row.expires_at <= target_expires_at:
                continue

            row.status = terminal_status
            if row.expires_at is None or row.expires_at > target_expires_at:
                row.expires_at = target_expires_at
            row.auto_renew = False
            row.latest_event_at = event_time
            if metadata_patch:
                merged_metadata = dict(row.internal_metadata or {})
                merged_metadata.update(metadata_patch)
                row.internal_metadata = merged_metadata
            self.session.add(row)
            self._sync_row_entitlements(row, now=event_time)
            touched.append(row)

        if touched:
            self.session.commit()
            for row in touched:
                self.session.refresh(row)
        return touched

    def activate_manual_personal_premium(
        self,
        *,
        target_user_id: uuid.UUID,
        actor_user_id: uuid.UUID,
        expires_at: dt.datetime | None = None,
        reason: str | None = None,
    ) -> Subscription:
        """Activate personal premium using manual provider state for dev/testing."""

        event = build_manual_subscription_event(
            action="activate",
            target_user_id=target_user_id,
            actor_user_id=actor_user_id,
            expires_at=expires_at,
            reason=reason,
        )
        return self.apply_normalized_event(event)

    def expire_manual_personal_premium(
        self,
        *,
        target_user_id: uuid.UUID,
        actor_user_id: uuid.UUID,
        expires_at: dt.datetime | None = None,
        reason: str | None = None,
    ) -> Subscription:
        """Expire personal premium using manual provider state for dev/testing."""

        event = build_manual_subscription_event(
            action="expire",
            target_user_id=target_user_id,
            actor_user_id=actor_user_id,
            expires_at=expires_at,
            reason=reason,
        )
        return self.apply_normalized_event(event)

    def revoke_manual_personal_premium(
        self,
        *,
        target_user_id: uuid.UUID,
        actor_user_id: uuid.UUID,
        reason: str | None = None,
    ) -> Subscription:
        """Revoke personal premium using manual provider state for dev/testing."""

        event = build_manual_subscription_event(
            action="revoke",
            target_user_id=target_user_id,
            actor_user_id=actor_user_id,
            reason=reason,
        )
        return self.apply_normalized_event(event)
