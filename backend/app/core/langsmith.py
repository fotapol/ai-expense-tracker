"""LangSmith helpers for production-safe receipt tracing."""

from __future__ import annotations

from collections.abc import Mapping
from contextlib import nullcontext
from typing import Any

from app.core.config import app_settings, observability_settings


def langsmith_tracing_enabled() -> bool:
    return observability_settings.LANGSMITH_TRACING and bool(
        observability_settings.LANGSMITH_API_KEY
    )


def build_receipt_trace_context(
    *,
    receipt_id: str,
    attempt: int,
    mime_type: str,
    image_size_bytes: int,
    transaction_category_count: int,
    item_category_count: int,
):
    """Return a tracing context manager or a no-op context when disabled."""

    if not langsmith_tracing_enabled():
        return nullcontext()

    import langsmith as ls

    metadata = {
        "environment": app_settings.APP_ENV,
        "receipt_id": receipt_id,
        "attempt": attempt,
        "mime_type": mime_type,
        "image_size_bytes": image_size_bytes,
        "transaction_category_count": transaction_category_count,
        "item_category_count": item_category_count,
        "sensitive_payload_redacted": True,
    }
    return ls.tracing_context(
        enabled=True,
        project_name=observability_settings.LANGSMITH_PROJECT,
        metadata=metadata,
        tags=["receipt-extraction", app_settings.APP_ENV],
    )


def build_receipt_trace_inputs(
    *,
    receipt_id: str,
    attempt: int,
    mime_type: str,
    image_size_bytes: int,
    transaction_category_count: int,
    item_category_count: int,
) -> dict[str, Any]:
    return {
        "receipt_id": receipt_id,
        "attempt": attempt,
        "mime_type": mime_type,
        "image_size_bytes": image_size_bytes,
        "transaction_category_count": transaction_category_count,
        "item_category_count": item_category_count,
        "input_redacted": True,
    }


def build_receipt_trace_outputs(
    *,
    provider: str,
    model_name: str,
    latency_ms: int,
    item_count: int,
    currency: str | None,
    warning_count: int,
    token_usage: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "provider": provider,
        "model_name": model_name,
        "latency_ms": latency_ms,
        "item_count": item_count,
        "currency": currency,
        "warning_count": warning_count,
        "output_redacted": True,
    }
    if token_usage:
        payload["token_usage"] = token_usage
    return payload


def extract_langchain_token_usage(raw_response: Any) -> dict[str, Any] | None:
    """Return LangSmith-safe token usage from a LangChain AIMessage-like response."""

    for attr_name in ("usage_metadata", "response_metadata"):
        metadata = getattr(raw_response, attr_name, None)
        if not isinstance(metadata, Mapping):
            continue

        usage = metadata.get("usage_metadata") if attr_name == "response_metadata" else metadata
        sanitized = _sanitize_usage_metadata(usage)
        if sanitized:
            return sanitized
    return None


def _sanitize_usage_metadata(value: Any) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        return {}

    sanitized: dict[str, Any] = {}
    for raw_key, raw_value in value.items():
        key = str(raw_key)
        if isinstance(raw_value, bool):
            continue
        if isinstance(raw_value, int | float):
            sanitized[key] = raw_value
        elif isinstance(raw_value, Mapping):
            nested = {
                str(nested_key): nested_value
                for nested_key, nested_value in raw_value.items()
                if not isinstance(nested_value, bool) and isinstance(nested_value, int | float)
            }
            if nested:
                sanitized[key] = nested
    return sanitized
