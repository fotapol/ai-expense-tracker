"""Feature request API endpoints."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request, status
from sqlmodel import Session

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.shared.enums import FeatureRequestModerationState
from app.models.users.user import User
from app.schemas.feature_requests import (
    FeatureRequestCreateRequest,
    FeatureRequestMineRead,
    FeatureRequestPublicRead,
    FeatureRequestVoteSummary,
    FeatureRequestVoteUpdateRequest,
    InternalFeatureRequestCreateRequest,
    InternalFeatureRequestRead,
    InternalFeatureRequestUpdateRequest,
)
from app.services import feature_requests as feature_request_service

router = APIRouter(prefix="/v1", tags=["feature-requests"])
internal_router = APIRouter(prefix="/internal", tags=["feature-requests-internal"])


@router.get("/feature-requests", response_model=list[FeatureRequestPublicRead])
@limiter.limit("60/minute")
async def list_feature_requests(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return curated public feature requests sorted by popularity."""

    return feature_request_service.list_public_feature_requests(
        session,
        viewer_user_id=current_user.id,
    )


@router.get("/feature-requests/mine", response_model=list[FeatureRequestMineRead])
@limiter.limit("60/minute")
async def list_my_feature_request_history(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return the current user's own feature request history."""

    return feature_request_service.list_my_feature_requests(
        session,
        viewer_user_id=current_user.id,
    )


@router.post(
    "/feature-requests",
    response_model=FeatureRequestMineRead,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("5/hour")
async def create_feature_request(
    payload: FeatureRequestCreateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create a new pending feature request and the creator's first vote."""

    feature_request = feature_request_service.create_feature_request(
        session,
        creator=current_user,
        title=payload.title,
        description=payload.description,
        category=payload.category,
    )
    return feature_request_service.serialize_created_feature_request_for_user(
        session,
        feature_request=feature_request,
        viewer_user_id=current_user.id,
    )


@router.put("/feature-requests/{feature_request_id}/vote", response_model=FeatureRequestVoteSummary)
@limiter.limit("60/minute")
async def update_feature_request_vote(
    feature_request_id: uuid.UUID,
    payload: FeatureRequestVoteUpdateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Idempotently set the current user's vote state for a feature request."""

    feature_request = feature_request_service.get_feature_request_for_user_vote(
        session,
        feature_request_id=feature_request_id,
        viewer_user_id=current_user.id,
    )
    return feature_request_service.set_feature_request_vote(
        session,
        feature_request=feature_request,
        viewer_user_id=current_user.id,
        voted=payload.voted,
    )


@internal_router.get("/feature-requests", response_model=list[InternalFeatureRequestRead])
@limiter.limit("60/minute")
async def list_internal_feature_requests(
    request: Request,
    moderation_state: FeatureRequestModerationState | None = None,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return feature requests for internal moderation tooling."""

    feature_request_service.assert_feature_request_admin_access(current_user)
    return feature_request_service.list_internal_feature_requests(
        session,
        moderation_state=moderation_state,
    )


@internal_router.post(
    "/feature-requests",
    response_model=InternalFeatureRequestRead,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("30/minute")
async def create_internal_feature_request(
    payload: InternalFeatureRequestCreateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create an immediately public curated feature request."""

    feature_request_service.assert_feature_request_admin_access(current_user)
    feature_request = feature_request_service.create_internal_feature_request(
        session,
        creator=current_user,
        title=payload.title,
        description=payload.description,
        category=payload.category,
        public_status=payload.public_status,
        moderation_note=payload.moderation_note,
    )
    return feature_request_service.serialize_internal_feature_request(
        session,
        feature_request=feature_request,
    )


@internal_router.patch(
    "/feature-requests/{feature_request_id}",
    response_model=InternalFeatureRequestRead,
)
@limiter.limit("30/minute")
async def update_internal_feature_request(
    feature_request_id: uuid.UUID,
    payload: InternalFeatureRequestUpdateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Moderate an existing feature request."""

    feature_request_service.assert_feature_request_admin_access(current_user)
    feature_request = session.get(
        feature_request_service.FeatureRequest,
        feature_request_id,
    )
    if feature_request is None:
        from fastapi import HTTPException

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Feature request not found.",
        )

    update_data = payload.model_dump(exclude_unset=True)
    feature_request = feature_request_service.update_feature_request_moderation(
        session,
        feature_request=feature_request,
        reviewer=current_user,
        moderation_state=update_data.get("moderation_state"),
        public_status=update_data.get("public_status", feature_request_service._UNSET),
        moderation_note=update_data.get("moderation_note", feature_request_service._UNSET),
    )
    return feature_request_service.serialize_internal_feature_request(
        session,
        feature_request=feature_request,
    )
