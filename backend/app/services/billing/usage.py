"""Usage and free-plan limit helpers for receipt scan access."""

from __future__ import annotations

import datetime as dt
import uuid
from dataclasses import dataclass

from sqlalchemy import func
from sqlmodel import Session, select

from app.models.receipts.receipt import Receipt
from app.services.billing.entitlements import user_has_feature
from app.services.billing.features import (
    FREE_PLAN_RECEIPT_SCAN_LIMIT,
    PREMIUM_RECEIPT_SCANS_UNLIMITED,
)


@dataclass(slots=True, frozen=True)
class ReceiptScanUsage:
    """Current receipt scan usage snapshot for one user."""

    used: int
    limit: int | None
    remaining: int | None
    is_unlimited: bool
    period_start_at: dt.datetime
    period_end_at: dt.datetime


def rolling_30_day_window(*, now: dt.datetime | None = None) -> tuple[dt.datetime, dt.datetime]:
    """Return the 30-day rolling [start, end) window."""

    current_time = now or dt.datetime.now(dt.UTC)
    window_start = current_time - dt.timedelta(days=30)
    return window_start, current_time


def count_user_processed_receipts_in_window(
    session: Session,
    user_id: uuid.UUID,
    *,
    period_start_at: dt.datetime,
    period_end_at: dt.datetime,
) -> int:
    """Count receipts processed in the given time window.

    Usage is consumed when AI processing is requested at confirm-upload time,
    represented by a non-null ``uploaded_at`` timestamp.
    """

    count = session.exec(
        select(func.count()).select_from(Receipt).where(
            Receipt.user_id == user_id,
            Receipt.uploaded_at.is_not(None),
            Receipt.uploaded_at >= period_start_at,
            Receipt.uploaded_at < period_end_at,
        )
    ).one()
    return int(count or 0)


def resolve_receipt_scan_usage(
    session: Session,
    user_id: uuid.UUID,
    *,
    now: dt.datetime | None = None,
) -> ReceiptScanUsage:
    """Resolve receipt scan usage from entitlements + persisted receipts."""

    period_start_at, period_end_at = rolling_30_day_window(now=now)
    used = count_user_processed_receipts_in_window(
        session,
        user_id,
        period_start_at=period_start_at,
        period_end_at=period_end_at,
    )
    is_unlimited = user_has_feature(
        session,
        user_id,
        PREMIUM_RECEIPT_SCANS_UNLIMITED,
    )
    if is_unlimited:
        return ReceiptScanUsage(
            used=used,
            limit=None,
            remaining=None,
            is_unlimited=True,
            period_start_at=period_start_at,
            period_end_at=period_end_at,
        )

    remaining = max(FREE_PLAN_RECEIPT_SCAN_LIMIT - used, 0)
    return ReceiptScanUsage(
        used=used,
        limit=FREE_PLAN_RECEIPT_SCAN_LIMIT,
        remaining=remaining,
        is_unlimited=False,
        period_start_at=period_start_at,
        period_end_at=period_end_at,
    )


def receipt_scan_limit_reached(usage: ReceiptScanUsage) -> bool:
    """Return ``True`` when the user cannot process more receipts this month."""

    if usage.is_unlimited or usage.limit is None:
        return False
    return usage.used >= usage.limit
