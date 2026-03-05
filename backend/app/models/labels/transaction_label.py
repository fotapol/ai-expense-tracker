import uuid

from sqlmodel import Field, SQLModel

from app.models.shared.timestamps import TimestampedModel


class TransactionLabel(TimestampedModel, table=True):
    """Many-to-many junction table: transactions ↔ labels."""

    __tablename__ = "transaction_labels"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    transaction_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="transactions.id")
    label_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="labels.id")
