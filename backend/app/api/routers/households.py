"""Household API endpoints.
# TODO(household): disabled for single-user launch
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.households.household_invite import HouseholdInvite
from app.models.households.household_member import HouseholdMember
from app.models.users.profile import Profile
from app.models.users.user import User
from app.schemas.households import (
    HouseholdCreate,
    HouseholdMemberRead,
    HouseholdRead,
    HouseholdUpdate,
    HouseholdUserSnippet,
    InviteCreate,
    InviteRead,
)
from app.services.billing import PREMIUM_FAMILY_PLAN, user_has_feature
from app.services.households import (
    accept_invite,
    build_invite_link,
    create_household,
    create_invite,
    delete_household,
    derive_invite_effective_state,
    get_active_household_for_user,
    get_invite_by_id,
    get_member_for_user,
    leave_household,
    list_household_invites,
    list_household_members,
    remove_member,
    revoke_invite,
    update_household,
)
from app.services.households.membership import assert_household_member, assert_household_owner

router = APIRouter(prefix="/v1", tags=["households"])


def _require_active_household(session: Session, current_user: User):
    """Return the current user's active household or raise 404."""
    household = get_active_household_for_user(session, current_user.id)
    if household is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="You are not a member of any household.",
        )
    return household


def _assert_household_management_entitlement(session: Session, current_user: User) -> None:
    """Require the family-plan entitlement for mutating household actions."""
    if user_has_feature(session, current_user.id, PREMIUM_FAMILY_PLAN):
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Household management requires an active family plan.",
    )


def _load_user_snippets(
    session: Session,
    user_ids: set[UUID],
) -> dict[UUID, HouseholdUserSnippet]:
    """Load user snippets (email/profile) for household views."""
    if not user_ids:
        return {}
    rows = session.exec(
        select(User.id, User.email, Profile.display_name, Profile.avatar_url)
        .select_from(User)
        .join(Profile, Profile.user_id == User.id, isouter=True)
        .where(User.id.in_(user_ids))
    ).all()
    return {
        user_id: HouseholdUserSnippet(
            user_id=user_id,
            display_name=display_name,
            email=email,
            avatar_url=avatar_url,
        )
        for user_id, email, display_name, avatar_url in rows
    }


def _to_member_read(
    member: HouseholdMember,
    snippets_by_user_id: dict[UUID, HouseholdUserSnippet],
) -> HouseholdMemberRead:
    payload = HouseholdMemberRead.model_validate(member)
    payload.user = snippets_by_user_id.get(member.user_id)
    return payload


def _to_invite_read(
    invite: HouseholdInvite,
    snippets_by_user_id: dict[UUID, HouseholdUserSnippet],
) -> InviteRead:
    payload = InviteRead.model_validate(invite)
    payload.invite_link = build_invite_link(invite.token)
    payload.effective_state = derive_invite_effective_state(
        status_value=invite.status,
        expires_at=invite.expires_at,
    )
    payload.created_by = snippets_by_user_id.get(invite.invited_by_user_id)
    if invite.invited_user_id is not None:
        payload.invited_user = snippets_by_user_id.get(invite.invited_user_id)
    return payload


@router.post("/households", response_model=HouseholdRead, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")
async def create_household_endpoint(
    payload: HouseholdCreate,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> HouseholdRead:
    """Create a new household. The caller becomes the owner."""
    _assert_household_management_entitlement(session, current_user)
    household = create_household(session, name=payload.name, owner=current_user)
    return HouseholdRead.model_validate(household)


@router.get("/households/current", response_model=HouseholdRead)
@limiter.limit("60/minute")
async def get_current_household(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> HouseholdRead:
    """Return the caller's active household."""
    household = _require_active_household(session, current_user)
    return HouseholdRead.model_validate(household)


@router.patch("/households/current", response_model=HouseholdRead)
@limiter.limit("20/minute")
async def update_current_household(
    payload: HouseholdUpdate,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> HouseholdRead:
    """Update the household display name. Owner only."""
    household = _require_active_household(session, current_user)
    member = get_member_for_user(session, household.id, current_user.id)
    assert_household_owner(member)
    _assert_household_management_entitlement(session, current_user)
    household = update_household(session, household, name=payload.name)
    return HouseholdRead.model_validate(household)


@router.post("/households/current/leave", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("20/minute")
async def leave_current_household(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Leave the active household as a non-owner member."""

    household = _require_active_household(session, current_user)
    member = get_member_for_user(session, household.id, current_user.id)
    assert_household_member(member)
    leave_household(session, member)
    return None


@router.delete("/households/current", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def delete_current_household(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Remove the caller's household entirely. Owner only."""

    household = _require_active_household(session, current_user)
    member = get_member_for_user(session, household.id, current_user.id)
    assert_household_owner(member)
    delete_household(session, household)
    return None


@router.get("/households/current/members", response_model=list[HouseholdMemberRead])
@limiter.limit("60/minute")
async def list_current_members(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> list[HouseholdMemberRead]:
    """List active/invited members in the caller's household."""
    household = _require_active_household(session, current_user)
    member = get_member_for_user(session, household.id, current_user.id)
    assert_household_member(member)
    members = list_household_members(session, household.id)
    snippets = _load_user_snippets(session, {row.user_id for row in members})
    return [_to_member_read(row, snippets) for row in members]


@router.post(
    "/households/current/invites",
    response_model=InviteRead,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("20/minute")
async def create_household_invite(
    payload: InviteCreate,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> InviteRead:
    """Create a household invite. Owner only in v1."""
    household = _require_active_household(session, current_user)
    member = get_member_for_user(session, household.id, current_user.id)
    assert_household_owner(member)
    _assert_household_management_entitlement(session, current_user)
    invite = create_invite(
        session,
        household,
        current_user,
        invited_email=payload.invited_email,
        invited_user_id=payload.invited_user_id,
    )
    snippet_user_ids: set[UUID] = {current_user.id}
    if invite.invited_user_id is not None:
        snippet_user_ids.add(invite.invited_user_id)
    snippets = _load_user_snippets(session, snippet_user_ids)
    return _to_invite_read(invite, snippets)


@router.get("/households/current/invites", response_model=list[InviteRead])
@limiter.limit("60/minute")
async def list_current_household_invites(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> list[InviteRead]:
    """List household invites across all states. Owner only in v1."""
    household = _require_active_household(session, current_user)
    member = get_member_for_user(session, household.id, current_user.id)
    assert_household_owner(member)
    invites = list_household_invites(session, household.id)
    user_ids: set[UUID] = {current_user.id}
    for invite in invites:
        user_ids.add(invite.invited_by_user_id)
        if invite.invited_user_id is not None:
            user_ids.add(invite.invited_user_id)
    snippets = _load_user_snippets(session, user_ids)
    return [_to_invite_read(invite, snippets) for invite in invites]


@router.post(
    "/households/current/invites/{invite_id}/revoke",
    response_model=InviteRead,
)
@limiter.limit("20/minute")
async def revoke_current_household_invite(
    invite_id: UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> InviteRead:
    """Revoke a pending household invite. Owner only in v1."""
    household = _require_active_household(session, current_user)
    member = get_member_for_user(session, household.id, current_user.id)
    assert_household_owner(member)
    _assert_household_management_entitlement(session, current_user)

    invite = get_invite_by_id(session, invite_id)
    if invite is None or invite.household_id != household.id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invite not found in your household.",
        )

    updated = revoke_invite(session, invite)
    snippet_user_ids: set[UUID] = {current_user.id, updated.invited_by_user_id}
    if updated.invited_user_id is not None:
        snippet_user_ids.add(updated.invited_user_id)
    snippets = _load_user_snippets(session, snippet_user_ids)
    return _to_invite_read(updated, snippets)


@router.post("/household-invites/{token}/accept", response_model=HouseholdMemberRead)
@limiter.limit("20/minute")
async def accept_household_invite(
    token: str,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> HouseholdMemberRead:
    """Accept a household invite by token and join the household."""
    member = accept_invite(session, token, current_user)
    snippets = _load_user_snippets(session, {member.user_id})
    return _to_member_read(member, snippets)


@router.post(
    "/households/current/members/{member_id}/remove",
    response_model=HouseholdMemberRead,
)
@limiter.limit("20/minute")
async def remove_household_member(
    member_id: UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
) -> HouseholdMemberRead:
    """Remove a member from the household. Owner only in v1."""
    household = _require_active_household(session, current_user)
    requesting_member = get_member_for_user(session, household.id, current_user.id)
    assert_household_owner(requesting_member)
    _assert_household_management_entitlement(session, current_user)

    target_member = session.exec(
        select(HouseholdMember).where(
            HouseholdMember.id == member_id,
            HouseholdMember.household_id == household.id,
        )
    ).first()

    if target_member is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found in your household.",
        )

    updated = remove_member(session, target_member, requesting_member=requesting_member)
    snippets = _load_user_snippets(session, {updated.user_id})
    return _to_member_read(updated, snippets)
