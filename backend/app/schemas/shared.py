"""Shared schema primitives used across API and worker DTOs."""

from __future__ import annotations

import datetime as dt
from decimal import ROUND_HALF_UP, Decimal
from typing import Annotated, Generic, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

CurrencyCode = Annotated[str, Field(min_length=3, max_length=3)]
Amount2DP = Annotated[Decimal, Field(max_digits=12, decimal_places=2)]
UnitPrice4DP = Annotated[Decimal, Field(max_digits=12, decimal_places=4)]
Quantity3DP = Annotated[Decimal, Field(max_digits=12, decimal_places=3)]
Cost6DP = Annotated[Decimal, Field(max_digits=12, decimal_places=6)]

_T = TypeVar("_T")
_QTY_QUANTUM = Decimal("0.001")
_PRICE_QUANTUM = Decimal("0.0001")
_AMOUNT_QUANTUM = Decimal("0.01")
_COST_QUANTUM = Decimal("0.000001")


def normalize_currency_code(value: str) -> str:
    """Normalize ISO-4217-like currency code text."""

    return value.strip().upper()


def quantize_quantity(value: Decimal) -> Decimal:
    """Quantize a decimal quantity to the model precision."""

    return value.quantize(_QTY_QUANTUM, rounding=ROUND_HALF_UP)


def quantize_unit_price(value: Decimal) -> Decimal:
    """Quantize a unit price decimal to the model precision."""

    return value.quantize(_PRICE_QUANTUM, rounding=ROUND_HALF_UP)


def quantize_amount(value: Decimal) -> Decimal:
    """Quantize a money amount decimal to the model precision."""

    return value.quantize(_AMOUNT_QUANTUM, rounding=ROUND_HALF_UP)


def quantize_cost(value: Decimal) -> Decimal:
    """Quantize a cost decimal to the model precision."""

    return value.quantize(_COST_QUANTUM, rounding=ROUND_HALF_UP)


class SchemaBase(BaseModel):
    """Base configuration for all request/response schemas."""

    model_config = ConfigDict(extra="forbid", from_attributes=True)


class UUIDSchema(SchemaBase):
    """Schema with an entity UUID primary identifier."""

    id: UUID


class TimestampSchema(SchemaBase):
    """Schema containing creation and update timestamps."""

    created_at: dt.datetime
    updated_at: dt.datetime


class UUIDTimestampSchema(UUIDSchema, TimestampSchema):
    """Schema with both UUID and timestamp metadata fields."""


class PaginationParams(SchemaBase):
    """Standard pagination query parameters."""

    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=50, ge=1, le=200)

    @property
    def offset(self) -> int:
        """Return SQL offset calculated from page and page size."""

        return (self.page - 1) * self.page_size


class PaginatedResponse(SchemaBase, Generic[_T]):  # noqa: UP046
    """Generic paginated response container."""

    items: list[_T]
    page: int
    page_size: int
    total: int = Field(ge=0)
