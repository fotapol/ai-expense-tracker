"""Real database regressions for matching, user decisions and safe removal."""

import asyncio
import datetime as dt
import hashlib
import uuid
from decimal import Decimal

import pytest
from fastapi import HTTPException
from sqlalchemy import event
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.compiler import compiles
from sqlmodel import Session, SQLModel, create_engine, select
from starlette.requests import Request

from app.api.routers import duplicates as router
from app.models import (
    Category,
    CategoryScope,
    Receipt,
    ReceiptExtraction,
    ReceiptStatus,
    Transaction,
    TransactionItem,
    TransactionSource,
    User,
)
from app.models.transactions.duplicate_dismissal import DuplicateDismissal
from app.schemas.duplicates import DuplicatePairRequest, DuplicateResolveRequest
from app.services.duplicates import find_duplicates

DAY = dt.datetime(2026, 4, 10, 12, tzinfo=dt.UTC)


@compiles(JSONB, "sqlite")
def _sqlite_json(_type, _compiler, **_kwargs):
    return "JSON"


@pytest.fixture
def db():
    engine = create_engine("sqlite://")

    @event.listens_for(engine, "connect")
    def foreign_keys(connection, _record):
        connection.execute("PRAGMA foreign_keys=ON")

    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        owner = User(auth_subject="duplicates-owner")
        other = User(auth_subject="duplicates-other")
        category = Category(code="UNCATEGORIZED", name="Uncategorized", scope=CategoryScope.ITEM)
        session.add_all([owner, other, category])
        session.commit()
        session.info.update(owner=owner, other=other, category=category, engine=engine)
        yield session
    engine.dispose()


def add(
    db,
    number,
    *,
    merchant="Market",
    amount="12.00",
    currency="EUR",
    day=DAY,
    source=TransactionSource.MANUAL,
    photo=False,
    sha=None,
    verified=False,
    owner=None,
):
    owner = owner or db.info["owner"]
    receipt = None
    if photo:
        receipt = Receipt(
            user_id=owner.id,
            status=ReceiptStatus.COMPLETED,
            storage_bucket="test",
            storage_key=f"receipt-{number}",
            original_filename="receipt.jpg",
            mime_type="image/jpeg",
            sha256=sha or "",
            sha256_verified=verified,
            size_bytes=10,
        )
        db.add(receipt)
        db.flush()
        source = TransactionSource.RECEIPT
    tx = Transaction(
        id=uuid.UUID(int=number),
        user_id=owner.id,
        merchant_name=merchant,
        amount_total=Decimal(amount) if amount is not None else None,
        currency=currency,
        occurred_at=day,
        receipt_id=receipt.id if receipt else None,
        status="CONFIRMED",
        source=source,
    )
    db.add(tx)
    db.flush()
    return tx


def lines(db, tx, descriptions):
    for index, description in enumerate(descriptions, 1):
        db.add(
            TransactionItem(
                transaction_id=tx.id,
                line_no=index,
                description=description,
                amount=Decimal("6"),
                qty=Decimal("1"),
                category_id=db.info["category"].id,
            )
        )
    db.flush()


def find(db, **kwargs):
    db.commit()
    return find_duplicates(db, user_id=db.info["owner"].id, **kwargs)


def call(endpoint, db, payload, **kwargs):
    while hasattr(endpoint, "__wrapped__"):
        endpoint = endpoint.__wrapped__
    request = Request(
        {"type": "http", "method": "POST", "path": "/", "headers": [], "client": ("127.0.0.1", 1)}
    )
    return asyncio.run(
        endpoint(
            request=request, payload=payload, session=db, current_user=db.info["owner"], **kwargs
        )
    )


def resolution(first, second):
    return DuplicateResolveRequest(
        keep_transaction_id=first.id,
        discard_transaction_id=second.id,
        keep_updated_at=first.updated_at,
        discard_updated_at=second.updated_at,
    )


def test_different_photos_match_original_details_and_item_multisets(db):
    first = add(db, 1, merchant="\uff2d\uff21\uff32\uff2b\uff25\uff34!", photo=True)
    second = add(db, 2, merchant="market", photo=True)
    lines(db, first, ["Milk", "Milk"])
    lines(db, second, ["milk", "Bread"])
    pair = find(db).items[0]
    assert pair.matching_item_count == 1  # A repeated line cannot match the same product twice.
    assert pair.confidence == "possible"
    assert "matching_items" in pair.reasons
    db.exec(select(TransactionItem).where(TransactionItem.transaction_id == second.id)).all()[
        1
    ].description = "MILK"
    pair = find(db).items[0]
    assert pair.matching_item_count == 2
    assert pair.confidence == "high"


def test_legitimate_different_baskets_or_currencies_do_not_match(db):
    first = add(db, 1, photo=True)
    second = add(db, 2, photo=True)
    lines(db, first, ["Milk", "Bread"])
    lines(db, second, ["Soap", "Shampoo"])
    add(db, 3, currency="USD")
    add(db, 4, amount="12.01")
    add(db, 5, day=DAY + dt.timedelta(days=2))
    assert find(db).items == []


def test_adjacent_days_need_strong_item_evidence(db):
    first = add(db, 1)
    second = add(db, 2, day=DAY + dt.timedelta(days=1))
    assert find(db).items == []
    lines(db, first, ["Milk", "Bread"])
    lines(db, second, ["Milk", "Bread"])
    pair = find(db).items[0]
    assert pair.confidence == "high"
    assert "nearby_dates" in pair.reasons


def test_only_server_verified_hashes_match_missing_or_edited_metadata(db):
    sha = "a" * 64
    first = add(db, 1, merchant=None, amount=None, day=None, photo=True, sha=sha, verified=True)
    second = add(db, 2, merchant="Changed", amount="99", photo=True, sha=sha)
    assert find(db).items == []  # Client-supplied and legacy hashes are untrusted.
    receipt = db.get(Receipt, second.receipt_id)
    receipt.sha256_verified = True
    pair = find(db).items[0]
    assert pair.confidence == "exact" and pair.reasons == ["same_image"]
    assert {pair.first.id, pair.second.id} == {first.id, second.id}


def test_complete_history_is_matched_before_paging_and_users_are_isolated(db):
    for number in range(1, 65):
        add(db, number, amount=str(number), merchant="Other shop")
    add(db, 100, amount="999")
    add(db, 101, amount="999")
    add(db, 102, amount="999", owner=db.info["other"])
    add(db, 103, amount="777")
    add(db, 104, amount="777")
    first, second = find(db, page_size=1), find(db, page_size=1, page=2)
    assert len(first.items) == len(second.items) == 1
    assert first.has_more and not second.has_more
    assert first.items[0].first.id != second.items[0].first.id
    assert find(db, transaction_id=uuid.UUID(int=100)).items[0].second.id.int == 101
    with pytest.raises(HTTPException) as error:
        find(db, transaction_id=uuid.UUID(int=102))
    assert error.value.status_code == 404


def test_keep_both_is_symmetric_idempotent_and_does_not_change_totals(db):
    first, second = add(db, 1), add(db, 2)
    db.commit()
    for one, two in [(first, second), (second, first)]:
        call(
            router.dismiss_duplicates,
            db,
            DuplicatePairRequest(first_transaction_id=one.id, second_transaction_id=two.id),
        )
    assert find(db).items == []
    assert len(db.exec(select(DuplicateDismissal)).all()) == 1
    assert len(db.exec(select(Transaction)).all()) == 2
    assert sum(row.amount_total for row in db.exec(select(Transaction)).all()) == Decimal("24")


def test_cross_user_dismiss_and_resolution_are_rejected(db):
    first = add(db, 1)
    second = add(db, 2, owner=db.info["other"])
    db.commit()
    for endpoint, payload in [
        (
            router.dismiss_duplicates,
            DuplicatePairRequest(first_transaction_id=first.id, second_transaction_id=second.id),
        ),
        (router.resolve_duplicates, resolution(first, second)),
    ]:
        with pytest.raises(HTTPException) as error:
            call(endpoint, db, payload)
        assert error.value.status_code == 404
    assert len(db.exec(select(Transaction)).all()) == 2


def test_keep_selected_removes_only_discarded_receipt_and_items(db, monkeypatch):
    first, second = add(db, 1, photo=True), add(db, 2, photo=True)
    lines(db, second, ["Milk"])
    db.add(
        ReceiptExtraction(
            receipt_id=second.receipt_id, provider="test", model_name="test", structured_json={}
        )
    )
    db.commit()
    discarded_receipt_id = second.receipt_id
    removed = []
    monkeypatch.setattr(router, "delete_object", lambda key, **_kwargs: removed.append(key))
    result = call(router.resolve_duplicates, db, resolution(first, second))
    assert result.kept_transaction_id == first.id
    assert db.get(Transaction, first.id) is not None
    assert db.get(Transaction, second.id) is None
    assert db.get(Receipt, discarded_receipt_id) is None
    assert db.get(Receipt, first.receipt_id) is not None
    assert db.exec(select(TransactionItem)).all() == []
    assert removed == ["receipt-2"]


def test_stale_or_dismissed_pair_never_deletes_anything(db, monkeypatch):
    first, second = add(db, 1, photo=True), add(db, 2, photo=True)
    db.commit()
    payload = resolution(first, second)
    second.updated_at += dt.timedelta(seconds=1)
    db.commit()
    monkeypatch.setattr(
        router,
        "delete_object",
        lambda *_args, **_kwargs: pytest.fail("Must not delete a stale receipt"),
    )
    with pytest.raises(HTTPException) as error:
        call(router.resolve_duplicates, db, payload)
    assert error.value.status_code == 409
    payload = resolution(first, second)
    call(
        router.dismiss_duplicates,
        db,
        DuplicatePairRequest(first_transaction_id=first.id, second_transaction_id=second.id),
    )
    with pytest.raises(HTTPException) as error:
        call(router.resolve_duplicates, db, payload)
    assert error.value.status_code == 409
    assert len(db.exec(select(Transaction)).all()) == 2


def test_storage_failure_preserves_database_records(db, monkeypatch):
    first, second = add(db, 1), add(db, 2, photo=True)
    db.commit()

    def fail(*_args, **_kwargs):
        raise OSError("storage unavailable")

    monkeypatch.setattr(router, "delete_object", fail)
    with pytest.raises(HTTPException) as error:
        call(router.resolve_duplicates, db, resolution(first, second))
    assert error.value.status_code == 503
    assert db.get(Transaction, second.id) is not None
    assert db.get(Receipt, second.receipt_id) is not None


def test_manual_resolution_does_not_contact_receipt_storage(db, monkeypatch):
    first, second = add(db, 1), add(db, 2)
    db.commit()
    monkeypatch.setattr(
        router, "delete_object", lambda *_args, **_kwargs: pytest.fail("No receipt exists")
    )
    call(router.resolve_duplicates, db, resolution(first, second))
    assert db.get(Transaction, second.id) is None


@pytest.mark.parametrize("edit", ["item", "label"])
def test_child_edits_invalidate_a_previously_loaded_comparison(db, monkeypatch, edit):
    from app.api.routers import labels, transactions_crud
    from app.models.labels.label import Label
    from app.schemas.labels import LabelAssignRequest
    from app.schemas.transactions import TransactionItemUpdate, TransactionUpdateRequest

    first, second = add(db, 1), add(db, 2)
    lines(db, second, ["Milk"])
    db.commit()
    stale = resolution(first, second)
    if edit == "item":
        item = db.exec(
            select(TransactionItem).where(TransactionItem.transaction_id == second.id)
        ).first()
        call(
            transactions_crud.update_transaction,
            db,
            TransactionUpdateRequest(
                items=[TransactionItemUpdate(id=item.id, description="Whole milk")],
            ),
            transaction_id=second.id,
        )
    else:
        label = Label(user_id=db.info["owner"].id, name="Work")
        db.add(label)
        db.commit()
        call(
            labels.assign_label, db, LabelAssignRequest(transaction_id=second.id, label_id=label.id)
        )
    assert second.updated_at != stale.discard_updated_at
    with pytest.raises(HTTPException) as error:
        call(router.resolve_duplicates, db, stale)
    assert error.value.status_code == 409
    assert db.get(Transaction, second.id) is not None


def test_worker_overwrites_forged_hash_with_downloaded_bytes(db, monkeypatch):
    from app.worker import receipt_processor as worker

    user, category = db.info["owner"], db.info["category"]
    receipt = Receipt(
        user_id=user.id,
        status=ReceiptStatus.UPLOADED,
        storage_bucket="test",
        storage_key="test",
        original_filename="test.jpg",
        mime_type="image/jpeg",
        sha256="f" * 64,
        size_bytes=10,
    )
    db.add(receipt)
    db.commit()
    monkeypatch.setattr(worker, "engine", db.info["engine"])
    monkeypatch.setattr(worker, "download_object", lambda **_kwargs: b"actual receipt bytes")
    monkeypatch.setenv("ITEM_NORMALIZATION_ENABLED", "false")
    monkeypatch.setattr(
        worker,
        "_call_vision_llm",
        lambda **_kwargs: {
            "raw_json": {
                "merchant_name": "Market",
                "amount_total": "6",
                "currency": "EUR",
                "items": [
                    {"description": "Milk", "amount": "6", "category_code": category.code},
                ],
            },
            "provider": "test",
            "model_name": "test",
            "latency_ms": 1,
        },
    )
    worker.process_receipt(str(receipt.id))
    db.refresh(receipt)
    assert receipt.status == ReceiptStatus.COMPLETED
    assert receipt.sha256_verified
    assert receipt.sha256 == hashlib.sha256(b"actual receipt bytes").hexdigest()


def test_duplicate_migration_defaults_old_hashes_to_unverified():
    import importlib
    import io

    from alembic.migration import MigrationContext
    from alembic.operations import Operations

    output = io.StringIO()
    context = MigrationContext.configure(
        dialect_name="postgresql", opts={"as_sql": True, "output_buffer": output}
    )
    migration = importlib.import_module("app.alembic.versions.a6c8e2f4b9d1_add_duplicate_review")
    with Operations.context(context):
        migration.upgrade()
    sql = output.getvalue()
    assert "sha256_verified BOOLEAN DEFAULT false NOT NULL" in sql
    assert "CREATE TABLE duplicate_dismissals" in sql
    assert sql.count("ON DELETE CASCADE") == 3
