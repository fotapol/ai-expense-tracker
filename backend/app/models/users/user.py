import uuid

from sqlalchemy import CHAR, Column, String
from sqlmodel import Field, SQLModel

from app.models.shared.timestamps import TimestampedModel


class UserBase(SQLModel):
    """User attributes that are independent from the external auth provider."""

    email: str | None = Field(default=None, max_length=320, index=True)
    default_currency: str = Field(
        default="EUR",
        sa_column=Column(CHAR(3), nullable=False, default="EUR"),
    )
    is_active: bool = Field(default=True, nullable=False)


class User(UserBase, TimestampedModel, table=True):
    """Local application user linked to a Firebase subject identifier.

    This table maps a stable internal UUID to external auth identity fields so
    downstream records can rely on internal foreign keys.
    """

    __tablename__ = "users"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    auth_provider: str = Field(
        default="firebase",
        sa_column=Column(String(32), nullable=False, default="firebase"),
    )
    auth_subject: str = Field(max_length=255, nullable=False, unique=True, index=True)

