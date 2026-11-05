"""Receipt history must order and filter the full scope before taking a page."""

import asyncio
import datetime as dt
import json
import uuid
from decimal import Decimal
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import JSON, Column, MetaData, Table, Uuid, event, insert
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.compiler import compiles
from sqlmodel import Session, create_engine, select

from app.models.fx.exchange_rate import ExchangeRate
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.schemas.transactions import TransactionListFilter
from app.services import fx_rates
from app.services.fx_rates import FxRateLookup, load_cached_rate_snapshot
from app.services.transactions import listing
from app.services.transactions.read_models import _build_filtered_transaction_ids_query

OWNER = uuid.UUID(int=10000)
DAY = dt.datetime(2026, 1, 10, 12, tzinfo=dt.UTC)


@compiles(JSONB, "sqlite")
def compile_jsonb_sqlite(_type, _compiler, **_kwargs):
    return "JSON"


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
    TransactionItem.__table__.create(engine)
    ExchangeRate.__table__.create(engine)
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


def add_rate(session, base, rate, *, date=None, quote="EUR", **fields):
    session.add(
        ExchangeRate(
            base_currency=base,
            quote_currency=quote,
            rate=Decimal(rate),
            rate_date=date or DAY.date(),
            fetched_at=DAY,
            **fields,
        )
    )


def reject_live_fx(*_args, **_kwargs):
    raise AssertionError("Amount sorting must not resolve live exchange rates")


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
    add_rate(session, "RSD", "0.01")
    add_rate(session, "USD", "0.5")
    session.commit()
    monkeypatch.setattr(fx_rates, "lookup_rate", reject_live_fx)
    monkeypatch.setattr(fx_rates, "_fetch_rate_from_provider", reject_live_fx)
    assert [row.id.int for row in page(session, sort_by=sort_by, page_size=2)] == first_page
    assert [row.id.int for row in page(session, sort_by=sort_by, page_size=5, page=2)] == [6, 7]


def test_cached_snapshot_uses_exact_previous_latest_and_missing_rate_semantics(session):
    earlier = DAY.date() - dt.timedelta(days=10)
    add_rate(session, "USD", "0.4", date=earlier)
    add_rate(session, "USD", "0.5", is_fallback=True)
    add_rate(session, "USD", "500", quote="GBP")
    add_rate(session, "USD", "100", provider="other")
    session.commit()
    selects = []

    @event.listens_for(session.get_bind(), "before_cursor_execute")
    def count_queries(_connection, _cursor, statement, _parameters, _context, _many):
        if statement.lstrip().upper().startswith("SELECT"):
            selects.append(statement)

    snapshot = load_cached_rate_snapshot(session, quote_currency="eur")
    assert len(selects) == 1
    for date, expected_rate, expected_date, expected_fallback in [
        (earlier, Decimal("0.4"), earlier, False),
        (DAY.date(), Decimal("0.5"), DAY.date(), True),
        (earlier + dt.timedelta(days=2), Decimal("0.4"), earlier, True),
        (earlier - dt.timedelta(days=2), Decimal("0.5"), DAY.date(), True),
    ]:
        result = snapshot.lookup(
            session, base_currency="usd", quote_currency="EUR", target_date=date
        )
        assert (result.rate, result.effective_date, result.is_fallback) == (
            expected_rate,
            expected_date,
            expected_fallback,
        )
    assert (
        snapshot.lookup(
            session, base_currency="ZZZ", quote_currency="EUR", target_date=earlier
        ).rate
        is None
    )
    assert (
        snapshot.lookup(
            session, base_currency="EUR", quote_currency="EUR", target_date=earlier
        ).rate
        == 1
    )
    assert len(selects) == 1  # Lookup itself performs neither SQL nor network I/O.


@pytest.mark.parametrize(
    "sort_by,expected_amount,expected_live_calls",
    [
        ("amount_desc", Decimal("50"), 0),
        ("newest", Decimal("80"), 3),
    ],
)
def test_route_uses_same_cached_snapshot_for_amount_order_and_item_display(
    session,
    monkeypatch,
    sort_by,
    expected_amount,
    expected_live_calls,
):
    from app.api.routers import transactions_crud as router

    transaction = add(session, 1, amount="100", currency="USD")
    add_rate(session, "USD", "0.5")
    session.commit()
    item = TransactionItem(
        id=uuid.uuid4(),
        transaction_id=transaction.id,
        line_no=1,
        description="Imported item",
        qty=Decimal("2"),
        unit="pc",
        unit_price=Decimal("50"),
        amount=Decimal("100"),
        category_id=uuid.uuid4(),
        created_at=DAY,
        updated_at=DAY,
    )

    class ItemSession:
        def exec(self, statement):
            if statement.column_descriptions[0].get("entity") is TransactionItem:
                return SimpleNamespace(all=lambda: [item])
            return session.exec(statement)

    for name in [
        "_load_labels_by_transaction_id",
        "_load_category_names_by_id",
        "_load_warnings_by_receipt_id",
        "_load_translation_lookup",
    ]:
        monkeypatch.setattr(router, name, lambda *_args, **_kwargs: {})
    live_calls = []

    def normal_lookup(*_args, **kwargs):
        live_calls.append(kwargs)
        if sort_by == "amount_desc":
            reject_live_fx()
        return FxRateLookup(Decimal("0.8"), DAY.date(), False)

    monkeypatch.setattr(fx_rates, "lookup_rate", normal_lookup)
    monkeypatch.setattr(fx_rates, "_fetch_rate_from_provider", reject_live_fx)
    rate_queries = []

    @event.listens_for(session.get_bind(), "before_cursor_execute")
    def count_rate_queries(_connection, _cursor, statement, _parameters, _context, _many):
        if statement.lstrip().upper().startswith("SELECT") and "exchange_rates" in statement:
            rate_queries.append(statement)

    endpoint = router.list_transactions
    while hasattr(endpoint, "__wrapped__"):
        endpoint = endpoint.__wrapped__
    result = asyncio.run(
        endpoint(
            request=None,
            filters=TransactionListFilter(sort_by=sort_by),
            session=ItemSession(),
            current_user=SimpleNamespace(
                id=OWNER,
                default_currency="EUR",
                items_language=None,
            ),
        )
    )
    assert len(rate_queries) == (1 if sort_by == "amount_desc" else 0)
    assert len(live_calls) == expected_live_calls
    assert result[0].display_amount_total == expected_amount
    assert result[0].items[0].display_amount == expected_amount
    assert result[0].items[0].display_unit_price == expected_amount / 2


def test_cached_snapshot_survives_rate_updates_during_a_request(session, monkeypatch):
    usd = add(session, 1, amount="100", currency="USD")
    add(session, 2, amount="75")
    add_rate(session, "USD", "0.5")
    session.commit()
    snapshot = load_cached_rate_snapshot(session, quote_currency="EUR")
    cached = session.exec(select(ExchangeRate)).first()
    cached.rate = Decimal("2")
    session.add(cached)
    session.commit()
    monkeypatch.setattr(fx_rates, "lookup_rate", reject_live_fx)
    monkeypatch.setattr(fx_rates, "_fetch_rate_from_provider", reject_live_fx)
    ordered = listing.list_transaction_page(
        session=session,
        query=select(Transaction),
        filters=TransactionListFilter(sort_by="amount_desc"),
        target_currency="EUR",
        rate_lookup=snapshot.lookup,
    )
    assert [row.id.int for row in ordered] == [2, 1]
    result = fx_rates.convert_amount(
        amount=usd.amount_total,
        base_currency="USD",
        target_currency="EUR",
        target_date=DAY.date(),
        session=session,
        quantizer=lambda amount: amount,
        rate_lookup=snapshot.lookup,
    )
    assert result.value == Decimal("50")


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


@pytest.mark.parametrize(
    "field",
    [
        "description",
        "raw_name",
        "translatable_name",
        "expanded_name",
        "normalized_display_name",
        "brand_name",
        "product_type",
    ],
)
def test_item_search_finds_older_transactions_in_every_name_field(session, field):
    for number in range(1, 66):
        add(session, number, merchant="Unrelated shop")
    for line in (1, 2):
        values = {"description": "An item", field: "Fresh Coffee Beans"}
        session.add(
            TransactionItem(
                transaction_id=uuid.UUID(int=1),
                line_no=line,
                amount=1,
                category_id=uuid.uuid4(),
                **values,
            )
        )
    session.commit()
    assert [row.id.int for row in page(session, search="  cOfFeE  ")] == [1]


def test_search_combines_merchant_and_items_and_respects_user_scope(session):
    add(session, 1, merchant="Coffee shop")
    add(session, 2, merchant="Other shop")
    other = add(session, 3, merchant="Coffee shop")
    other.user_id = uuid.uuid4()
    session.add(
        TransactionItem(
            transaction_id=uuid.UUID(int=2),
            line_no=1,
            description="Coffee",
            amount=1,
            category_id=uuid.uuid4(),
        )
    )
    session.commit()
    assert [row.id.int for row in page(session, search="coffee")] == [2, 1]
    assert [row.id.int for row in page(session, search="coffee", merchant_name_search="Other")] == [
        2
    ]
    assert [row.id.int for row in page(session, search="   ")] == [2, 1]


@pytest.mark.parametrize("text", ["%", "_", "\\"])
def test_search_treats_sql_wildcards_and_escape_characters_literally(session, text):
    add(session, 1, merchant=f"Store {text}")
    add(session, 2, merchant="Store everything")
    add(session, 3, merchant="Different")
    session.add(
        TransactionItem(
            transaction_id=uuid.UUID(int=3),
            line_no=1,
            description=f"Item {text}",
            amount=1,
            category_id=uuid.uuid4(),
        )
    )
    session.commit()
    assert [row.id.int for row in page(session, search=text)] == [3, 1]


def test_combined_search_amount_currency_source_status_filters_precede_pagination(session):
    for number in range(1, 126):
        add(session, number, merchant="Coffee shop", amount="20.25", source="MANUAL")
    add(session, 200, merchant="Coffee shop", amount="20.25", currency="USD", source="MANUAL")
    add(session, 201, merchant="Coffee shop", amount="20.26", source="MANUAL")
    add(session, 202, merchant="Coffee shop", amount="20.25", source="IMPORTED")
    draft = add(session, 203, merchant="Coffee shop", amount="20.25", source="MANUAL")
    draft.status = "DRAFT"
    add(session, 204, merchant="Other shop", amount="20.25", source="MANUAL")
    session.commit()
    filters = dict(
        search="coffee",
        min_amount="20.25",
        max_amount="20.25",
        currency="EUR",
        source="MANUAL",
        status="CONFIRMED",
        sort_by="oldest",
    )
    pages = [page(session, **filters, page=i) for i in (1, 2, 3)]
    assert [len(rows) for rows in pages] == [50, 50, 25]
    assert [row.id.int for rows in pages for row in rows] == list(range(1, 126))
    assert [row.id.int for row in page(session, source="IMPORTED")] == [202]
    assert [row.id.int for row in page(session, status="DRAFT")] == [203]
    assert [row.id.int for row in page(session, currency="USD")] == [200]


def test_amount_bounds_include_zero_and_refunds_and_exclude_unknown_totals(session):
    for number, amount in enumerate(["-10.01", "-10", "0", "0.01", None], 1):
        add(session, number, amount=amount)
    session.commit()
    assert [
        row.id.int for row in page(session, currency="EUR", min_amount="-10", max_amount="0")
    ] == [3, 2]
    assert [row.id.int for row in page(session, currency="EUR", max_amount="0")] == [3, 2, 1]
    assert [row.id.int for row in page(session, currency="EUR", min_amount="0")] == [4, 3]


@pytest.mark.parametrize(
    "filters",
    [
        dict(min_amount="0"),
        dict(max_amount="0"),
        dict(currency="EUR", min_amount="10", max_amount="9"),
    ],
)
def test_invalid_amount_ranges_return_a_validation_error(session, filters):
    with pytest.raises(HTTPException) as error:
        page(session, **filters)
    assert error.value.status_code == 422


@pytest.mark.parametrize(
    "filters",
    [
        dict(search="a" * 201),
        dict(min_amount="1.001"),
        dict(max_amount="NaN"),
        dict(min_amount="10000000000"),
    ],
)
def test_invalid_search_and_decimal_shapes_are_rejected(filters):
    with pytest.raises(ValidationError):
        TransactionListFilter(**filters)


def test_http_history_search_and_validation_match_analytics_scope(session, monkeypatch):
    import httpx
    from fastapi import FastAPI

    from app.api.routers import transactions_crud as router

    add(session, 1, merchant="Coffee shop", amount="10.25", source="MANUAL")
    add(session, 2, merchant="Different shop", amount="10.25", source="MANUAL")
    session.add(
        TransactionItem(
            transaction_id=uuid.UUID(int=2),
            line_no=1,
            description="Ground coffee",
            amount=1,
            category_id=uuid.uuid4(),
        )
    )
    session.commit()
    for name in (
        "_load_labels_by_transaction_id",
        "_load_category_names_by_id",
        "_load_warnings_by_receipt_id",
        "_load_translation_lookup",
    ):
        monkeypatch.setattr(router, name, lambda *_args, **_kwargs: {})
    app = FastAPI()
    app.include_router(router.router)
    app.state.limiter = router.limiter
    monkeypatch.setattr(router.limiter, "enabled", False)
    app.dependency_overrides[router.get_session] = lambda: session
    app.dependency_overrides[router.get_current_user] = lambda: SimpleNamespace(
        id=OWNER, default_currency="EUR", items_language=None
    )
    params = dict(
        search="coffee",
        currency="EUR",
        min_amount="10.25",
        max_amount="10.25",
        source="MANUAL",
        status="CONFIRMED",
    )

    async def check():
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app), base_url="http://test"
        ) as client:
            response = await client.get("/v1/transactions", params=params)
            assert response.status_code == 200, response.text
            assert [row["id"] for row in response.json()] == [
                str(row.id) for row in page(session, **params)
            ]
            for invalid in (
                dict(min_amount="0"),
                dict(max_amount="0"),
                dict(currency="EUR", min_amount="10", max_amount="9"),
                dict(currency="EUR", min_amount="1.001"),
                dict(search="a" * 201),
            ):
                response = await client.get("/v1/transactions", params=invalid)
                assert response.status_code == 422, response.text

    asyncio.run(check())
