import uuid

from sqlmodel import Field, SQLModel

from app.models.shared.timestamps import TimestampedModel


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
