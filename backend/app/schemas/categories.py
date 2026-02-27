"""Category taxonomy schemas."""

from __future__ import annotations

from uuid import UUID

from pydantic import Field, field_validator

from app.models.shared.enums import CategoryScope
from app.schemas.shared import SchemaBase, UUIDTimestampSchema


class CategoryCreate(SchemaBase):
    """Payload for creating a taxonomy category node."""

    scope: CategoryScope
    code: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=120)
    parent_id: UUID | None = None
    is_active: bool = True

    @field_validator("code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        """Normalize category code for stable lookups."""

        return value.strip().upper()


class CategoryUpdate(SchemaBase):
    """Partial payload for updating a taxonomy category node."""

    name: str | None = Field(default=None, min_length=1, max_length=120)
    parent_id: UUID | None = None
    is_active: bool | None = None


class CategoryRead(UUIDTimestampSchema):
    """Read model for taxonomy categories."""

    scope: CategoryScope
    code: str
    name: str
    parent_id: UUID | None
    is_active: bool


class CategoryTreeNode(CategoryRead):
    """Recursive read model for hierarchical taxonomy responses."""

    children: list[CategoryTreeNode] = Field(default_factory=list)
