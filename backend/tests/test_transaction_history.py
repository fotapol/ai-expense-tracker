"""Receipt history must order and filter the full scope before taking a page."""

import datetime as dt
import json
import uuid
from decimal import Decimal
from types import SimpleNamespace

import pytest
from pydantic import ValidationError
from sqlalchemy import JSON, Column, MetaData, Table, Uuid, event, insert
from sqlmodel import Session, create_engine, select

from app.models.transactions.transaction import Transaction
from app.schemas.transactions import TransactionListFilter
from app.services.fx_rates import FxRateLookup
from app.services.transactions import listing
from app.services.transactions.read_models import _build_filtered_transaction_ids_query

OWNER = uuid.UUID(int=10000)
DAY = dt.datetime(2026, 1, 10, 12, tzinfo=dt.UTC)


@pytest.fixture
def session():
    engine = create_engine("sqlite://")

    @event.listens_for(engine, "connect")
    def json_functions(connection, _record):
        # Exercise the PostgreSQL JSONB review predicate against real rows locally.
        connection.create_function(
            "jsonb_typeof",
            1,
            lambda value: "array" if isinstance(json.loads(value or "null"), list) else "other",
        )
        connection.create_function(
            "jsonb_array_length",
            1,
            lambda value: len(json.loads(value)),
        )

    Transaction.__table__.create(engine)
    extractions = Table(
        "receipt_extractions",
        MetaData(),
        Column("id", Uuid, primary_key=True),
        Column("receipt_id", Uuid),
        Column("structured_json", JSON),
    )
    extractions.create(engine)
    with Session(engine) as value:
        value.info["extractions"] = extractions
        yield value
    engine.dispose()


def add(session, number, *, currency="EUR", amount="20", merchant="Shop", **fields):
    transaction = Transaction(
        id=uuid.UUID(int=number),
        user_id=OWNER,
        occurred_at=DAY,
        amount_total=Decimal(amount) if amount is not None else None,
        currency=currency,
        merchant_name=merchant,
        status="CONFIRMED",
        **fields,
    )
    session.add(transaction)
    return transaction


def page(session, **kwargs):
    filters = TransactionListFilter(**kwargs)
    ids = _build_filtered_transaction_ids_query(
        session=session,
        current_user=SimpleNamespace(id=OWNER),
        filters=filters,
    )
    return listing.list_transaction_page(
        session=session,
        query=select(Transaction).where(Transaction.id.in_(ids)),
        filters=filters,
        target_currency="EUR",
    )


def test_history_beyond_50_rows_has_stable_pages_and_user_scope(session):
    for number in range(1, 126):
        add(session, number)
    session.add(Transaction(user_id=uuid.uuid4(), occurred_at=DAY, amount_total=9999))
    session.commit()

    pages = [page(session, page=number) for number in range(1, 4)]
    assert [len(rows) for rows in pages] == [50, 50, 25]
    assert [row.id.int for rows in pages for row in rows] == list(range(125, 0, -1))
    assert page(session, page=4) == []


def test_oldest_and_merchant_sorts_apply_before_pagination(session):
    for number, merchant in enumerate(["zulu", " Alpha ", "alpha", "Beta", None, ""], 1):
        add(session, number, merchant=merchant)
    older = add(session, 7)
    older.occurred_at = None
    older.created_at = DAY - dt.timedelta(days=30)
    session.commit()

    assert page(session, sort_by="oldest", page_size=1)[0].id.int == 7
    assert [row.id.int for row in page(session, sort_by="merchant_asc", page_size=3)] == [2, 3, 4]
    assert [row.id.int for row in page(session, sort_by="merchant_asc", page_size=3, page=3)] == [6]


@pytest.mark.parametrize("sort_by,first_page", [("amount_desc", [3, 4]), ("amount_asc", [2, 1])])
def test_amount_sort_uses_display_currency_and_leaves_unknown_rates_last(
    session,
    monkeypatch,
    sort_by,
    first_page,
):
    add(session, 1, amount="20")
    add(session, 2, amount="1000", currency="RSD")
    add(session, 3, amount="30")
    add(session, 4, amount="50", currency="USD")
    add(session, 5, amount="40", currency="USD")
    add(session, 6, amount="999999", currency="ZZZ")
    add(session, 7, amount=None)
    session.commit()
    lookups = []

    def rate(_session, *, base_currency, quote_currency, target_date):
        lookups.append((base_currency, quote_currency, target_date))
        return FxRateLookup(
            rate={"RSD": Decimal("0.01"), "USD": Decimal("0.5")}.get(base_currency),
            effective_date=target_date,
            is_fallback=False,
        )

    monkeypatch.setattr(listing, "lookup_rate", rate)
    assert [row.id.int for row in page(session, sort_by=sort_by, page_size=2)] == first_page
    assert len(lookups) == 3  # One lookup per currency/date, including repeated USD rows.
    assert [row.id.int for row in page(session, sort_by=sort_by, page_size=5, page=2)] == [6, 7]


def test_review_filter_finds_older_drafts_and_warnings_before_pagination(session):
    for number in range(1, 65):
        add(session, number)
    draft = add(session, 100)
    draft.status = "DRAFT"
    draft.occurred_at = DAY - dt.timedelta(days=10)
    receipt_id = uuid.uuid4()
    warned = add(session, 101, receipt_id=receipt_id)
    warned.occurred_at = DAY - dt.timedelta(days=20)
    # Use the actual model's predicate and a SQLite JSON column for its payload.
    for number, warnings in [
        (101, [{"code": "TOTAL_MISMATCH"}]),
        (102, []),
        (103, None),
        (104, "malformed"),
    ]:
        tx = warned if number == 101 else add(session, number, receipt_id=uuid.uuid4())
        session.exec(
            insert(session.info["extractions"]).values(
                id=uuid.uuid4(),
                receipt_id=tx.receipt_id,
                structured_json={"warnings": warnings},
            )
        )
    session.commit()

    assert [row.id.int for row in page(session, needs_review=True, page_size=1)] == [100]
    assert [row.id.int for row in page(session, needs_review=True, page_size=1, page=2)] == [101]
    assert page(session, needs_review=True, page_size=1, page=3) == []


def test_sort_and_pagination_reject_invalid_input():
    for payload in [
        {"sort_by": "amount; DROP TABLE transactions"},
        {"page": 0},
        {"page_size": 201},
    ]:
        with pytest.raises(ValidationError):
            TransactionListFilter(**payload)
