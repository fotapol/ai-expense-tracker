import datetime
import uuid

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class UserBase(SQLModel):
    """Application-level user fields.

    This model stores settings and metadata that are not owned by the auth provider.
    Authentication identity (provider + subject) lives in the User table.
    """

    email: str | None = Field(default=None, max_length=320, index=True)
    default_currency: str = Field(default="EUR", max_length=3)
    timezone: str = Field(default="Europe/Paris", max_length=64)
    is_active: bool = Field(default=True)


class User(UserBase, table=True):
    """User entity in the application database.

    This table links an external auth identity (e.g., Firebase UID) to an internal
    stable UUID used as a foreign key across domain tables (receipts, transactions, etc.).
    """

    __tablename__ = "users"
    
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    auth_provider: str = Field(default="firebase", max_length=32, nullable=False)
    auth_subject: str = Field(max_length=128, nullable=False, unique=True, index=True)

    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
    updated_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), onupdate=func.now(), nullable=False)
    )
