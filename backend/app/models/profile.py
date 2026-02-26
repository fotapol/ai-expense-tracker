import datetime
import uuid

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class ProfileBase(SQLModel):
    """Shared fields for a user profile.

    This model is not a table. It is used to compose the table model and
    request/response schemas.
    """

    display_name: str | None = Field(default=None, max_length=100)
    avatar_url: str | None = Field(default=None, max_length=255)


class Profile(ProfileBase, table=True):
    """User profile stored in the database.

    A profile is a 1:1 extension of a user identity. It stores app-specific
    user-facing fields (e.g., display name, avatar) that are not part of the
    authentication provider.
    """

    user_id: uuid.UUID = Field(index=True, unique=True, nullable=False, foreign_key="user.id", primary_key=True)

    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
    updated_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), onupdate=func.now(), nullable=False)
    )
