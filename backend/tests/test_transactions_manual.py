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

from app.models.shared.enums import CategoryScope, HouseholdMemberRole, TransactionSource
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


def test_create_transaction_defaults_to_shared_household_without_synthesized_item(
    monkeypatch,
) -> None:
    """Blank manual creation should stay item-less and inherit active household sharing."""

    from app.api.routers import transactions as router

    session = _Session()
    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )
    item_category_id = uuid.uuid4()
    tx_category_id = uuid.uuid4()
    household_id = uuid.uuid4()

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: household_id,
    )
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
    assert created_transaction.household_id == household_id
    assert created_transaction.category_id == tx_category_id
    assert created_transaction.created_by_user_id == current_user.id
    assert created_transaction.owner_user_id == current_user.id
    assert created_items == []
    assert result["item_count"] == 0


def test_get_transactions_summary_blocks_subcategory_mode_without_feature(monkeypatch) -> None:
    """Subcategory summary mode should require the advanced analytics entitlement."""

    from app.api.routers import transactions as router

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


def test_create_transaction_without_active_household_stays_solo(monkeypatch) -> None:
    """Manual creation without shared household access should remain a solo transaction."""

    from app.api.routers import transactions as router

    session = _Session()
    current_user = SimpleNamespace(
        id=uuid.uuid4(),
        default_currency="EUR",
        items_language=None,
    )

    monkeypatch.setattr(router, "validate_transaction_attribution", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: None,
    )
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

    from app.api.routers import transactions as router

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
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: None,
    )
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

    from app.api.routers import transactions as router

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

    from app.api.routers import transactions as router

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

    from app.api.routers import transactions as router

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
    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: None,
    )

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


def test_delete_transaction_allows_household_owner_for_shared_manual_transaction() -> None:
    """Household owners should be able to delete member-created shared manual transactions."""

    from app.api.routers import transactions as router

    owner_user = SimpleNamespace(id=uuid.uuid4())
    member_user_id = uuid.uuid4()
    household_id = uuid.uuid4()
    transaction = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=member_user_id,
        household_id=household_id,
        receipt_id=None,
    )
    owner_member = SimpleNamespace(role=HouseholdMemberRole.OWNER)
    label_link = SimpleNamespace(transaction_id=transaction.id)
    item = SimpleNamespace(transaction_id=transaction.id)
    session = _Session(
        exec_results=[
            [transaction],
            [owner_member],
            [label_link],
            [item],
        ]
    )
    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: household_id,
    )

    try:
        result = asyncio.run(
            _unwrap(router.delete_transaction)(
                request=_request(),
                transaction_id=transaction.id,
                session=session,
                current_user=owner_user,
            )
        )
    finally:
        monkeypatch.undo()

    assert session.committed is True
    assert session.flush_calls == 2
    assert result is None
    assert session.deleted == [label_link, item, transaction]


def test_delete_transaction_denies_non_owner_member_for_shared_manual_transaction() -> None:
    """Shared manual delete should be denied for members who are not the creator."""

    from app.api.routers import transactions as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    transaction = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=uuid.uuid4(),
        household_id=uuid.uuid4(),
        receipt_id=None,
    )
    member = SimpleNamespace(role=HouseholdMemberRole.MEMBER)
    session = _Session(exec_results=[[transaction], [member]])
    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: transaction.household_id,
    )

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

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Only the creator or household owner can delete this transaction."
    assert session.committed is False
    assert session.deleted == []


def test_delete_transaction_rejects_receipt_backed_transaction() -> None:
    """Receipt-backed transactions should still be deleted via the receipt endpoint."""

    from app.api.routers import transactions as router

    current_user = SimpleNamespace(id=uuid.uuid4())
    transaction = SimpleNamespace(
        id=uuid.uuid4(),
        user_id=current_user.id,
        household_id=None,
        receipt_id=uuid.uuid4(),
    )
    session = _Session(exec_results=[[transaction]])
    monkeypatch = pytest.MonkeyPatch()
    monkeypatch.setattr(
        router,
        "_resolve_active_shared_household_id",
        lambda *_args, **_kwargs: None,
    )

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

    from app.api.routers import transactions as router

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
