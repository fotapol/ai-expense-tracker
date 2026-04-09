"""Tests for Firebase auth dependency and cache lookup."""

import uuid

import pytest
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from firebase_admin import auth as firebase_auth
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.models.users.user import User


class _MockRedis:
    def __init__(self):
        self.store = {}
    
    async def get(self, key):
        return self.store.get(key)
    
    async def setex(self, key, ttl, payload):
        self.store[key] = payload

    async def delete(self, key):
        self.store.pop(key, None)


@pytest.fixture
def mock_redis(monkeypatch):
    r = _MockRedis()
    monkeypatch.setattr("app.auth.deps.get_redis", lambda: r)
    return r


class _MockSession:
    def __init__(self):
        self.users = []
        self._commit_called = False
    
    def exec(self, query):
        class Result:
            def __init__(self, u):
                self.u = u
            def first(self):
                return self.u
        
        # Simple mock logic based on the query we expect
        if "User.id ==" in str(query):
            # Extract id from query if we were doing a real mock, 
            # here we just return the first user if there is one.
            return Result(self.users[0] if self.users else None)
        elif "User.auth_subject ==" in str(query):
            return Result(self.users[0] if self.users else None)
        return Result(None)

    def add(self, obj):
        if not hasattr(obj, "id") or obj.id is None:
            obj.id = uuid.uuid4()
        self.users.append(obj)

    def commit(self):
        self._commit_called = True

    def refresh(self, obj):
        pass

    def rollback(self):
        pass


@pytest.fixture
def mock_session():
    return _MockSession()


def _make_creds():
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials="fake_token")


@pytest.mark.anyio
async def test_get_current_user_new_user_auto_create(monkeypatch, mock_session, mock_redis):
    # Mock verify_token to return valid claims
    monkeypatch.setattr(
        "app.auth.deps.verify_token",
        lambda _: {"uid": "new_uid", "email": "test@example.com", "email_verified": True}
    )

    user = await get_current_user(request=None, credentials=_make_creds(), session=mock_session)
    
    assert user is not None
    assert user.auth_subject == "new_uid"
    assert user.email == "test@example.com"
    assert mock_session._commit_called


@pytest.mark.anyio
async def test_get_current_user_rejects_unverified_email(monkeypatch, mock_session, mock_redis):
    # Mock verify_token to return unverified email
    monkeypatch.setattr(
        "app.auth.deps.verify_token",
        lambda _: {"uid": "new_uid", "email": "test@example.com", "email_verified": False}
    )

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(request=None, credentials=_make_creds(), session=mock_session)
    
    assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN


@pytest.mark.anyio
async def test_get_current_user_expired_token(monkeypatch, mock_session, mock_redis):
    def _raise_expired(_):
        raise firebase_auth.ExpiredIdTokenError("expired", "expired")
        
    monkeypatch.setattr("app.auth.deps.verify_token", _raise_expired)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(request=None, credentials=_make_creds(), session=mock_session)
    
    assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED
    assert "expired" in exc_info.value.detail


@pytest.mark.anyio
async def test_get_current_user_cache_hit(monkeypatch, mock_session, mock_redis):
    monkeypatch.setattr(
        "app.auth.deps.verify_token",
        lambda _: {"uid": "existing_uid", "email": "test@example.com", "email_verified": True}
    )

    existing_user = User(
        id=uuid.uuid4(),
        auth_subject="existing_uid",
        auth_provider="firebase",
        email="test@example.com",
    )
    mock_session.users.append(existing_user)

    # First call places it in cache
    user1 = await get_current_user(request=None, credentials=_make_creds(), session=mock_session)
    assert user1.id == existing_user.id
    
    # Empty DB, but keep cache
    mock_session.users = [existing_user]
    
    # Second call uses cache + DB refresh
    user2 = await get_current_user(request=None, credentials=_make_creds(), session=mock_session)
    assert user2.id == existing_user.id
