import datetime
import uuid

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class UserCategoryOverride(SQLModel, table=True):
    """Per-user merchant-to-category override.

    Used to auto-categorize future transactions from the same merchant.
    """

    __tablename__ = "user_category_overrides"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)

    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")

    merchant_key: str = Field(max_length=128, nullable=False, index=True)
    category_id: uuid.UUID = Field(nullable=False, foreign_key="categories.id")

    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
