"""User and profile API schemas."""

from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.shared import (
    CurrencyCode,
    SchemaBase,
    UUIDTimestampSchema,
    normalize_currency_code,
    normalize_language_code,
)


class UserCreate(SchemaBase):
    """Payload for creating or upserting a local user record."""

    auth_provider: str = Field(default="firebase", max_length=32)
    auth_subject: str = Field(min_length=1, max_length=255)
    email: str | None = Field(default=None, max_length=320)
    default_currency: CurrencyCode = "EUR"
    items_language: str | None = Field(default=None, max_length=16)
    is_active: bool = True

    @field_validator("default_currency")
    @classmethod
    def normalize_currency(cls, value: str) -> str:
        """Normalize currency code casing."""

        return normalize_currency_code(value)

    @field_validator("items_language")
    @classmethod
    def normalize_items_language(cls, value: str | None) -> str | None:
        """Normalize items translation language code casing."""

        if value is None:
            return None
        normalized = normalize_language_code(value)
        return normalized or None


class UserUpdate(SchemaBase):
    """Partial update payload for user settings."""

    email: str | None = Field(default=None, max_length=320)
    display_name: str | None = Field(default=None, max_length=100)
    default_currency: CurrencyCode | None = None
    items_language: str | None = Field(default=None, max_length=16)
    is_active: bool | None = None

    @field_validator("default_currency")
    @classmethod
    def normalize_currency(cls, value: str | None) -> str | None:
        """Normalize currency code casing if provided."""

        if value is None:
            return None
        return normalize_currency_code(value)

    @field_validator("items_language")
    @classmethod
    def normalize_items_language(cls, value: str | None) -> str | None:
        """Normalize items translation language code casing."""

        if value is None:
            return None
        normalized = normalize_language_code(value)
        return normalized or None


class UserRead(UUIDTimestampSchema):
    """Read model for local user records."""

    auth_provider: str
    auth_subject: str
    email: str | None
    default_currency: CurrencyCode
    items_language: str | None
    is_active: bool


class ProfileCreate(SchemaBase):
    """Payload for creating a user profile row."""

    user_id: UUID
    display_name: str | None = Field(default=None, max_length=100)
    avatar_url: str | None = Field(default=None, max_length=512)


class ProfileUpdate(SchemaBase):
    """Partial update payload for profile fields."""

    display_name: str | None = Field(default=None, max_length=100)
    avatar_url: str | None = Field(default=None, max_length=512)


class ProfileRead(UUIDTimestampSchema):
    """Read model for profile data."""

    user_id: UUID
    display_name: str | None
    avatar_url: str | None


class UserWithProfileRead(UserRead):
    """User read model with optional one-to-one profile included."""

    profile: ProfileRead | None = None
