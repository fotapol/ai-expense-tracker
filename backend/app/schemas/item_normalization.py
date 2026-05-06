"""Schemas for Gemini-assisted receipt item name normalization."""

from __future__ import annotations

from typing import Any

from pydantic import Field, field_validator, model_validator

from app.schemas.shared import SchemaBase, normalize_language_code


def whitespace_normalized_text(value: str) -> str:
    """Collapse visible whitespace for raw-name identity checks."""

    return " ".join(value.strip().split())


def _clean_optional_text(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = whitespace_normalized_text(value)
    return cleaned or None


class NormalizedReceiptItemAttributes(SchemaBase):
    """Structured attributes separated from a noisy receipt item name."""

    package_size: str | None = None
    unit: str | None = None
    quantity: float | None = None
    percentage: str | None = None
    fat_percent: str | None = None
    flavor: str | None = None
    process: str | None = None
    variant: str | None = None
    size: str | None = None
    color: str | None = None
    material: str | None = None

    @field_validator(
        "package_size",
        "unit",
        "percentage",
        "fat_percent",
        "flavor",
        "process",
        "variant",
        "size",
        "color",
        "material",
    )
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        return _clean_optional_text(value)

    def compact_dump(self) -> dict[str, Any] | None:
        data = self.model_dump(mode="json", exclude_none=True)
        return data or None


class NormalizedReceiptItem(SchemaBase):
    """Normalized metadata for one extracted receipt item."""

    raw_name: str = Field(min_length=1, max_length=500)
    translatable_name: str | None = Field(default=None, max_length=500)
    expanded_name: str | None = Field(default=None, max_length=500)
    normalized_display_name: str | None = Field(default=None, max_length=500)
    brand_name: str | None = Field(default=None, max_length=255)
    product_type: str | None = Field(default=None, max_length=255)
    category_hint: str | None = Field(default=None, max_length=255)
    preserve_terms: list[str] = Field(default_factory=list)
    attributes: NormalizedReceiptItemAttributes = Field(
        default_factory=NormalizedReceiptItemAttributes
    )
    cleaned_unit: str | None = Field(default=None, max_length=32)
    cleaned_quantity: float | None = None
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    warnings: list[str] = Field(default_factory=list)

    @field_validator("raw_name")
    @classmethod
    def normalize_raw_name(cls, value: str) -> str:
        return whitespace_normalized_text(value)

    @field_validator(
        "translatable_name",
        "expanded_name",
        "normalized_display_name",
        "brand_name",
        "product_type",
        "category_hint",
        "cleaned_unit",
    )
    @classmethod
    def normalize_optional_text(cls, value: str | None) -> str | None:
        return _clean_optional_text(value)

    @field_validator("preserve_terms", "warnings")
    @classmethod
    def normalize_text_list(cls, value: list[str]) -> list[str]:
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            normalized = _clean_optional_text(item)
            if normalized is None:
                continue
            key = normalized.casefold()
            if key in seen:
                continue
            cleaned.append(normalized)
            seen.add(key)
        return cleaned


class NormalizedReceiptItemsResponse(SchemaBase):
    """Batch normalization response; item count and order must match input."""

    normalization_base_language: str = Field(default="en", max_length=16)
    items: list[NormalizedReceiptItem] = Field(default_factory=list)

    @model_validator(mode="after")
    def normalize_base_language(self) -> NormalizedReceiptItemsResponse:
        normalized = normalize_language_code(self.normalization_base_language or "en")
        self.normalization_base_language = normalized or "en"
        return self
