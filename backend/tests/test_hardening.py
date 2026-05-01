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
# AI privacy: LangSmith traces must stay receipt-content redacted
# ---------------------------------------------------------------------------

def test_langsmith_receipt_trace_payloads_are_redacted() -> None:
    """Trace helper payloads must not include raw receipt content."""

    from app.core.langsmith import (
        build_receipt_trace_inputs,
        build_receipt_trace_outputs,
    )

    raw_receipt_marker = "RAW_RECEIPT_TOTAL_123.45"
    inputs = build_receipt_trace_inputs(
        receipt_id="receipt-123",
        attempt=1,
        mime_type="image/jpeg",
        image_size_bytes=len(raw_receipt_marker.encode()),
        transaction_category_count=12,
        item_category_count=42,
    )
    outputs = build_receipt_trace_outputs(
        provider="google",
        model_name="gemini-test",
        latency_ms=100,
        item_count=3,
        currency="USD",
        warning_count=0,
        token_usage={"input_tokens": 100, "output_tokens": 50},
    )

    serialized = repr({"inputs": inputs, "outputs": outputs})
    assert raw_receipt_marker not in serialized
    assert inputs["input_redacted"] is True
    assert outputs["output_redacted"] is True


def test_production_startup_blocks_unredacted_langsmith(monkeypatch) -> None:
    """Production must not start with LangSmith receipt payload hiding disabled."""

    from app.core.startup_checks import validate_production_config

    env = {
        "APP_ENV": "production",
        "PUBLIC_API_BASE_URL": "https://api.nexavend.store:8443",
        "DATABASE_URL": "postgresql+psycopg://user:pass@postgres:5432/db",
        "S3_ACCESS_KEY": "access",
        "S3_SECRET_KEY": "secret",
        "S3_EXTERNAL_ENDPOINT": "https://storage.nexavend.store:8443",
        "GOOGLE_API_KEY": "google-key",
        "RABBITMQ_URL": "amqp://expense_tracker:pass@rabbitmq:5672/",
        "FIREBASE_SERVICE_ACCOUNT_PATH": "/run/secrets/firebase_sa.json",
        "FIREBASE_SERVICE_ACCOUNT_JSON_B64": "firebase-json",
        "LANGSMITH_TRACING": "true",
        "LANGSMITH_API_KEY": "langsmith-key",
        "LANGSMITH_HIDE_INPUTS": "false",
        "LANGSMITH_HIDE_OUTPUTS": "true",
    }
    for key, value in env.items():
        monkeypatch.setenv(key, value)

    with pytest.raises(SystemExit) as exc_info:
        validate_production_config()

    assert "Production startup blocked" in str(exc_info.value)


def test_production_startup_blocks_wildcard_forwarded_trust(monkeypatch) -> None:
    """Production must not trust forwarded headers from every source."""

    from app.core.startup_checks import validate_production_config

    env = {
        "APP_ENV": "production",
        "PUBLIC_API_BASE_URL": "https://api.nexavend.store:8443",
        "DATABASE_URL": "postgresql+psycopg://user:pass@postgres:5432/db",
        "S3_ACCESS_KEY": "access",
        "S3_SECRET_KEY": "secret",
        "S3_EXTERNAL_ENDPOINT": "https://storage.nexavend.store:8443",
        "GOOGLE_API_KEY": "google-key",
        "RABBITMQ_URL": "amqp://expense_tracker:pass@rabbitmq:5672/",
        "FIREBASE_SERVICE_ACCOUNT_PATH": "/run/secrets/firebase_sa.json",
        "FIREBASE_SERVICE_ACCOUNT_JSON_B64": "firebase-json",
        "LANGSMITH_TRACING": "true",
        "LANGSMITH_API_KEY": "langsmith-key",
        "LANGSMITH_HIDE_INPUTS": "true",
        "LANGSMITH_HIDE_OUTPUTS": "true",
        "UVICORN_FORWARDED_ALLOW_IPS": "*",
    }
    for key, value in env.items():
        monkeypatch.setenv(key, value)

    with pytest.raises(SystemExit) as exc_info:
        validate_production_config()

    assert "Production startup blocked" in str(exc_info.value)


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
