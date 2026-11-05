"""Stable transaction ordering before pagination."""

import datetime as dt
from decimal import Decimal

from sqlalchemy import func
from sqlmodel import Session, select

from app.models.transactions.transaction import Transaction
from app.schemas.shared import quantize_amount
from app.schemas.transactions import TransactionListFilter
from app.services.fx_rates import lookup_rate, resolve_conversion_date


def list_transaction_page(
    *,
    session: Session,
    query,
    filters: TransactionListFilter,
    target_currency: str,
) -> list[Transaction]:
    """Order the complete filtered scope, then load only this page's records."""

    occurred_at = func.coalesce(Transaction.occurred_at, Transaction.created_at)
    if filters.sort_by not in {"amount_asc", "amount_desc"}:
        if filters.sort_by == "oldest":
            order = (occurred_at.asc(), Transaction.id.asc())
        elif filters.sort_by == "merchant_asc":
            merchant = func.lower(func.nullif(func.trim(Transaction.merchant_name), ""))
            order = (merchant.asc().nullslast(), occurred_at.desc(), Transaction.id.asc())
        else:
            order = (occurred_at.desc(), Transaction.id.desc())
        return list(
            session.exec(
                query.order_by(*order).offset(filters.offset).limit(filters.page_size)
            ).all()
        )

    # Historical FX uses the existing conversion service. Sort lightweight metadata
    # rather than loading every transaction's items, translations and receipt data.
    rows = session.exec(
        select(
            Transaction.id,
            Transaction.amount_total,
            Transaction.currency,
            Transaction.occurred_at,
            Transaction.created_at,
        ).where(Transaction.id.in_(query.with_only_columns(Transaction.id)))
    ).all()
    rates: dict[tuple[str, dt.date], Decimal | None] = {}
    ordered = []
    for transaction_id, amount, currency, occurred, created in rows:
        conversion_date = resolve_conversion_date(occurred, created)
        rate = Decimal("1")
        if amount is not None and currency != target_currency:
            key = (currency, conversion_date)
            if key not in rates:
                rates[key] = lookup_rate(
                    session,
                    base_currency=currency,
                    quote_currency=target_currency,
                    target_date=conversion_date,
                ).rate
            rate = rates[key]
        value = quantize_amount(amount * rate) if amount is not None and rate is not None else None
        if value is not None and filters.sort_by == "amount_desc":
            value = -value
        timestamp = occurred or created
        if timestamp.tzinfo is None:
            timestamp = timestamp.replace(tzinfo=dt.UTC)
        # Missing amounts/rates go last in either direction; never compare raw
        # amounts from different currencies. IDs break ties across page boundaries.
        ordered.append(
            (
                value is None,
                value or Decimal("0"),
                -timestamp.timestamp(),
                str(transaction_id),
                transaction_id,
            )
        )
    ordered.sort()
    page_ids = [row[-1] for row in ordered[filters.offset : filters.offset + filters.page_size]]
    if not page_ids:
        return []
    by_id = {row.id: row for row in session.exec(query.where(Transaction.id.in_(page_ids))).all()}
    return [by_id[transaction_id] for transaction_id in page_ids]
