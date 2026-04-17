"""Health endpoint regressions for Kubernetes probes."""

from __future__ import annotations

import json

import pytest


@pytest.mark.anyio
async def test_liveness_check_is_process_only() -> None:
    from app import main

    assert await main.liveness_check() == {"status": "ok"}


@pytest.mark.anyio
async def test_root_healthcheck_is_public_safe() -> None:
    from app import main

    assert await main.healthcheck() == {
        "status": "ok",
        "service": "expense-tracker-api",
    }


@pytest.mark.anyio
async def test_readiness_check_requires_database_and_rabbitmq(monkeypatch) -> None:
    from app import main

    async def _true() -> bool:
        return True

    monkeypatch.setattr(main, "check_database_health", lambda: False)
    monkeypatch.setattr(main, "check_redis_health", _true)
    monkeypatch.setattr(main, "check_rabbitmq_health", _true)

    response = await main.readiness_check()
    payload = json.loads(response.body)

    assert response.status_code == 503
    assert payload["status"] == "degraded"
    assert payload["dependencies"]["database"] == "down"


@pytest.mark.anyio
async def test_readiness_check_allows_redis_degradation(monkeypatch) -> None:
    from app import main

    async def _false() -> bool:
        return False

    async def _true() -> bool:
        return True

    monkeypatch.setattr(main, "check_database_health", lambda: True)
    monkeypatch.setattr(main, "check_redis_health", _false)
    monkeypatch.setattr(main, "check_rabbitmq_health", _true)

    response = await main.readiness_check()
    payload = json.loads(response.body)

    assert response.status_code == 200
    assert payload["status"] == "ok"
    assert payload["dependencies"]["redis"] == "down"
