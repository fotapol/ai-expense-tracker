"""Household (family group) ORM model."""

import uuid

from sqlalchemy import Column, Index, String
from sqlmodel import Field, SQLModel

from app.models.shared.timestamps import TimestampedModel


class HouseholdBase(SQLModel):
    """Shared attributes for household read and write schemas."""

    name: str = Field(sa_column=Column(String(255), nullable=False))


class Household(HouseholdBase, TimestampedModel, table=True):
    """A household groups users together for shared expense tracking.

    The ``owner_user_id`` refers to the user who created the household and
    retains full management rights.  Membership is tracked in a separate
    ``household_members`` table so that roles and statuses can evolve over time.
    """

    __tablename__ = "households"
    __table_args__ = (
        Index("ix_households_owner_user_id", "owner_user_id"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    owner_user_id: uuid.UUID = Field(
        index=True,
        nullable=False,
        foreign_key="users.id",
    )
