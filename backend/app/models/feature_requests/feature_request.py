"""Feature request ORM model."""

from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import CheckConstraint, Column, DateTime, Index, String
from sqlalchemy import Enum as SAEnum
from sqlmodel import Field, SQLModel

from app.models.shared.enums import (
    FeatureRequestCategory,
    FeatureRequestModerationState,
    FeatureRequestPublicStatus,
)
from app.models.shared.timestamps import TimestampedModel


def _enum_values(enum_cls: type) -> list[str]:
    return [member.value for member in enum_cls]


class FeatureRequestBase(SQLModel):
    """Shared feature request fields."""

    title: str = Field(sa_column=Column(String(120), nullable=False))
    description: str = Field(sa_column=Column(String(2000), nullable=False))
    category: FeatureRequestCategory = Field(
        sa_column=Column(
            SAEnum(
                FeatureRequestCategory,
                name="feature_request_category",
                native_enum=False,
                values_callable=_enum_values,
            ),
            nullable=False,
        ),
    )
    moderation_state: FeatureRequestModerationState = Field(
        default=FeatureRequestModerationState.PENDING,
        sa_column=Column(
            SAEnum(
                FeatureRequestModerationState,
                name="feature_request_moderation_state",
                native_enum=False,
                values_callable=_enum_values,
            ),
            nullable=False,
            default=FeatureRequestModerationState.PENDING,
        ),
    )
    public_status: FeatureRequestPublicStatus | None = Field(
        default=None,
        sa_column=Column(
            SAEnum(
                FeatureRequestPublicStatus,
                name="feature_request_public_status",
                native_enum=False,
                values_callable=_enum_values,
            ),
            nullable=True,
        ),
    )
    moderation_note: str | None = Field(
        default=None,
        sa_column=Column(String(2000), nullable=True),
    )


class FeatureRequest(FeatureRequestBase, TimestampedModel, table=True):
    """A feature request created by an end user or internal admin."""

    __tablename__ = "feature_requests"
    __table_args__ = (
        CheckConstraint(
            """
            (
                moderation_state = 'approved'
                AND public_status IS NOT NULL
            )
            OR (
                moderation_state IN ('pending', 'rejected')
                AND public_status IS NULL
            )
            """,
            name="ck_feature_requests_public_state_consistency",
        ),
        Index("ix_feature_requests_creator_user_id", "creator_user_id"),
        Index("ix_feature_requests_moderation_state", "moderation_state"),
        Index("ix_feature_requests_public_status", "public_status"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    creator_user_id: uuid.UUID = Field(
        nullable=False,
        foreign_key="users.id",
    )
    reviewed_by_user_id: uuid.UUID | None = Field(
        default=None,
        nullable=True,
        foreign_key="users.id",
    )
    reviewed_at: dt.datetime | None = Field(
        default=None,
        sa_column=Column(DateTime(timezone=True), nullable=True),
    )
