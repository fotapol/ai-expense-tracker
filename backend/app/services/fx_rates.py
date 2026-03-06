"""FX conversion service backed by cached Frankfurter (ECB) rates."""

from __future__ import annotations

import datetime as dt
import logging
import os
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from functools import lru_cache
from typing import Callable

import httpx
from sqlalchemy.exc import OperationalError, ProgrammingError
from sqlmodel import Session, select

from app.models.fx.exchange_rate import ExchangeRate
from app.schemas.shared import normalize_currency_code

logger = logging.getLogger(__name__)

_FRANKFURTER_BASE_URL = os.environ.get("FRANKFURTER_BASE_URL", "https://api.frankfurter.app")
_CURRENCY_API_CDN_BASE_URL = os.environ.get(
    "CURRENCY_API_CDN_BASE_URL",
    "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api",
)
_FX_TIMEOUT_SECONDS = float(os.environ.get("FX_HTTP_TIMEOUT_SECONDS", "8"))
_PROVIDER = "frankfurter"


def _is_missing_exchange_rates_table(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "exchange_rates" in message
        and ("does not exist" in message or "no such table" in message)
    )


@dataclass(slots=True)
class FxRateLookup:
    rate: Decimal | None
    effective_date: dt.date | None
    is_fallback: bool


@dataclass(slots=True)
class FxConvertedAmount:
    value: Decimal | None
    currency: str
    rate_date: dt.date | None
    rate_fallback: bool | None


def resolve_conversion_date(
    occurred_at: dt.datetime | None,
    created_at: dt.datetime | None,
) -> dt.date:
    """Select the reference date for historical conversion."""

    if occurred_at is not None:
        return occurred_at.date()
    if created_at is not None:
        return created_at.date()
    return dt.datetime.now(dt.timezone.utc).date()


def _find_cached_rate(
    session: Session,
    *,
    base_currency: str,
    quote_currency: str,
    on_or_before: dt.date | None = None,
    exact_date: dt.date | None = None,
) -> ExchangeRate | None:
    query = select(ExchangeRate).where(
        ExchangeRate.provider == _PROVIDER,
        ExchangeRate.base_currency == base_currency,
        ExchangeRate.quote_currency == quote_currency,
    )
    if exact_date is not None:
        query = query.where(ExchangeRate.rate_date == exact_date)
    if on_or_before is not None:
        query = query.where(ExchangeRate.rate_date <= on_or_before)
    query = query.order_by(ExchangeRate.rate_date.desc())
    try:
        return session.exec(query).first()
    except (ProgrammingError, OperationalError) as exc:
        if _is_missing_exchange_rates_table(exc):
            session.rollback()
            logger.warning(
                "Skipping FX cache lookup because exchange_rates table is missing."
            )
            return None
        raise


def _find_latest_cached_rate(
    session: Session,
    *,
    base_currency: str,
    quote_currency: str,
) -> ExchangeRate | None:
    query = (
        select(ExchangeRate)
        .where(
            ExchangeRate.provider == _PROVIDER,
            ExchangeRate.base_currency == base_currency,
            ExchangeRate.quote_currency == quote_currency,
        )
        .order_by(ExchangeRate.rate_date.desc())
    )
    try:
        return session.exec(query).first()
    except (ProgrammingError, OperationalError) as exc:
        if _is_missing_exchange_rates_table(exc):
            session.rollback()
            logger.warning(
                "Skipping FX latest-rate lookup because exchange_rates table is missing."
            )
            return None
        raise


def _persist_rate(
    session: Session,
    *,
    base_currency: str,
    quote_currency: str,
    rate_date: dt.date,
    rate: Decimal,
    is_fallback: bool,
) -> None:
    existing = _find_cached_rate(
        session,
        base_currency=base_currency,
        quote_currency=quote_currency,
        exact_date=rate_date,
    )
    now = dt.datetime.now(dt.timezone.utc)

    if existing is None:
        existing = ExchangeRate(
            provider=_PROVIDER,
            base_currency=base_currency,
            quote_currency=quote_currency,
            rate_date=rate_date,
            rate=rate,
            fetched_at=now,
            is_fallback=is_fallback,
        )
    else:
        existing.rate = rate
        existing.fetched_at = now
        existing.is_fallback = is_fallback

    session.add(existing)
    try:
        session.commit()
    except (ProgrammingError, OperationalError) as exc:
        if _is_missing_exchange_rates_table(exc):
            session.rollback()
            logger.warning(
                "Skipping FX cache persist because exchange_rates table is missing."
            )
            return
        session.rollback()
        raise


def _fetch_rate_from_provider(
    *,
    base_currency: str,
    quote_currency: str,
    target_date: dt.date,
) -> FxRateLookup:
    frankfurter_result = _fetch_rate_from_frankfurter(
        base_currency=base_currency,
        quote_currency=quote_currency,
        target_date=target_date,
    )
    if frankfurter_result.rate is not None:
        return frankfurter_result

    currency_api_result = _fetch_rate_from_currency_api(
        base_currency=base_currency,
        quote_currency=quote_currency,
        target_date=target_date,
    )
    if currency_api_result.rate is not None:
        return currency_api_result

    return FxRateLookup(rate=None, effective_date=None, is_fallback=True)


def _fetch_rate_from_frankfurter(
    *,
    base_currency: str,
    quote_currency: str,
    target_date: dt.date,
) -> FxRateLookup:
    if not _frankfurter_supports_pair(base_currency, quote_currency):
        return FxRateLookup(rate=None, effective_date=None, is_fallback=True)

    url = f"{_FRANKFURTER_BASE_URL}/{target_date.isoformat()}"
    params = {
        "amount": "1",
        "from": base_currency,
        "to": quote_currency,
    }
    try:
        with httpx.Client(timeout=_FX_TIMEOUT_SECONDS) as client:
            response = client.get(url, params=params)
            response.raise_for_status()
    except Exception:
        logger.warning(
            "FX provider request failed base=%s quote=%s date=%s.",
            base_currency,
            quote_currency,
            target_date.isoformat(),
            exc_info=True,
        )
        return FxRateLookup(rate=None, effective_date=None, is_fallback=True)

    payload = response.json()
    rates = payload.get("rates", {})
    raw_rate = rates.get(quote_currency)
    if raw_rate is None:
        return FxRateLookup(rate=None, effective_date=None, is_fallback=True)

    try:
        rate = Decimal(str(raw_rate))
    except (InvalidOperation, TypeError):
        return FxRateLookup(rate=None, effective_date=None, is_fallback=True)

    raw_effective_date = payload.get("date")
    effective_date = target_date
    if isinstance(raw_effective_date, str):
        try:
            effective_date = dt.date.fromisoformat(raw_effective_date)
        except ValueError:
            effective_date = target_date

    return FxRateLookup(
        rate=rate,
        effective_date=effective_date,
        is_fallback=effective_date != target_date,
    )


@lru_cache(maxsize=1)
def _get_frankfurter_supported_currencies() -> frozenset[str] | None:
    url = f"{_FRANKFURTER_BASE_URL}/currencies"
    try:
        with httpx.Client(timeout=_FX_TIMEOUT_SECONDS) as client:
            response = client.get(url)
            response.raise_for_status()
    except Exception:
        logger.warning("Unable to load supported currencies from Frankfurter.", exc_info=True)
        return None

    payload = response.json()
    if not isinstance(payload, dict):
        return None

    supported = {
        normalize_currency_code(code)
        for code in payload.keys()
        if isinstance(code, str) and len(code.strip()) == 3
    }
    return frozenset(supported)


def _frankfurter_supports_pair(base_currency: str, quote_currency: str) -> bool:
    supported = _get_frankfurter_supported_currencies()
    if supported is None:
        return True
    return (
        normalize_currency_code(base_currency) in supported
        and normalize_currency_code(quote_currency) in supported
    )


def _fetch_rate_from_currency_api(
    *,
    base_currency: str,
    quote_currency: str,
    target_date: dt.date,
) -> FxRateLookup:
    base_code = base_currency.lower()
    quote_code = quote_currency.lower()
    historical_url = (
        f"{_CURRENCY_API_CDN_BASE_URL}@{target_date.isoformat()}/v1/currencies/{base_code}.json"
    )
    latest_url = f"{_CURRENCY_API_CDN_BASE_URL}@latest/v1/currencies/{base_code}.json"

    def _parse_payload(payload: dict, *, fallback_used: bool) -> FxRateLookup:
        base_rates = payload.get(base_code)
        if not isinstance(base_rates, dict):
            return FxRateLookup(rate=None, effective_date=None, is_fallback=True)
        raw_rate = base_rates.get(quote_code)
        if raw_rate is None:
            return FxRateLookup(rate=None, effective_date=None, is_fallback=True)
        try:
            parsed_rate = Decimal(str(raw_rate))
        except (InvalidOperation, TypeError):
            return FxRateLookup(rate=None, effective_date=None, is_fallback=True)

        effective_date = target_date
        raw_date = payload.get("date")
        if isinstance(raw_date, str):
            try:
                effective_date = dt.date.fromisoformat(raw_date)
            except ValueError:
                effective_date = target_date
        return FxRateLookup(
            rate=parsed_rate,
            effective_date=effective_date,
            is_fallback=fallback_used or effective_date != target_date,
        )

    try:
        with httpx.Client(timeout=_FX_TIMEOUT_SECONDS) as client:
            response = client.get(historical_url)
            if response.status_code == 404:
                latest_response = client.get(latest_url)
                latest_response.raise_for_status()
                return _parse_payload(latest_response.json(), fallback_used=True)
            response.raise_for_status()
            return _parse_payload(response.json(), fallback_used=False)
    except Exception:
        logger.warning(
            "Currency API fallback request failed base=%s quote=%s date=%s.",
            base_currency,
            quote_currency,
            target_date.isoformat(),
            exc_info=True,
        )
        return FxRateLookup(rate=None, effective_date=None, is_fallback=True)


def lookup_rate(
    session: Session,
    *,
    base_currency: str,
    quote_currency: str,
    target_date: dt.date,
) -> FxRateLookup:
    """Resolve conversion rate using cache + provider + cache fallback."""

    normalized_base = normalize_currency_code(base_currency)
    normalized_quote = normalize_currency_code(quote_currency)
    if normalized_base == normalized_quote:
        return FxRateLookup(rate=Decimal("1"), effective_date=target_date, is_fallback=False)

    exact = _find_cached_rate(
        session,
        base_currency=normalized_base,
        quote_currency=normalized_quote,
        exact_date=target_date,
    )
    if exact is not None:
        return FxRateLookup(
            rate=exact.rate,
            effective_date=exact.rate_date,
            is_fallback=exact.is_fallback,
        )

    fetched = _fetch_rate_from_provider(
        base_currency=normalized_base,
        quote_currency=normalized_quote,
        target_date=target_date,
    )
    if fetched.rate is not None and fetched.effective_date is not None:
        _persist_rate(
            session,
            base_currency=normalized_base,
            quote_currency=normalized_quote,
            rate_date=fetched.effective_date,
            rate=fetched.rate,
            is_fallback=fetched.is_fallback,
        )
        return fetched

    previous = _find_cached_rate(
        session,
        base_currency=normalized_base,
        quote_currency=normalized_quote,
        on_or_before=target_date,
    )
    if previous is not None:
        return FxRateLookup(
            rate=previous.rate,
            effective_date=previous.rate_date,
            is_fallback=True,
        )

    latest = _find_latest_cached_rate(
        session,
        base_currency=normalized_base,
        quote_currency=normalized_quote,
    )
    if latest is not None:
        return FxRateLookup(
            rate=latest.rate,
            effective_date=latest.rate_date,
            is_fallback=True,
        )

    return FxRateLookup(rate=None, effective_date=None, is_fallback=True)


def _convert_with_rate(
    *,
    amount: Decimal | None,
    base_currency: str,
    target_currency: str,
    target_date: dt.date,
    session: Session,
    quantizer: Callable[[Decimal], Decimal],
) -> FxConvertedAmount:
    normalized_target = normalize_currency_code(target_currency)
    normalized_base = normalize_currency_code(base_currency)

    if amount is None:
        return FxConvertedAmount(
            value=None,
            currency=normalized_target,
            rate_date=None,
            rate_fallback=None,
        )

    if normalized_base == normalized_target:
        return FxConvertedAmount(
            value=quantizer(amount),
            currency=normalized_target,
            rate_date=target_date,
            rate_fallback=False,
        )

    lookup = lookup_rate(
        session,
        base_currency=normalized_base,
        quote_currency=normalized_target,
        target_date=target_date,
    )
    if lookup.rate is None:
        return FxConvertedAmount(
            value=None,
            currency=normalized_target,
            rate_date=None,
            rate_fallback=None,
        )

    converted = quantizer(amount * lookup.rate)
    return FxConvertedAmount(
        value=converted,
        currency=normalized_target,
        rate_date=lookup.effective_date,
        rate_fallback=lookup.is_fallback,
    )


def convert_amount(
    *,
    amount: Decimal | None,
    base_currency: str,
    target_currency: str,
    target_date: dt.date,
    session: Session,
    quantizer: Callable[[Decimal], Decimal],
) -> FxConvertedAmount:
    """Convert a money amount into target currency using historical FX."""

    return _convert_with_rate(
        amount=amount,
        base_currency=base_currency,
        target_currency=target_currency,
        target_date=target_date,
        session=session,
        quantizer=quantizer,
    )
