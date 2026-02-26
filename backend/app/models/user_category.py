import uuid

from sqlalchemy import Index, UniqueConstraint, text
from sqlmodel import Field

from app.models.timestamps import TimestampedModel


class UserCategoryOverride(TimestampedModel, table=True):
    """Per-user merchant default category override for transaction-level categorization."""

    __tablename__ = "user_category_overrides"
    __table_args__ = (
        UniqueConstraint("user_id", "merchant_id", name="uq_user_category_overrides_user_merchant"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")
    merchant_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="merchants.id")
    category_id: uuid.UUID = Field(nullable=False, foreign_key="categories.id")


class UserItemCategoryOverride(TimestampedModel, table=True):
    """Per-user item categorization override, optionally scoped to a merchant."""

    __tablename__ = "user_item_category_overrides"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "merchant_id",
            "item_key",
            name="uq_user_item_category_overrides_user_merchant_item",
        ),
        Index(
            "uq_user_item_category_overrides_user_item_global",
            "user_id",
            "item_key",
            unique=True,
            postgresql_where=text("merchant_id IS NULL"),
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(nullable=False, index=True, foreign_key="users.id")
    merchant_id: uuid.UUID | None = Field(default=None, index=True, foreign_key="merchants.id")
    item_key: str = Field(max_length=255, nullable=False)
    category_id: uuid.UUID = Field(nullable=False, foreign_key="categories.id")
