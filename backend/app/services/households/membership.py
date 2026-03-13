"""Household membership and permission helpers."""

from __future__ import annotations

import uuid

from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.models.households.household_member import HouseholdMember
from app.models.shared.enums import HouseholdMemberRole, HouseholdMemberStatus


def get_member_for_user(
    session: Session,
    household_id: uuid.UUID,
    user_id: uuid.UUID,
) -> HouseholdMember | None:
    """Return the active membership row for a specific user in a household."""
    return session.exec(
        select(HouseholdMember).where(
            HouseholdMember.household_id == household_id,
            HouseholdMember.user_id == user_id,
            HouseholdMember.status == HouseholdMemberStatus.ACTIVE,
        )
    ).first()


def assert_household_owner(member: HouseholdMember | None) -> None:
    """Raise 403 if the user is not the household owner."""
    if member is None or member.role != HouseholdMemberRole.OWNER:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the household owner can perform this action.",
        )


def assert_household_admin_or_owner(member: HouseholdMember | None) -> None:
    """Raise 403 if the user is not an admin or the household owner."""
    if member is None or member.role not in {
        HouseholdMemberRole.OWNER,
        HouseholdMemberRole.ADMIN,
    }:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin or owner access is required for this action.",
        )


def assert_household_member(member: HouseholdMember | None) -> None:
    """Raise 403 if the user is not an active member of the household."""
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this household.",
        )


def remove_member(
    session: Session,
    member: HouseholdMember,
    *,
    requesting_member: HouseholdMember,
) -> HouseholdMember:
    """Remove a member from a household.

    Rules for v1:
    - Owner cannot be removed.
    - Only owner can remove members.
    """
    if member.role == HouseholdMemberRole.OWNER:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="The household owner cannot be removed. Transfer ownership first.",
        )

    if requesting_member.role != HouseholdMemberRole.OWNER:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the household owner can remove members.",
        )

    member.status = HouseholdMemberStatus.REMOVED
    session.add(member)
    session.commit()
    session.refresh(member)
    return member


def validate_transaction_attribution(
    session: Session,
    *,
    household_id: uuid.UUID | None,
    owner_user_id: uuid.UUID | None,
) -> None:
    """Validate expense attribution for a transaction.

    If ``household_id`` is provided, ``owner_user_id`` must be an active member
    of that household.  If ``household_id`` is None, no cross-user attribution
    validation is required at this layer (the router handles user scoping).

    Raises ``HTTPException(422)`` on validation failures.
    """
    if household_id is None:
        return  # Solo transaction — no membership check needed.

    if owner_user_id is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="owner_user_id must be set when household_id is provided.",
        )

    member = get_member_for_user(session, household_id, owner_user_id)
    if member is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="owner_user_id must be an active member of the specified household.",
        )
