"""The normalized expense import payload shared by file adapters and the API."""

import datetime as dt
from decimal import Decimal
from enum import StrEnum

from pydantic import Field, model_validator

from app.schemas.shared import SchemaBase

MAX_IMPORT_EXPENSES = 20_000
MAX_IMPORT_FILE_BYTES = 16 * 1024 * 1024


class ImportSource(StrEnum):
    MONEY_MANAGER = "money_manager"


class ImportCategory(SchemaBase):
    uid: str = Field(min_length=1, max_length=128)
    name: str = Field(min_length=1, max_length=120)


class ImportExpense(SchemaBase):
    uid: str = Field(min_length=1, max_length=128)
    day: dt.date = Field(ge=dt.date(1900, 1, 1), le=dt.date(9998, 12, 31))
    amount: Decimal = Field(gt=0, max_digits=12, decimal_places=2)
    currency: str = Field(pattern="^[A-Z]{3}$")
    description: str | None = Field(default=None, max_length=255)
    category_uid: str | None = Field(default=None, max_length=128)
    utc_offset_minutes: int = Field(default=0, ge=-720, le=840)


class ExternalImportPlan(SchemaBase):
    source: ImportSource
    categories: list[ImportCategory] = Field(max_length=MAX_IMPORT_EXPENSES)
    expenses: list[ImportExpense] = Field(max_length=MAX_IMPORT_EXPENSES)

    @model_validator(mode="after")
    def check_references(self) -> "ExternalImportPlan":
        category_ids = {category.uid for category in self.categories}
        if len(category_ids) != len(self.categories):
            raise ValueError("Duplicate external category IDs")
        if len({expense.uid for expense in self.expenses}) != len(self.expenses):
            raise ValueError("Duplicate external expense IDs")
        if any(
            expense.category_uid is not None and expense.category_uid not in category_ids
            for expense in self.expenses
        ):
            raise ValueError("Missing external category reference")
        return self


class ExternalImportPreview(SchemaBase):
    plan: ExternalImportPlan
    already_imported: int
    skipped: int
    totals: dict[str, Decimal]
    samples: list[ImportExpense]


class ExternalImportResult(SchemaBase):
    imported: int
    already_imported: int
