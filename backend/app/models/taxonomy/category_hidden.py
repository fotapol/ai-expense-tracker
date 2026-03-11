import uuid
from sqlmodel import Field, SQLModel
from app.models.shared.timestamps import TimestampedModel

class UserHiddenCategory(TimestampedModel, table=True):
    """Tracks global built-in categories that a specific user has chosen to hide/delete."""

    __tablename__ = "user_hidden_categories"

    user_id: uuid.UUID = Field(foreign_key="users.id", primary_key=True)
    category_id: uuid.UUID = Field(foreign_key="categories.id", primary_key=True)
