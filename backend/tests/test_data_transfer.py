"""Tests for data import and export."""

import datetime as dt
import uuid
from decimal import Decimal

import pytest
from fastapi import Request

from app.api.routers.data import export_data
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.user import User


class _MockSession:
    def __init__(self, exec_results=None):
        self._exec_results = exec_results or []
        self._exec_call_count = 0
    
    def exec(self, query):
        class Result:
            def __init__(self, values):
                self.values = values
            def all(self):
                return self.values
        
        idx = self._exec_call_count
        self._exec_call_count += 1
        if idx < len(self._exec_results):
            return Result(self._exec_results[idx])
        return Result([])


@pytest.fixture
def mock_session():
    return _MockSession()


@pytest.fixture
def test_user():
    return User(id=uuid.uuid4(), email="test@example.com")


@pytest.mark.anyio
async def test_export_data_empty(monkeypatch, test_user):
    # Mock user_has_feature
    monkeypatch.setattr("app.api.routers.data.user_has_feature", lambda *args, **kwargs: True)

    session = _MockSession(exec_results=[
        [], # user_categories
        [], # transactions
        [], # items
    ])

    res = await export_data(request=None, session=session, current_user=test_user)
    
    assert res.categories == []
    assert res.transactions == []


@pytest.mark.anyio
async def test_export_data_with_records(monkeypatch, test_user):
    monkeypatch.setattr("app.api.routers.data.user_has_feature", lambda *args, **kwargs: True)

    cat_id = uuid.uuid4()
    tx_id = uuid.uuid4()
    item_id = uuid.uuid4()

    cat = Category(
        id=cat_id,
        user_id=test_user.id,
        name="Exported Category",
        code="EXP",
        scope=CategoryScope.TRANSACTION,
        is_active=True,
    )
    
    tx = Transaction(
        id=tx_id,
        user_id=test_user.id,
        amount_total=Decimal("100.00"),
        currency="USD",
        occurred_at=dt.datetime.now(dt.UTC),
    )

    item = TransactionItem(
        id=item_id,
        transaction_id=tx_id,
        line_no=1,
        amount=Decimal("100.00"),
    )

    session = _MockSession(exec_results=[
        [cat], # user_categories
        [tx], # transactions
        [item], # items
    ])

    res = await export_data(request=None, session=session, current_user=test_user)
    
    assert len(res.categories) == 1
    assert res.categories[0].id == cat_id
    assert res.categories[0].name == "Exported Category"

    assert len(res.transactions) == 1
    assert res.transactions[0].id == tx_id
    assert len(res.transactions[0].items) == 1
    assert res.transactions[0].items[0].id == item_id

