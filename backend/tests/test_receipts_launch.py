"""Launch-focused regressions for receipt visibility and enqueue safety."""

from __future__ import annotations

import asyncio
import datetime as dt
import sys
import types
import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.models.shared.enums import ReceiptStatus


class _Result:
    """Minimal query result wrapper."""

    def __init__(self, values: list):
        self._values = values

    def all(self) -> list:
        return self._values

    def first(self):
        return self._values[0] if self._values else None


class _Session:
    """Mock session that records ORM operations in-memory."""

    def __init__(self, exec_results: list | None = None):
        self._exec_results = exec_results or []
        self._exec_call_count = 0
        self.added: list = []
        self.deleted: list = []
        self.committed = False
        self.commit_calls = 0
        self.refreshed: list = []
        self.flush_calls = 0

    def exec(self, _statement) -> _Result:
        idx = self._exec_call_count
        self._exec_call_count += 1
        if idx < len(self._exec_results):
            return _Result(self._exec_results[idx])
        return _Result([])

    def add(self, obj) -> None:
        self.added.append(obj)

    def delete(self, obj) -> None:
        self.deleted.append(obj)

    def flush(self) -> None:
        self.flush_calls += 1

    def commit(self) -> None:
        self.committed = True
        self.commit_calls += 1

    def refresh(self, obj) -> None:
        self.refreshed.append(obj)


def _request() -> Request:
    """Build a minimal Starlette request for SlowAPI-wrapped endpoints."""

    return Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/",
            "headers": [],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
            "scheme": "http",
        }
    )


def _unwrap(func):
    """Return the original endpoint function beneath decorators."""

    while hasattr(func, "__wrapped__"):
        func = func.__wrapped__
    return func


def test_get_visible_receipt_and_transaction_allows_owner_row() -> None:
    """Receipt polling should stay visible for the uploader's data."""

    from app.api.routers import receipts as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    receipt = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        status=ReceiptStatus.COMPLETED,
    )
    transaction = SimpleNamespace(
        id=uuid.uuid4(),
        receipt_id=receipt.id,
    )
    session = _Session(exec_results=[[receipt], [transaction]])

    visible_receipt, visible_transaction = router._get_visible_receipt_and_transaction(
        session,
        receipt_id=receipt.id,
        current_user=current_user,
    )

    assert visible_receipt is receipt
    assert visible_transaction is transaction


def test_confirm_upload_reverts_receipt_state_when_enqueue_publish_fails(monkeypatch) -> None:
    """Queue handoff failures should leave the receipt retryable instead of stranded."""

    from app.api.routers import receipts as router

    class _ExplodingExchange:
        async def publish(self, *_args, **_kwargs) -> None:
            raise RuntimeError("queue publish failed")

    class _Channel:
        default_exchange = _ExplodingExchange()

    class _Connection:
        async def channel(self) -> _Channel:
            return _Channel()

    current_user = SimpleNamespace(id=uuid.uuid4())
    receipt = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        status=ReceiptStatus.CREATED,
        storage_key="receipts/test.png",
        storage_bucket="receipts",
        uploaded_at=None,
        size_bytes=0,
        mime_type="image/png",
    )
    usage = SimpleNamespace(
        used=0,
        limit=5,
        remaining=5,
        is_unlimited=False,
        period_start_at=dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
        period_end_at=dt.datetime(2026, 3, 31, tzinfo=dt.UTC),
    )
    session = _Session(exec_results=[[receipt], [current_user.id]])

    fake_aio_pika = types.SimpleNamespace(
        Message=lambda **kwargs: kwargs,
        DeliveryMode=types.SimpleNamespace(PERSISTENT="persistent"),
    )

    monkeypatch.setitem(sys.modules, "aio_pika", fake_aio_pika)
    monkeypatch.setattr(
        router,
        "head_object",
        lambda **_kwargs: {"size_bytes": 123, "content_type": "image/png"},
    )
    monkeypatch.setattr(
        router,
        "read_object_prefix",
        lambda **_kwargs: b"\x89PNG\r\n\x1a\n",
    )
    monkeypatch.setattr(
        router,
        "resolve_receipt_scan_usage",
        lambda *_args, **_kwargs: usage,
    )
    monkeypatch.setattr(router, "receipt_scan_limit_reached", lambda _usage: False)
    monkeypatch.setattr(router, "get_rabbitmq_connection", lambda: _Connection())

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            _unwrap(router.confirm_upload)(
                receipt_id=receipt.id,
                request=_request(),
                session=session,
                current_user=current_user,
            )
        )

    assert exc_info.value.status_code == 503
    assert exc_info.value.detail == "Failed to enqueue extraction job."
    assert session.committed is True
    assert session.commit_calls == 2
    assert receipt.status == ReceiptStatus.CREATED
    assert receipt.uploaded_at is None
    assert receipt.mime_type == "image/png"
    assert session.refreshed == [receipt, receipt]


def test_delete_receipt_aborts_when_storage_cleanup_fails(monkeypatch) -> None:
    """Receipt deletion must not remove DB rows if object deletion fails."""

    from app.api.routers import receipts as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    receipt = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        status=ReceiptStatus.COMPLETED,
        storage_key="receipts/test.png",
        storage_bucket="receipts",
    )
    session = _Session(exec_results=[[receipt]])

    def _fail_delete_object(*_args, **_kwargs) -> None:
        raise RuntimeError("storage unavailable")

    monkeypatch.setattr(router, "delete_object", _fail_delete_object)

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            _unwrap(router.delete_receipt)(
                receipt_id=receipt.id,
                request=_request(),
                session=session,
                current_user=current_user,
            )
        )

    assert exc_info.value.status_code == 503
    assert session.deleted == []
    assert session.commit_calls == 0
