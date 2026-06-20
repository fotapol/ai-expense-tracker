import datetime as dt
import uuid
from types import SimpleNamespace

from app.models.shared.enums import EntitlementStatus, SubscriptionStatus
from app.services.billing.entitlements import decide_entitlement_state, user_has_feature
from app.services.billing.subscriptions import (
    SubscriptionSyncService,
    build_manual_subscription_event,
    select_effective_subscription,
)


def _utc(hours: int = 0) -> dt.datetime:
    return dt.datetime(2026, 3, 9, tzinfo=dt.UTC) + dt.timedelta(hours=hours)


def _subscription_row(
    *,
    status: SubscriptionStatus,
    expires_at: dt.datetime | None = None,
    latest_event_at: dt.datetime | None = None,
    updated_at: dt.datetime | None = None,
    created_at: dt.datetime | None = None,
    row_id: uuid.UUID | None = None,
):
    return SimpleNamespace(
        id=row_id or uuid.uuid4(),
        status=status,
        expires_at=expires_at,
        latest_event_at=latest_event_at,
        updated_at=updated_at or _utc(1),
        created_at=created_at or _utc(0),
    )


def test_entitlement_state_active_subscription_grants() -> None:
    decision = decide_entitlement_state(
        subscription_status=SubscriptionStatus.ACTIVE,
        expires_at=_utc(24),
        now=_utc(0),
    )
    assert decision.should_grant is True
    assert decision.terminal_status is None


def test_entitlement_state_expired_subscription_revokes_access() -> None:
    decision = decide_entitlement_state(
        subscription_status=SubscriptionStatus.EXPIRED,
        expires_at=_utc(-1),
        now=_utc(0),
    )
    assert decision.should_grant is False
    assert decision.terminal_status == EntitlementStatus.EXPIRED


def test_entitlement_state_cancelled_with_future_expiry_stays_active() -> None:
    decision = decide_entitlement_state(
        subscription_status=SubscriptionStatus.CANCELLED,
        expires_at=_utc(12),
        now=_utc(0),
    )
    assert decision.should_grant is True
    assert decision.terminal_status is None


def test_entitlement_state_grace_period_stays_active() -> None:
    decision = decide_entitlement_state(
        subscription_status=SubscriptionStatus.GRACE_PERIOD,
        expires_at=_utc(2),
        now=_utc(0),
    )
    assert decision.should_grant is True
    assert decision.terminal_status is None


def test_entitlement_state_pending_has_no_active_entitlement() -> None:
    decision = decide_entitlement_state(
        subscription_status=SubscriptionStatus.PENDING,
        expires_at=_utc(48),
        now=_utc(0),
    )
    assert decision.should_grant is False
    assert decision.terminal_status == EntitlementStatus.EXPIRED


def test_entitlement_state_revoked_has_no_active_entitlement() -> None:
    decision = decide_entitlement_state(
        subscription_status=SubscriptionStatus.REVOKED,
        expires_at=_utc(48),
        now=_utc(0),
    )
    assert decision.should_grant is False
    assert decision.terminal_status == EntitlementStatus.REVOKED


def test_effective_subscription_tier_precedence() -> None:
    now = _utc(0)
    expired_row = _subscription_row(
        status=SubscriptionStatus.EXPIRED,
        expires_at=_utc(-24),
        latest_event_at=_utc(3),
    )
    pending_row = _subscription_row(
        status=SubscriptionStatus.PENDING,
        expires_at=_utc(48),
        latest_event_at=_utc(2),
    )
    active_row = _subscription_row(
        status=SubscriptionStatus.ACTIVE,
        expires_at=_utc(24),
        latest_event_at=_utc(1),
    )

    selected = select_effective_subscription([expired_row, pending_row, active_row], now=now)
    assert selected is active_row


def test_effective_subscription_tie_breakers_are_deterministic() -> None:
    now = _utc(0)
    first = _subscription_row(
        status=SubscriptionStatus.CANCELLED,
        expires_at=_utc(10),
        latest_event_at=_utc(2),
        updated_at=_utc(3),
        created_at=_utc(1),
        row_id=uuid.UUID("00000000-0000-0000-0000-000000000001"),
    )
    second = _subscription_row(
        status=SubscriptionStatus.CANCELLED,
        expires_at=_utc(10),
        latest_event_at=_utc(2),
        updated_at=_utc(3),
        created_at=_utc(1),
        row_id=uuid.UUID("00000000-0000-0000-0000-000000000002"),
    )
    selected = select_effective_subscription([first, second], now=now)
    assert selected is second


def test_manual_activation_event_uses_internal_metadata_not_raw_payload() -> None:
    actor_id = uuid.uuid4()
    target_id = uuid.uuid4()
    event = build_manual_subscription_event(
        action="activate",
        actor_user_id=actor_id,
        target_user_id=target_id,
        reason="qa-validation",
        now=_utc(0),
    )
    assert event.status == SubscriptionStatus.ACTIVE
    assert event.raw_payload is None
    assert event.internal_metadata is not None
    assert event.internal_metadata["action"] == "activate"
    assert event.internal_metadata["actor_user_id"] == str(actor_id)


def test_user_has_feature_checks_resolved_entitlements(monkeypatch) -> None:
    user_id = uuid.uuid4()

    def _fake_resolve(_session, _user_id, *, now=None):
        return {"premium.exports"}

    monkeypatch.setattr(
        "app.services.billing.entitlements.resolve_effective_entitlements",
        _fake_resolve,
    )

    assert user_has_feature(object(), user_id, "premium.exports")
    assert not user_has_feature(object(), user_id, "premium.analytics.advanced")


def test_manual_terminal_override_forces_other_provider_rows_to_terminal(monkeypatch) -> None:
    user_id = uuid.uuid4()
    manual_id = uuid.uuid4()
    current_time = _utc(0)

    manual_row = SimpleNamespace(
        id=manual_id,
        user_id=user_id,
        product_id="personal_premium",
        status=SubscriptionStatus.REVOKED,
        expires_at=current_time,
        auto_renew=False,
        latest_event_at=current_time,
        internal_metadata={"action": "revoke"},
    )
    revenuecat_row = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=user_id,
        product_id="personal_premium",
        status=SubscriptionStatus.ACTIVE,
        expires_at=_utc(24),
        auto_renew=True,
        latest_event_at=_utc(-2),
        internal_metadata={"provider": "revenuecat"},
    )
    rows = [manual_row, revenuecat_row]

    class _Result:
        def __init__(self, values):
            self._values = values

        def all(self):
            return self._values

    class _Session:
        def __init__(self, values):
            self._values = values
            self.committed = False

        def exec(self, _statement):
            return _Result(self._values)

        def add(self, _row):
            return None

        def commit(self):
            self.committed = True

        def refresh(self, _row):
            return None

    monkeypatch.setattr(
        "app.services.billing.subscriptions.sync_subscription_entitlements",
        lambda *_args, **_kwargs: [],
    )

    session = _Session(rows)
    service = SubscriptionSyncService(session)
    touched = service.apply_terminal_state_to_other_provider_rows(
        user_id=user_id,
        product_id="personal_premium",
        terminal_status=SubscriptionStatus.REVOKED,
        terminal_expires_at=current_time,
        latest_event_at=current_time,
        exclude_subscription_id=manual_id,
        metadata_patch={"dev_override_action": "revoke"},
    )

    assert touched == [revenuecat_row]
    assert session.committed is True
    assert revenuecat_row.status == SubscriptionStatus.REVOKED
    assert revenuecat_row.auto_renew is False
    assert revenuecat_row.expires_at == current_time
    assert revenuecat_row.internal_metadata["dev_override_action"] == "revoke"
