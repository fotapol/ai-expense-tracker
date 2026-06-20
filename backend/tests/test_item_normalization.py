"""Tests for Gemini-assisted receipt item normalization."""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.schemas.extraction import ExtractedReceiptData, ExtractedTransactionItem
from app.schemas.item_normalization import (
    NormalizedReceiptItem,
    NormalizedReceiptItemAttributes,
    NormalizedReceiptItemsResponse,
)
from app.schemas.transactions import TransactionItemRead


class _FakeStructuredLLM:
    def __init__(self, response):
        self.response = response
        self.messages = None

    def invoke(self, messages):
        self.messages = messages
        if isinstance(self.response, BaseException):
            raise self.response
        return self.response


def _extracted(items: list[ExtractedTransactionItem]) -> ExtractedReceiptData:
    return ExtractedReceiptData(
        merchant_name="Test Market",
        merchant_country="US",
        receipt_language="en",
        currency="USD",
        amount_total=Decimal("12.34"),
        items=items,
    )


def _item(description: str, amount: str = "1.00") -> ExtractedTransactionItem:
    return ExtractedTransactionItem(
        description=description,
        qty=Decimal("1"),
        unit="pc",
        unit_price=Decimal(amount),
        amount=Decimal(amount),
        category_code="UNKNOWN_ITEM",
    )


def _normalized(raw_name: str, **updates) -> NormalizedReceiptItem:
    payload = {
        "raw_name": raw_name,
        "translatable_name": "expanded product name",
        "expanded_name": "expanded product name",
        "normalized_display_name": "expanded product name",
        "brand_name": None,
        "product_type": "product",
        "category_hint": "grocery",
        "preserve_terms": [],
        "attributes": {},
        "cleaned_unit": None,
        "cleaned_quantity": None,
        "confidence": 0.86,
        "warnings": [],
    }
    payload.update(updates)
    return NormalizedReceiptItem.model_validate(payload)


def _read_item(**updates) -> TransactionItemRead:
    payload = {
        "id": uuid.uuid4(),
        "created_at": dt.datetime.now(dt.UTC),
        "updated_at": dt.datetime.now(dt.UTC),
        "transaction_id": uuid.uuid4(),
        "line_no": 1,
        "description": "RAW ITEM",
        "description_lang": "sr",
        "qty": Decimal("1"),
        "unit": "pc",
        "unit_price": Decimal("1.0000"),
        "amount": Decimal("1.00"),
        "amount_before_discount": None,
        "discount_amount": None,
        "is_adjustment": False,
        "category_id": uuid.uuid4(),
        "raw_line": None,
    }
    payload.update(updates)
    return TransactionItemRead.model_validate(payload)


def test_normalized_item_schema_validates_and_compacts_attributes() -> None:
    item = NormalizedReceiptItem(
        raw_name="  BRAND   WIDGET 2PK ",
        translatable_name="widget",
        expanded_name="brand widget",
        normalized_display_name="brand widget",
        brand_name="BRAND",
        product_type="widget",
        category_hint="cleaning",
        preserve_terms=["BRAND", "BRAND", "  MODEL-X  "],
        attributes=NormalizedReceiptItemAttributes(package_size=" 2 pack ", color=" blue "),
        cleaned_unit="pc",
        cleaned_quantity=2,
        confidence=0.75,
        warnings=["  ambiguous size  "],
    )

    assert item.raw_name == "BRAND WIDGET 2PK"
    assert item.preserve_terms == ["BRAND", "MODEL-X"]
    assert item.attributes.compact_dump() == {"package_size": "2 pack", "color": "blue"}


def test_normalization_schema_rejects_price_fields() -> None:
    with pytest.raises(ValidationError):
        NormalizedReceiptItem.model_validate(
            {
                "raw_name": "ITEM",
                "price": "9.99",
                "confidence": 0.5,
            }
        )


def test_gemini_normalization_success_preserves_order_and_raw_names(monkeypatch) -> None:
    from app.services import item_normalization as service

    response = NormalizedReceiptItemsResponse(
        normalization_base_language="en",
        items=[
            _normalized(
                "BRAND COFFEE 250G",
                translatable_name="coffee",
                brand_name="BRAND",
                preserve_terms=["BRAND"],
                attributes={"package_size": "250 g"},
            ),
            _normalized(
                "XL BAG 2PK",
                translatable_name="large bag",
                attributes={"size": "XL", "package_size": "2 pack"},
            ),
        ],
    )
    fake_llm = _FakeStructuredLLM({"parsed": response})
    monkeypatch.setattr(service, "_build_structured_llm", lambda: fake_llm)

    result = service.normalize_receipt_items(
        receipt_id=str(uuid.uuid4()),
        attempt=1,
        extracted=_extracted([_item("BRAND COFFEE 250G"), _item("XL BAG 2PK")]),
    )

    assert result.succeeded is True
    assert [item.raw_name for item in result.items] == ["BRAND COFFEE 250G", "XL BAG 2PK"]
    assert result.items[0].brand_name == "BRAND"
    assert result.items[1].attributes.package_size == "2 pack"
    assert "Input JSON:" in fake_llm.messages[0].content


def test_gemini_normalization_accepts_whitespace_normalized_raw_name(monkeypatch) -> None:
    from app.services import item_normalization as service

    fake_llm = _FakeStructuredLLM(NormalizedReceiptItemsResponse(items=[_normalized("MILK 1L")]))
    monkeypatch.setattr(service, "_build_structured_llm", lambda: fake_llm)

    result = service.normalize_receipt_items(
        receipt_id=str(uuid.uuid4()),
        attempt=1,
        extracted=_extracted([_item("MILK   1L")]),
    )

    assert result.succeeded is True


def test_gemini_normalization_rejects_item_count_or_order_mismatch(monkeypatch) -> None:
    from app.services import item_normalization as service

    fake_llm = _FakeStructuredLLM(
        NormalizedReceiptItemsResponse(items=[_normalized("SECOND ITEM")])
    )
    monkeypatch.setattr(service, "_build_structured_llm", lambda: fake_llm)

    result = service.normalize_receipt_items(
        receipt_id=str(uuid.uuid4()),
        attempt=1,
        extracted=_extracted([_item("FIRST ITEM"), _item("SECOND ITEM")]),
    )

    assert result.status == service.NORMALIZATION_STATUS_INVALID
    assert result.items == []


def test_gemini_normalization_failure_falls_back(monkeypatch) -> None:
    from app.services import item_normalization as service

    fake_llm = _FakeStructuredLLM(TimeoutError("timeout"))
    monkeypatch.setattr(service, "_build_structured_llm", lambda: fake_llm)

    result = service.normalize_receipt_items(
        receipt_id=str(uuid.uuid4()),
        attempt=1,
        extracted=_extracted([_item("ANY ITEM")]),
    )

    assert result.status == service.NORMALIZATION_STATUS_FAILED
    assert result.items == []


def test_kill_switch_and_max_item_limit_skip_gemini(monkeypatch) -> None:
    from app.services import item_normalization as service

    monkeypatch.setenv("ITEM_NORMALIZATION_ENABLED", "false")
    monkeypatch.setattr(
        service,
        "_build_structured_llm",
        lambda: pytest.fail("Gemini should not be called when disabled"),
    )

    disabled = service.normalize_receipt_items(
        receipt_id=str(uuid.uuid4()),
        attempt=1,
        extracted=_extracted([_item("ANY ITEM")]),
    )

    assert disabled.status == service.NORMALIZATION_STATUS_DISABLED

    monkeypatch.setenv("ITEM_NORMALIZATION_ENABLED", "true")
    monkeypatch.setenv("ITEM_NORMALIZATION_MAX_ITEMS", "1")
    skipped = service.normalize_receipt_items(
        receipt_id=str(uuid.uuid4()),
        attempt=1,
        extracted=_extracted([_item("ONE"), _item("TWO")]),
    )

    assert skipped.status == service.NORMALIZATION_STATUS_SKIPPED_MAX_ITEMS


def test_item_normalization_timeout_setting_is_used(monkeypatch) -> None:
    from app.core.config import item_normalization_settings

    monkeypatch.setenv("ITEM_NORMALIZATION_TIMEOUT_SECONDS", "7.5")

    assert item_normalization_settings.ITEM_NORMALIZATION_TIMEOUT_SECONDS == 7.5


def test_api_translation_source_prefers_normalized_name_unless_user_edited() -> None:
    from app.services.transactions import read_models as router

    normalized_item = _read_item(
        description="RAW ITEM",
        raw_name="RAW ITEM",
        translatable_name="clean item",
        normalization_base_language="en",
    )
    edited_item = _read_item(
        description="My custom name",
        raw_name="RAW ITEM",
        translatable_name="clean item",
        normalization_base_language="en",
    )
    legacy_item = _read_item(
        description="Legacy item",
        raw_name=None,
        translatable_name=None,
        description_lang="de",
    )

    assert router._preferred_item_translation_source(normalized_item) == ("clean item", "en")
    assert router._preferred_item_translation_source(edited_item) == ("My custom name", "sr")
    assert router._preferred_item_translation_source(legacy_item) == ("Legacy item", "de")


def test_migration_uses_current_head_and_jsonb() -> None:
    migration = Path(
        "app/alembic/versions/4d8f2c7b1a6e_add_item_normalization_fields.py"
    ).read_text(encoding="utf-8")

    assert 'down_revision: str | Sequence[str] | None = "2e9c4b1a7d8f"' in migration
    assert "postgresql.JSONB" in migration
    assert "normalization_base_language" in migration
