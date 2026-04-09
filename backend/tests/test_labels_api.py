"""Tests for Labels API."""

import uuid

import pytest
from fastapi import HTTPException, status

from app.api.routers.labels import create_label, delete_label
from app.models.labels.label import Label
from app.schemas.labels import LabelCreateRequest
from app.models.users.user import User


class _MockSession:
    def __init__(self, existing=None):
        self.added = []
        self.deleted = []
        self._commit_called = False
        self.existing = existing or []
    
    def exec(self, query):
        class Result:
            def __init__(self, items):
                self.items = items
            def first(self):
                return self.items[0] if self.items else None
            def all(self):
                return self.items
        return Result(self.existing)

    def add(self, obj):
        if not hasattr(obj, "id") or obj.id is None:
            obj.id = uuid.uuid4()
        self.added.append(obj)

    def delete(self, obj):
        self.deleted.append(obj)

    def commit(self):
        self._commit_called = True

    def refresh(self, obj):
        pass


@pytest.fixture
def test_user():
    return User(id=uuid.uuid4(), email="test@example.com")


@pytest.mark.anyio
async def test_create_label_happy_path(test_user):
    session = _MockSession()
    payload = LabelCreateRequest(
        name="Business Trip",
    )
    
    res = await create_label(payload=payload, request=None, session=session, current_user=test_user)
    
    assert res.name == "Business Trip"
    assert session._commit_called
    assert len(session.added) == 1


@pytest.mark.anyio
async def test_create_label_rejects_duplicate_name(test_user):
    existing = Label(
        id=uuid.uuid4(),
        user_id=test_user.id,
        name="Business Trip",
    )
    session = _MockSession(existing=[existing])

    payload = LabelCreateRequest(
        name="Business Trip",
    )
    
    with pytest.raises(HTTPException) as exc_info:
        await create_label(payload=payload, request=None, session=session, current_user=test_user)
    
    assert exc_info.value.status_code == status.HTTP_409_CONFLICT


@pytest.mark.anyio
async def test_delete_label_happy_path(test_user):
    label_id = uuid.uuid4()
    existing = Label(
        id=label_id,
        user_id=test_user.id,
        name="Business Trip",
    )
    session = _MockSession(existing=[existing])
    
    await delete_label(label_id=label_id, request=None, session=session, current_user=test_user)
    
    assert session._commit_called
    assert existing in session.deleted
