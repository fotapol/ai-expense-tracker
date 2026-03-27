"""Launch-focused worker regressions for duplicate receipt processing safety."""

from __future__ import annotations

import datetime as dt
import uuid
from types import SimpleNamespace

from app.models.shared.enums import ReceiptStatus


class _Result:
    """Minimal query result wrapper."""

    def __init__(self, values: list):
        self._values = values

    def first(self):
        return self._values[0] if self._values else None


class _Session:
    """Mock session that records ORM operations in-memory."""

    def __init__(self, exec_results: list | None = None):
        self._exec_results = exec_results or []
        self._exec_call_count = 0
        self.added: list = []
        self.commit_calls = 0

    def exec(self, _statement) -> _Result:
        idx = self._exec_call_count
        self._exec_call_count += 1
        if idx < len(self._exec_results):
            return _Result(self._exec_results[idx])
        return _Result([])

    def add(self, obj) -> None:
        self.added.append(obj)

    def commit(self) -> None:
        self.commit_calls += 1


class _SessionContext:
    """Context manager wrapper for the fake session."""

    def __init__(self, session: _Session):
        self._session = session

    def __enter__(self) -> _Session:
        return self._session

    def __exit__(self, exc_type, exc, tb) -> bool:
        return False


def test_reconcile_existing_processing_state_completes_duplicate_transaction_job() -> None:
    """Duplicate redeliveries should restore a stable COMPLETED state when tx already exists."""

    from app.worker import receipt_processor as worker

    session = _Session()
    receipt = SimpleNamespace(
        status=ReceiptStatus.PROCESSING,
        failure_reason="worker crashed mid-flight",
    )
    existing_tx = SimpleNamespace(id=uuid.uuid4())

    result = worker._reconcile_existing_processing_state(
        session,
        receipt=receipt,
        receipt_id=str(uuid.uuid4()),
        existing_extraction=None,
        existing_tx=existing_tx,
    )

    assert result is True
    assert receipt.status == ReceiptStatus.COMPLETED
    assert receipt.failure_reason is None
    assert session.added == [receipt]
    assert session.commit_calls == 1


def test_reconcile_existing_processing_state_marks_orphaned_extraction_failed() -> None:
    """An extraction without a transaction should surface an explicit launch-visible failure."""

    from app.worker import receipt_processor as worker

    session = _Session()
    receipt = SimpleNamespace(
        status=ReceiptStatus.PROCESSING,
        failure_reason=None,
    )
    existing_extraction = SimpleNamespace(id=uuid.uuid4())

    result = worker._reconcile_existing_processing_state(
        session,
        receipt=receipt,
        receipt_id=str(uuid.uuid4()),
        existing_extraction=existing_extraction,
        existing_tx=None,
    )

    assert result is True
    assert receipt.status == ReceiptStatus.FAILED
    assert "Please re-upload the receipt." in receipt.failure_reason
    assert session.added == [receipt]
    assert session.commit_calls == 1


def test_process_receipt_skips_recent_duplicate_processing_attempt(monkeypatch) -> None:
    """A redelivered in-flight receipt job should not run extraction work a second time."""

    from app.worker import receipt_processor as worker

    receipt = SimpleNamespace(
        id=uuid.uuid4(),
        status=ReceiptStatus.PROCESSING,
        updated_at=dt.datetime.now(dt.UTC),
        created_at=dt.datetime.now(dt.UTC),
        processing_attempt=1,
        failure_reason=None,
        storage_key="receipts/test.jpg",
        storage_bucket="receipts",
        user_id=uuid.uuid4(),
        mime_type="image/jpeg",
    )
    session = _Session(exec_results=[[receipt], [], []])

    monkeypatch.setattr(worker, "Session", lambda _engine: _SessionContext(session))
    monkeypatch.setattr(
        worker,
        "download_object",
        lambda **_kwargs: (_ for _ in ()).throw(
            AssertionError("duplicate in-flight receipt should not download again")
        ),
    )

    worker.process_receipt(str(receipt.id))

    assert receipt.status == ReceiptStatus.PROCESSING
    assert session.commit_calls == 0
    assert session.added == []
