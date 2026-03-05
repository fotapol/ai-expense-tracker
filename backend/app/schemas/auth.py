"""Authentication-related schemas for Firebase identity mapping."""

from typing import Literal
from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.shared import SchemaBase


class FirebaseIdentityIn(SchemaBase):
    """Incoming Firebase identity payload used to upsert local user records."""

    auth_provider: Literal["firebase"] = "firebase"
    auth_subject: str = Field(min_length=1, max_length=255)
    email: str | None = Field(default=None, max_length=320)

    @field_validator("auth_subject")
    @classmethod
    def normalize_subject(cls, value: str) -> str:
        """Strip auth subject before persistence."""

        return value.strip()


class FirebaseIdentityOut(SchemaBase):
    """Resolved local identity after Firebase subject lookup/upsert."""

    user_id: UUID
    auth_provider: Literal["firebase"] = "firebase"
    auth_subject: str
    email: str | None = None
    is_active: bool
    is_new_user: bool = False


class TokenExchangeRequest(SchemaBase):
    """Request payload for exchanging a Firebase ID token."""

    id_token: str = Field(min_length=1)
