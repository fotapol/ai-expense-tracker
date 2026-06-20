"""Unit tests for feature request services and moderation helpers."""

from __future__ import annotations

import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.models.feature_requests.feature_request import FeatureRequest
from app.models.feature_requests.feature_request_vote import FeatureRequestVote
from app.models.shared.enums import (
    FeatureRequestCategory,
    FeatureRequestModerationState,
    FeatureRequestPublicStatus,
)
from app.models.users.user import User
from app.services.feature_requests import (
    assert_feature_request_admin_access,
    create_feature_request,
    get_feature_request_for_user_vote,
    list_my_feature_requests,
    list_public_feature_requests,
    serialize_created_feature_request_for_user,
    set_feature_request_vote,
    update_feature_request_moderation,
    validate_feature_request_content,
)


@pytest.fixture()
def session() -> Session:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(
        engine,
        tables=[
            User.__table__,
            FeatureRequest.__table__,
            FeatureRequestVote.__table__,
        ],
    )
    with Session(engine) as session:
        yield session


def _create_user(session: Session, email: str) -> User:
    user = User(
        email=email,
        auth_provider="firebase",
        auth_subject=f"uid-{uuid.uuid4()}",
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


def test_create_feature_request_normalizes_content_and_adds_initial_vote(session: Session) -> None:
    creator = _create_user(session, "creator@example.com")

    feature_request = create_feature_request(
        session,
        creator=creator,
        title="  Dark   mode   support  ",
        description="  First line\r\n\r\n\r\nSecond line  ",
        category=FeatureRequestCategory.DESIGN_ACCESSIBILITY,
    )

    payload = serialize_created_feature_request_for_user(
        session,
        feature_request=feature_request,
        viewer_user_id=creator.id,
    )

    assert feature_request.title == "Dark mode support"
    assert feature_request.description == "First line\n\nSecond line"
    assert feature_request.moderation_state == FeatureRequestModerationState.PENDING
    assert feature_request.public_status is None
    assert payload["vote_count"] == 1
    assert payload["viewer_has_voted"] is True


def test_list_my_feature_requests_returns_full_creator_history(session: Session) -> None:
    creator = _create_user(session, "creator@example.com")
    reviewer = _create_user(session, "reviewer@example.com")
    other_user = _create_user(session, "other@example.com")

    pending = create_feature_request(
        session,
        creator=creator,
        title="Pending feature",
        description="Pending feature description.",
        category=FeatureRequestCategory.OTHER,
    )
    approved = create_feature_request(
        session,
        creator=creator,
        title="Approved feature",
        description="Approved feature description.",
        category=FeatureRequestCategory.ANALYTICS_REPORTS,
    )
    rejected = create_feature_request(
        session,
        creator=creator,
        title="Rejected feature",
        description="Rejected feature description.",
        category=FeatureRequestCategory.BUDGETS_PLANNING,
    )
    create_feature_request(
        session,
        creator=other_user,
        title="Other user feature",
        description="Other user feature description.",
        category=FeatureRequestCategory.OTHER,
    )

    update_feature_request_moderation(
        session,
        feature_request=approved,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.APPROVED,
    )
    update_feature_request_moderation(
        session,
        feature_request=rejected,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.REJECTED,
    )

    history = list_my_feature_requests(session, viewer_user_id=creator.id)

    assert len(history) == 3
    assert {item["id"] for item in history} == {pending.id, approved.id, rejected.id}
    assert {item["moderation_state"] for item in history} == {
        FeatureRequestModerationState.PENDING,
        FeatureRequestModerationState.APPROVED,
        FeatureRequestModerationState.REJECTED,
    }


def test_public_feature_requests_hide_non_approved_and_sort_by_votes(session: Session) -> None:
    creator_one = _create_user(session, "one@example.com")
    creator_two = _create_user(session, "two@example.com")
    reviewer = _create_user(session, "reviewer@example.com")
    viewer = _create_user(session, "viewer@example.com")

    first = create_feature_request(
        session,
        creator=creator_one,
        title="Shared budgets",
        description="Shared budgets with family members.",
        category=FeatureRequestCategory.BUDGETS_PLANNING,
    )
    second = create_feature_request(
        session,
        creator=creator_two,
        title="Receipt notes",
        description="Add notes to receipts after upload.",
        category=FeatureRequestCategory.RECEIPTS_SCANNING,
    )
    create_feature_request(
        session,
        creator=creator_two,
        title="Hidden pending request",
        description="This should not appear publicly at all.",
        category=FeatureRequestCategory.OTHER,
    )

    update_feature_request_moderation(
        session,
        feature_request=first,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.APPROVED,
        public_status=FeatureRequestPublicStatus.PLANNED,
    )
    update_feature_request_moderation(
        session,
        feature_request=second,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.APPROVED,
        public_status=FeatureRequestPublicStatus.UNDER_REVIEW,
    )
    set_feature_request_vote(
        session,
        feature_request=first,
        viewer_user_id=viewer.id,
        voted=True,
    )

    items = list_public_feature_requests(session, viewer_user_id=viewer.id)

    assert [item["id"] for item in items] == [first.id, second.id]
    assert items[0]["vote_count"] == 2
    assert items[0]["viewer_has_voted"] is True
    assert items[1]["vote_count"] == 1
    assert items[1]["viewer_has_voted"] is False


def test_vote_toggle_is_idempotent_and_returns_authoritative_state(session: Session) -> None:
    creator = _create_user(session, "creator@example.com")
    reviewer = _create_user(session, "reviewer@example.com")
    viewer = _create_user(session, "viewer@example.com")

    feature_request = create_feature_request(
        session,
        creator=creator,
        title="Widget support",
        description="Please add home screen widget support.",
        category=FeatureRequestCategory.DESIGN_ACCESSIBILITY,
    )
    update_feature_request_moderation(
        session,
        feature_request=feature_request,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.APPROVED,
    )

    feature_request = get_feature_request_for_user_vote(
        session,
        feature_request_id=feature_request.id,
        viewer_user_id=viewer.id,
    )

    first_vote = set_feature_request_vote(
        session,
        feature_request=feature_request,
        viewer_user_id=viewer.id,
        voted=True,
    )
    second_vote = set_feature_request_vote(
        session,
        feature_request=feature_request,
        viewer_user_id=viewer.id,
        voted=True,
    )
    first_unvote = set_feature_request_vote(
        session,
        feature_request=feature_request,
        viewer_user_id=viewer.id,
        voted=False,
    )
    second_unvote = set_feature_request_vote(
        session,
        feature_request=feature_request,
        viewer_user_id=viewer.id,
        voted=False,
    )

    assert first_vote == second_vote == {
        "id": feature_request.id,
        "vote_count": 2,
        "viewer_has_voted": True,
    }
    assert first_unvote == second_unvote == {
        "id": feature_request.id,
        "vote_count": 1,
        "viewer_has_voted": False,
    }


def test_other_users_cannot_vote_on_non_public_requests(session: Session) -> None:
    creator = _create_user(session, "creator@example.com")
    reviewer = _create_user(session, "reviewer@example.com")
    viewer = _create_user(session, "viewer@example.com")

    pending = create_feature_request(
        session,
        creator=creator,
        title="Pending request",
        description="This should stay creator-only for now.",
        category=FeatureRequestCategory.OTHER,
    )

    with pytest.raises(HTTPException) as pending_exc:
        get_feature_request_for_user_vote(
            session,
            feature_request_id=pending.id,
            viewer_user_id=viewer.id,
        )
    assert pending_exc.value.status_code == 404

    update_feature_request_moderation(
        session,
        feature_request=pending,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.REJECTED,
    )

    with pytest.raises(HTTPException) as rejected_exc:
        get_feature_request_for_user_vote(
            session,
            feature_request_id=pending.id,
            viewer_user_id=viewer.id,
        )
    assert rejected_exc.value.status_code == 404


def test_moderation_defaults_approved_requests_and_clears_non_public_state(session: Session) -> None:
    creator = _create_user(session, "creator@example.com")
    reviewer = _create_user(session, "reviewer@example.com")

    feature_request = create_feature_request(
        session,
        creator=creator,
        title="Budget reminders",
        description="Send reminders before budgets are exceeded.",
        category=FeatureRequestCategory.BUDGETS_PLANNING,
    )

    feature_request = update_feature_request_moderation(
        session,
        feature_request=feature_request,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.APPROVED,
    )
    assert feature_request.public_status == FeatureRequestPublicStatus.UNDER_REVIEW

    feature_request = update_feature_request_moderation(
        session,
        feature_request=feature_request,
        reviewer=reviewer,
        moderation_state=FeatureRequestModerationState.REJECTED,
    )
    assert feature_request.public_status is None


def test_admin_access_helper_rejects_non_admin() -> None:
    with pytest.raises(HTTPException) as exc_info:
        assert_feature_request_admin_access(SimpleNamespace(is_admin=False))
    assert exc_info.value.status_code == 403


def test_normalized_validation_rejects_short_values() -> None:
    with pytest.raises(HTTPException) as title_exc:
        validate_feature_request_content(title="ab", description="Valid enough description.")
    assert title_exc.value.status_code == 422

    with pytest.raises(HTTPException) as description_exc:
        validate_feature_request_content(title="Valid title", description="short")
    assert description_exc.value.status_code == 422
