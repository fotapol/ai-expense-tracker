"""External backup import coverage using a synthetic Money Manager archive."""

import io
import sqlite3
import zipfile
from contextlib import closing
from decimal import Decimal

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

import app.models  # noqa: F401
from app.api.routers.data import router
from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.shared.enums import TransactionSource
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.users.user import User

_PREVIEW = "/v1/data/external-import/preview?source=money_manager"
_IMPORT = "/v1/data/external-import"


@pytest.fixture
def backup():
    with closing(sqlite3.connect(":memory:")) as db:
        db.executescript("""
            CREATE TABLE "transaction" (
                uid TEXT PRIMARY KEY, type TEXT, date TEXT, comment TEXT,
                amountInRealCurrency INTEGER, realCurrencyCode TEXT,
                amountInAccountCurrency INTEGER, accountCurrencyCode TEXT, isRemoved INTEGER
            );
            CREATE TABLE category (uid TEXT PRIMARY KEY, title TEXT);
            CREATE TABLE sync_link (
                entityUid TEXT, otherUid TEXT, entityType TEXT, otherType TEXT, isRemoved INTEGER
            );
            CREATE TABLE transfer (isRemoved INTEGER);
            INSERT INTO category VALUES ('category-1', 'Groceries');
            INSERT INTO sync_link VALUES ('one', 'category-1', 'Transaction', 'Category', 0);
            INSERT INTO transfer VALUES (0), (1);
        """)
        db.executemany(
            'INSERT INTO "transaction" VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
                ("one", "Expense", "2026-06-18", "Market", None, None, 12345, "RSD", 0),
                ("two", "Expense", "2026-06-17", "Rail", 2500, "EUR", 292800, "RSD", 0),
                ("three", "Income", "2026-06-17", None, None, None, 600, "EUR", 0),
                ("removed", "Expense", "2026-06-16", None, None, None, 900, "EUR", 1),
                ("broken", "Expense", "invalid", None, None, None, 900, "EUR", 0),
            ],
        )
        db.commit()
        buffer = io.BytesIO()
        buffer.write(bytes([8]) * 8)
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("MyFinance.db", db.serialize())
        return buffer.getvalue()


@pytest.fixture
def api(monkeypatch):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(
        engine, tables=[User.__table__, Category.__table__, Transaction.__table__]
    )
    monkeypatch.setattr(limiter, "enabled", False)
    with Session(engine) as session:
        first = User(auth_subject="test-external-owner")
        second = User(auth_subject="test-external-other")
        session.add_all([first, second])
        session.commit()
        owner = [first]

        app = FastAPI()
        app.dependency_overrides[get_session] = lambda: session
        app.dependency_overrides[get_current_user] = lambda: owner[0]
        app.include_router(router)
        with TestClient(app) as client:
            yield client, session, owner, second
    engine.dispose()


def test_backup_preview_is_read_only_and_repeat_import_preserves_edits(api, backup):
    client, session, owner, second = api
    preview = client.post(_PREVIEW, content=backup)
    assert preview.status_code == 200
    assert preview.headers["cache-control"] == "no-store"
    result = preview.json()
    plan = result["plan"]
    assert result["skipped"] == 3  # income, transfer, unparseable date
    assert result["already_imported"] == 0
    assert {code: Decimal(value) for code, value in result["totals"].items()} == {
        "EUR": Decimal("25.00"),
        "RSD": Decimal("123.45"),
    }
    assert [expense["day"] for expense in result["samples"]] == ["2026-06-18", "2026-06-17"]
    assert not session.exec(select(Transaction)).all()
    assert not session.exec(select(Category)).all()

    confirmed = client.post(_IMPORT, json=plan)
    assert confirmed.status_code == 201
    assert confirmed.json() == {"imported": 2, "already_imported": 0}
    imported = session.exec(select(Transaction).where(Transaction.merchant_name == "Market")).one()
    assert imported.owner_user_id == owner[0].id
    assert imported.source == TransactionSource.IMPORTED
    assert imported.status == "CONFIRMED"
    assert imported.amount_total == Decimal("123.45")
    assert imported.occurred_at.date().isoformat() == "2026-06-18"
    category = session.get(Category, imported.category_id)
    assert category.name == "Groceries"
    assert category.user_id == owner[0].id
    imported.merchant_name = "Edited after import"
    session.add(imported)
    session.commit()

    preview_again = client.post(_PREVIEW, content=backup).json()
    assert preview_again["already_imported"] == 2
    assert preview_again["totals"] == {}
    assert client.post(_IMPORT, json=plan).json() == {"imported": 0, "already_imported": 2}
    assert session.get(Transaction, imported.id).merchant_name == "Edited after import"

    owner[0] = second
    assert client.post(_PREVIEW, content=backup).json()["already_imported"] == 0
    assert client.post(_IMPORT, json=plan).json() == {"imported": 2, "already_imported": 0}
    assert len(session.exec(select(Transaction)).all()) == 4


def test_invalid_or_oversize_backups_are_rejected_without_writes(api, monkeypatch):
    client, session, _, _ = api
    assert client.post(_PREVIEW, content=b"broken").status_code == 422
    monkeypatch.setattr("app.api.routers.data.MAX_IMPORT_FILE_BYTES", 8)
    assert client.post(_PREVIEW, content=b"123456789").status_code == 413
    assert not session.exec(select(Transaction)).all()
