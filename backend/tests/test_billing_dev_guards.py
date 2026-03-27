from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.api.routers.billing import _assert_dev_billing_access, _dev_billing_routes_enabled


def _request_with_secret(secret: str | None = None) -> Request:
    headers = []
    if secret is not None:
        headers.append((b"x-internal-dev-key", secret.encode()))
    return Request(scope={"type": "http", "headers": headers})


def test_dev_routes_enabled_requires_dev_environment_and_flag(monkeypatch) -> None:
    monkeypatch.setenv("DEV_BILLING_INTERNAL_SECRET", "dummy-secret")
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("ENABLE_DEV_BILLING_ENDPOINTS", "true")
    assert _dev_billing_routes_enabled() is True

    monkeypatch.setenv("APP_ENV", "production")
    assert _dev_billing_routes_enabled() is False

    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("ENABLE_DEV_BILLING_ENDPOINTS", "false")
    assert _dev_billing_routes_enabled() is False


def test_dev_access_rejects_non_admin(monkeypatch) -> None:
    monkeypatch.delenv("DEV_BILLING_INTERNAL_SECRET", raising=False)
    with pytest.raises(HTTPException) as exc_info:
        _assert_dev_billing_access(_request_with_secret(), SimpleNamespace(is_admin=False))
    assert exc_info.value.status_code == 403


def test_dev_access_requires_secret_when_configured(monkeypatch) -> None:
    monkeypatch.setenv("DEV_BILLING_INTERNAL_SECRET", "expected-secret")
    with pytest.raises(HTTPException) as exc_info:
        _assert_dev_billing_access(_request_with_secret("wrong-secret"), SimpleNamespace(is_admin=True))
    assert exc_info.value.status_code == 403

    _assert_dev_billing_access(_request_with_secret("expected-secret"), SimpleNamespace(is_admin=True))


def test_dev_router_mounts_in_local_even_if_flag_disabled(monkeypatch) -> None:
    from app.api.routers.billing import should_include_dev_billing_router

    monkeypatch.setenv("DEV_BILLING_INTERNAL_SECRET", "dummy-secret")

    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("ENABLE_DEV_BILLING_ENDPOINTS", "false")
    assert should_include_dev_billing_router() is False

    monkeypatch.setenv("ENABLE_DEV_BILLING_ENDPOINTS", "true")
    assert should_include_dev_billing_router() is True

    monkeypatch.setenv("APP_ENV", "production")
    assert should_include_dev_billing_router() is False
