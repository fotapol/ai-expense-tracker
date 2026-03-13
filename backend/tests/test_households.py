"""Unit tests for household services.

All tests use SimpleNamespace mock sessions — no real database required.
This follows the same pattern as test_billing_foundation.py.
"""

from __future__ import annotations

import datetime as dt
import uuid
from types import SimpleNamespace

from app.models.shared.enums import (
    EntitlementScopeType,
    EntitlementStatus,
    HouseholdInviteStatus,
    HouseholdMemberRole,
    HouseholdMemberStatus,
)
from app.services.billing.entitlements import (
    resolve_effective_entitlements,
    resolve_user_entitlements,
)
from app.services.households.membership import validate_transaction_attribution


def _utc(hours: int = 0) -> dt.datetime:
    return dt.datetime(2026, 3, 11, tzinfo=dt.UTC) + dt.timedelta(hours=hours)


# ============================================================
# Mock session helpers
# ============================================================


class _Result:
    """Minimal query result wrapper."""

    def __init__(self, values: list):
        self._values = values

    def all(self) -> list:
        return self._values

    def first(self):
        return self._values[0] if self._values else None


class _Session:
    """Mock session that records added objects and supports simple exec."""

    def __init__(self, exec_results: list | None = None):
        self._exec_results = exec_results or []
        self._exec_call_count = 0
        self.added: list = []
        self.committed = False
        self._flushed = False

    def exec(self, _statement) -> _Result:
        idx = self._exec_call_count
        self._exec_call_count += 1
        if idx < len(self._exec_results):
            return _Result(self._exec_results[idx])
        return _Result([])

    def get(self, _model_class, pk):
        # Return the first added item whose id matches, for simplicity
        for obj in self.added:
            if getattr(obj, "id", None) == pk:
                return obj
        return None

    def add(self, obj) -> None:
        self.added.append(obj)

    def flush(self) -> None:
        self._flushed = True

    def commit(self) -> None:
        self.committed = True

    def refresh(self, obj) -> None:
        pass  # no-op in tests


# ============================================================
# test_household_creation
# ============================================================


def test_household_creation_inserts_owner_member(monkeypatch) -> None:
    """create_household should create the household and insert an owner member."""
    from app.services.households.households import create_household

    owner = SimpleNamespace(id=uuid.uuid4(), email="owner@example.com")

    # No existing active household for this user.
    session = _Session(exec_results=[[]])  # empty result for get_active_household call

    # Patch get_active_household_for_user to return None directly.
    monkeypatch.setattr(
        "app.services.households.households.get_active_household_for_user",
        lambda _session, _user_id: None,
    )

    household = None
    member = None

    original_add = session.add

    def _capture_add(obj):
        nonlocal household, member
        original_add(obj)
        from app.models.households.household import Household
        from app.models.households.household_member import HouseholdMember

        if isinstance(obj, Household):
            household = obj
            obj.id = uuid.uuid4()  # Simulate DB-assigned PK after flush.
        elif isinstance(obj, HouseholdMember):
            member = obj

    session.add = _capture_add

    result = create_household(session, name="  Smith Family  ", owner=owner)

    assert session.committed is True
    assert household is not None
    assert household.name == "Smith Family"  # Stripped
    assert household.owner_user_id == owner.id

    assert member is not None
    assert member.role == HouseholdMemberRole.OWNER
    assert member.status == HouseholdMemberStatus.ACTIVE
    assert member.user_id == owner.id
    assert member.joined_at is not None


def test_household_creation_rejects_duplicate_active_membership(monkeypatch) -> None:
    """create_household should raise 409 if user already has an active household."""
    import pytest
    from fastapi import HTTPException

    from app.services.households.households import create_household

    owner = SimpleNamespace(id=uuid.uuid4())
    existing_household = SimpleNamespace(id=uuid.uuid4(), name="Old Family")

    monkeypatch.setattr(
        "app.services.households.households.get_active_household_for_user",
        lambda _session, _user_id: existing_household,
    )

    session = _Session()
    with pytest.raises(HTTPException) as exc_info:
        create_household(session, name="New Family", owner=owner)

    assert exc_info.value.status_code == 409


# ============================================================
# test_invite_acceptance
# ============================================================


def test_invite_acceptance_creates_active_member(monkeypatch) -> None:
    """accept_invite should activate membership and mark invite accepted."""
    from app.services.households.invites import accept_invite

    household_id = uuid.uuid4()
    accepting_user = SimpleNamespace(id=uuid.uuid4())
    token = "abc123"

    pending_invite = SimpleNamespace(
        id=uuid.uuid4(),
        household_id=household_id,
        status=HouseholdInviteStatus.PENDING,
        expires_at=_utc(24),
        accepted_at=None,
    )

    # Patch supporting functions.
    monkeypatch.setattr(
        "app.services.households.invites.get_invite_by_token",
        lambda _session, _token: pending_invite,
    )
    monkeypatch.setattr(
        "app.services.households.invites._get_active_household_for_user",
        lambda _session, _user_id: None,
    )

    session = _Session(exec_results=[[]])  # No existing member row.

    added_objects = []
    original_add = session.add

    def _capture_add(obj):
        original_add(obj)
        added_objects.append(obj)

    session.add = _capture_add

    member = accept_invite(session, token, accepting_user)

    assert session.committed is True
    assert member.status == HouseholdMemberStatus.ACTIVE
    assert member.role == HouseholdMemberRole.MEMBER
    assert member.user_id == accepting_user.id
    assert member.joined_at is not None
    assert pending_invite.status == HouseholdInviteStatus.ACCEPTED
    assert pending_invite.accepted_at is not None


def test_invite_acceptance_rejects_expired_invite(monkeypatch) -> None:
    """accept_invite should raise 410 for expired invites."""
    import pytest
    from fastapi import HTTPException

    from app.services.households.invites import accept_invite

    expired_invite = SimpleNamespace(
        id=uuid.uuid4(),
        household_id=uuid.uuid4(),
        status=HouseholdInviteStatus.PENDING,
        expires_at=_utc(-1),  # In the past.
        accepted_at=None,
    )

    monkeypatch.setattr(
        "app.services.households.invites.get_invite_by_token",
        lambda _session, _token: expired_invite,
    )

    session = _Session()
    with pytest.raises(HTTPException) as exc_info:
        accept_invite(session, "anytoken", SimpleNamespace(id=uuid.uuid4()))

    assert exc_info.value.status_code == 410


def test_invite_acceptance_rejects_existing_household_membership(monkeypatch) -> None:
    """accept_invite should reject users who already belong to another household."""
    import pytest
    from fastapi import HTTPException

    from app.services.households.invites import accept_invite

    existing_household = SimpleNamespace(id=uuid.uuid4(), name="Current Household")
    pending_invite = SimpleNamespace(
        id=uuid.uuid4(),
        household_id=uuid.uuid4(),
        status=HouseholdInviteStatus.PENDING,
        expires_at=_utc(24),
        accepted_at=None,
    )

    monkeypatch.setattr(
        "app.services.households.invites.get_invite_by_token",
        lambda _session, _token: pending_invite,
    )
    monkeypatch.setattr(
        "app.services.households.invites._get_active_household_for_user",
        lambda _session, _user_id: existing_household,
    )

    session = _Session()
    with pytest.raises(HTTPException) as exc_info:
        accept_invite(session, "any-token", SimpleNamespace(id=uuid.uuid4()))

    assert exc_info.value.status_code == 409
    assert "already belong to another household" in str(exc_info.value.detail).lower()


def test_build_invite_link_uses_public_base_url(monkeypatch) -> None:
    """build_invite_link should always derive link base from PUBLIC_APP_BASE_URL."""
    from app.services.households.invites import build_invite_link

    monkeypatch.setattr(
        "app.services.households.invites.app_settings.PUBLIC_APP_BASE_URL",
        "https://example.com",
        raising=False,
    )

    link = build_invite_link("abc123")
    assert link == "https://example.com/household-invite?token=abc123"


def test_derive_invite_effective_state_from_status_and_expiry() -> None:
    """effective_state should be derived from invite status + expiry timestamp."""
    from app.services.households.invites import derive_invite_effective_state

    now = _utc(0)
    assert (
        derive_invite_effective_state(
            status_value=HouseholdInviteStatus.PENDING,
            expires_at=_utc(1),
            now=now,
        )
        == "pending"
    )
    assert (
        derive_invite_effective_state(
            status_value=HouseholdInviteStatus.PENDING,
            expires_at=_utc(-1),
            now=now,
        )
        == "expired"
    )
    assert (
        derive_invite_effective_state(
            status_value=HouseholdInviteStatus.ACCEPTED,
            expires_at=_utc(1),
            now=now,
        )
        == "accepted"
    )
    assert (
        derive_invite_effective_state(
            status_value=HouseholdInviteStatus.REVOKED,
            expires_at=_utc(1),
            now=now,
        )
        == "revoked"
    )


# ============================================================
# test_entitlement_resolution — user + household scope union
# ============================================================


def test_resolve_effective_entitlements_merges_user_and_household_scope(monkeypatch) -> None:
    """resolve_effective_entitlements should return the union of user + household entitlements."""
    user_id = uuid.uuid4()
    household_id = uuid.uuid4()

    # Stub resolve_user_entitlements to return a user-scope feature.
    monkeypatch.setattr(
        "app.services.billing.entitlements.resolve_user_entitlements",
        lambda _session, _user_id, *, now=None: {"premium.exports"},
    )

    # Stub HouseholdMember lookup.
    fake_member = SimpleNamespace(
        household_id=household_id,
        user_id=user_id,
        status=HouseholdMemberStatus.ACTIVE,
    )

    # Stub Entitlement household lookup — returns "premium.family_plan".
    call_count = [0]

    class _FakeSession:
        def exec(self, _stmt):
            call_count[0] += 1
            if call_count[0] == 1:
                # HouseholdMember query
                return _Result([fake_member])
            # Entitlement household query
            return _Result(["premium.family_plan"])

    result = resolve_effective_entitlements(_FakeSession(), user_id)  # type: ignore[arg-type]

    assert "premium.exports" in result
    assert "premium.family_plan" in result


def test_resolve_effective_entitlements_no_household_returns_user_only(monkeypatch) -> None:
    """resolve_effective_entitlements without household returns only user-scope entitlements."""
    user_id = uuid.uuid4()

    monkeypatch.setattr(
        "app.services.billing.entitlements.resolve_user_entitlements",
        lambda _session, _user_id, *, now=None: {"premium.receipt_scans.unlimited"},
    )

    class _EmptySession:
        def exec(self, _stmt):
            return _Result([])  # No household memberships.

    result = resolve_effective_entitlements(_EmptySession(), user_id)  # type: ignore[arg-type]

    assert result == {"premium.receipt_scans.unlimited"}


# ============================================================
# test_transaction_owner_validation
# ============================================================


def test_validate_attribution_allows_active_member(monkeypatch) -> None:
    """validate_transaction_attribution should pass when owner is a household member."""
    household_id = uuid.uuid4()
    owner_user_id = uuid.uuid4()

    active_member = SimpleNamespace(
        household_id=household_id,
        user_id=owner_user_id,
        status=HouseholdMemberStatus.ACTIVE,
    )

    monkeypatch.setattr(
        "app.services.households.membership.get_member_for_user",
        lambda _session, _household_id, _user_id: active_member,
    )

    # Should not raise.
    validate_transaction_attribution(
        object(),  # type: ignore[arg-type]
        household_id=household_id,
        owner_user_id=owner_user_id,
    )


def test_validate_attribution_rejects_non_member(monkeypatch) -> None:
    """validate_transaction_attribution should raise 422 when owner is not a member."""
    import pytest
    from fastapi import HTTPException

    household_id = uuid.uuid4()
    owner_user_id = uuid.uuid4()

    monkeypatch.setattr(
        "app.services.households.membership.get_member_for_user",
        lambda _session, _household_id, _user_id: None,
    )

    with pytest.raises(HTTPException) as exc_info:
        validate_transaction_attribution(
            object(),  # type: ignore[arg-type]
            household_id=household_id,
            owner_user_id=owner_user_id,
        )

    assert exc_info.value.status_code == 422


def test_validate_attribution_no_household_is_noop(monkeypatch) -> None:
    """validate_transaction_attribution skips member check when household_id is None."""
    # Should not raise even without a member.
    validate_transaction_attribution(
        object(),  # type: ignore[arg-type]
        household_id=None,
        owner_user_id=uuid.uuid4(),
    )


def test_validate_attribution_household_without_owner_user_id_raises(monkeypatch) -> None:
    """validate_transaction_attribution should raise 422 when household_id is set but owner_user_id is None."""
    import pytest
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        validate_transaction_attribution(
            object(),  # type: ignore[arg-type]
            household_id=uuid.uuid4(),
            owner_user_id=None,
        )

    assert exc_info.value.status_code == 422
