import datetime as dt
import uuid
from decimal import Decimal

from sqlalchemy import Boolean, Column, Date, Numeric, String, UniqueConstraint
from sqlmodel import Field

from app.models.shared.timestamps import TimestampedModel


class ExchangeRate(TimestampedModel, table=True):
    """Cached FX rate for converting source transaction currency to display currency."""

    __tablename__ = "exchange_rates"
    __table_args__ = (
        UniqueConstraint(
            "provider",
            "base_currency",
            "quote_currency",
            "rate_date",
            name="uq_exchange_rates_provider_pair_date",
        ),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    provider: str = Field(
        default="frankfurter",
        sa_column=Column(String(32), nullable=False, index=True, default="frankfurter"),
    )
    base_currency: str = Field(
        sa_column=Column(String(3), nullable=False, index=True),
        max_length=3,
    )
    quote_currency: str = Field(
        sa_column=Column(String(3), nullable=False, index=True),
        max_length=3,
    )
    rate_date: dt.date = Field(
        sa_column=Column(Date, nullable=False, index=True),
    )
    rate: Decimal = Field(
        sa_column=Column(Numeric(18, 8), nullable=False),
    )
    fetched_at: dt.datetime = Field(nullable=False)
    is_fallback: bool = Field(
        default=False,
        sa_column=Column(Boolean, nullable=False, default=False),
    )
