"""Schemas for item translation cache APIs."""

from typing import Literal

from pydantic import Field, field_validator

from app.schemas.shared import SchemaBase, normalize_language_code


def normalize_translation_source_text(value: str) -> str:
    """Normalize source text for stable cache lookups."""

    return " ".join(value.strip().split())


def normalized_source_text_key(value: str) -> str:
    """Return case-insensitive normalized source text key."""

    return normalize_translation_source_text(value).lower()


class ItemTranslationBatchItem(SchemaBase):
    """Single translation cache upsert payload entry."""

    source_text: str = Field(min_length=1, max_length=500)
    source_language: str = Field(min_length=2, max_length=16)
    target_language: str = Field(min_length=2, max_length=16)
    translated_text: str = Field(min_length=1, max_length=500)
    provider: str | None = Field(default="mlkit", min_length=1, max_length=32)

    @field_validator("source_text")
    @classmethod
    def normalize_source_text(cls, value: str) -> str:
        """Normalize source text before persisting."""

        normalized = normalize_translation_source_text(value)
        if not normalized:
            raise ValueError("source_text cannot be empty.")
        return normalized

    @field_validator("translated_text")
    @classmethod
    def normalize_translated_text(cls, value: str) -> str:
        """Normalize translated text before persisting."""

        normalized = " ".join(value.strip().split())
        if not normalized:
            raise ValueError("translated_text cannot be empty.")
        return normalized

    @field_validator("source_language", "target_language")
    @classmethod
    def normalize_language(cls, value: str) -> str:
        """Normalize language code values."""

        normalized = normalize_language_code(value)
        if not normalized:
            raise ValueError("language code cannot be empty.")
        return normalized

    @field_validator("provider")
    @classmethod
    def normalize_provider(cls, value: str | None) -> str:
        """Normalize provider text."""

        normalized = (value or "mlkit").strip().lower()
        return normalized or "mlkit"


class ItemTranslationBatchRequest(SchemaBase):
    """Batch upsert request payload."""

    items: list[ItemTranslationBatchItem] = Field(min_length=1, max_length=200)


class ItemTranslationBatchResponse(SchemaBase):
    """Batch upsert response payload."""

    inserted_count: int
    updated_count: int
    provider: Literal["mlkit"] | str = "mlkit"
