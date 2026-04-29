"""Tests for Categories API."""

import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException, status

from app.api.routers import categories as router
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.users.user import User


def _unwrap(func):
    while hasattr(func, "__wrapped__"):
        func = func.__wrapped__
    return func


class _MockSession:
    def __init__(self, existing_categories=None):
        self.added = []
        self._commit_called = False
        self.existing = existing_categories or []

    def exec(self, _query):
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

    def refresh(self, _obj):
        pass


@pytest.fixture
def test_user():
    return User(
        id=uuid.uuid4(),
        email="test@example.com",
        auth_subject="firebase:test-user",
    )


def _usage(
    *,
    categories_used=0,
    categories_limit=3,
    subcategories_used=0,
    subcategories_limit=10,
    is_unlimited=False,
):
    return SimpleNamespace(
        categories_used=categories_used,
        categories_limit=None if is_unlimited else categories_limit,
        categories_remaining=None if is_unlimited else max(categories_limit - categories_used, 0),
        subcategories_used=subcategories_used,
        subcategories_limit=None if is_unlimited else subcategories_limit,
        subcategories_remaining=None
        if is_unlimited
        else max(subcategories_limit - subcategories_used, 0),
        is_unlimited=is_unlimited,
    )


@pytest.mark.anyio
async def test_create_category_happy_path(monkeypatch, test_user):
    monkeypatch.setattr(router, "resolve_category_usage", lambda *_args: _usage())
    session = _MockSession()
    payload = router.CategoryCreateRequest(name="New Test Category")

    res = await _unwrap(router.create_category)(
        payload=payload,
        request=None,
        session=session,
        current_user=test_user,
    )

    assert res["name"] == "New Test Category"
    assert res["is_custom"] is True
    assert session._commit_called
    assert len(session.added) == 1
    assert session.added[0].code == "NEW_TEST_CATEGORY"
    assert session.added[0].scope == CategoryScope.ITEM


@pytest.mark.anyio
async def test_create_category_rejects_duplicate_name(monkeypatch, test_user):
    monkeypatch.setattr(router, "resolve_category_usage", lambda *_args: _usage())
    existing = Category(
        id=uuid.uuid4(),
        user_id=test_user.id,
        name="Dup Category",
        code="DUP_CATEGORY",
        scope=CategoryScope.ITEM,
        is_active=True,
    )
    session = _MockSession(existing_categories=[existing])
    payload = router.CategoryCreateRequest(name="Dup Category")

    with pytest.raises(HTTPException) as exc_info:
        await _unwrap(router.create_category)(
            payload=payload,
            request=None,
            session=session,
            current_user=test_user,
        )

    assert exc_info.value.status_code == status.HTTP_409_CONFLICT


@pytest.mark.anyio
async def test_free_plan_category_limit_blocks_new_top_level_category(
    monkeypatch,
    test_user,
):
    monkeypatch.setattr(
        router,
        "resolve_category_usage",
        lambda *_args: _usage(categories_used=3),
    )
    payload = router.CategoryCreateRequest(name="Fourth Category")

    with pytest.raises(HTTPException) as exc_info:
        await _unwrap(router.create_category)(
            payload=payload,
            request=None,
            session=_MockSession(),
            current_user=test_user,
        )

    assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
    assert exc_info.value.detail["code"] == "free_plan_category_limit_reached"


@pytest.mark.anyio
async def test_free_plan_subcategory_limit_blocks_new_subcategory(
    monkeypatch,
    test_user,
):
    parent_id = uuid.uuid4()
    monkeypatch.setattr(
        router,
        "resolve_category_usage",
        lambda *_args: _usage(subcategories_used=10),
    )
    monkeypatch.setattr(
        router,
        "_resolve_parent_or_400",
        lambda *_args, **_kwargs: SimpleNamespace(id=parent_id),
    )
    payload = router.CategoryCreateRequest(
        name="Eleventh Subcategory",
        parent_id=parent_id,
    )

    with pytest.raises(HTTPException) as exc_info:
        await _unwrap(router.create_category)(
            payload=payload,
            request=None,
            session=_MockSession(),
            current_user=test_user,
        )

    assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
    assert exc_info.value.detail["code"] == "free_plan_subcategory_limit_reached"


@pytest.mark.anyio
async def test_premium_category_access_is_unlimited(monkeypatch, test_user):
    monkeypatch.setattr(
        router,
        "resolve_category_usage",
        lambda *_args: _usage(categories_used=99, is_unlimited=True),
    )
    session = _MockSession()
    payload = router.CategoryCreateRequest(name="Premium Category")

    res = await _unwrap(router.create_category)(
        payload=payload,
        request=None,
        session=session,
        current_user=test_user,
    )

    assert res["name"] == "Premium Category"
    assert session._commit_called
