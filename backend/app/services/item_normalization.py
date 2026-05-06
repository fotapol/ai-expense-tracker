"""Gemini-backed receipt item name normalization."""

from __future__ import annotations

import json
import logging
import time
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from app.core.config import item_normalization_settings, llm_settings
from app.schemas.extraction import ExtractedReceiptData, ExtractedTransactionItem
from app.schemas.item_normalization import (
    NormalizedReceiptItem,
    NormalizedReceiptItemsResponse,
    whitespace_normalized_text,
)

logger = logging.getLogger(__name__)

NORMALIZATION_SOURCE_GEMINI = "gemini"
NORMALIZATION_STATUS_DISABLED = "disabled"
NORMALIZATION_STATUS_FAILED = "failed"
NORMALIZATION_STATUS_INVALID = "invalid"
NORMALIZATION_STATUS_NORMALIZED = "normalized"
NORMALIZATION_STATUS_SKIPPED_MAX_ITEMS = "skipped_max_items"
NORMALIZATION_STATUS_SKIPPED_EMPTY = "skipped_empty"


@dataclass(frozen=True)
class ItemNormalizationResult:
    """Safe normalization outcome consumed by the receipt worker."""

    status: str
    items: list[NormalizedReceiptItem]
    normalization_base_language: str = "en"
    source: str | None = None
    warnings: list[str] | None = None
    latency_ms: int | None = None
    token_usage: dict[str, Any] | None = None

    @property
    def succeeded(self) -> bool:
        return self.status == NORMALIZATION_STATUS_NORMALIZED


def _decimal_to_json(value: Decimal | None) -> str | None:
    if value is None:
        return None
    return format(value, "f")


def _build_item_payload(item: ExtractedTransactionItem, index: int) -> dict[str, Any]:
    return {
        "index": index,
        "raw_name": item.description,
        "quantity": _decimal_to_json(item.qty),
        "unit": item.unit,
        "price": _decimal_to_json(item.amount),
        "price_per_unit": _decimal_to_json(item.unit_price),
        "category_code": item.category_code,
        "raw_line_present": bool(item.raw_line),
    }


def _build_prompt(
    *,
    extracted: ExtractedReceiptData,
    item_payloads: list[dict[str, Any]],
    normalization_base_language: str,
) -> str:
    payload = {
        "merchant_name": extracted.merchant_name,
        "receipt_country": extracted.merchant_country,
        "receipt_language": extracted.receipt_language,
        "currency": extracted.currency,
        "normalization_base_language": normalization_base_language,
        "items": item_payloads,
    }
    payload_json = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    return f"""You normalize extracted receipt item names after OCR/vision extraction.

Your task is to produce one normalized object for each input item, in the same order.
Return exactly the requested structured schema. Do not add, remove, merge, split, or reorder items.

Normalize noisy receipt item names into clean, compact, expanded product names that are easier for
an offline translation layer to translate. Keep the output generally language-neutral, using the
configured base language for translatable_name when a clean base-language wording is possible.

Rules:
- Keep raw_name unchanged except for harmless whitespace normalization.
- translatable_name should be generic, expanded, and easy to translate.
- expanded_name may include clarified abbreviations when confidence is reasonable.
- normalized_display_name should be a clean fallback display name, not a target-language translation.
- Separate package size, unit, quantity, percentage, process type, flavor, variant, size, color,
  material, model, and similar details into attributes when present.
- Preserve real brand names, store/private-label names, model names, product series, legal product
  names, and ambiguous proper nouns in preserve_terms.
- Do not translate or invent preserved brand/model/proper names.
- Do not hallucinate missing brands or attributes.
- If an abbreviation or term is ambiguous, preserve it and add a warning instead of guessing.
- category_hint is non-binding metadata only. Do not alter or override the provided category.
- Do not change prices, totals, quantities, units, categories, or item count.

Input JSON:
{payload_json}
"""


def _build_structured_llm():
    from langchain_google_genai import ChatGoogleGenerativeAI

    model = ChatGoogleGenerativeAI(
        model=llm_settings.MODEL_NAME,
        google_api_key=llm_settings.GOOGLE_API_KEY,
        temperature=0,
        request_timeout=item_normalization_settings.ITEM_NORMALIZATION_TIMEOUT_SECONDS,
        retries=1,
    )
    return model.with_structured_output(
        NormalizedReceiptItemsResponse,
        include_raw=True,
    )


def _parse_structured_response(raw_response: Any) -> tuple[NormalizedReceiptItemsResponse, Any]:
    if isinstance(raw_response, NormalizedReceiptItemsResponse):
        return raw_response, None
    if isinstance(raw_response, dict):
        parsed = raw_response.get("parsed")
        if isinstance(parsed, NormalizedReceiptItemsResponse):
            return parsed, raw_response.get("raw")
        if isinstance(parsed, dict):
            return NormalizedReceiptItemsResponse.model_validate(parsed), raw_response.get("raw")
        return NormalizedReceiptItemsResponse.model_validate(raw_response), raw_response.get("raw")
    return NormalizedReceiptItemsResponse.model_validate(raw_response), None


def _extract_token_usage(raw_response: Any) -> dict[str, Any] | None:
    for attr_name in ("usage_metadata", "response_metadata"):
        metadata = getattr(raw_response, attr_name, None)
        if not isinstance(metadata, dict):
            continue
        usage = metadata.get("usage_metadata") if attr_name == "response_metadata" else metadata
        if isinstance(usage, dict) and usage:
            return {
                key: value
                for key, value in usage.items()
                if isinstance(value, int | float | str | bool)
            }
    return None


def _raw_names_match(
    input_items: list[ExtractedTransactionItem], output_items: list[NormalizedReceiptItem]
) -> bool:
    if len(input_items) != len(output_items):
        return False
    for input_item, output_item in zip(input_items, output_items, strict=True):
        if whitespace_normalized_text(input_item.description) != output_item.raw_name:
            return False
    return True


def normalize_receipt_items(
    *,
    receipt_id: str,
    attempt: int,
    extracted: ExtractedReceiptData,
) -> ItemNormalizationResult:
    """Normalize item names with Gemini and return a fail-open result."""

    item_count = len(extracted.items)
    base_language = item_normalization_settings.NORMALIZATION_BASE_LANGUAGE

    if not item_normalization_settings.ITEM_NORMALIZATION_ENABLED:
        return ItemNormalizationResult(
            status=NORMALIZATION_STATUS_DISABLED,
            items=[],
            normalization_base_language=base_language,
        )
    if item_count == 0:
        return ItemNormalizationResult(
            status=NORMALIZATION_STATUS_SKIPPED_EMPTY,
            items=[],
            normalization_base_language=base_language,
        )

    max_items = item_normalization_settings.ITEM_NORMALIZATION_MAX_ITEMS
    if item_count > max_items:
        logger.info(
            "Receipt item normalization skipped because item count exceeds limit.",
            extra={
                "service": "worker",
                "event": "item_normalization_skipped_max_items",
                "receipt_id": receipt_id,
                "attempt": attempt,
                "item_count": item_count,
                "max_items": max_items,
            },
        )
        return ItemNormalizationResult(
            status=NORMALIZATION_STATUS_SKIPPED_MAX_ITEMS,
            items=[],
            normalization_base_language=base_language,
            warnings=[f"item_count_exceeds_limit:{item_count}>{max_items}"],
        )

    try:
        from langchain_core.messages import HumanMessage

        item_payloads = [
            _build_item_payload(item, index) for index, item in enumerate(extracted.items, start=1)
        ]
        prompt = _build_prompt(
            extracted=extracted,
            item_payloads=item_payloads,
            normalization_base_language=base_language,
        )
        structured_llm = _build_structured_llm()

        start = time.monotonic()
        raw_response = structured_llm.invoke([HumanMessage(content=prompt)])
        latency_ms = int((time.monotonic() - start) * 1000)
        parsed_response, raw_model_response = _parse_structured_response(raw_response)

        if not _raw_names_match(extracted.items, parsed_response.items):
            logger.warning(
                "Receipt item normalization returned invalid item count or raw-name order.",
                extra={
                    "service": "worker",
                    "event": "item_normalization_invalid",
                    "receipt_id": receipt_id,
                    "attempt": attempt,
                    "item_count": item_count,
                    "output_item_count": len(parsed_response.items),
                },
            )
            return ItemNormalizationResult(
                status=NORMALIZATION_STATUS_INVALID,
                items=[],
                normalization_base_language=base_language,
                warnings=["item_count_or_raw_name_mismatch"],
                latency_ms=latency_ms,
                token_usage=_extract_token_usage(raw_model_response),
            )

        token_usage = _extract_token_usage(raw_model_response)
        logger.info(
            "Receipt item normalization completed.",
            extra={
                "service": "worker",
                "event": "item_normalization_completed",
                "receipt_id": receipt_id,
                "attempt": attempt,
                "item_count": item_count,
                "latency_ms": latency_ms,
                "model": llm_settings.MODEL_NAME,
                "token_usage": token_usage,
            },
        )
        return ItemNormalizationResult(
            status=NORMALIZATION_STATUS_NORMALIZED,
            items=parsed_response.items,
            normalization_base_language=parsed_response.normalization_base_language
            or base_language,
            source=NORMALIZATION_SOURCE_GEMINI,
            latency_ms=latency_ms,
            token_usage=token_usage,
        )
    except Exception as exc:
        logger.warning(
            "Receipt item normalization failed; continuing with raw item names.",
            extra={
                "service": "worker",
                "event": "item_normalization_failed",
                "receipt_id": receipt_id,
                "attempt": attempt,
                "item_count": item_count,
                "error_type": type(exc).__name__,
            },
        )
        return ItemNormalizationResult(
            status=NORMALIZATION_STATUS_FAILED,
            items=[],
            normalization_base_language=base_language,
            warnings=[type(exc).__name__],
        )
