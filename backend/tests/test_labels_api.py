"""Tests for Labels API."""

import uuid

import pytest
from fastapi import HTTPException, status

from app.api.routers.labels import create_label, delete_label
from app.models.labels.label import Label
from app.models.users.user import User
from app.schemas.labels import LabelCreateRequest


class _MockSession:
    def __init__(self, existing=None, exec_results=None):
        self.added = []
        self.deleted = []
        self._commit_called = False
        if exec_results is not None:
            self._exec_results = list(exec_results)
        else:
            self._exec_results = [existing or []]
    
    def exec(self, query):
        class Result:
            def __init__(self, items):
                self.items = items
            def first(self):
                return self.items[0] if self.items else None
            def all(self):
                return self.items
        items = self._exec_results.pop(0) if self._exec_results else []
        return Result(items)

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


def _unwrap(func):
    while hasattr(func, "__wrapped__"):
        func = func.__wrapped__
    return func


@pytest.mark.anyio
async def test_create_label_happy_path(test_user):
    session = _MockSession()
    payload = LabelCreateRequest(
        name="Business Trip",
    )
    
    res = await _unwrap(create_label)(
        payload=payload,
        request=None,
        session=session,
        current_user=test_user,
    )
    
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
        await _unwrap(create_label)(
            payload=payload,
            request=None,
            session=session,
            current_user=test_user,
        )
    
    assert exc_info.value.status_code == status.HTTP_409_CONFLICT


@pytest.mark.anyio
async def test_delete_label_happy_path(test_user):
    label_id = uuid.uuid4()
    existing = Label(
        id=label_id,
        user_id=test_user.id,
        name="Business Trip",
    )
    session = _MockSession(exec_results=[[existing], []])
    
    await _unwrap(delete_label)(
        label_id=label_id,
        request=None,
        session=session,
        current_user=test_user,
    )
    
    assert session._commit_called
    assert existing not in session.deleted
    assert existing.is_active is False
