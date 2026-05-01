import uuid

from sqlalchemy import UniqueConstraint
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class TransactionLabel(TimestampedModel, table=True):
    """Many-to-many junction table: transactions ↔ labels."""

    __tablename__ = "transaction_labels"
    __table_args__ = (
        UniqueConstraint(
            "transaction_id",
            "label_id",
            name="uq_transaction_labels_transaction_id_label_id",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    transaction_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="transactions.id")
    label_id: uuid.UUID = Field(index=True, nullable=False, foreign_key="labels.id")
