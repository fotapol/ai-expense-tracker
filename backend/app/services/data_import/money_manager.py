"""Read Orange Dog Money Manager backups as expense history."""

import datetime as dt
import io
import re
import sqlite3
import zipfile
import zlib
from contextlib import closing
from decimal import Decimal

from app.schemas.external_import import MAX_IMPORT_EXPENSES, ImportCategory, ImportExpense

_MAX_DATABASE_BYTES = 64 * 1024 * 1024
_MAX_AMOUNT_MINOR = 999_999_999_999
_DATABASE_MEMBER = "MyFinance.db"
_CURRENCY = re.compile(r"[A-Z]{3}")


class BackupReadError(ValueError):
    """Malformed or unsupported backup."""


class BackupLimitError(BackupReadError):
    """Backup exceeds the accepted data size."""


def _read_database(file_bytes: bytes) -> bytes:
    # ZipFile handles the prefix present on device-created backups.
    with zipfile.ZipFile(io.BytesIO(file_bytes)) as archive:
        members = [info for info in archive.infolist() if info.filename == _DATABASE_MEMBER]
        if len(members) != 1:
            raise BackupReadError
        member = members[0]
        if member.file_size > _MAX_DATABASE_BYTES:
            raise BackupLimitError
        with archive.open(member) as data:
            content = data.read(_MAX_DATABASE_BYTES + 1)
        if len(content) > _MAX_DATABASE_BYTES:
            raise BackupLimitError
    if not content.startswith(b"SQLite format 3\x00"):
        raise BackupReadError
    return content


def _expense_amount(row: sqlite3.Row) -> tuple[int, str] | None:
    # Prefer the amount originally entered if the expense was converted.
    for amount_key, currency_key in (
        ("amountInRealCurrency", "realCurrencyCode"),
        ("amountInAccountCurrency", "accountCurrencyCode"),
    ):
        amount = row[amount_key]
        currency = str(row[currency_key] or "").strip().upper()
        if amount is not None and currency:
            if (
                isinstance(amount, int)
                and 0 < amount <= _MAX_AMOUNT_MINOR
                and _CURRENCY.fullmatch(currency)
            ):
                return amount, currency
            return None
    return None


def _read_expenses(db: sqlite3.Connection) -> tuple[list[ImportCategory], list[ImportExpense], int]:
    required = {"transaction", "category", "sync_link", "transfer"}
    ordinary_tables = {
        name for _, name, kind, *_ in db.execute("PRAGMA table_list") if kind == "table"
    }
    if not required <= ordinary_tables:
        raise BackupReadError

    transactions = db.execute(
        """
        SELECT uid, type, date, comment, amountInRealCurrency, realCurrencyCode,
               amountInAccountCurrency, accountCurrencyCode
        FROM "transaction"
        WHERE COALESCE(isRemoved, 0) = 0
        ORDER BY date DESC, uid
        LIMIT ?
        """,
        (MAX_IMPORT_EXPENSES + 1,),
    ).fetchall()
    if len(transactions) > MAX_IMPORT_EXPENSES:
        raise BackupLimitError

    category_for_expense = {}
    categories_by_id = {}
    links = db.execute(
        """
        SELECT link.entityUid, category.uid, category.title
        FROM sync_link AS link
        JOIN category ON category.uid = link.otherUid
        WHERE link.entityType = 'Transaction' AND link.otherType = 'Category'
          AND COALESCE(link.isRemoved, 0) = 0
        ORDER BY link.entityUid, link.otherUid
        LIMIT ?
        """,
        (MAX_IMPORT_EXPENSES * 2 + 1,),
    )
    for index, (expense_uid, category_uid, title) in enumerate(links):
        if index >= MAX_IMPORT_EXPENSES * 2:
            raise BackupLimitError
        if (
            isinstance(category_uid, str)
            and 0 < len(category_uid) <= 128
            and isinstance(title, str)
            and title.strip()
        ):
            category_for_expense.setdefault(expense_uid, category_uid)
            categories_by_id[category_uid] = ImportCategory(
                uid=category_uid, name=title.strip()[:120]
            )

    skipped = db.execute(
        "SELECT count(*) FROM transfer WHERE COALESCE(isRemoved, 0) = 0"
    ).fetchone()[0]
    expenses = []
    categories_in_use = {}
    seen_uids = set()
    for row in transactions:
        uid = row["uid"]
        if (
            row["type"] != "Expense"
            or not isinstance(uid, str)
            or not 0 < len(uid) <= 128
            or uid in seen_uids
        ):
            skipped += 1
            continue
        value = _expense_amount(row)
        try:
            day = dt.date.fromisoformat(row["date"])
        except (ValueError, TypeError):
            skipped += 1
            continue
        if value is None or not 1900 <= day.year <= 9998:
            skipped += 1
            continue

        amount_minor, currency = value
        category_uid = category_for_expense.get(uid)
        if category_uid:
            categories_in_use[category_uid] = categories_by_id[category_uid]
        description = row["comment"]
        expenses.append(
            ImportExpense(
                uid=uid,
                day=day,
                # The backup stores hundredths for all currencies.
                amount=Decimal(amount_minor).scaleb(-2),
                currency=currency,
                description=(description.strip()[:255] or None)
                if isinstance(description, str)
                else None,
                category_uid=category_uid,
            )
        )
        seen_uids.add(uid)
    return list(categories_in_use.values()), expenses, skipped


def read_money_manager_backup(
    file_bytes: bytes,
) -> tuple[list[ImportCategory], list[ImportExpense], int]:
    try:
        data = _read_database(file_bytes)
        with closing(sqlite3.connect(":memory:")) as db:
            db.deserialize(data)
            db.execute("PRAGMA trusted_schema = OFF")
            db.execute("PRAGMA query_only = ON")
            db.set_progress_handler(lambda: 1, 20_000_000)
            db.row_factory = sqlite3.Row
            return _read_expenses(db)
    except (zipfile.BadZipFile, sqlite3.DatabaseError, RuntimeError, EOFError, zlib.error) as error:
        raise BackupReadError from error
