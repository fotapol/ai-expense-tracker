"""Household invite service."""

from __future__ import annotations

import datetime as dt
import uuid
from typing import Literal

from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.core.config import app_settings
from app.models.households.household import Household
from app.models.households.household_invite import HouseholdInvite
from app.models.households.household_member import HouseholdMember
from app.models.shared.enums import (
    HouseholdInviteStatus,
    HouseholdMemberRole,
    HouseholdMemberStatus,
)
from app.models.users.user import User


# NOTE: imported here rather than from households.households to avoid a circular
# dependency at module load time; the households service is loaded lazily via
# the services.households package.
def _get_active_household_for_user(session, user_id):
    """Thin wrapper imported lazily to allow monkeypatching in tests."""
    from app.services.households.households import get_active_household_for_user
    return get_active_household_for_user(session, user_id)


_DEFAULT_INVITE_TTL_HOURS = 72
InviteEffectiveState = Literal["pending", "accepted", "revoked", "expired"]


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def build_invite_link(token: str) -> str:
    """Build a canonical HTTPS invite link from ``PUBLIC_APP_BASE_URL``."""
    base_url = app_settings.PUBLIC_APP_BASE_URL
    if not base_url:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Invite links are not configured. Missing PUBLIC_APP_BASE_URL.",
        )
    return f"{base_url}/household-invite?token={token}"


def derive_invite_effective_state(
    *,
    status_value: HouseholdInviteStatus | str,
    expires_at: dt.datetime,
    now: dt.datetime | None = None,
) -> InviteEffectiveState:
    """Derive a read-only invite state from status + expiry timestamp."""
    current_time = now or _utcnow()
    if (
        status_value == HouseholdInviteStatus.PENDING
        and expires_at <= current_time
    ):
        return "expired"
    if status_value == HouseholdInviteStatus.ACCEPTED:
        return "accepted"
    if status_value == HouseholdInviteStatus.REVOKED:
        return "revoked"
    if status_value == HouseholdInviteStatus.EXPIRED:
        return "expired"
    return "pending"


def create_invite(
    session: Session,
    household: Household,
    invited_by: User,
    *,
    invited_email: str | None = None,
    invited_user_id: uuid.UUID | None = None,
    ttl_hours: int = _DEFAULT_INVITE_TTL_HOURS,
) -> HouseholdInvite:
    """Create a new pending invite for a household.

    Either ``invited_email`` or ``invited_user_id`` must be provided.
    """
    if not invited_email and not invited_user_id:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Provide either invited_email or invited_user_id.",
        )

    # If targeting an existing user, check they are not already a member.
    if invited_user_id is not None:
        existing = session.exec(
            select(HouseholdMember).where(
                HouseholdMember.household_id == household.id,
                HouseholdMember.user_id == invited_user_id,
                HouseholdMember.status == HouseholdMemberStatus.ACTIVE,
            )
        ).first()
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="User is already an active member of this household.",
            )

    now = _utcnow()
    token = uuid.uuid4().hex  # 32-char hex token

    invite = HouseholdInvite(
        household_id=household.id,
        invited_by_user_id=invited_by.id,
        invited_email=invited_email,
        invited_user_id=invited_user_id,
        token=token,
        status=HouseholdInviteStatus.PENDING,
        expires_at=now + dt.timedelta(hours=ttl_hours),
    )
    session.add(invite)
    session.commit()
    session.refresh(invite)
    return invite


def get_invite_by_token(
    session: Session,
    token: str,
) -> HouseholdInvite | None:
    """Look up an invite by its token string."""
    return session.exec(
        select(HouseholdInvite).where(HouseholdInvite.token == token)
    ).first()


def get_invite_by_id(
    session: Session,
    invite_id: uuid.UUID,
) -> HouseholdInvite | None:
    """Look up an invite by primary key."""
    return session.get(HouseholdInvite, invite_id)


def accept_invite(
    session: Session,
    token: str,
    accepting_user: User,
) -> HouseholdMember:
    """Accept a household invite and create/activate the membership row.

    Raises ``HTTPException(404)`` if token not found.
    Raises ``HTTPException(410)`` if invite is expired or already used.
    Raises ``HTTPException(409)`` if user already belongs to another active household.
    """
    invite = get_invite_by_token(session, token)
    if invite is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invite not found.",
        )

    now = _utcnow()

    if invite.status != HouseholdInviteStatus.PENDING or invite.expires_at <= now:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="This invite has already been used, revoked, or has expired.",
        )

    # Ensure the accepting user doesn't already have an active household.
    existing_household = _get_active_household_for_user(session, accepting_user.id)
    if existing_household is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "You already belong to another household. "
                "Leave your current household before accepting this invite."
            ),
        )

    # Upsert household_members row.
    existing_member = session.exec(
        select(HouseholdMember).where(
            HouseholdMember.household_id == invite.household_id,
            HouseholdMember.user_id == accepting_user.id,
        )
    ).first()

    if existing_member is not None:
        existing_member.status = HouseholdMemberStatus.ACTIVE
        existing_member.joined_at = now
        member = existing_member
    else:
        member = HouseholdMember(
            household_id=invite.household_id,
            user_id=accepting_user.id,
            role=HouseholdMemberRole.MEMBER,
            status=HouseholdMemberStatus.ACTIVE,
            joined_at=now,
        )

    session.add(member)
    from app.services.households.households import (
        attach_existing_manual_transactions_to_household,
    )

    attach_existing_manual_transactions_to_household(
        session,
        user_id=accepting_user.id,
        household_id=invite.household_id,
    )

    # Mark invite accepted.
    invite.status = HouseholdInviteStatus.ACCEPTED
    invite.accepted_at = now
    session.add(invite)

    session.commit()
    session.refresh(member)
    return member


def revoke_invite(
    session: Session,
    invite: HouseholdInvite,
) -> HouseholdInvite:
    """Revoke a pending invite so it can no longer be accepted."""
    now = _utcnow()
    if (
        invite.status != HouseholdInviteStatus.PENDING
        or derive_invite_effective_state(
            status_value=invite.status,
            expires_at=invite.expires_at,
            now=now,
        ) != "pending"
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only pending invites can be revoked.",
        )
    invite.status = HouseholdInviteStatus.REVOKED
    session.add(invite)
    session.commit()
    session.refresh(invite)
    return invite


def list_pending_invites(
    session: Session,
    household_id: uuid.UUID,
) -> list[HouseholdInvite]:
    """Return all pending (non-expired) invites for a household."""
    now = _utcnow()
    return session.exec(
        select(HouseholdInvite).where(
            HouseholdInvite.household_id == household_id,
            HouseholdInvite.status == HouseholdInviteStatus.PENDING,
            HouseholdInvite.expires_at > now,
        )
    ).all()


def list_household_invites(
    session: Session,
    household_id: uuid.UUID,
) -> list[HouseholdInvite]:
    """Return household invites across all statuses for management UI."""
    return session.exec(
        select(HouseholdInvite)
        .where(HouseholdInvite.household_id == household_id)
        .order_by(HouseholdInvite.created_at.desc())
    ).all()
