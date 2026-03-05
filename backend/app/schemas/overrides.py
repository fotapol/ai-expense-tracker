"""Schemas for user-level categorization override rules."""

from uuid import UUID

from pydantic import Field, field_validator

from app.schemas.shared import SchemaBase, UUIDTimestampSchema


class UserCategoryOverrideUpsert(SchemaBase):
    """Payload for setting a user's transaction category override by merchant."""

    user_id: UUID
    merchant_id: UUID
    category_id: UUID


class UserCategoryOverrideRead(UUIDTimestampSchema):
    """Read model for user transaction-category override rules."""

    user_id: UUID
    merchant_id: UUID
    category_id: UUID


class UserItemCategoryOverrideUpsert(SchemaBase):
    """Payload for setting a user's item-level category override."""

    user_id: UUID
    merchant_id: UUID | None = None
    item_key: str = Field(min_length=1, max_length=255)
    category_id: UUID

    @field_validator("item_key")
    @classmethod
    def normalize_item_key(cls, value: str) -> str:
        """Normalize item key for consistent matching."""

        return value.strip().lower()


class UserItemCategoryOverrideRead(UUIDTimestampSchema):
    """Read model for user item-category override rules."""

    user_id: UUID
    merchant_id: UUID | None
    item_key: str
    category_id: UUID
