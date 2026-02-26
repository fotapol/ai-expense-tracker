import datetime
import uuid

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class Category(SQLModel, table=True):
    """Spending category taxonomy (e.g., Groceries, Transport).

    Used primarily to categorize transactions for analytics and reporting.
    """

    __tablename__ = "categories"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    code: str = Field(primary_key=True, unique=True, nullable=False)
    name: str = Field(max_length=30, nullable=False)
    parent_id: uuid.UUID | None = Field(default=None, foreign_key="categories.id")

    is_active: bool = Field(default=True)
    
    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
