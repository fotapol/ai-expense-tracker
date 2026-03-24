"""Feature request vote ORM model."""

import uuid

from sqlalchemy import Index, UniqueConstraint
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class FeatureRequestVote(TimestampedModel, table=True):
    """Per-user vote row for a single feature request."""

    __tablename__ = "feature_request_votes"
    __table_args__ = (
        UniqueConstraint(
            "feature_request_id",
            "user_id",
            name="uq_feature_request_votes_request_user",
        ),
        Index("ix_feature_request_votes_feature_request_id", "feature_request_id"),
        Index("ix_feature_request_votes_user_id", "user_id"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    feature_request_id: uuid.UUID = Field(
        nullable=False,
        foreign_key="feature_requests.id",
    )
    user_id: uuid.UUID = Field(
        nullable=False,
        foreign_key="users.id",
    )
