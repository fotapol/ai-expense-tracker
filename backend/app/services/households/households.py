"""Household creation and management service."""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import HTTPException, status
from sqlmodel import Session, select

from app.models.billing.entitlement import Entitlement
from app.models.households.household import Household
from app.models.households.household_invite import HouseholdInvite
from app.models.households.household_member import HouseholdMember
from app.models.shared.enums import (
    EntitlementScopeType,
    EntitlementStatus,
    HouseholdMemberRole,
    HouseholdMemberStatus,
    TransactionSource,
)
from app.models.transactions.transaction import Transaction
from app.models.users.user import User


def _utcnow() -> dt.datetime:
    return dt.datetime.now(dt.UTC)


def attach_existing_manual_transactions_to_household(
    session: Session,
    *,
    user_id: uuid.UUID,
    household_id: uuid.UUID,
) -> list[Transaction]:
    """Attach legacy solo manual transactions to a newly active household."""

    transactions = session.exec(
        select(Transaction).where(
            Transaction.user_id == user_id,
            Transaction.source == TransactionSource.MANUAL,
            Transaction.receipt_id.is_(None),
            Transaction.household_id.is_(None),
        )
    ).all()

    attached: list[Transaction] = []
    for transaction in transactions:
        if (
            transaction.source != TransactionSource.MANUAL
            or transaction.receipt_id is not None
            or transaction.household_id is not None
        ):
            continue
        transaction.household_id = household_id
        if transaction.created_by_user_id is None:
            transaction.created_by_user_id = transaction.user_id
        if transaction.owner_user_id is None:
            transaction.owner_user_id = transaction.user_id
        session.add(transaction)
        attached.append(transaction)

    return attached


def create_household(
    session: Session,
    *,
    name: str,
    owner: User,
) -> Household:
    """Create a new household and insert the creator as the owner member.

    Raises ``HTTPException(409)`` if the creator already has an active household.
    """
    # Enforce single active membership per user.
    existing = get_active_household_for_user(session, owner.id)
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You already belong to an active household. Leave it before creating a new one.",
        )

    household = Household(
        name=name.strip(),
        owner_user_id=owner.id,
    )
    session.add(household)
    session.flush()  # Obtain PK before member insert.

    now = _utcnow()
    member = HouseholdMember(
        household_id=household.id,
        user_id=owner.id,
        role=HouseholdMemberRole.OWNER,
        status=HouseholdMemberStatus.ACTIVE,
        joined_at=now,
    )
    session.add(member)
    attach_existing_manual_transactions_to_household(
        session,
        user_id=owner.id,
        household_id=household.id,
    )
    session.commit()
    session.refresh(household)
    return household


def get_active_household_for_user(
    session: Session,
    user_id: uuid.UUID,
) -> Household | None:
    """Return the first household where the user has an active membership, or None."""
    member_row = session.exec(
        select(HouseholdMember).where(
            HouseholdMember.user_id == user_id,
            HouseholdMember.status == HouseholdMemberStatus.ACTIVE,
        )
    ).first()
    if member_row is None:
        return None
    return session.get(Household, member_row.household_id)


def update_household(
    session: Session,
    household: Household,
    *,
    name: str,
) -> Household:
    """Update a household's display name."""
    household.name = name.strip()
    session.add(household)
    session.commit()
    session.refresh(household)
    return household


def list_household_members(
    session: Session,
    household_id: uuid.UUID,
) -> list[HouseholdMember]:
    """Return all non-removed members for the given household."""
    return session.exec(
        select(HouseholdMember).where(
            HouseholdMember.household_id == household_id,
            HouseholdMember.status.in_([  # type: ignore[attr-defined]
                HouseholdMemberStatus.ACTIVE,
                HouseholdMemberStatus.INVITED,
            ]),
        )
    ).all()


def delete_household(
    session: Session,
    household: Household,
) -> None:
    """Remove a household and detach its shared transactions."""

    current_time = _utcnow()

    transactions = session.exec(
        select(Transaction).where(Transaction.household_id == household.id)
    ).all()
    for transaction in transactions:
        transaction.household_id = None
        session.add(transaction)

    household_entitlements = session.exec(
        select(Entitlement).where(
            Entitlement.scope_type == EntitlementScopeType.HOUSEHOLD,
            Entitlement.scope_id == household.id,
        )
    ).all()
    for entitlement in household_entitlements:
        entitlement.status = EntitlementStatus.REVOKED
        entitlement.expires_at = current_time
        session.add(entitlement)

    invites = session.exec(
        select(HouseholdInvite).where(HouseholdInvite.household_id == household.id)
    ).all()
    for invite in invites:
        session.delete(invite)

    members = session.exec(
        select(HouseholdMember).where(HouseholdMember.household_id == household.id)
    ).all()
    for member in members:
        session.delete(member)

    session.flush()
    session.delete(household)
    session.commit()
