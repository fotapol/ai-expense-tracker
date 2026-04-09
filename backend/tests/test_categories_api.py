"""Tests for Categories API."""

import uuid

import pytest
from fastapi import HTTPException, status

from app.api.routers.categories import create_category
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.schemas.categories import CategoryCreateRequest
from app.models.users.user import User


class _MockSession:
    def __init__(self, existing_categories=None):
        self.added = []
        self._commit_called = False
        self.existing = existing_categories or []
    
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

    def commit(self):
        self._commit_called = True

    def refresh(self, obj):
        pass


@pytest.fixture
def test_user():
    return User(id=uuid.uuid4(), email="test@example.com")


@pytest.mark.anyio
async def test_create_category_happy_path(test_user):
    session = _MockSession()
    payload = CategoryCreateRequest(
        name="New Test Category",
        scope=CategoryScope.TRANSACTION,
    )
    
    res = await create_category(payload=payload, request=None, session=session, current_user=test_user)
    
    assert res.name == "New Test Category"
    assert session._commit_called
    assert len(session.added) == 1
    assert session.added[0].code == "NEW_TEST_CATEGORY"


@pytest.mark.anyio
async def test_create_category_rejects_duplicate_name(test_user):
    # Mocking that a category with same name/scope already exists
    existing = Category(
        id=uuid.uuid4(),
        user_id=test_user.id,
        name="Dup Category",
        code="DUP_CATEGORY",
        scope=CategoryScope.TRANSACTION,
    )
    session = _MockSession(existing_categories=[existing])

    payload = CategoryCreateRequest(
        name="Dup Category",
        scope=CategoryScope.TRANSACTION,
    )
    
    with pytest.raises(HTTPException) as exc_info:
        await create_category(payload=payload, request=None, session=session, current_user=test_user)
    
    assert exc_info.value.status_code == status.HTTP_409_CONFLICT
