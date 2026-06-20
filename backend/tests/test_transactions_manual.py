"""Focused tests for manual transactions, analytics gating, and receipt viewing."""

from __future__ import annotations

import asyncio
import datetime as dt
import uuid
from decimal import Decimal
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import CategoryScope, TransactionSource
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.schemas.transactions import (
    TransactionCreateManual,
    TransactionListFilter,
    TransactionRead,
    TransactionUpdateRequest,
    TransactionUserSnippetRead,
)
from app.services.taxonomy import collect_disable_target_ids


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
        self.flushed = False
        self.flush_calls = 0
        self.refreshed: list = []

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
        self.flushed = True
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


def test_create_transaction_stays_single_user_even_with_active_shared_household(
    monkeypatch,
) -> None:
    """Blank manual creation should stay item-less and ignore shared household defaults."""

    from app.api.routers import transactions_crud as router

    session = _Session()
    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    item_category_id = uuid.uuid4()
    tx_category_id = uuid.uuid4()
    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_get_user_visible_category_by_id",
        lambda *_args, **_kwargs: SimpleNamespace(id=item_category_id),
    )
    monkeypatch.setattr(router, "_get_uncategorized_item_category_id", lambda _session: uuid.uuid4())
    monkeypatch.setattr(
        router,
        "_resolve_transaction_category_from_item_category",
        lambda _session, *, item_category_id: tx_category_id if item_category_id else None,
    )
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: {
            "transaction_id": kwargs["transaction"].id,
            "item_count": len(kwargs["items"]),
            "category_id": kwargs["transaction"].category_id,
        },
    )

    payload = TransactionCreateManual(
        amount_total=Decimal("18.25"),
        currency="eur",
        merchant_name="Corner Market",
        category_id=item_category_id,
        items=[],
    )

    result = asyncio.run(
        _unwrap(router.create_transaction)(
            request=_request(),
            payload=payload,
            session=session,
            current_user=current_user,
        )
    )

    created_transaction = next(obj for obj in session.added if isinstance(obj, Transaction))
    created_items = [obj for obj in session.added if isinstance(obj, TransactionItem)]

    assert session.flushed is True
    assert session.committed is True
    assert created_transaction.source == TransactionSource.MANUAL
    assert created_transaction.receipt_id is None
    assert created_transaction.household_id is None
    assert created_transaction.category_id == tx_category_id
    assert created_transaction.created_by_user_id == current_user.id
    assert created_transaction.owner_user_id == current_user.id
    assert created_items == []
    assert result["item_count"] == 0


def test_get_transactions_summary_blocks_subcategory_mode_without_feature(monkeypatch) -> None:
    """Subcategory summary mode should require the advanced analytics entitlement."""

    from app.api.routers import transactions_analytics as router

    monkeypatch.setattr(router, "user_has_feature", lambda *args, **kwargs: False)

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            _unwrap(router.get_transactions_summary)(
                request=_request(),
                filters=TransactionListFilter(),
                group_by="subcategory",
                session=_Session(),
                current_user=current_user,
            )
        )

    assert exc_info.value.status_code == 403


def test_infer_analytics_bucket_unit_matches_expected_ranges() -> None:
    """Trend bucket selection should follow the selected range width."""

    from app.services.transactions import read_models as router

    assert (
        router._infer_analytics_bucket_unit(
            TransactionListFilter(
                from_occurred_at=dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
                to_occurred_at=dt.datetime(2026, 3, 7, tzinfo=dt.UTC),
            )
        )
        == "day"
    )
    assert (
        router._infer_analytics_bucket_unit(
            TransactionListFilter(
                from_occurred_at=dt.datetime(2026, 1, 1, tzinfo=dt.UTC),
                to_occurred_at=dt.datetime(2026, 4, 1, tzinfo=dt.UTC),
            )
        )
        == "week"
    )
    assert (
        router._infer_analytics_bucket_unit(
            TransactionListFilter(
                from_occurred_at=dt.datetime(2025, 1, 1, tzinfo=dt.UTC),
                to_occurred_at=dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
            )
        )
        == "month"
    )


def test_build_previous_period_filters_matches_current_window() -> None:
    """Previous trend range should mirror the current selected window."""

    from app.services.transactions import read_models as router

    filters = TransactionListFilter(
        from_occurred_at=dt.datetime(2026, 3, 10, tzinfo=dt.UTC),
        to_occurred_at=dt.datetime(2026, 3, 20, tzinfo=dt.UTC),
    )

    previous = router._build_previous_period_filters(filters)

    assert previous is not None
    assert previous.to_occurred_at < filters.from_occurred_at
    assert (
        previous.to_occurred_at - previous.from_occurred_at
        == filters.to_occurred_at - filters.from_occurred_at
    )


def test_get_transaction_trend_summary_aggregates_rows(monkeypatch) -> None:
    """Trend summary should bucket current rows and compare with the previous range."""

    from app.api.routers import transactions_analytics as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    filters = TransactionListFilter(
        from_occurred_at=dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
        to_occurred_at=dt.datetime(2026, 3, 7, tzinfo=dt.UTC),
    )
    current_rows = [
        (
            uuid.uuid4(),
            Decimal("10.00"),
            "EUR",
            dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
            dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
            current_user.id,
            current_user.id,
        ),
        (
            uuid.uuid4(),
            Decimal("20.00"),
            "EUR",
            dt.datetime(2026, 3, 2, tzinfo=dt.UTC),
            dt.datetime(2026, 3, 2, tzinfo=dt.UTC),
            current_user.id,
            current_user.id,
        ),
    ]
    previous_rows = [
        (
            uuid.uuid4(),
            Decimal("15.00"),
            "EUR",
            dt.datetime(2026, 2, 25, tzinfo=dt.UTC),
            dt.datetime(2026, 2, 25, tzinfo=dt.UTC),
            current_user.id,
            current_user.id,
        ),
    ]
    load_calls = {"count": 0}

    monkeypatch.setattr(
        router,
        "_build_analytics_scope",
        lambda **_kwargs: ("EUR", object(), object(), False),
    )

    def fake_load_rows(*_args, **_kwargs):
        load_calls["count"] += 1
        return current_rows if load_calls["count"] == 1 else previous_rows

    monkeypatch.setattr(router, "_load_analytics_spend_rows", fake_load_rows)
    monkeypatch.setattr(
        router,
        "convert_amount",
        lambda **kwargs: SimpleNamespace(
            value=kwargs["amount"],
            currency=kwargs["target_currency"],
            rate_date=None,
            rate_fallback=False,
        ),
    )

    result = asyncio.run(
        _unwrap(router.get_transaction_trend_summary)(
            request=_request(),
            filters=filters,
            session=_Session(),
            current_user=current_user,
        )
    )

    assert result.bucket_unit == "day"
    assert result.current_total_amount == Decimal("30.00")
    assert result.previous_total_amount == Decimal("15.00")
    assert result.change_percentage == 100.0
    assert result.buckets[0].amount == Decimal("10.00")
    assert result.buckets[1].amount == Decimal("20.00")


def test_get_household_analytics_summary_returns_empty_without_active_household(
    monkeypatch,
) -> None:
    """Household analytics should return an empty summary when no household exists."""

    from app.api.routers import transactions_analytics as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )

    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: None,
    )

    result = asyncio.run(
        _unwrap(router.get_household_analytics_summary)(
            request=_request(),
            filters=TransactionListFilter(),
            session=_Session(),
            current_user=current_user,
        )
    )

    assert result.household is None
    assert result.total_amount == Decimal("0.00")
    assert result.total_transactions == 0
    assert result.members == []


def test_get_household_analytics_summary_ranks_members(monkeypatch) -> None:
    """Household analytics should rank members and surface each member's top category."""

    from app.api.routers import transactions_analytics as router

    household_id = uuid.uuid4()
    owner_one = uuid.uuid4()
    owner_two = uuid.uuid4()
    groceries_id = uuid.uuid4()
    transport_id = uuid.uuid4()
    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    spend_rows = [
        (
            uuid.uuid4(),
            Decimal("20.00"),
            "EUR",
            dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
            dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
            owner_one,
            owner_one,
        ),
        (
            uuid.uuid4(),
            Decimal("5.00"),
            "EUR",
            dt.datetime(2026, 3, 2, tzinfo=dt.UTC),
            dt.datetime(2026, 3, 2, tzinfo=dt.UTC),
            owner_one,
            owner_one,
        ),
        (
            uuid.uuid4(),
            Decimal("10.00"),
            "EUR",
            dt.datetime(2026, 3, 3, tzinfo=dt.UTC),
            dt.datetime(2026, 3, 3, tzinfo=dt.UTC),
            owner_two,
            owner_two,
        ),
    ]
    category_rows = [
        (
            owner_one,
            owner_one,
            groceries_id,
            "Groceries",
            "GROCERIES",
            None,
            Decimal("25.00"),
            uuid.uuid4(),
            "EUR",
            dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
            dt.datetime(2026, 3, 1, tzinfo=dt.UTC),
        ),
        (
            owner_two,
            owner_two,
            transport_id,
            "Transport",
            "TRANSPORT",
            None,
            Decimal("10.00"),
            uuid.uuid4(),
            "EUR",
            dt.datetime(2026, 3, 3, tzinfo=dt.UTC),
            dt.datetime(2026, 3, 3, tzinfo=dt.UTC),
        ),
    ]
    session = _Session(
        exec_results=[
            [SimpleNamespace(id=household_id, name="Family")],
        ]
    )

    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: household_id,
    )
    monkeypatch.setattr(
        router,
        "_build_analytics_scope",
        lambda **_kwargs: ("EUR", object(), object(), False),
    )
    monkeypatch.setattr(router, "_load_analytics_spend_rows", lambda *_args, **_kwargs: spend_rows)
    monkeypatch.setattr(
        router,
        "_load_household_category_item_rows",
        lambda *_args, **_kwargs: category_rows,
    )
    monkeypatch.setattr(
        router,
        "_load_transaction_user_snippets",
        lambda *_args, **_kwargs: {
            owner_one: TransactionUserSnippetRead(
                user_id=owner_one,
                display_name="Alex",
                email="alex@example.com",
                avatar_url=None,
            ),
            owner_two: TransactionUserSnippetRead(
                user_id=owner_two,
                display_name="Jamie",
                email="jamie@example.com",
                avatar_url=None,
            ),
        },
    )
    monkeypatch.setattr(
        router,
        "convert_amount",
        lambda **kwargs: SimpleNamespace(
            value=kwargs["amount"],
            currency=kwargs["target_currency"],
            rate_date=None,
            rate_fallback=False,
        ),
    )

    result = asyncio.run(
        _unwrap(router.get_household_analytics_summary)(
            request=_request(),
            filters=TransactionListFilter(),
            session=session,
            current_user=current_user,
        )
    )

    assert result.household is not None
    assert result.household.household_id == household_id
    assert result.total_amount == Decimal("35.00")
    assert result.total_transactions == 3
    assert [member.owner_user_id for member in result.members] == [owner_one, owner_two]
    assert result.members[0].total_amount == Decimal("25.00")
    assert result.members[0].transaction_count == 2
    assert result.members[0].top_category is not None
    assert result.members[0].top_category.code == "GROCERIES"
    assert result.members[1].top_category is not None
    assert result.members[1].top_category.code == "TRANSPORT"


def test_create_transaction_without_active_household_stays_solo(monkeypatch) -> None:
    """Manual creation without shared household access should remain a solo transaction."""

    from app.api.routers import transactions_crud as router

    session = _Session()
    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(router, "_get_uncategorized_item_category_id", lambda _session: uuid.uuid4())
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: {
            "transaction_id": kwargs["transaction"].id,
            "item_count": len(kwargs["items"]),
        },
    )

    payload = TransactionCreateManual(
        amount_total=Decimal("4.50"),
        currency="EUR",
        merchant_name="Solo purchase",
        items=[],
    )

    asyncio.run(
        _unwrap(router.create_transaction)(
            request=_request(),
            payload=payload,
            session=session,
            current_user=current_user,
        )
    )

    created_transaction = next(obj for obj in session.added if isinstance(obj, Transaction))
    assert created_transaction.household_id is None
    assert created_transaction.owner_user_id == current_user.id


def test_create_transaction_normalizes_item_units(monkeypatch) -> None:
    """Manual transaction creation should normalize item units into canonical values."""

    from app.api.routers import transactions_crud as router

    session = _Session()
    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    item_category_id = uuid.uuid4()
    tx_category_id = uuid.uuid4()

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_get_user_visible_category_by_id",
        lambda *_args, **_kwargs: SimpleNamespace(id=item_category_id),
    )
    monkeypatch.setattr(router, "_get_uncategorized_item_category_id", lambda _session: uuid.uuid4())
    monkeypatch.setattr(
        router,
        "_resolve_transaction_category_from_item_category",
        lambda _session, *, item_category_id: tx_category_id if item_category_id else None,
    )
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: kwargs["transaction"],
    )

    payload = TransactionCreateManual(
        amount_total=Decimal("18.36"),
        currency="eur",
        merchant_name="Corner Market",
        category_id=item_category_id,
        items=[
            {
                "line_no": 1,
                "description": "Organic Apples",
                "qty": Decimal("2.000"),
                "unit": "pcs",
                "unit_price": Decimal("8.5000"),
                "amount": Decimal("17.00"),
                "category_id": item_category_id,
            }
        ],
    )

    result = asyncio.run(
        _unwrap(router.create_transaction)(
            request=_request(),
            payload=payload,
            session=session,
            current_user=current_user,
        )
    )

    created_transaction = next(obj for obj in session.added if isinstance(obj, Transaction))
    created_item = next(obj for obj in session.added if isinstance(obj, TransactionItem))

    assert created_transaction.amount_total == Decimal("18.36")
    assert created_item.unit == "pc"
    assert result.amount_total == Decimal("18.36")


def test_update_transaction_deletes_omitted_existing_items(monkeypatch) -> None:
    """Receipt editor saves should delete existing items omitted from the submitted list."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction_id = uuid.uuid4()
    kept_item_id = uuid.uuid4()
    removed_item_id = uuid.uuid4()

    transaction = Transaction(
        id=transaction_id,
        user_id=current_user.id,
        amount_total=Decimal("9.99"),
        currency="EUR",
        merchant_name="Corner Market",
        source=TransactionSource.MANUAL,
        status="DRAFT",
    )
    kept_item = TransactionItem(
        id=kept_item_id,
        transaction_id=transaction_id,
        line_no=1,
        description="Kept item",
        amount=Decimal("4.00"),
    )
    removed_item = TransactionItem(
        id=removed_item_id,
        transaction_id=transaction_id,
        line_no=2,
        description="Removed item",
        amount=Decimal("5.99"),
    )
    session = _Session(exec_results=[[transaction], [kept_item, removed_item]])

    monkeypatch.setattr(
        router,
        "_assert_household_transaction_access",
        lambda *args, **kwargs: None,
    )
    monkeypatch.setattr(
        router,
        "validate_transaction_attribution",
        lambda *args, **kwargs: None,
    )
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: kwargs["items"],
    )

    payload = TransactionUpdateRequest(
        amount_total=Decimal("5.00"),
        items=[
            {
                "id": kept_item_id,
                "description": "Kept item updated",
                "amount": Decimal("4.00"),
            }
        ],
    )

    result = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction_id,
            payload=payload,
            target_currency=None,
            item_language=None,
            app_language=None,
            session=session,
            current_user=current_user,
        )
    )

    assert session.deleted == [removed_item]
    assert kept_item.description == "Kept item updated"
    assert session.committed is True
    assert result == [kept_item]


def test_update_transaction_accepts_transaction_and_item_category_scopes(monkeypatch) -> None:
    """Receipt edit saves should validate transaction and item categories by their own scopes."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction_id = uuid.uuid4()
    transaction_category_id = uuid.uuid4()
    item_category_id = uuid.uuid4()
    existing_item_id = uuid.uuid4()

    transaction = Transaction(
        id=transaction_id,
        user_id=current_user.id,
        amount_total=Decimal("9.99"),
        currency="EUR",
        merchant_name="LIDL SRBIJA",
        source=TransactionSource.RECEIPT,
        status="DRAFT",
    )
    existing_item = TransactionItem(
        id=existing_item_id,
        transaction_id=transaction_id,
        line_no=1,
        description="Lovorov list",
        amount=Decimal("1.00"),
        category_id=item_category_id,
    )
    session = _Session(
        exec_results=[
            [transaction],
            [transaction_category_id],
            [item_category_id],
            [existing_item],
        ]
    )

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: {
            "category_id": kwargs["transaction"].category_id,
            "item_category_ids": [item.category_id for item in kwargs["items"]],
        },
    )

    result = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction_id,
            payload=TransactionUpdateRequest(
                amount_total=Decimal("10.00"),
                category_id=transaction_category_id,
                items=[
                    {
                        "id": existing_item_id,
                        "description": "Lovorov list",
                        "amount": Decimal("1.00"),
                        "category_id": item_category_id,
                    }
                ],
            ),
            target_currency=None,
            item_language=None,
            app_language=None,
            session=session,
            current_user=current_user,
        )
    )

    assert session.committed is True
    assert transaction.category_id == transaction_category_id
    assert existing_item.category_id == item_category_id
    assert result["category_id"] == transaction_category_id
    assert result["item_category_ids"] == [item_category_id]


def test_update_transaction_rejects_invalid_transaction_category_scope(monkeypatch) -> None:
    """Receipt edit saves should fail fast when the transaction category is not visible."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction = Transaction(
        id=uuid.uuid4(),
        user_id=current_user.id,
        amount_total=Decimal("9.99"),
        currency="EUR",
        merchant_name="Corner Market",
        source=TransactionSource.RECEIPT,
        status="DRAFT",
    )
    session = _Session(exec_results=[[transaction], []])

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            _unwrap(router.update_transaction)(
                request=_request(),
                transaction_id=transaction.id,
                payload=TransactionUpdateRequest(
                    amount_total=Decimal("10.00"),
                    category_id=uuid.uuid4(),
                ),
                target_currency=None,
                item_language=None,
                app_language=None,
                session=session,
                current_user=current_user,
            )
        )

    assert exc_info.value.status_code == 400
    assert "invalid or not active" in str(exc_info.value.detail)


def test_update_transaction_rejects_invalid_item_category_scope(monkeypatch) -> None:
    """Receipt edit saves should fail fast when an item category is not visible."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction = Transaction(
        id=uuid.uuid4(),
        user_id=current_user.id,
        amount_total=Decimal("9.99"),
        currency="EUR",
        merchant_name="Corner Market",
        source=TransactionSource.RECEIPT,
        status="DRAFT",
    )
    existing_item_id = uuid.uuid4()
    session = _Session(exec_results=[[transaction], []])

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            _unwrap(router.update_transaction)(
                request=_request(),
                transaction_id=transaction.id,
                payload=TransactionUpdateRequest(
                    amount_total=Decimal("10.00"),
                    items=[
                        {
                            "id": existing_item_id,
                            "description": "Line item",
                            "amount": Decimal("1.00"),
                            "category_id": uuid.uuid4(),
                        }
                    ],
                ),
                target_currency=None,
                item_language=None,
                app_language=None,
                session=session,
                current_user=current_user,
            )
        )

    assert exc_info.value.status_code == 400
    assert "invalid or not active" in str(exc_info.value.detail)


def test_update_transaction_clears_legacy_household_attribution(monkeypatch) -> None:
    """Saving a legacy shared row should clear household attribution in launch mode."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction = Transaction(
        id=uuid.uuid4(),
        user_id=current_user.id,
        household_id=uuid.uuid4(),
        amount_total=Decimal("10.00"),
        currency="EUR",
        merchant_name="Legacy shared receipt",
        source=TransactionSource.MANUAL,
        status="DRAFT",
    )
    session = _Session(exec_results=[[transaction], []])

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: kwargs["transaction"],
    )

    result = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction.id,
            payload=TransactionUpdateRequest(
                amount_total=Decimal("12.00"),
                household_id=uuid.uuid4(),
            ),
            target_currency=None,
            item_language=None,
            app_language=None,
            session=session,
            current_user=current_user,
        )
    )

    assert session.committed is True
    assert transaction.amount_total == Decimal("12.00")
    assert transaction.household_id is None
    assert result is transaction


def test_update_transaction_duplicate_submissions_stay_stable_and_keep_labels(monkeypatch) -> None:
    """Repeated save submissions should update the same item without dropping labels."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction_id = uuid.uuid4()
    item_id = uuid.uuid4()
    label_id = uuid.uuid4()
    transaction = Transaction(
        id=transaction_id,
        user_id=current_user.id,
        amount_total=Decimal("9.99"),
        currency="EUR",
        merchant_name="Corner Market",
        source=TransactionSource.RECEIPT,
        status="DRAFT",
    )
    item = TransactionItem(
        id=item_id,
        transaction_id=transaction_id,
        line_no=1,
        description="Line item",
        amount=Decimal("9.99"),
    )

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: {
            "labels": [{"id": label_id}],
            "item_ids": [entry.id for entry in kwargs["items"]],
            "merchant_name": kwargs["transaction"].merchant_name,
        },
    )

    payload = TransactionUpdateRequest(
        amount_total=Decimal("9.99"),
        merchant_name="Corner Market Updated",
        items=[
            {
                "id": item_id,
                "description": "Line item updated",
                "amount": Decimal("9.99"),
            }
        ],
    )

    session_one = _Session(exec_results=[[transaction], [item]])
    result_one = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction_id,
            payload=payload,
            target_currency=None,
            item_language=None,
            app_language=None,
            session=session_one,
            current_user=current_user,
        )
    )

    session_two = _Session(exec_results=[[transaction], [item]])
    result_two = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction_id,
            payload=payload,
            target_currency=None,
            item_language=None,
            app_language=None,
            session=session_two,
            current_user=current_user,
        )
    )

    assert session_one.committed is True
    assert session_two.committed is True
    assert [obj for obj in session_one.added if isinstance(obj, TransactionItem)] == [item]
    assert [obj for obj in session_two.added if isinstance(obj, TransactionItem)] == [item]
    assert session_one.deleted == []
    assert session_two.deleted == []
    assert result_one["labels"] == [{"id": label_id}]
    assert result_two["labels"] == [{"id": label_id}]
    assert result_two["item_ids"] == [item_id]
    assert item.description == "Line item updated"


def test_confirmed_receipt_update_clears_extraction_warnings(monkeypatch) -> None:
    """A user save should accept edited receipt data and clear stale extraction warnings."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction_id = uuid.uuid4()
    receipt_id = uuid.uuid4()
    item_id = uuid.uuid4()
    transaction = Transaction(
        id=transaction_id,
        user_id=current_user.id,
        receipt_id=receipt_id,
        amount_total=Decimal("9.99"),
        currency="EUR",
        merchant_name="Corner Market",
        source=TransactionSource.RECEIPT,
        status="DRAFT",
    )
    extraction = ReceiptExtraction(
        receipt_id=receipt_id,
        provider="test",
        model_name="test-model",
        structured_json={
            "warnings": [
                {
                    "code": "total_mismatch",
                    "message": "Receipt total differs from item sum.",
                }
            ]
        },
    )
    item = TransactionItem(
        id=item_id,
        transaction_id=transaction_id,
        line_no=1,
        description="Line item",
        amount=Decimal("9.99"),
    )

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: kwargs["transaction"],
    )

    session = _Session(exec_results=[[transaction], [extraction], [item]])
    result = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction_id,
            payload=TransactionUpdateRequest(
                status="CONFIRMED",
                amount_total=Decimal("9.99"),
            ),
            target_currency=None,
            item_language=None,
            app_language=None,
            session=session,
            current_user=current_user,
        )
    )

    assert result is transaction
    assert transaction.status == "CONFIRMED"
    assert extraction.structured_json["warnings"] == []
    assert extraction in session.added


def test_update_transaction_last_write_wins_without_revision_guard(monkeypatch) -> None:
    """Sequential saves currently overwrite each other because launch mode has no revision token."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    transaction = Transaction(
        id=uuid.uuid4(),
        user_id=current_user.id,
        amount_total=Decimal("9.99"),
        currency="EUR",
        merchant_name="Original",
        source=TransactionSource.RECEIPT,
        status="DRAFT",
    )

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_build_transaction_read",
        lambda **kwargs: kwargs["transaction"],
    )

    first_session = _Session(exec_results=[[transaction], []])
    first_result = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction.id,
            payload=TransactionUpdateRequest(
                amount_total=Decimal("10.00"),
                merchant_name="First Save",
            ),
            target_currency=None,
            item_language=None,
            app_language=None,
            session=first_session,
            current_user=current_user,
        )
    )
    assert first_result.merchant_name == "First Save"
    assert transaction.merchant_name == "First Save"
    assert transaction.amount_total == Decimal("10.00")

    second_session = _Session(exec_results=[[transaction], []])
    second_result = asyncio.run(
        _unwrap(router.update_transaction)(
            request=_request(),
            transaction_id=transaction.id,
            payload=TransactionUpdateRequest(
                amount_total=Decimal("11.00"),
                merchant_name="Second Save",
            ),
            target_currency=None,
            item_language=None,
            app_language=None,
            session=second_session,
            current_user=current_user,
        )
    )

    assert second_result.merchant_name == "Second Save"
    assert transaction.merchant_name == "Second Save"
    assert transaction.amount_total == Decimal("11.00")


def test_collect_disable_target_ids_includes_descendants_and_transaction_match() -> None:
    """Disabling a top-level built-in item category should also disable descendants and matching tx code."""

    top_level = Category(
        id=uuid.uuid4(),
        scope=CategoryScope.ITEM,
        code="FOOD",
        name="Food",
        user_id=None,
        is_custom=False,
    )
    child = Category(
        id=uuid.uuid4(),
        scope=CategoryScope.ITEM,
        code="GROCERIES",
        name="Groceries",
        parent_id=top_level.id,
        user_id=None,
        is_custom=False,
    )
    grandchild = Category(
        id=uuid.uuid4(),
        scope=CategoryScope.ITEM,
        code="ORGANIC",
        name="Organic",
        parent_id=child.id,
        user_id=None,
        is_custom=False,
    )
    matching_transaction = Category(
        id=uuid.uuid4(),
        scope=CategoryScope.TRANSACTION,
        code="FOOD",
        name="Food",
        user_id=None,
        is_custom=False,
    )
    session = _Session(
        exec_results=[
            [
                (top_level.id, None),
                (child.id, top_level.id),
                (grandchild.id, child.id),
            ],
            [matching_transaction.id],
        ]
    )

    target_ids = collect_disable_target_ids(session, top_level)

    assert target_ids == {
        top_level.id,
        child.id,
        grandchild.id,
        matching_transaction.id,
    }


def test_attribution_snapshot_uses_receipt_owner_for_legacy_created_by(monkeypatch) -> None:
    """Legacy receipt-backed rows should resolve created_by from the receipt uploader."""

    from app.services.transactions import read_models as router

    receipt_owner_id = uuid.uuid4()
    transaction_user_id = uuid.uuid4()
    session = _Session(exec_results=[[receipt_owner_id]])
    snippet_lookup = {
        receipt_owner_id: TransactionUserSnippetRead(
            user_id=receipt_owner_id,
            display_name="Uploader",
            email="uploader@example.com",
        ),
        transaction_user_id: TransactionUserSnippetRead(
            user_id=transaction_user_id,
            display_name="Owner",
            email="owner@example.com",
        ),
    }

    monkeypatch.setattr(
        router,
        "_load_transaction_user_snippets",
        lambda *_args, **_kwargs: snippet_lookup,
    )

    read = TransactionRead(
        id=uuid.uuid4(),
        created_at=dt.datetime.now(dt.UTC),
        updated_at=dt.datetime.now(dt.UTC),
        user_id=transaction_user_id,
        receipt_id=uuid.uuid4(),
        occurred_at=None,
        amount_total=Decimal("10.00"),
        currency="EUR",
        merchant_id=None,
        merchant_name="Legacy receipt",
        category_id=None,
        source=TransactionSource.RECEIPT,
        status="DRAFT",
        household_id=None,
        created_by_user_id=None,
        owner_user_id=None,
    )

    router._enrich_transaction_attribution_snapshot(session, read=read)

    assert read.created_by_user_id == receipt_owner_id
    assert read.owner_user_id == transaction_user_id
    assert read.created_by_user == snippet_lookup[receipt_owner_id]
    assert read.owner_user == snippet_lookup[transaction_user_id]


def test_get_receipt_view_url_returns_presigned_payload(monkeypatch) -> None:
    """Receipt photo viewing should return a presigned GET URL for the owner's receipt."""

    from app.api.routers import receipts as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    receipt = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        storage_key="receipts/test.png",
        storage_bucket="receipts",
        mime_type="image/png",
        original_filename="test.png",
    )

    monkeypatch.setattr(
        router,
        "generate_presigned_get",
        lambda **kwargs: "https://cdn.example.test/receipts/test.png",
    )

    response = asyncio.run(
        _unwrap(router.get_receipt_view_url)(
            receipt_id=receipt.id,
            request=_request(),
            session=_Session(exec_results=[[receipt]]),
            current_user=current_user,
        )
    )

    assert response.receipt_id == receipt.id
    assert response.view_url == "https://cdn.example.test/receipts/test.png"
    assert response.mime_type == "image/png"
    assert response.original_filename == "test.png"


def test_delete_transaction_removes_manual_transaction_children() -> None:
    """Manual deletion should remove label links and items, then commit the delete."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    transaction = SimpleNamespace(id=uuid.uuid4(), user_id=current_user.id, receipt_id=None)
    label_link = SimpleNamespace(transaction_id=transaction.id)
    item_one = SimpleNamespace(transaction_id=transaction.id)
    item_two = SimpleNamespace(transaction_id=transaction.id)
    session = _Session(
        exec_results=[
            [transaction],
            [label_link],
            [item_one, item_two],
        ]
    )
    monkeypatch = pytest.MonkeyPatch()

    try:
        result = asyncio.run(
            _unwrap(router.delete_transaction)(
                request=_request(),
                transaction_id=transaction.id,
                session=session,
                current_user=current_user,
            )
        )
    finally:
        monkeypatch.undo()

    assert session.committed is True
    assert session.flush_calls == 2
    assert result is None
    assert session.deleted == [label_link, item_one, item_two, transaction]


def test_transaction_visibility_predicates_ignore_household_state_in_launch_mode() -> None:
    """Launch visibility should key off owner id only, not household membership."""

    from app.services.transactions import read_models as router

    current_user = SimpleNamespace(id=uuid.uuid4())

    read_predicate = router._build_transaction_read_visibility_predicate(_Session(), current_user)
    write_predicate = router._build_transaction_write_visibility_predicate(_Session(), current_user)

    assert "user_id" in str(read_predicate)
    assert "household_id" not in str(read_predicate)
    assert "user_id" in str(write_predicate)
    assert "household_id" not in str(write_predicate)


def test_delete_transaction_allows_owner_for_legacy_household_tagged_transaction() -> None:
    """Owners should still be able to delete their own legacy household-tagged rows."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    transaction = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        household_id=uuid.uuid4(),
        receipt_id=None,
    )
    label_link = SimpleNamespace(transaction_id=transaction.id)
    item = SimpleNamespace(transaction_id=transaction.id)
    session = _Session(
        exec_results=[
            [transaction],
            [label_link],
            [item],
        ]
    )
    result = asyncio.run(
        _unwrap(router.delete_transaction)(
            request=_request(),
            transaction_id=transaction.id,
            session=session,
            current_user=current_user,
        )
    )

    assert session.committed is True
    assert session.flush_calls == 2
    assert result is None
    assert session.deleted == [label_link, item, transaction]


def test_delete_transaction_rejects_receipt_backed_transaction() -> None:
    """Receipt-backed transactions should still be deleted via the receipt endpoint."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    transaction = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        household_id=None,
        receipt_id=uuid.uuid4(),
    )
    session = _Session(exec_results=[[transaction]])
    monkeypatch = pytest.MonkeyPatch()

    try:
        with pytest.raises(HTTPException) as exc_info:
            asyncio.run(
                _unwrap(router.delete_transaction)(
                    request=_request(),
                    transaction_id=transaction.id,
                    session=session,
                    current_user=current_user,
                )
            )
    finally:
        monkeypatch.undo()

    assert exc_info.value.status_code == 409
    assert session.committed is False
    assert session.deleted == []


def test_delete_transaction_item_recalculates_total_from_remaining_items(monkeypatch) -> None:
    """Deleting a line item should recalculate the total from the remaining items."""

    from app.api.routers import transactions_crud as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    transaction = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        amount_total=Decimal("24.36"),
    )
    item = SimpleNamespace(id=uuid.uuid4(), transaction_id=transaction.id)
    session = _Session(exec_results=[[transaction], [item], [Decimal("17.00")]])


    asyncio.run(
        _unwrap(router.delete_transaction_item)(
            request=_request(),
            transaction_id=transaction.id,
            item_id=item.id,
            session=session,
            current_user=current_user,
        )
    )

    assert session.committed is True
    assert transaction.amount_total == Decimal("17.00")
