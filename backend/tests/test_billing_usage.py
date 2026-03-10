import datetime as dt
import uuid

from app.services.billing.features import FREE_PLAN_RECEIPT_SCAN_LIMIT
from app.services.billing.usage import (
    current_utc_month_window,
    receipt_scan_limit_reached,
    resolve_receipt_scan_usage,
)


def test_current_utc_month_window_boundaries() -> None:
    now = dt.datetime(2026, 3, 15, 12, 30, tzinfo=dt.UTC)
    start, end = current_utc_month_window(now=now)
    assert start == dt.datetime(2026, 3, 1, 0, 0, tzinfo=dt.UTC)
    assert end == dt.datetime(2026, 4, 1, 0, 0, tzinfo=dt.UTC)


def test_free_plan_usage_has_limit_and_remaining(monkeypatch) -> None:
    monkeypatch.setattr(
        "app.services.billing.usage.count_user_monthly_processed_receipts",
        lambda _session, _user_id, *, period_start_at, period_end_at: 3,
    )
    monkeypatch.setattr(
        "app.services.billing.usage.user_has_feature",
        lambda _session, _user_id, _feature: False,
    )

    usage = resolve_receipt_scan_usage(
        object(),
        uuid.uuid4(),
        now=dt.datetime(2026, 3, 9, tzinfo=dt.UTC),
    )
    assert usage.used == 3
    assert usage.limit == FREE_PLAN_RECEIPT_SCAN_LIMIT
    assert usage.remaining == FREE_PLAN_RECEIPT_SCAN_LIMIT - 3
    assert usage.is_unlimited is False
    assert usage.period_start_at == dt.datetime(2026, 3, 1, tzinfo=dt.UTC)
    assert usage.period_end_at == dt.datetime(2026, 4, 1, tzinfo=dt.UTC)
    assert receipt_scan_limit_reached(usage) is False


def test_free_plan_limit_reached_blocks_new_monthly_scans(monkeypatch) -> None:
    monkeypatch.setattr(
        "app.services.billing.usage.count_user_monthly_processed_receipts",
        lambda _session, _user_id, *, period_start_at, period_end_at: FREE_PLAN_RECEIPT_SCAN_LIMIT,
    )
    monkeypatch.setattr(
        "app.services.billing.usage.user_has_feature",
        lambda _session, _user_id, _feature: False,
    )

    usage = resolve_receipt_scan_usage(
        object(),
        uuid.uuid4(),
        now=dt.datetime(2026, 3, 9, tzinfo=dt.UTC),
    )
    assert usage.remaining == 0
    assert receipt_scan_limit_reached(usage) is True


def test_premium_usage_is_unlimited(monkeypatch) -> None:
    monkeypatch.setattr(
        "app.services.billing.usage.count_user_monthly_processed_receipts",
        lambda _session, _user_id, *, period_start_at, period_end_at: 145,
    )
    monkeypatch.setattr(
        "app.services.billing.usage.user_has_feature",
        lambda _session, _user_id, _feature: True,
    )

    usage = resolve_receipt_scan_usage(
        object(),
        uuid.uuid4(),
        now=dt.datetime(2026, 3, 9, tzinfo=dt.UTC),
    )
    assert usage.used == 145
    assert usage.limit is None
    assert usage.remaining is None
    assert usage.is_unlimited is True
    assert receipt_scan_limit_reached(usage) is False
