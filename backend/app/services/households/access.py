"""Helpers for household-scoped access and attribution defaults."""

from __future__ import annotations

import uuid

from sqlmodel import Session

from app.services.billing import PREMIUM_FAMILY_PLAN, user_has_feature
from app.services.households.households import get_active_household_for_user


def get_active_shared_household_id(
    session: Session,
    user_id: uuid.UUID,
) -> uuid.UUID | None:
    """Return the caller's active household when family sharing is currently active."""

    if not user_has_feature(session, user_id, PREMIUM_FAMILY_PLAN):
        return None
    household = get_active_household_for_user(session, user_id)
    if household is None:
        return None
    from app.services.households.households import (
        attach_existing_manual_transactions_to_household,
    )

    attached = attach_existing_manual_transactions_to_household(
        session,
        user_id=user_id,
        household_id=household.id,
    )
    if attached:
        session.commit()
    return household.id
