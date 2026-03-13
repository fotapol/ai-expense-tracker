"""Household analytics queries.

These functions provide spending aggregations scoped to a household.
They are designed to back future analytics dashboard endpoints.

Query patterns illustrated here:
- Total spending grouped by ``owner_user_id`` across all transactions in the household.
- Per-member spending broken down by ``category_id``.
"""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import func
from sqlmodel import Session, select

from app.models.transactions.transaction import Transaction


def get_spending_by_member(
    session: Session,
    household_id: uuid.UUID,
    *,
    from_dt: dt.datetime | None = None,
    to_dt: dt.datetime | None = None,
) -> list[dict]:
    """Return total spending aggregated by ``owner_user_id`` for a household.

    Each row is a dict with keys:
    - ``owner_user_id: uuid.UUID``
    - ``total: Decimal``
    - ``currency: str``

    Results are limited to CONFIRMED transactions to avoid double-counting drafts.
    Grouped by (owner_user_id, currency) so multi-currency households work correctly.

    Example future usage::

        rows = get_spending_by_member(session, household_id, from_dt=start, to_dt=end)
        for row in rows:
            print(f"{row['owner_user_id']}: {row['total']} {row['currency']}")
    """
    query = (
        select(
            Transaction.owner_user_id,
            Transaction.currency,
            func.sum(Transaction.amount_total).label("total"),
        )
        .where(
            Transaction.household_id == household_id,
            Transaction.status == "CONFIRMED",
            Transaction.owner_user_id.is_not(None),  # type: ignore[union-attr]
        )
        .group_by(Transaction.owner_user_id, Transaction.currency)  # type: ignore[arg-type]
        .order_by(func.sum(Transaction.amount_total).desc())
    )

    if from_dt is not None:
        query = query.where(Transaction.occurred_at >= from_dt)
    if to_dt is not None:
        query = query.where(Transaction.occurred_at <= to_dt)

    rows = session.exec(query).all()
    return [
        {
            "owner_user_id": row.owner_user_id,
            "currency": row.currency,
            "total": Decimal(str(row.total)) if row.total is not None else Decimal("0"),
        }
        for row in rows
    ]


def get_spending_by_category_per_member(
    session: Session,
    household_id: uuid.UUID,
    *,
    from_dt: dt.datetime | None = None,
    to_dt: dt.datetime | None = None,
) -> list[dict]:
    """Return spending grouped by (owner_user_id, category_id, currency).

    Each row is a dict with keys:
    - ``owner_user_id: uuid.UUID``
    - ``category_id: uuid.UUID | None``
    - ``currency: str``
    - ``total: Decimal``

    Useful for building per-member category breakdown charts.

    Example future usage::

        rows = get_spending_by_category_per_member(
            session, household_id, from_dt=start, to_dt=end
        )
    """
    query = (
        select(
            Transaction.owner_user_id,
            Transaction.category_id,
            Transaction.currency,
            func.sum(Transaction.amount_total).label("total"),
        )
        .where(
            Transaction.household_id == household_id,
            Transaction.status == "CONFIRMED",
            Transaction.owner_user_id.is_not(None),  # type: ignore[union-attr]
        )
        .group_by(
            Transaction.owner_user_id,  # type: ignore[arg-type]
            Transaction.category_id,  # type: ignore[arg-type]
            Transaction.currency,  # type: ignore[arg-type]
        )
        .order_by(Transaction.owner_user_id, func.sum(Transaction.amount_total).desc())
    )

    if from_dt is not None:
        query = query.where(Transaction.occurred_at >= from_dt)
    if to_dt is not None:
        query = query.where(Transaction.occurred_at <= to_dt)

    rows = session.exec(query).all()
    return [
        {
            "owner_user_id": row.owner_user_id,
            "category_id": row.category_id,
            "currency": row.currency,
            "total": Decimal(str(row.total)) if row.total is not None else Decimal("0"),
        }
        for row in rows
    ]
