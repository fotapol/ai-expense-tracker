import uuid
from types import SimpleNamespace

import pytest
from fastapi import status

from app.api.routers import users as users_router
from app.auth import firebase_admin
from app.models.users.user import User
from app.services import account_deletion
from app.services.account_deletion import (
    StoredReceiptObject,
    _delete_receipt_objects_best_effort,
)


def test_receipt_object_cleanup_is_best_effort(monkeypatch):
    calls = []

    def fake_delete_object(key: str, *, bucket: str | None = None) -> None:
        calls.append((bucket, key))
        if key == "receipts/fail.jpg":
            raise RuntimeError("storage unavailable")

    monkeypatch.setattr(account_deletion, "delete_object", fake_delete_object)

    failures = _delete_receipt_objects_best_effort(
        [
            StoredReceiptObject(bucket="receipts", key="receipts/ok.jpg"),
            StoredReceiptObject(bucket="receipts", key="receipts/fail.jpg"),
        ]
    )

    assert calls == [
        ("receipts", "receipts/ok.jpg"),
        ("receipts", "receipts/fail.jpg"),
    ]
    assert failures == [StoredReceiptObject(bucket="receipts", key="receipts/fail.jpg")]


def test_delete_firebase_user_returns_true_on_success(monkeypatch):
    calls = []

    def fake_delete_user(uid: str) -> None:
        calls.append(uid)

    monkeypatch.setattr(firebase_admin.auth, "delete_user", fake_delete_user)

    assert firebase_admin.delete_firebase_user("firebase-uid") is True
    assert calls == ["firebase-uid"]


def test_delete_firebase_user_treats_missing_user_as_non_fatal(monkeypatch):
    class MissingFirebaseUser(Exception):
        pass

    def fake_delete_user(_uid: str) -> None:
        raise MissingFirebaseUser()

    monkeypatch.setattr(firebase_admin.auth, "UserNotFoundError", MissingFirebaseUser)
    monkeypatch.setattr(firebase_admin.auth, "delete_user", fake_delete_user)

    assert firebase_admin.delete_firebase_user("firebase-uid") is False


@pytest.mark.anyio
async def test_delete_me_invalidates_cache_and_returns_no_content(monkeypatch):
    user = User(
        id=uuid.uuid4(),
        email="user@example.com",
        auth_provider="firebase",
        auth_subject="firebase-uid",
    )

    class FakeSession:
        def merge(self, value):
            return value

    deleted_users = []
    invalidated_subjects = []

    def fake_delete_account_for_user(*, session, user):
        deleted_users.append(user.id)
        return SimpleNamespace(
            user_id=user.id,
            auth_subject=user.auth_subject,
            storage_delete_failures=[],
            firebase_user_deleted=True,
        )

    async def fake_invalidate_user_cache(_redis, auth_subject):
        invalidated_subjects.append(auth_subject)

    monkeypatch.setattr(users_router, "delete_account_for_user", fake_delete_account_for_user)
    monkeypatch.setattr(users_router, "get_redis", lambda: object())
    monkeypatch.setattr(users_router, "invalidate_user_cache", fake_invalidate_user_cache)

    response = await users_router.delete_me.__wrapped__(
        request=None,
        session=FakeSession(),
        current_user=user,
    )

    assert response.status_code == status.HTTP_204_NO_CONTENT
    assert deleted_users == [user.id]
    assert invalidated_subjects == ["firebase-uid"]
