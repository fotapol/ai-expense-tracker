"""Schemas for feature request endpoints."""

import datetime as dt
from uuid import UUID

from pydantic import Field

from app.models.shared.enums import (
    FeatureRequestCategory,
    FeatureRequestModerationState,
    FeatureRequestPublicStatus,
)
from app.schemas.shared import SchemaBase, UUIDTimestampSchema


class FeatureRequestCreateRequest(SchemaBase):
    """User-facing payload for submitting a new idea."""

    title: str = Field(min_length=1, max_length=500)
    category: FeatureRequestCategory
    description: str = Field(min_length=1, max_length=5000)


class FeatureRequestVoteUpdateRequest(SchemaBase):
    """Desired vote state for the current user."""

    voted: bool


class InternalFeatureRequestCreateRequest(SchemaBase):
    """Internal-only payload for creating a curated feature request."""

    title: str = Field(min_length=1, max_length=500)
    category: FeatureRequestCategory
    description: str = Field(min_length=1, max_length=5000)
    public_status: FeatureRequestPublicStatus | None = None
    moderation_note: str | None = Field(default=None, max_length=2000)


class InternalFeatureRequestUpdateRequest(SchemaBase):
    """Internal-only moderation update payload."""

    moderation_state: FeatureRequestModerationState | None = None
    public_status: FeatureRequestPublicStatus | None = None
    moderation_note: str | None = Field(default=None, max_length=2000)


class FeatureRequestVoteSummary(SchemaBase):
    """Vote state summary for the current viewer."""

    id: UUID
    vote_count: int = Field(ge=0)
    viewer_has_voted: bool


class FeatureRequestPublicRead(UUIDTimestampSchema):
    """Public curated feature request payload."""

    title: str
    category: FeatureRequestCategory
    public_status: FeatureRequestPublicStatus
    vote_count: int = Field(ge=0)
    viewer_has_voted: bool


class FeatureRequestMineRead(UUIDTimestampSchema):
    """Current user's own feature request history entry."""

    title: str
    description: str
    category: FeatureRequestCategory
    moderation_state: FeatureRequestModerationState
    public_status: FeatureRequestPublicStatus | None
    vote_count: int = Field(ge=0)
    viewer_has_voted: bool


class InternalFeatureRequestRead(UUIDTimestampSchema):
    """Internal moderation payload."""

    title: str
    description: str
    category: FeatureRequestCategory
    moderation_state: FeatureRequestModerationState
    public_status: FeatureRequestPublicStatus | None
    moderation_note: str | None
    creator_user_id: UUID
    reviewed_by_user_id: UUID | None
    reviewed_at: dt.datetime | None
    vote_count: int = Field(ge=0)
