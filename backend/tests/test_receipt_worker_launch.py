"""Launch-focused worker regressions for duplicate receipt processing safety."""

from __future__ import annotations

import asyncio
import datetime as dt
import uuid
from decimal import Decimal
from types import SimpleNamespace

from app.models.shared.enums import ReceiptStatus
from app.schemas.extraction import ExtractedReceiptData, ExtractedTransactionItem


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


class _FakeMessageProcess:
    def __init__(self, message: _FakeMessage, *, requeue: bool):
        self._message = message
        self._requeue = requeue

    async def __aenter__(self):
        return self._message

    async def __aexit__(self, exc_type, _exc, _tb) -> bool:
        self._message.process_exited = True
        if exc_type is None:
            self._message.acked = True
        else:
            self._message.nacked = True
            self._message.nack_requeue = self._requeue
        return False


class _FakeMessage:
    def __init__(self, body: bytes):
        self.body = body
        self.process_kwargs: dict | None = None
        self.process_exited = False
        self.acked = False
        self.nacked = False
        self.nack_requeue: bool | None = None

    def process(self, **kwargs):
        self.process_kwargs = kwargs
        return _FakeMessageProcess(
            self,
            requeue=bool(kwargs.get("requeue", False)),
        )


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


def test_worker_message_processing_failures_are_requeued(monkeypatch) -> None:
    """Transient worker failures must NACK/requeue instead of ACKing stuck receipts."""

    from app.worker import receipt_processor as worker

    receipt_id = str(uuid.uuid4())
    message = _FakeMessage(f'{{"receipt_id": "{receipt_id}"}}'.encode())

    def _failing_process_receipt(_receipt_id: str) -> None:
        raise RuntimeError("temporary provider failure")

    monkeypatch.setattr(worker, "process_receipt", _failing_process_receipt)

    asyncio.run(worker._handle_worker_message(message))

    assert message.process_kwargs == {"requeue": True}
    assert message.process_exited is True
    assert message.acked is False
    assert message.nacked is True
    assert message.nack_requeue is True


def test_invalid_worker_messages_are_acked_without_requeue() -> None:
    """Malformed queue payloads should not poison-loop forever."""

    from app.worker import receipt_processor as worker

    message = _FakeMessage(b"not-json")

    asyncio.run(worker._handle_worker_message(message))

    assert message.process_kwargs == {"requeue": False}
    assert message.process_exited is True
    assert message.acked is True
    assert message.nacked is False


def test_rabbitmq_startup_log_redacts_credentials() -> None:
    """Worker startup logs must not print queue credentials."""

    from app.worker import receipt_processor as worker

    redacted = worker._redact_url_credentials("amqp://expense_tracker:super-secret@rabbitmq:5672/")

    assert redacted == "amqp://rabbitmq:5672/"
    assert "super-secret" not in redacted
    assert "expense_tracker" not in redacted


def test_parse_structured_receipt_response_preserves_raw_usage_message() -> None:
    """Structured output include_raw responses should keep raw metadata separate."""

    from app.worker import receipt_processor as worker

    extracted = ExtractedReceiptData(
        merchant_name="Test Store",
        currency="EUR",
        amount_total=Decimal("12.34"),
        items=[],
    )
    raw_message = SimpleNamespace(
        usage_metadata={
            "input_tokens": 20,
            "output_tokens": 10,
            "total_tokens": 30,
        }
    )

    parsed, raw = worker._parse_structured_receipt_response(
        {"parsed": extracted, "raw": raw_message, "parsing_error": None}
    )

    assert parsed is extracted
    assert raw is raw_message


def test_extraction_discount_normalization_infers_missing_discount_fields() -> None:
    """Discounted line totals should preserve final price and explicit savings."""

    from app.worker import receipt_processor as worker

    extracted = ExtractedReceiptData(
        currency="RSD",
        amount_total=Decimal("80.00"),
        items=[
            ExtractedTransactionItem(
                line_no=1,
                description="Discounted item",
                qty=Decimal("1"),
                unit="pc",
                unit_price=Decimal("100.00"),
                amount=Decimal("80.00"),
            )
        ],
    )

    normalized = worker._normalize_extracted_item_discounts(extracted)

    item = normalized.items[0]
    assert item.amount == Decimal("80.00")
    assert item.amount_before_discount == Decimal("100.00")
    assert item.discount_amount == Decimal("20.00")
    assert worker._compute_extraction_warnings(normalized) == []


def test_extraction_discount_normalization_derives_discount_from_original_amount() -> None:
    """An original amount without explicit discount should still enable discount UX."""

    from app.worker import receipt_processor as worker

    extracted = ExtractedReceiptData(
        currency="RSD",
        amount_total=Decimal("75.50"),
        items=[
            ExtractedTransactionItem(
                line_no=1,
                description="Loyalty price item",
                qty=Decimal("1"),
                unit="pc",
                amount=Decimal("75.50"),
                amount_before_discount=Decimal("99.99"),
            )
        ],
    )

    normalized = worker._normalize_extracted_item_discounts(extracted)

    item = normalized.items[0]
    assert item.amount_before_discount == Decimal("99.99")
    assert item.discount_amount == Decimal("24.49")
    assert worker._compute_extraction_warnings(normalized) == []
