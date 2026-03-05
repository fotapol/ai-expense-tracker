"""Reusable timestamp mixin for SQLModel tables."""

import datetime as dt

from sqlalchemy import DateTime, func
from sqlmodel import Field, SQLModel


class TimestampedModel(SQLModel):
    """Mixin that adds creation and update timestamps with timezone support."""

    created_at: dt.datetime = Field(
        sa_type=DateTime(timezone=True),
        sa_column_kwargs={"nullable": False, "default": func.now()},
    )
    updated_at: dt.datetime = Field(
        sa_type=DateTime(timezone=True),
        sa_column_kwargs={"nullable": False, "default": func.now(), "onupdate": func.now()},
    )
