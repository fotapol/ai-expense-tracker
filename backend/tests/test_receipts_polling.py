"""Tests for polling receipt status."""

import uuid

import pytest
from fastapi import HTTPException, status

from app.api.routers.receipts import get_receipt
from app.models.receipts.receipt import Receipt
from app.models.shared.enums import ReceiptStatus
from app.models.transactions.transaction import Transaction
from app.models.users.user import User


class _MockSession:
    def __init__(self):
        self.receipt = None
        self.transaction = None
    
    def exec(self, query):
        class Result:
            def __init__(self, item):
                self.item = item
            def first(self):
                return self.item
        
        if "Receipt." in str(query):
            return Result(self.receipt)
        if "Transaction." in str(query):
            return Result(self.transaction)
        return Result(None)


@pytest.fixture
def mock_session():
    return _MockSession()


@pytest.fixture
def test_user():
    return User(id=uuid.uuid4(), email="test@example.com")


@pytest.mark.anyio
async def test_get_receipt_created_status(mock_session, test_user):
    receipt_id = uuid.uuid4()
    mock_session.receipt = Receipt(
        id=receipt_id,
        user_id=test_user.id,
        status=ReceiptStatus.CREATED,
        storage_bucket="root",
        storage_key="test",
        mime_type="image/jpeg",
        original_filename="a",
        sha256="",
        size_bytes=10,
    )

    res = await get_receipt(receipt_id=receipt_id, request=None, session=mock_session, current_user=test_user)
    
    assert res.status == ReceiptStatus.CREATED
    assert res.transaction_id is None


@pytest.mark.anyio
async def test_get_receipt_completed_status_with_transaction(mock_session, test_user):
    receipt_id = uuid.uuid4()
    transaction_id = uuid.uuid4()

    mock_session.receipt = Receipt(
        id=receipt_id,
        user_id=test_user.id,
        status=ReceiptStatus.COMPLETED,
        storage_bucket="root",
        storage_key="test",
        mime_type="image/jpeg",
        original_filename="a",
        sha256="",
        size_bytes=10,
    )
    
    # Mock time
    import datetime as dt
    mock_session.transaction = Transaction(
        id=transaction_id,
        user_id=test_user.id,
        receipt_id=receipt_id,
        amount_total=0.0,
        currency="USD",
        occurred_at=dt.datetime.now(dt.UTC),
    )

    res = await get_receipt(receipt_id=receipt_id, request=None, session=mock_session, current_user=test_user)
    
    assert res.status == ReceiptStatus.COMPLETED
    assert res.transaction_id == transaction_id


@pytest.mark.anyio
async def test_get_receipt_rejects_other_user_ownership(mock_session, test_user):
    receipt_id = uuid.uuid4()
    other_user_id = uuid.uuid4()

    mock_session.receipt = Receipt(
        id=receipt_id,
        user_id=other_user_id, # Different user
        status=ReceiptStatus.CREATED,
        storage_bucket="root",
        storage_key="test",
        mime_type="image/jpeg",
        original_filename="a",
        sha256="",
        size_bytes=10,
    )

    with pytest.raises(HTTPException) as exc_info:
        await get_receipt(receipt_id=receipt_id, request=None, session=mock_session, current_user=test_user)
    
    assert exc_info.value.status_code == status.HTTP_404_NOT_FOUND
