"""Label API schemas."""

from uuid import UUID

from pydantic import Field

from app.schemas.shared import SchemaBase


class LabelCreateRequest(SchemaBase):
    name: str = Field(min_length=1, max_length=120)
    color: str | None = Field(default=None, max_length=7)


class LabelAssignRequest(SchemaBase):
    transaction_id: UUID
    label_id: UUID


class LabelRead(SchemaBase):
    id: UUID
    name: str
    color: str | None = None
