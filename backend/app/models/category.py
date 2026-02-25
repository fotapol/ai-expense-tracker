import datetime
import uuid

from sqlalchemy import DateTime, func
from sqlmodel import Column, Field, SQLModel


class CategoryBase(SQLModel):
    icon_url: str | None = Field(default=None, max_length=255)

class Category(CategoryBase, table=True):
    code: str = Field(primary_key=True, unique=True, nullable=False)
    name: str = Field(max_length=30, nullable=False)
    description: str | None = Field(default=None, max_length=100)
    is_active: bool = Field(default=True)
    created_at: datetime.datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=func.now(), nullable=False)
    )
