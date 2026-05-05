"""Schemas for household, membership, and invite API endpoints.
# TODO(household): disabled for single-user launch
"""

from __future__ import annotations

import datetime as dt
from typing import Literal
from uuid import UUID

from pydantic import Field, model_validator

from app.models.shared.enums import (
    HouseholdInviteStatus,
    HouseholdMemberRole,
    HouseholdMemberStatus,
)
from app.schemas.shared import SchemaBase, UUIDTimestampSchema

InviteEffectiveState = Literal["pending", "accepted", "revoked", "expired"]


class HouseholdUserSnippet(SchemaBase):
    """Lightweight user identity fields for household UI rendering."""

    user_id: UUID
    display_name: str | None = None
    email: str | None = None
    avatar_url: str | None = None


class HouseholdCreate(SchemaBase):
    """Payload for creating a new household."""

    name: str = Field(min_length=1, max_length=255)


class HouseholdUpdate(SchemaBase):
    """Payload for updating a household's display name."""

    name: str = Field(min_length=1, max_length=255)


class HouseholdRead(UUIDTimestampSchema):
    """Read model for a household record."""

    name: str
    owner_user_id: UUID


class HouseholdMemberRead(UUIDTimestampSchema):
    """Read model for a household membership row."""

    household_id: UUID
    user_id: UUID
    role: HouseholdMemberRole
    status: HouseholdMemberStatus
    joined_at: dt.datetime | None
    user: HouseholdUserSnippet | None = None


class InviteCreate(SchemaBase):
    """Payload for creating a household invite.

    Provide exactly one of ``invited_email`` or ``invited_user_id``.
    """

    invited_email: str | None = Field(default=None, max_length=320)
    invited_user_id: UUID | None = None

    @model_validator(mode="after")
    def check_at_least_one_target(self) -> InviteCreate:
        """Require exactly one invite target."""
        if not self.invited_email and not self.invited_user_id:
            raise ValueError("Provide either invited_email or invited_user_id.")
        return self


class InviteRead(UUIDTimestampSchema):
    """Read model for a household invite token."""

    household_id: UUID
    invited_by_user_id: UUID
    invited_email: str | None
    invited_user_id: UUID | None
    token: str
    invite_link: str = ""
    status: HouseholdInviteStatus
    effective_state: InviteEffectiveState = "pending"
    expires_at: dt.datetime
    accepted_at: dt.datetime | None
    created_by: HouseholdUserSnippet | None = None
    invited_user: HouseholdUserSnippet | None = None
