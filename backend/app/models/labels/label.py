import uuid

from sqlalchemy import Column, String
from sqlmodel import Field, SQLModel

from app.models.shared.timestamps import TimestampedModel


class LabelBase(SQLModel):
    """Base label fields."""

    name: str = Field(max_length=120, nullable=False)
    color: str | None = Field(
        default=None,
        sa_column=Column(String(7), nullable=True),  # Hex color like #FF5733
    )


class Label(LabelBase, TimestampedModel, table=True):
    """User-created label (tag) that can be linked to transactions."""

    __tablename__ = "labels"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    user_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="users.id")
    is_active: bool = Field(default=True, nullable=False)
