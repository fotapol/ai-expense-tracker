"""Merchant normalization and alias schemas."""

from uuid import UUID

from pydantic import Field, model_validator

from app.schemas.shared import SchemaBase, UUIDTimestampSchema


class MerchantRead(UUIDTimestampSchema):
    """Read model for canonical merchants."""

    canonical_name: str
    country: str | None


class MerchantAliasCreate(SchemaBase):
    """Payload for creating merchant alias mappings."""

    merchant_id: UUID
    user_id: UUID | None = None
    alias: str = Field(min_length=1, max_length=255)
    normalized_alias: str | None = Field(default=None, min_length=1, max_length=255)

    @model_validator(mode="after")
    def infer_normalized_alias(self) -> "MerchantAliasCreate":
        """Populate normalized alias when omitted."""

        if self.normalized_alias is None:
            self.normalized_alias = self.alias.strip().lower()
        else:
            self.normalized_alias = self.normalized_alias.strip().lower()
        return self


class MerchantAliasRead(UUIDTimestampSchema):
    """Read model for merchant alias mappings."""

    merchant_id: UUID
    user_id: UUID | None
    alias: str
    normalized_alias: str
