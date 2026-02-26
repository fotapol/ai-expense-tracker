import uuid

from sqlalchemy import Column, Index, UniqueConstraint
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.enums import CategoryScope
from app.models.timestamps import TimestampedModel


class CategoryBase(SQLModel):
    """Base category fields shared by category table and payload schemas."""

    scope: CategoryScope = Field(
        sa_column=Column(
            SAEnum(CategoryScope, name="category_scope", native_enum=False),
            nullable=False,
        )
    )
    code: str = Field(max_length=64, nullable=False)
    name: str = Field(max_length=120, nullable=False)
    parent_id: uuid.UUID | None = Field(default=None, foreign_key="categories.id", index=True)
    is_active: bool = Field(default=True, nullable=False)


class Category(CategoryBase, TimestampedModel, table=True):
    """Hierarchical taxonomy node used for transaction and item categorization."""

    __tablename__ = "categories"
    __table_args__ = (
        UniqueConstraint("scope", "code", name="uq_categories_scope_code"),
        Index("ix_categories_scope_name", "scope", "name"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
