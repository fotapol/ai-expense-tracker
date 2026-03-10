import datetime as dt
import uuid

from app.services.billing.features import FREE_PLAN_RECEIPT_SCAN_LIMIT
from app.services.billing.usage import (
    rolling_30_day_window,
    receipt_scan_limit_reached,
    resolve_receipt_scan_usage,
)


def test_rolling_30_day_window_boundaries() -> None:
    now = dt.datetime(2026, 3, 15, 12, 30, tzinfo=dt.UTC)
    start, end = rolling_30_day_window(now=now)
    assert start == now - dt.timedelta(days=30)
    assert end == now


def test_free_plan_usage_has_limit_and_remaining(monkeypatch) -> None:
    monkeypatch.setattr(
        "app.services.billing.usage.count_user_processed_receipts_in_window",
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
    
    expected_end = dt.datetime(2026, 3, 9, tzinfo=dt.UTC)
    expected_start = expected_end - dt.timedelta(days=30)
    
    assert usage.period_start_at == expected_start
    assert usage.period_end_at == expected_end
    assert receipt_scan_limit_reached(usage) is False


def test_free_plan_limit_reached_blocks_new_monthly_scans(monkeypatch) -> None:
    monkeypatch.setattr(
        "app.services.billing.usage.count_user_processed_receipts_in_window",
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
        "app.services.billing.usage.count_user_processed_receipts_in_window",
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
