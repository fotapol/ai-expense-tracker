"""Production API runtime hardening regressions."""

from __future__ import annotations

import importlib

import pytest
from fastapi.testclient import TestClient


def _reload_main(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("PUBLIC_API_BASE_URL", "https://api.nexavend.store:8443")
    monkeypatch.setenv("PUBLIC_APP_BASE_URL", "https://nexavend.store")
    monkeypatch.setenv(
        "TRUSTED_HOSTS",
        ",".join(
            [
                "api.nexavend.store",
                "expense-tracker-api",
                "expense-tracker-api.expense-tracker",
            ]
        ),
    )
    monkeypatch.setenv("CORS_ALLOWED_ORIGINS", "https://nexavend.store")
    monkeypatch.delenv("API_DOCS_ENABLED", raising=False)

    import app.main as main

    return importlib.reload(main)


def test_production_docs_and_openapi_are_disabled(monkeypatch) -> None:
    main = _reload_main(monkeypatch)
    client = TestClient(main.app)

    for path in ("/docs", "/redoc", "/openapi.json"):
        response = client.get(path, headers={"host": "api.nexavend.store"})
        assert response.status_code == 404


def test_trusted_host_accepts_public_host_with_custom_port(monkeypatch) -> None:
    main = _reload_main(monkeypatch)
    client = TestClient(main.app)

    response = client.get("/", headers={"host": "api.nexavend.store:8443"})

    assert response.status_code == 200
    assert response.json()["service"] == "expense-tracker-api"


def test_trusted_host_rejects_unknown_hosts(monkeypatch) -> None:
    main = _reload_main(monkeypatch)
    client = TestClient(main.app)

    response = client.get("/", headers={"host": "attacker.example"})

    assert response.status_code == 400
    assert response.text == "Invalid host header"


def test_trusted_host_accepts_internal_probe_host(monkeypatch) -> None:
    main = _reload_main(monkeypatch)
    client = TestClient(main.app)

    response = client.get("/health/live", headers={"host": "expense-tracker-api"})

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.anyio
async def test_startup_migrations_can_be_disabled(monkeypatch) -> None:
    monkeypatch.setenv("RUN_STARTUP_MIGRATIONS", "false")

    import app.core.minio as minio
    import app.main as main

    main = importlib.reload(main)
    migration_calls = 0

    async def _migrate() -> None:
        nonlocal migration_calls
        migration_calls += 1

    async def _redis_ok() -> bool:
        return True

    async def _async_noop() -> None:
        return None

    monkeypatch.setattr(main, "validate_production_config", lambda: None)
    monkeypatch.setattr(main, "run_startup_migrations", _migrate)
    monkeypatch.setattr(main, "initialize_firebase", lambda: None)
    monkeypatch.setattr(main, "check_redis_health", _redis_ok)
    monkeypatch.setattr(main, "connect_rabbitmq", _async_noop)
    monkeypatch.setattr(main, "close_rabbitmq", _async_noop)
    monkeypatch.setattr(main, "close_redis_pool", _async_noop)
    monkeypatch.setattr(minio, "ensure_bucket", lambda _bucket: None)

    async with main.lifespan(main.app):
        pass

    assert migration_calls == 0
