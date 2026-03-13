import uuid
from typing import TYPE_CHECKING

from sqlmodel import Field, Relationship, SQLModel

from app.models.shared.timestamps import TimestampedModel

if TYPE_CHECKING:
    from app.models.users.user import User


class ProfileBase(SQLModel):
    """Base profile attributes displayed in the frontend."""

    display_name: str | None = Field(default=None, max_length=100)
    avatar_url: str | None = Field(default=None, max_length=512)


class Profile(ProfileBase, TimestampedModel, table=True):
    """One-to-one extension table containing user-facing profile metadata."""

    __tablename__ = "profiles"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(
        nullable=False,
        unique=True,
        index=True,
        foreign_key="users.id",
    )

    user: "User" = Relationship(back_populates="profile")
