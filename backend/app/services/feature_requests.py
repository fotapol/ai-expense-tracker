"""Feature request business logic and serialization helpers."""

from __future__ import annotations

import datetime as dt
import re
import uuid
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.models.feature_requests.feature_request import FeatureRequest
from app.models.feature_requests.feature_request_vote import FeatureRequestVote
from app.models.shared.enums import (
    FeatureRequestCategory,
    FeatureRequestModerationState,
    FeatureRequestPublicStatus,
)
from app.models.users.user import User

_UNSET = object()
_TITLE_WHITESPACE_RE = re.compile(r"\s+")
_EXCESSIVE_BLANK_LINES_RE = re.compile(r"\n{3,}")


def normalize_feature_request_title(value: str) -> str:
    """Trim title text and collapse internal whitespace."""

    return _TITLE_WHITESPACE_RE.sub(" ", value.strip())


def normalize_feature_request_description(value: str) -> str:
    """Normalize line endings and reduce excessive vertical whitespace."""

    normalized = value.replace("\r\n", "\n").replace("\r", "\n")
    normalized = "\n".join(line.rstrip() for line in normalized.split("\n")).strip()
    return _EXCESSIVE_BLANK_LINES_RE.sub("\n\n", normalized)


def normalize_moderation_note(value: str | None) -> str | None:
    """Trim moderation notes and treat blank strings as absent."""

    if value is None:
        return None
    normalized = value.strip()
    return normalized or None


def validate_feature_request_content(*, title: str, description: str) -> None:
    """Enforce normalized content length constraints for v1 anti-spam."""

    if len(title) < 3 or len(title) > 120:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Title must be between 3 and 120 characters.",
        )
    if len(description) < 10 or len(description) > 2000:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Description must be between 10 and 2000 characters.",
        )


def assert_feature_request_admin_access(current_user: User) -> None:
    """Require a general app admin for internal moderation endpoints."""

    if current_user.is_admin:
        return
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Admin access is required for internal feature request endpoints.",
    )


def _vote_count_by_feature_request_id(
    session: Session,
    feature_request_ids: list[uuid.UUID],
) -> dict[uuid.UUID, int]:
    if not feature_request_ids:
        return {}
    rows = session.exec(
        select(
            FeatureRequestVote.feature_request_id,
            func.count(FeatureRequestVote.id),
        )
        .where(FeatureRequestVote.feature_request_id.in_(feature_request_ids))
        .group_by(FeatureRequestVote.feature_request_id)
    ).all()
    return {row[0]: int(row[1]) for row in rows}


def _viewer_voted_feature_request_ids(
    session: Session,
    *,
    feature_request_ids: list[uuid.UUID],
    viewer_user_id: uuid.UUID,
) -> set[uuid.UUID]:
    if not feature_request_ids:
        return set()
    rows = session.exec(
        select(FeatureRequestVote.feature_request_id).where(
            FeatureRequestVote.user_id == viewer_user_id,
            FeatureRequestVote.feature_request_id.in_(feature_request_ids),
        )
    ).all()
    return set(rows)


def _serialize_public_item(
    feature_request: FeatureRequest,
    *,
    vote_count: int,
    viewer_has_voted: bool,
) -> dict[str, Any]:
    return {
        "id": feature_request.id,
        "title": feature_request.title,
        "category": feature_request.category,
        "public_status": feature_request.public_status,
        "vote_count": vote_count,
        "viewer_has_voted": viewer_has_voted,
        "created_at": feature_request.created_at,
        "updated_at": feature_request.updated_at,
    }


def _serialize_mine_item(
    feature_request: FeatureRequest,
    *,
    vote_count: int,
    viewer_has_voted: bool,
) -> dict[str, Any]:
    return {
        "id": feature_request.id,
        "title": feature_request.title,
        "description": feature_request.description,
        "category": feature_request.category,
        "moderation_state": feature_request.moderation_state,
        "public_status": feature_request.public_status,
        "vote_count": vote_count,
        "viewer_has_voted": viewer_has_voted,
        "created_at": feature_request.created_at,
        "updated_at": feature_request.updated_at,
    }


def _serialize_internal_item(
    feature_request: FeatureRequest,
    *,
    vote_count: int,
) -> dict[str, Any]:
    return {
        "id": feature_request.id,
        "title": feature_request.title,
        "description": feature_request.description,
        "category": feature_request.category,
        "moderation_state": feature_request.moderation_state,
        "public_status": feature_request.public_status,
        "moderation_note": feature_request.moderation_note,
        "creator_user_id": feature_request.creator_user_id,
        "reviewed_by_user_id": feature_request.reviewed_by_user_id,
        "reviewed_at": feature_request.reviewed_at,
        "vote_count": vote_count,
        "created_at": feature_request.created_at,
        "updated_at": feature_request.updated_at,
    }


def _count_votes_for_feature_request(
    session: Session,
    *,
    feature_request_id: uuid.UUID,
) -> int:
    return int(
        session.exec(
            select(func.count(FeatureRequestVote.id)).where(
                FeatureRequestVote.feature_request_id == feature_request_id
            )
        ).one()
    )


def _viewer_has_vote(
    session: Session,
    *,
    feature_request_id: uuid.UUID,
    viewer_user_id: uuid.UUID,
) -> bool:
    return (
        session.exec(
            select(FeatureRequestVote.id).where(
                FeatureRequestVote.feature_request_id == feature_request_id,
                FeatureRequestVote.user_id == viewer_user_id,
            )
        ).first()
        is not None
    )


def _normalize_and_validate_request_fields(
    *,
    title: str,
    description: str,
) -> tuple[str, str]:
    normalized_title = normalize_feature_request_title(title)
    normalized_description = normalize_feature_request_description(description)
    validate_feature_request_content(
        title=normalized_title,
        description=normalized_description,
    )
    return normalized_title, normalized_description


def _apply_public_state_rules(
    *,
    moderation_state: FeatureRequestModerationState,
    public_status: FeatureRequestPublicStatus | None,
) -> FeatureRequestPublicStatus | None:
    if moderation_state == FeatureRequestModerationState.APPROVED:
        return public_status or FeatureRequestPublicStatus.UNDER_REVIEW
    return None


def create_feature_request(
    session: Session,
    *,
    creator: User,
    title: str,
    description: str,
    category: FeatureRequestCategory,
) -> FeatureRequest:
    """Create a pending feature request and add the creator's first vote."""

    normalized_title, normalized_description = _normalize_and_validate_request_fields(
        title=title,
        description=description,
    )
    feature_request = FeatureRequest(
        creator_user_id=creator.id,
        title=normalized_title,
        description=normalized_description,
        category=category,
        moderation_state=FeatureRequestModerationState.PENDING,
        public_status=None,
    )
    session.add(feature_request)
    session.add(
        FeatureRequestVote(
            feature_request_id=feature_request.id,
            user_id=creator.id,
        )
    )
    session.commit()
    session.refresh(feature_request)
    return feature_request


def create_internal_feature_request(
    session: Session,
    *,
    creator: User,
    title: str,
    description: str,
    category: FeatureRequestCategory,
    public_status: FeatureRequestPublicStatus | None,
    moderation_note: str | None,
) -> FeatureRequest:
    """Create an immediately public curated feature request."""

    normalized_title, normalized_description = _normalize_and_validate_request_fields(
        title=title,
        description=description,
    )
    feature_request = FeatureRequest(
        creator_user_id=creator.id,
        title=normalized_title,
        description=normalized_description,
        category=category,
        moderation_state=FeatureRequestModerationState.APPROVED,
        public_status=_apply_public_state_rules(
            moderation_state=FeatureRequestModerationState.APPROVED,
            public_status=public_status,
        ),
        moderation_note=normalize_moderation_note(moderation_note),
        reviewed_by_user_id=creator.id,
        reviewed_at=dt.datetime.now(dt.UTC),
    )
    session.add(feature_request)
    session.commit()
    session.refresh(feature_request)
    return feature_request


def update_feature_request_moderation(
    session: Session,
    *,
    feature_request: FeatureRequest,
    reviewer: User,
    moderation_state: FeatureRequestModerationState | None = None,
    public_status: FeatureRequestPublicStatus | object | None = _UNSET,
    moderation_note: str | object | None = _UNSET,
) -> FeatureRequest:
    """Apply a moderation update while keeping public-state invariants intact."""

    next_moderation_state = moderation_state or feature_request.moderation_state
    next_public_status = feature_request.public_status
    if public_status is not _UNSET:
        next_public_status = public_status
    next_public_status = _apply_public_state_rules(
        moderation_state=next_moderation_state,
        public_status=next_public_status,
    )

    feature_request.moderation_state = next_moderation_state
    feature_request.public_status = next_public_status
    if moderation_note is not _UNSET:
        feature_request.moderation_note = normalize_moderation_note(moderation_note)
    feature_request.reviewed_by_user_id = reviewer.id
    feature_request.reviewed_at = dt.datetime.now(dt.UTC)

    session.add(feature_request)
    session.commit()
    session.refresh(feature_request)
    return feature_request


def get_feature_request_for_user_vote(
    session: Session,
    *,
    feature_request_id: uuid.UUID,
    viewer_user_id: uuid.UUID,
) -> FeatureRequest:
    """Return a feature request the user may vote on, or raise 404."""

    feature_request = session.get(FeatureRequest, feature_request_id)
    if feature_request is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Feature request not found.",
        )
    if feature_request.moderation_state == FeatureRequestModerationState.APPROVED:
        return feature_request
    if feature_request.creator_user_id == viewer_user_id:
        return feature_request
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Feature request not found.",
    )


def set_feature_request_vote(
    session: Session,
    *,
    feature_request: FeatureRequest,
    viewer_user_id: uuid.UUID,
    voted: bool,
) -> dict[str, Any]:
    """Idempotently apply the current user's vote state to a feature request."""

    existing_vote = session.exec(
        select(FeatureRequestVote).where(
            FeatureRequestVote.feature_request_id == feature_request.id,
            FeatureRequestVote.user_id == viewer_user_id,
        )
    ).first()

    if voted and existing_vote is None:
        session.add(
            FeatureRequestVote(
                feature_request_id=feature_request.id,
                user_id=viewer_user_id,
            )
        )
        try:
            session.commit()
        except IntegrityError:
            session.rollback()
    elif not voted and existing_vote is not None:
        session.delete(existing_vote)
        session.commit()

    return {
        "id": feature_request.id,
        "vote_count": _count_votes_for_feature_request(
            session,
            feature_request_id=feature_request.id,
        ),
        "viewer_has_voted": _viewer_has_vote(
            session,
            feature_request_id=feature_request.id,
            viewer_user_id=viewer_user_id,
        ),
    }


def list_public_feature_requests(
    session: Session,
    *,
    viewer_user_id: uuid.UUID,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Return public curated requests sorted by popularity for the current user."""

    feature_requests = session.exec(
        select(FeatureRequest).where(
            FeatureRequest.moderation_state == FeatureRequestModerationState.APPROVED
        )
    ).all()
    feature_request_ids = [row.id for row in feature_requests]
    vote_counts = _vote_count_by_feature_request_id(session, feature_request_ids)
    viewer_voted_ids = _viewer_voted_feature_request_ids(
        session,
        feature_request_ids=feature_request_ids,
        viewer_user_id=viewer_user_id,
    )
    ranked = sorted(
        feature_requests,
        key=lambda row: (vote_counts.get(row.id, 0), row.updated_at),
        reverse=True,
    )[:limit]
    return [
        _serialize_public_item(
            row,
            vote_count=vote_counts.get(row.id, 0),
            viewer_has_voted=row.id in viewer_voted_ids,
        )
        for row in ranked
    ]


def list_my_feature_requests(
    session: Session,
    *,
    viewer_user_id: uuid.UUID,
) -> list[dict[str, Any]]:
    """Return the current user's full feature request history."""

    feature_requests = session.exec(
        select(FeatureRequest)
        .where(FeatureRequest.creator_user_id == viewer_user_id)
        .order_by(FeatureRequest.created_at.desc())
    ).all()
    feature_request_ids = [row.id for row in feature_requests]
    vote_counts = _vote_count_by_feature_request_id(session, feature_request_ids)
    viewer_voted_ids = _viewer_voted_feature_request_ids(
        session,
        feature_request_ids=feature_request_ids,
        viewer_user_id=viewer_user_id,
    )
    return [
        _serialize_mine_item(
            row,
            vote_count=vote_counts.get(row.id, 0),
            viewer_has_voted=row.id in viewer_voted_ids,
        )
        for row in feature_requests
    ]


def list_internal_feature_requests(
    session: Session,
    *,
    moderation_state: FeatureRequestModerationState | None = None,
) -> list[dict[str, Any]]:
    """Return internal moderation data for feature requests."""

    statement = select(FeatureRequest).order_by(FeatureRequest.created_at.desc())
    if moderation_state is not None:
        statement = statement.where(FeatureRequest.moderation_state == moderation_state)
    feature_requests = session.exec(statement).all()
    feature_request_ids = [row.id for row in feature_requests]
    vote_counts = _vote_count_by_feature_request_id(session, feature_request_ids)
    return [
        _serialize_internal_item(row, vote_count=vote_counts.get(row.id, 0))
        for row in feature_requests
    ]


def serialize_created_feature_request_for_user(
    session: Session,
    *,
    feature_request: FeatureRequest,
    viewer_user_id: uuid.UUID,
) -> dict[str, Any]:
    """Serialize a freshly created feature request for the current user."""

    return _serialize_mine_item(
        feature_request,
        vote_count=_count_votes_for_feature_request(
            session,
            feature_request_id=feature_request.id,
        ),
        viewer_has_voted=_viewer_has_vote(
            session,
            feature_request_id=feature_request.id,
            viewer_user_id=viewer_user_id,
        ),
    )


def serialize_internal_feature_request(
    session: Session,
    *,
    feature_request: FeatureRequest,
) -> dict[str, Any]:
    """Serialize a single feature request for internal moderation use."""

    return _serialize_internal_item(
        feature_request,
        vote_count=_count_votes_for_feature_request(
            session,
            feature_request_id=feature_request.id,
        ),
    )
