"""Household invite token ORM model."""

import datetime as dt
import uuid

from sqlalchemy import Column, DateTime, Index, String
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.shared.enums import HouseholdInviteStatus
from app.models.shared.timestamps import TimestampedModel


class HouseholdInviteBase(SQLModel):
    """A one-time invite token sent to join a household.

    Invites may target an existing user (``invited_user_id``) or an email
    address (``invited_email``) for users who haven't yet registered.
    The ``token`` is a UUID-based string that must remain secret until shared
    via an out-of-band channel (e.g., deep-link or copy-paste).

    Status transitions: ``pending`` → ``accepted`` | ``expired`` | ``revoked``.
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    household_id: uuid.UUID = Field(
        index=True,
        nullable=False,
        foreign_key="households.id",
    )
    invited_by_user_id: uuid.UUID = Field(
        index=True,
        nullable=False,
        foreign_key="users.id",
    )
    invited_email: str | None = Field(
        default=None,
        sa_column=Column(String(320), nullable=True),
    )
    invited_user_id: uuid.UUID | None = Field(
        default=None,
        nullable=True,
        foreign_key="users.id",
    )
    token: str = Field(
        sa_column=Column(String(64), nullable=False, unique=True),
    )
    status: HouseholdInviteStatus = Field(
        sa_column=Column(
            SAEnum(HouseholdInviteStatus, name="household_invite_status", native_enum=False),
            nullable=False,
        )
    )
    expires_at: dt.datetime = Field(
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
    accepted_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )


class HouseholdInvite(HouseholdInviteBase, TimestampedModel, table=True):
    """ORM table class for household invites."""

    __tablename__ = "household_invites"
    __table_args__ = (
        Index("ix_household_invites_token", "token", unique=True),
        Index("ix_household_invites_household_status", "household_id", "status"),
        Index("ix_household_invites_invited_user_id", "invited_user_id"),
    )
