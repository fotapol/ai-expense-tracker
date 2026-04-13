"""Tests for Phase 3 backend hardening changes."""

from __future__ import annotations

import datetime as dt
import uuid
from types import SimpleNamespace

import pytest

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
        self.committed = False
        self.commit_calls = 0
        self.refreshed: list = []
        self._rolled_back = False

    def exec(self, _statement) -> _Result:
        idx = self._exec_call_count
        self._exec_call_count += 1
        if idx < len(self._exec_results):
            return _Result(self._exec_results[idx])
        return _Result([])

    def add(self, obj) -> None:
        self.added.append(obj)

    def commit(self) -> None:
        self.committed = True
        self.commit_calls += 1

    def refresh(self, obj) -> None:
        self.refreshed.append(obj)

    def rollback(self) -> None:
        self._rolled_back = True


# ---------------------------------------------------------------------------
# SEC-19: Receipt failure_reason must not leak tracebacks
# ---------------------------------------------------------------------------

def test_receipt_failure_reason_is_user_safe_message() -> None:
    """Worker must store a user-friendly message, not a raw Python traceback."""

    from app.worker import receipt_processor as worker

    receipt = SimpleNamespace(
        id=uuid.uuid4(),
        status=ReceiptStatus.PROCESSING,
        updated_at=dt.datetime.now(dt.UTC) - dt.timedelta(minutes=30),
        created_at=dt.datetime.now(dt.UTC) - dt.timedelta(hours=1),
        processing_attempt=2,  # Start at 2 so it hits 3 (max retries) during processing
        failure_reason=None,
        storage_key="receipts/test.jpg",
        storage_bucket="receipts",
        user_id=uuid.uuid4(),
        mime_type="image/jpeg",
    )

    class _FailingSession(_Session):
        """Session that lets the receipt load but fails on extraction."""

        def __init__(self):
            super().__init__(exec_results=[[receipt], [], []])
            self._refresh_count = 0

        def refresh(self, obj) -> None:
            self._refresh_count += 1
            super().refresh(obj)

    session = _FailingSession()

    class _SessionContext:
        def __init__(self, s):
            self._s = s
        def __enter__(self):
            return self._s
        def __exit__(self, *_args):
            return False

    # Make download_object raise to trigger the failure path
    def _exploding_download(**_kwargs):
        raise RuntimeError("Simulated LLM failure")

    import app.worker.receipt_processor as w
    original_session = w.Session
    original_download = w.download_object

    try:
        w.Session = lambda _engine: _SessionContext(session)
        w.download_object = _exploding_download
        w.process_receipt(str(receipt.id))
    finally:
        w.Session = original_session
        w.download_object = original_download

    assert receipt.status == ReceiptStatus.FAILED
    # Must NOT contain traceback fragments
    assert "Traceback" not in (receipt.failure_reason or "")
    assert "RuntimeError" not in (receipt.failure_reason or "")
    assert "File " not in (receipt.failure_reason or "")
    # Must contain a user-friendly message
    assert "extract data" in receipt.failure_reason.lower() or "try" in receipt.failure_reason.lower()


# ---------------------------------------------------------------------------
# SEC-15: Server-side file size limit
# ---------------------------------------------------------------------------

def test_max_receipt_file_size_constant_exists() -> None:
    """The server-side file size limit constant must be defined."""

    from app.api.routers.receipts import _MAX_RECEIPT_FILE_BYTES

    # Must be a reasonable limit (between 1 MB and 100 MB)
    assert 1 * 1024 * 1024 <= _MAX_RECEIPT_FILE_BYTES <= 100 * 1024 * 1024
    # Current value should be 15 MB
    assert _MAX_RECEIPT_FILE_BYTES == 15 * 1024 * 1024


# ---------------------------------------------------------------------------
# PROD-19: Global exception handler
# ---------------------------------------------------------------------------

def test_global_exception_handler_is_registered() -> None:
    """The FastAPI app must have a global exception handler for Exception."""

    from app.main import app

    # FastAPI stores exception handlers in the exception_handlers dict
    # The key is the exception class, the value is the handler function
    assert Exception in app.exception_handlers, (
        "Global Exception handler not registered on the FastAPI app"
    )
