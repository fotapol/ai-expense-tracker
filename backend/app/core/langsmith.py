"""LangSmith helpers for production-safe receipt tracing."""

from __future__ import annotations

from contextlib import nullcontext
from typing import Any

from app.core.config import app_settings, observability_settings


def langsmith_tracing_enabled() -> bool:
    return observability_settings.LANGSMITH_TRACING and bool(observability_settings.LANGSMITH_API_KEY)


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
