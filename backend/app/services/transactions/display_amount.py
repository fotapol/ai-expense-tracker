"""One cached FX snapshot for displayed-amount bounds and read models."""

from sqlalchemy import Date, Numeric, String, case, column, func, literal, select, values

from app.models.transactions.transaction import Transaction


def displayed_amount_expression(snapshot, target_currency):
    rate_rows = [
        (base, day, rate.rate)
        for base, series in snapshot.rates_by_base.items()
        for day, rate in zip(series.dates, series.rates, strict=True)
    ]
    currency = func.upper(func.trim(Transaction.currency))
    foreign_rate = literal(None, type_=Numeric(18, 8))
    if rate_rows:
        rates = (
            values(column("base", String(3)), column("day", Date), column("rate", Numeric(18, 8)))
            .data(rate_rows)
            .cte("filter_fx_rates")
        )
        day = func.date(func.coalesce(Transaction.occurred_at, Transaction.created_at))
        previous = (
            select(rates.c.rate)
            .where(rates.c.base == currency, rates.c.day <= day)
            .order_by(rates.c.day.desc())
            .limit(1)
            .scalar_subquery()
        )
        latest = (
            select(rates.c.rate)
            .where(rates.c.base == currency)
            .order_by(rates.c.day.desc())
            .limit(1)
            .scalar_subquery()
        )
        foreign_rate = func.coalesce(previous, latest)
    rate = case((currency == target_currency, 1), else_=foreign_rate)
    # Round before testing inclusive bounds, exactly as the displayed total.
    # Missing amounts or exchange rates stay NULL and cannot match a range.
    return func.round(Transaction.amount_total * rate, 2)
