"""User decisions about legitimate repeated purchases."""

import uuid

from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class DuplicateDismissal(TimestampedModel, table=True):
    __tablename__ = "duplicate_dismissals"

    user_id: uuid.UUID = Field(primary_key=True, foreign_key="users.id", ondelete="CASCADE")
    first_transaction_id: uuid.UUID = Field(
        primary_key=True,
        foreign_key="transactions.id",
        ondelete="CASCADE",
    )
    second_transaction_id: uuid.UUID = Field(
        primary_key=True,
        foreign_key="transactions.id",
        ondelete="CASCADE",
    )
