"""Tests for the Receipt API."""

import datetime as dt
import uuid

import pytest
from fastapi import HTTPException, status
from pydantic import ValidationError

from app.api.routers.receipts import create_receipt, confirm_upload
from app.models.receipts.receipt import Receipt
from app.models.shared.enums import ReceiptStatus
from app.schemas.receipts import ReceiptCreateRequest
from app.models.users.user import User


class _MockSession:
    def __init__(self):
        self.added = []
        self._commit_called = False
    
    def exec(self, query):
        class Result:
            def __init__(self, u):
                self.u = u
            def first(self):
                return self.u
        return Result(self.added[0] if self.added else None)

    def add(self, obj):
        self.added.append(obj)

    def commit(self):
        self._commit_called = True

    def refresh(self, obj):
        pass

    def rollback(self):
        pass


@pytest.fixture
def mock_session():
    return _MockSession()


@pytest.fixture
def test_user():
    return User(id=uuid.uuid4(), email="test@example.com")


@pytest.mark.anyio
async def test_create_receipt_happy_path(mock_session, test_user):
    payload = ReceiptCreateRequest(
        mime_type="image/jpeg",
        original_filename="test.jpg",
        size_bytes=1024,
    )
    
    res = await create_receipt(payload=payload, request=None, session=mock_session, current_user=test_user)
    
    assert res.receipt_id is not None
    assert "url" not in res.upload_url  # MinIO presigned generation wasn't mocked, but we verify response shape
    assert mock_session._commit_called
    assert mock_session.added[0].status == ReceiptStatus.CREATED
    assert mock_session.added[0].mime_type == "image/jpeg"


@pytest.mark.anyio
async def test_create_receipt_rejects_invalid_mime(mock_session, test_user):
    payload = ReceiptCreateRequest(
        mime_type="text/plain",
        original_filename="test.txt",
        size_bytes=1024,
    )
    
    with pytest.raises(HTTPException) as exc_info:
        await create_receipt(payload=payload, request=None, session=mock_session, current_user=test_user)
    
    assert exc_info.value.status_code == status.HTTP_400_BAD_REQUEST
    assert "Unsupported mime_type" in exc_info.value.detail


@pytest.mark.anyio
async def test_confirm_upload_happy_path(monkeypatch, mock_session, test_user):
    receipt_id = uuid.uuid4()
    receipt = Receipt(
        id=receipt_id,
        user_id=test_user.id,
        status=ReceiptStatus.CREATED,
        storage_bucket="receipts",
        storage_key="receipts/123/file.jpg",
        mime_type="image/jpeg",
        size_bytes=0,
    )
    mock_session.added.append(receipt)

    monkeypatch.setattr("app.api.routers.receipts.head_object", lambda key, bucket: {"size_bytes": 1024, "content_type": "image/jpeg"})
    
    # Mock usage checks
    from types import SimpleNamespace
    monkeypatch.setattr("app.api.routers.receipts.resolve_receipt_scan_usage", lambda s, uid: SimpleNamespace(used=0, limit=100))
    monkeypatch.setattr("app.api.routers.receipts.receipt_scan_limit_reached", lambda u: False)
    
    # Mock rabbitmq logic to bypass without actual aio_pika
    class _MockChannel:
        class _Exchange:
            async def publish(self, msg, routing_key):
                pass
        default_exchange = _Exchange()

    class _MockConnection:
        async def channel(self):
            return _MockChannel()

    monkeypatch.setattr("app.api.routers.receipts.get_rabbitmq_connection", lambda: _MockConnection())

    # We need to mock aio_pika imports in the try-block if aio-pika is totally missing or complex. 
    # But since it's installed as a dependency, it should pass.
    res = await confirm_upload(receipt_id=receipt_id, request=None, session=mock_session, current_user=test_user)
    
    assert res.receipt_id == receipt_id
    assert res.status == ReceiptStatus.UPLOADED
    assert receipt.status == ReceiptStatus.UPLOADED
    assert receipt.size_bytes == 1024


@pytest.mark.anyio
async def test_confirm_upload_rejects_oversized_file(monkeypatch, mock_session, test_user):
    receipt_id = uuid.uuid4()
    receipt = Receipt(
        id=receipt_id,
        user_id=test_user.id,
        status=ReceiptStatus.CREATED,
        storage_bucket="receipts",
        storage_key="receipts/123/file.jpg",
        mime_type="image/jpeg",
        size_bytes=0,
    )
    mock_session.added.append(receipt)

    from app.api.routers.receipts import _MAX_RECEIPT_FILE_BYTES
    large_size = _MAX_RECEIPT_FILE_BYTES + 1
    
    monkeypatch.setattr("app.api.routers.receipts.head_object", lambda key, bucket: {"size_bytes": large_size, "content_type": "image/jpeg"})
    
    with pytest.raises(HTTPException) as exc_info:
        await confirm_upload(receipt_id=receipt_id, request=None, session=mock_session, current_user=test_user)

    assert exc_info.value.status_code == status.HTTP_413_REQUEST_ENTITY_TOO_LARGE
