import uuid

from sqlalchemy import Column, Index, String, text
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.shared.enums import CategoryScope
from app.models.shared.timestamps import TimestampedModel


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
    icon: str | None = Field(default=None, sa_column=Column(String(50)))
    color: str | None = Field(default=None, sa_column=Column(String(50)))
    is_active: bool = Field(default=True, nullable=False)
    user_id: uuid.UUID | None = Field(default=None, foreign_key="users.id", index=True)
    is_custom: bool = Field(default=False, nullable=False)


class Category(CategoryBase, TimestampedModel, table=True):
    """Hierarchical taxonomy node used for transaction and item categorization."""

    __tablename__ = "categories"
    __table_args__ = (
        Index("ix_categories_scope_name", "scope", "name"),
        Index(
            "uq_categories_global_scope_code",
            "scope",
            "code",
            unique=True,
            postgresql_where=text("user_id IS NULL"),
        ),
        Index(
            "uq_categories_user_scope_code",
            "scope",
            "user_id",
            "code",
            unique=True,
            postgresql_where=text("user_id IS NOT NULL"),
        ),
        Index(
            "ix_categories_scope_user_code_active",
            "scope",
            "user_id",
            "code",
            "is_active",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
