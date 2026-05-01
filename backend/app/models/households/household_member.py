"""Household membership ORM model."""

import datetime as dt
import uuid

from sqlalchemy import Column, DateTime, Index, UniqueConstraint
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.shared.enums import HouseholdMemberRole, HouseholdMemberStatus
from app.models.shared.timestamps import TimestampedModel


class HouseholdMemberBase(SQLModel):
    """A user's membership record within a household.

    A user may only have one *active* household membership at a time.
    The ``role`` determines management permissions:
    - ``owner`` - full control, cannot be removed by others.
    - ``admin`` - can invite / remove regular members.
    - ``member`` - read-only household visibility.

    Status transitions: ``invited`` -> ``active`` (on accept) or ``removed``/``left``.
    """

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    household_id: uuid.UUID = Field(
        index=True,
        nullable=False,
        foreign_key="households.id",
    )
    user_id: uuid.UUID = Field(
        index=True,
        nullable=False,
        foreign_key="users.id",
    )
    role: HouseholdMemberRole = Field(
        sa_column=Column(
            SAEnum(HouseholdMemberRole, name="household_member_role", native_enum=False),
            nullable=False,
        )
    )
    status: HouseholdMemberStatus = Field(
        sa_column=Column(
            SAEnum(HouseholdMemberStatus, name="household_member_status", native_enum=False),
            nullable=False,
        )
    )
    joined_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )


class HouseholdMember(HouseholdMemberBase, TimestampedModel, table=True):
    """ORM table class for household memberships."""

    __tablename__ = "household_members"
    __table_args__ = (
        UniqueConstraint("household_id", "user_id", name="uq_household_members_household_user"),
        Index("ix_household_members_household_status", "household_id", "status"),
        Index("ix_household_members_user_status", "user_id", "status"),
    )
