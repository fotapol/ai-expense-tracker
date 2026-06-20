"""Async RabbitMQ consumer that processes receipt images with a Vision LLM.

Run as a standalone process:
    python -m app.worker.receipt_processor

Flow per message:
1. Load Receipt row from DB
2. Idempotency guard — skip if already COMPLETED or has ReceiptExtraction
3. Set status → PROCESSING
4. Download image from MinIO
5. Call Gemini Vision LLM with structured output
6. Validate response with ExtractedReceiptData
7. Save ReceiptExtraction
8. Create Transaction + TransactionItems
9. Set status → COMPLETED (or FAILED on error)
"""

import asyncio
import base64
import datetime as dt
import json
import logging
import time
import uuid
from decimal import Decimal
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import aio_pika
from sqlalchemy import case, or_
from sqlmodel import Session, select

# ---------------------------------------------------------------------------
# Bootstrap: ensure the *backend* package is importable when invoked with
# ``python -m app.worker.receipt_processor`` from the repo-root workdir.
# ---------------------------------------------------------------------------
from app.core.config import llm_settings, rabbitmq_settings, worker_settings
from app.core.db import check_database_health, engine
from app.core.langsmith import (
    build_receipt_trace_context,
    build_receipt_trace_inputs,
    build_receipt_trace_outputs,
    extract_langchain_token_usage,
    langsmith_tracing_enabled,
)
from app.core.logging import configure_logging
from app.core.metrics import (
    record_receipt_extraction,
    record_worker_job_completed,
    record_worker_job_failed,
    record_worker_job_started,
    record_worker_retry_scheduled,
    set_worker_dependency_health,
    start_worker_metrics_server,
)
from app.core.minio import download_object, ensure_bucket
from app.models.receipts.receipt import Receipt
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import CategoryScope, ReceiptStatus, TransactionSource
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.schemas.extraction import (
    ExtractedReceiptData,
    LineTotalMismatchWarning,
    ReceiptTotalMismatchWarning,
)
from app.schemas.shared import quantize_amount
from app.services.item_normalization import normalize_receipt_items

configure_logging(service_name="worker")
logger = logging.getLogger(__name__)

RABBITMQ_URL: str = rabbitmq_settings.RABBITMQ_URL
QUEUE_NAME = rabbitmq_settings.RECEIPT_EXTRACTION_QUEUE_NAME
PROCESSING_STALE_AFTER = dt.timedelta(minutes=worker_settings.PROCESSING_STALE_AFTER_MINUTES)
MAX_RETRIES = worker_settings.MAX_RETRIES


def _redact_url_credentials(raw_url: str) -> str:
    parsed = urlsplit(raw_url)
    if not parsed.username and not parsed.password:
        return raw_url
    host = parsed.hostname or ""
    if parsed.port is not None:
        host = f"{host}:{parsed.port}"
    return urlunsplit((parsed.scheme, host, parsed.path, parsed.query, parsed.fragment))


# ---------------------------------------------------------------------------
# Vision LLM call
# ---------------------------------------------------------------------------


def _parse_structured_receipt_response(raw_response: Any) -> tuple[ExtractedReceiptData, Any]:
    if isinstance(raw_response, ExtractedReceiptData):
        return raw_response, None
    if isinstance(raw_response, dict):
        parsed = raw_response.get("parsed")
        raw_message = raw_response.get("raw")
        if isinstance(parsed, ExtractedReceiptData):
            return parsed, raw_message
        if isinstance(parsed, dict):
            return ExtractedReceiptData.model_validate(parsed), raw_message
        return ExtractedReceiptData.model_validate(raw_response), raw_message
    return ExtractedReceiptData.model_validate(raw_response), None


def _call_vision_llm(
    *,
    receipt_id: str,
    attempt: int,
    image_bytes: bytes,
    mime_type: str,
    transaction_category_list: list[str],
    item_subcategory_list: list[str],
) -> dict:
    """Send image to Gemini and get structured receipt data back via LangChain structured output.

    Returns the extracted dict from the LLM along with metadata.
    """
    from langchain_core.messages import HumanMessage
    from langchain_google_genai import ChatGoogleGenerativeAI

    model = ChatGoogleGenerativeAI(
        model=llm_settings.MODEL_NAME,
        google_api_key=llm_settings.GOOGLE_API_KEY,
        temperature=0,
    )

    # Use native structured output capability
    structured_llm = model.with_structured_output(
        ExtractedReceiptData,
        include_raw=True,
    )

    b64_image = base64.b64encode(image_bytes).decode("utf-8")

    tx_cat_lines = "\n".join(f"- {c}" for c in transaction_category_list)
    item_cat_lines = "\n".join(f"- {c}" for c in item_subcategory_list)

    prompt = f"""You are an expert accounting system and receipt parser. 
Analyze this receipt image and extract structured data accurately.

For the `occurred_at` field, extract BOTH the date AND the exact time (HH:mm) if it is visible on the receipt. If only the date is visible, extract just the date.
For the `receipt_language` field, return the best-known language code of the receipt text in lowercase short form (for example: en, de, fr, sr, es).
Set the `warnings` field to an empty list. The backend computes strict warnings after extraction.

For `primary_category_code`, choose the single best code from this TRANSACTION category list:
{tx_cat_lines}

For every single `item` you extract, you MUST provide a `category_code`.
You must choose the best fitting ITEM subcategory ONLY from this list:
{item_cat_lines}

If no item subcategory matches confidently, use UNKNOWN_ITEM.

Line item discount handling is required:
- If the receipt shows a discount, promotion, loyalty saving, coupon, or
  "discounted price" line for an item, attach that saving to the item above it.
- Do not create separate items for discount/promotion rows.
- For discounted items, set `amount` to the final paid line amount after the
  discount, set `amount_before_discount` to the original line amount before the
  saving, and set `discount_amount` to a positive absolute saving.
- If both a regular price and a discounted/final price are visible, keep both
  values by using `amount_before_discount` and `discount_amount`.
- Include related discount text in `raw_line` when it helps explain the item.
"""

    message = HumanMessage(
        content=[
            {"type": "text", "text": prompt},
            {
                "type": "image_url",
                "image_url": {"url": f"data:{mime_type};base64,{b64_image}"},
            },
        ]
    )

    start = time.monotonic()
    trace_inputs = build_receipt_trace_inputs(
        receipt_id=receipt_id,
        attempt=attempt,
        mime_type=mime_type,
        image_size_bytes=len(image_bytes),
        transaction_category_count=len(transaction_category_list),
        item_category_count=len(item_subcategory_list),
    )
    if langsmith_tracing_enabled():
        import langsmith as ls

        with (
            build_receipt_trace_context(
                receipt_id=receipt_id,
                attempt=attempt,
                mime_type=mime_type,
                image_size_bytes=len(image_bytes),
                transaction_category_count=len(transaction_category_list),
                item_category_count=len(item_subcategory_list),
            ),
            ls.trace(
                name="receipt_vision_extract",
                run_type="llm",
                inputs=trace_inputs,
                metadata={
                    "ls_provider": "google_genai",
                    "ls_model_name": llm_settings.MODEL_NAME,
                    "sensitive_payload_redacted": True,
                },
            ) as run_tree,
        ):
            structured_response = structured_llm.invoke([message])
            extracted_model, raw_model_response = _parse_structured_receipt_response(
                structured_response
            )
            token_usage = extract_langchain_token_usage(raw_model_response)
            latency_ms = int((time.monotonic() - start) * 1000)
            if token_usage:
                run_tree.set(usage_metadata=token_usage)
            run_tree.end(
                outputs=build_receipt_trace_outputs(
                    provider="google",
                    model_name=llm_settings.MODEL_NAME,
                    latency_ms=latency_ms,
                    item_count=len(extracted_model.items),
                    currency=extracted_model.currency,
                    warning_count=len(extracted_model.warnings),
                    token_usage=token_usage,
                ),
            )
    else:
        structured_response = structured_llm.invoke([message])
        extracted_model, _raw_model_response = _parse_structured_receipt_response(
            structured_response
        )
    latency_ms = int((time.monotonic() - start) * 1000)

    return {
        "raw_json": extracted_model.model_dump(mode="json"),
        "provider": "google",
        "model_name": llm_settings.MODEL_NAME,
        "latency_ms": latency_ms,
        "item_count": len(extracted_model.items),
        "currency": extracted_model.currency,
        "warning_count": len(extracted_model.warnings),
    }


def _compute_extraction_warnings(extracted: ExtractedReceiptData) -> list:
    """Build strict extraction mismatch warnings."""

    warnings = []

    for idx, item in enumerate(extracted.items, start=1):
        if item.amount is None:
            continue

        expected_amount: Decimal | None = None
        discount_amount = item.discount_amount or Decimal("0")
        if item.amount_before_discount is not None and discount_amount >= Decimal("0"):
            expected_amount = quantize_amount(item.amount_before_discount - discount_amount)
        elif item.qty is not None and item.unit_price is not None:
            expected_amount = quantize_amount((item.qty * item.unit_price) - discount_amount)

        if expected_amount is None:
            continue

        extracted_amount = quantize_amount(item.amount)
        if expected_amount != extracted_amount:
            warnings.append(
                LineTotalMismatchWarning(
                    line_no=item.line_no or idx,
                    expected_amount=expected_amount,
                    extracted_amount=extracted_amount,
                    difference=quantize_amount(extracted_amount - expected_amount),
                )
            )

    if extracted.amount_total is not None:
        expected_total = quantize_amount(
            sum((item.amount or Decimal("0")) for item in extracted.items)
        )
        extracted_total = quantize_amount(extracted.amount_total)
        if expected_total != extracted_total:
            warnings.append(
                ReceiptTotalMismatchWarning(
                    expected_total=expected_total,
                    extracted_total=extracted_total,
                    difference=quantize_amount(extracted_total - expected_total),
                )
            )

    return warnings


def _normalize_extracted_item_discounts(
    extracted: ExtractedReceiptData,
) -> ExtractedReceiptData:
    """Backfill item discount fields from reliable receipt math.

    Vision models sometimes read the final paid item amount correctly but omit
    `discount_amount`. Keeping the final price is important for totals, but the
    editor also needs explicit discount fields to show the discount toggle.
    """

    normalized_items = []
    changed = False

    for item in extracted.items:
        amount = item.amount
        discount_amount = item.discount_amount
        amount_before_discount = item.amount_before_discount

        if amount is not None:
            if (
                (discount_amount is None or discount_amount <= Decimal("0"))
                and amount_before_discount is not None
                and amount_before_discount > amount
            ):
                discount_amount = quantize_amount(amount_before_discount - amount)

            if (
                amount_before_discount is None
                and discount_amount is not None
                and discount_amount > Decimal("0")
            ):
                amount_before_discount = quantize_amount(amount + discount_amount)

            if (
                (discount_amount is None or discount_amount <= Decimal("0"))
                and amount_before_discount is None
                and item.qty is not None
                and item.unit_price is not None
            ):
                candidate_before = quantize_amount(item.qty * item.unit_price)
                candidate_discount = quantize_amount(candidate_before - amount)
                if candidate_discount > Decimal("0.01"):
                    amount_before_discount = candidate_before
                    discount_amount = candidate_discount

        if (
            discount_amount != item.discount_amount
            or amount_before_discount != item.amount_before_discount
        ):
            item = item.model_copy(
                update={
                    "discount_amount": discount_amount,
                    "amount_before_discount": amount_before_discount,
                }
            )
            changed = True

        normalized_items.append(item)

    if not changed:
        return extracted

    return extracted.model_copy(update={"items": normalized_items})


# ---------------------------------------------------------------------------
# Category resolution helpers
# ---------------------------------------------------------------------------


def _get_or_create_global_category(
    session: Session,
    *,
    scope: CategoryScope,
    code: str,
    name: str,
    parent_id: uuid.UUID | None = None,
) -> Category:
    cat = session.exec(
        select(Category).where(
            Category.scope == scope,
            Category.code == code,
            Category.user_id.is_(None),
        )
    ).first()
    if cat is not None:
        cat.name = name
        cat.parent_id = parent_id
        cat.is_active = True
        session.add(cat)
        session.flush()
        session.refresh(cat)
        return cat

    cat = Category(
        scope=scope,
        code=code,
        name=name,
        parent_id=parent_id,
        user_id=None,
        is_custom=False,
    )
    session.add(cat)
    session.flush()
    session.refresh(cat)
    logger.info("Created fallback category scope=%s code=%s id=%s.", scope.value, code, cat.id)
    return cat


def _disabled_category_subquery(user_id: uuid.UUID):
    return select(UserHiddenCategory.category_id).where(
        UserHiddenCategory.user_id == user_id,
    )


def _resolve_category_with_scope(
    session: Session,
    *,
    scope: CategoryScope,
    user_id: uuid.UUID,
    code: str | None,
) -> Category | None:
    if not code:
        return None

    clean_code = code.strip().upper()
    candidates = session.exec(
        select(Category)
        .where(
            Category.scope == scope,
            Category.code == clean_code,
            Category.is_active,
            Category.id.notin_(_disabled_category_subquery(user_id)),
            or_(Category.user_id.is_(None), Category.user_id == user_id),
        )
        .order_by(
            case(
                (Category.user_id == user_id, 0),
                else_=1,
            )
        )
    ).all()
    return candidates[0] if candidates else None


def _get_uncategorized_category_id(session: Session) -> uuid.UUID:
    """Return the UUID of the global UNCATEGORIZED ITEM category."""
    other_item = _get_or_create_global_category(
        session,
        scope=CategoryScope.ITEM,
        code="OTHER",
        name="Other",
    )
    uncategorized = _get_or_create_global_category(
        session,
        scope=CategoryScope.ITEM,
        code="UNCATEGORIZED",
        name="Uncategorized",
        parent_id=other_item.id,
    )
    return uncategorized.id


def _get_other_transaction_category_id(session: Session) -> uuid.UUID:
    """Return the UUID of the global OTHER TRANSACTION category."""
    category = _get_or_create_global_category(
        session,
        scope=CategoryScope.TRANSACTION,
        code="OTHER",
        name="Other",
    )
    return category.id


def _resolve_item_category_id(
    session: Session,
    user_id: uuid.UUID,
    code: str | None,
    fallback_id: uuid.UUID,
) -> uuid.UUID:
    category = _resolve_category_with_scope(
        session,
        scope=CategoryScope.ITEM,
        user_id=user_id,
        code=code,
    )
    if category is None:
        return fallback_id
    return category.id


def _resolve_transaction_category_id(
    session: Session,
    user_id: uuid.UUID,
    code: str | None,
) -> uuid.UUID | None:
    category = _resolve_category_with_scope(
        session,
        scope=CategoryScope.TRANSACTION,
        user_id=user_id,
        code=code,
    )
    return category.id if category else None


def _derive_transaction_category_id_from_items(
    session: Session,
    user_id: uuid.UUID,
    resolved_item_category_ids: list[tuple[uuid.UUID, Decimal]],
) -> uuid.UUID | None:
    if not resolved_item_category_ids:
        return None

    item_category_ids = {category_id for category_id, _ in resolved_item_category_ids}
    categories = session.exec(select(Category).where(Category.id.in_(item_category_ids))).all()
    category_by_id = {cat.id: cat for cat in categories}

    parent_ids = {cat.parent_id for cat in categories if cat.parent_id is not None}
    parent_by_id: dict[uuid.UUID, Category] = {}
    if parent_ids:
        parents = session.exec(select(Category).where(Category.id.in_(parent_ids))).all()
        parent_by_id = {cat.id: cat for cat in parents}

    totals_by_parent_code: dict[str, Decimal] = {}
    for category_id, amount in resolved_item_category_ids:
        category = category_by_id.get(category_id)
        if category is None:
            continue
        if category.parent_id is not None and category.parent_id in parent_by_id:
            parent_code = parent_by_id[category.parent_id].code
        else:
            parent_code = category.code
        totals_by_parent_code[parent_code] = totals_by_parent_code.get(
            parent_code, Decimal("0")
        ) + (amount or Decimal("0"))

    if not totals_by_parent_code:
        return None

    best_parent_code = max(totals_by_parent_code.items(), key=lambda x: x[1])[0]
    return _resolve_transaction_category_id(session, user_id, best_parent_code)


def _resolve_category_id(session: Session, code: str | None, fallback_id: uuid.UUID) -> uuid.UUID:
    """Backward-compatible wrapper used by legacy scripts."""
    return _resolve_item_category_id(session, uuid.UUID(int=0), code, fallback_id)


def _receipt_processing_is_stale(
    receipt: Receipt,
    *,
    now: dt.datetime | None = None,
) -> bool:
    comparison_now = now or dt.datetime.now(dt.UTC)
    updated_at = getattr(receipt, "updated_at", None) or getattr(receipt, "created_at", None)
    if updated_at is None:
        return True
    if updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=dt.UTC)
    return comparison_now - updated_at >= PROCESSING_STALE_AFTER


def _reconcile_existing_processing_state(
    session: Session,
    *,
    receipt: Receipt,
    receipt_id: str,
    existing_extraction: ReceiptExtraction | None,
    existing_tx: Transaction | None,
) -> bool:
    if existing_tx is not None:
        if receipt.status != ReceiptStatus.COMPLETED or receipt.failure_reason:
            receipt.status = ReceiptStatus.COMPLETED
            receipt.failure_reason = None
            session.add(receipt)
            session.commit()
        logger.info(
            "Receipt %s already has transaction %s - treating duplicate job as completed.",
            receipt_id,
            existing_tx.id,
        )
        return True

    if existing_extraction is not None:
        failure_reason = (
            "Receipt extraction exists without a completed transaction. "
            "Please re-upload the receipt."
        )
        if receipt.status != ReceiptStatus.FAILED or receipt.failure_reason != failure_reason:
            receipt.status = ReceiptStatus.FAILED
            receipt.failure_reason = failure_reason
            session.add(receipt)
            session.commit()
        logger.warning(
            "Receipt %s already has an extraction but no transaction - marked FAILED for visibility.",
            receipt_id,
        )
        return True

    if receipt.status == ReceiptStatus.PROCESSING:
        if _receipt_processing_is_stale(receipt):
            logger.warning(
                "Receipt %s was left in PROCESSING since %s - retrying extraction.",
                receipt_id,
                getattr(receipt, "updated_at", None),
            )
            return False
        logger.info(
            "Receipt %s is already PROCESSING - skipping duplicate redelivery.",
            receipt_id,
        )
        return True

    if receipt.status == ReceiptStatus.COMPLETED:
        logger.info(
            "Receipt %s is already COMPLETED with no additional work required.",
            receipt_id,
        )
        return True

    return False


# ---------------------------------------------------------------------------
# Core processing logic
# ---------------------------------------------------------------------------


def process_receipt(receipt_id: str) -> None:
    """Process a single receipt — called per RabbitMQ message."""
    with Session(engine) as session:
        receipt = session.exec(
            select(Receipt).where(Receipt.id == uuid.UUID(receipt_id)).with_for_update()
        ).first()

        if receipt is None:
            logger.error("Receipt %s not found — skipping.", receipt_id)
            return

        # --- Idempotency guard -----------------------------------------------
        existing_extraction = session.exec(
            select(ReceiptExtraction).where(ReceiptExtraction.receipt_id == receipt.id)
        ).first()
        existing_tx = session.exec(
            select(Transaction).where(Transaction.receipt_id == receipt.id)
        ).first()
        if _reconcile_existing_processing_state(
            session,
            receipt=receipt,
            receipt_id=receipt_id,
            existing_extraction=existing_extraction,
            existing_tx=existing_tx,
        ):
            return

        # --- Mark PROCESSING -------------------------------------------------
        receipt.status = ReceiptStatus.PROCESSING
        receipt.processing_attempt += 1
        session.add(receipt)
        session.commit()

        record_worker_job_started()
        started_at = time.monotonic()
        logger.info(
            "Started extraction job.",
            extra={
                "service": "worker",
                "event": "receipt_job_started",
                "receipt_id": receipt_id,
                "attempt": receipt.processing_attempt,
                "max_retries": MAX_RETRIES,
            },
        )

        try:
            # --- Download image from MinIO -----------------------------------
            logger.info(
                "Downloading receipt object.",
                extra={
                    "service": "worker",
                    "event": "receipt_download_started",
                    "receipt_id": receipt_id,
                    "storage_bucket": receipt.storage_bucket,
                },
            )
            image_bytes = download_object(key=receipt.storage_key, bucket=receipt.storage_bucket)
            logger.info(
                "Receipt object downloaded.",
                extra={
                    "service": "worker",
                    "event": "receipt_download_completed",
                    "receipt_id": receipt_id,
                    "byte_count": len(image_bytes),
                },
            )

            # --- Call Vision LLM ---------------------------------------------
            logger.info(
                "Calling receipt extraction model.",
                extra={
                    "service": "worker",
                    "event": "receipt_extraction_started",
                    "receipt_id": receipt_id,
                    "attempt": receipt.processing_attempt,
                    "provider": llm_settings.PROVIDER,
                    "model_name": llm_settings.MODEL_NAME,
                },
            )

            tx_category_codes = session.exec(
                select(Category.code).where(
                    Category.scope == CategoryScope.TRANSACTION,
                    Category.is_active,
                    Category.parent_id.is_(None),
                    Category.id.notin_(_disabled_category_subquery(receipt.user_id)),
                    or_(Category.user_id.is_(None), Category.user_id == receipt.user_id),
                )
            ).all()
            if not tx_category_codes:
                tx_category_codes = ["OTHER"]

            item_subcategory_codes = session.exec(
                select(Category.code).where(
                    Category.scope == CategoryScope.ITEM,
                    Category.is_active,
                    Category.parent_id.is_not(None),
                    Category.code != "UNCATEGORIZED",
                    Category.id.notin_(_disabled_category_subquery(receipt.user_id)),
                    or_(Category.user_id.is_(None), Category.user_id == receipt.user_id),
                )
            ).all()
            if not item_subcategory_codes:
                item_subcategory_codes = ["UNKNOWN_ITEM"]

            logger.info(
                "Using %d transaction categories and %d item subcategories for LLM prompt.",
                len(tx_category_codes),
                len(item_subcategory_codes),
            )

            llm_started_at = time.monotonic()
            try:
                llm_result = _call_vision_llm(
                    receipt_id=receipt_id,
                    attempt=receipt.processing_attempt,
                    image_bytes=image_bytes,
                    mime_type=receipt.mime_type,
                    transaction_category_list=tx_category_codes,
                    item_subcategory_list=item_subcategory_codes,
                )
                record_receipt_extraction(
                    provider=llm_result["provider"],
                    model=llm_result["model_name"],
                    success=True,
                    latency_ms=llm_result["latency_ms"],
                    item_count=llm_result.get("item_count"),
                )
            except Exception:
                record_receipt_extraction(
                    provider=llm_settings.PROVIDER,
                    model=llm_settings.MODEL_NAME,
                    success=False,
                    latency_ms=int((time.monotonic() - llm_started_at) * 1000),
                )
                raise
            raw_json = llm_result["raw_json"]

            # --- Validate with Pydantic --------------------------------------
            extracted = ExtractedReceiptData.model_validate(raw_json)
            extracted = _normalize_extracted_item_discounts(extracted)
            computed_warnings = _compute_extraction_warnings(extracted)
            if computed_warnings:
                extracted = extracted.model_copy(
                    update={"warnings": [*extracted.warnings, *computed_warnings]}
                )

            normalization_result = normalize_receipt_items(
                receipt_id=receipt_id,
                attempt=receipt.processing_attempt,
                extracted=extracted,
            )

            # --- Save ReceiptExtraction --------------------------------------
            extraction = ReceiptExtraction(
                receipt_id=receipt.id,
                provider=llm_result["provider"],
                model_name=llm_result["model_name"],
                structured_json=extracted.model_dump(mode="json"),
                raw_json=raw_json,
                latency_ms=llm_result["latency_ms"],
                prompt_version="v1",
            )
            session.add(extraction)

            # --- Resolve categories ------------------------------------------
            uncategorized_id = _get_uncategorized_category_id(session)
            resolved_items: list[tuple[int, object, uuid.UUID]] = []
            resolved_item_amounts: list[tuple[uuid.UUID, Decimal]] = []
            for idx, item in enumerate(extracted.items, start=1):
                resolved_category_id = _resolve_item_category_id(
                    session,
                    user_id=receipt.user_id,
                    code=item.category_code,
                    fallback_id=uncategorized_id,
                )
                resolved_items.append((item.line_no or idx, item, resolved_category_id))
                resolved_item_amounts.append((resolved_category_id, item.amount or Decimal("0")))

            transaction_category_id = _resolve_transaction_category_id(
                session,
                user_id=receipt.user_id,
                code=extracted.primary_category_code,
            )
            if transaction_category_id is None:
                transaction_category_id = _derive_transaction_category_id_from_items(
                    session,
                    user_id=receipt.user_id,
                    resolved_item_category_ids=resolved_item_amounts,
                )
            if transaction_category_id is None:
                transaction_category_id = _get_other_transaction_category_id(session)

            # --- Create Transaction ------------------------------------------
            transaction = Transaction(
                user_id=receipt.user_id,
                receipt_id=receipt.id,
                occurred_at=extracted.occurred_at,
                amount_total=extracted.amount_total,
                currency=extracted.currency,
                merchant_name=extracted.merchant_name,
                category_id=transaction_category_id,
                source=TransactionSource.RECEIPT,
                status="DRAFT",
                created_by_user_id=receipt.user_id,
                owner_user_id=receipt.user_id,
            )
            session.add(transaction)
            session.commit()
            session.refresh(transaction)

            # --- Create TransactionItems -------------------------------------
            for item_index, (line_no, item, cat_id) in enumerate(resolved_items):
                normalized_item = (
                    normalization_result.items[item_index]
                    if normalization_result.succeeded
                    and item_index < len(normalization_result.items)
                    else None
                )
                normalization_warnings = (
                    normalized_item.warnings
                    if normalized_item is not None and normalized_item.warnings
                    else normalization_result.warnings
                )
                ti = TransactionItem(
                    transaction_id=transaction.id,
                    line_no=line_no,
                    description=item.description,
                    description_lang=extracted.receipt_language,
                    raw_name=item.description,
                    translatable_name=(
                        normalized_item.translatable_name if normalized_item is not None else None
                    ),
                    expanded_name=normalized_item.expanded_name
                    if normalized_item is not None
                    else None,
                    normalized_display_name=(
                        normalized_item.normalized_display_name
                        if normalized_item is not None
                        else None
                    ),
                    normalization_base_language=normalization_result.normalization_base_language,
                    brand_name=normalized_item.brand_name if normalized_item is not None else None,
                    product_type=normalized_item.product_type
                    if normalized_item is not None
                    else None,
                    category_hint=normalized_item.category_hint
                    if normalized_item is not None
                    else None,
                    item_attributes_json=(
                        normalized_item.attributes.compact_dump()
                        if normalized_item is not None
                        else None
                    ),
                    preserve_terms_json=(
                        normalized_item.preserve_terms
                        if normalized_item is not None and normalized_item.preserve_terms
                        else None
                    ),
                    normalization_source=normalization_result.source,
                    normalization_status=normalization_result.status,
                    normalization_confidence=(
                        normalized_item.confidence if normalized_item is not None else None
                    ),
                    normalization_warnings_json=normalization_warnings or None,
                    qty=item.qty,
                    unit=item.unit,
                    unit_price=item.unit_price,
                    amount=item.amount,
                    amount_before_discount=item.amount_before_discount,
                    discount_amount=item.discount_amount,
                    is_adjustment=item.is_adjustment,
                    category_id=cat_id,
                    raw_line=item.raw_line,
                )
                session.add(ti)

            # --- Mark COMPLETED ----------------------------------------------
            receipt.status = ReceiptStatus.COMPLETED
            receipt.failure_reason = None
            session.add(receipt)
            session.commit()
            record_worker_job_completed(duration_seconds=time.monotonic() - started_at)
            logger.info(
                "Receipt processed successfully.",
                extra={
                    "service": "worker",
                    "event": "receipt_job_completed",
                    "receipt_id": receipt_id,
                    "transaction_id": str(transaction.id),
                    "item_count": len(extracted.items),
                },
            )

        except Exception:
            session.rollback()
            record_worker_job_failed(
                reason="processing",
                duration_seconds=time.monotonic() - started_at,
            )
            logger.exception(
                "Receipt processing failed.",
                extra={
                    "service": "worker",
                    "event": "receipt_job_failed",
                    "receipt_id": receipt_id,
                    "attempt": receipt.processing_attempt,
                    "max_retries": MAX_RETRIES,
                },
            )
            # Re-open session state after rollback
            session.refresh(receipt)

            if receipt.processing_attempt < MAX_RETRIES:
                record_worker_retry_scheduled()
                logger.warning(
                    "Scheduling receipt retry.",
                    extra={
                        "service": "worker",
                        "event": "receipt_retry_scheduled",
                        "receipt_id": receipt_id,
                        "attempt": receipt.processing_attempt,
                    },
                )
                receipt.status = ReceiptStatus.UPLOADED
                receipt.failure_reason = None
                session.add(receipt)
                session.commit()
                time.sleep(worker_settings.RETRY_BACKOFF_SECONDS)  # brief backoff before redelivery
                raise  # trigger aio_pika Nack and requeue

            logger.error(
                "Receipt retries exhausted.",
                extra={
                    "service": "worker",
                    "event": "receipt_retry_exhausted",
                    "receipt_id": receipt_id,
                    "attempt": receipt.processing_attempt,
                    "max_retries": MAX_RETRIES,
                },
            )
            receipt.status = ReceiptStatus.FAILED
            # Store a user-safe message — the full traceback is already
            # captured by logger.exception() above for operator debugging.
            receipt.failure_reason = (
                "We couldn't extract data from this receipt. "
                "Please try uploading a clearer image, or add the transaction manually."
            )
            session.add(receipt)
            session.commit()


# ---------------------------------------------------------------------------
# RabbitMQ consumer loop
# ---------------------------------------------------------------------------


async def main() -> None:
    """Connect to RabbitMQ and consume the receipt_extraction queue."""
    start_worker_metrics_server()
    logger.info("Worker starting — ensuring S3 bucket exists...")
    ensure_bucket()
    set_worker_dependency_health(dependency="s3", is_up=True)
    set_worker_dependency_health(dependency="database", is_up=check_database_health())

    logger.info("Connecting to RabbitMQ at %s ...", _redact_url_credentials(RABBITMQ_URL))
    connection = await aio_pika.connect_robust(RABBITMQ_URL)
    set_worker_dependency_health(dependency="rabbitmq", is_up=True)
    channel = await connection.channel()
    await channel.set_qos(prefetch_count=1)

    queue = await channel.declare_queue(QUEUE_NAME, durable=True)
    logger.info("Listening on queue '%s' ...", QUEUE_NAME)

    async with queue.iterator() as queue_iter:
        async for message in queue_iter:
            await _handle_worker_message(message)


async def _handle_worker_message(message) -> None:
    """Process one queue message while preserving RabbitMQ retry semantics."""

    try:
        body = json.loads(message.body.decode())
        receipt_id = body["receipt_id"]
    except (KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError):
        async with message.process(requeue=False):
            logger.exception(
                "Invalid worker message payload.",
                extra={
                    "service": "worker",
                    "event": "worker_message_invalid",
                },
            )
        return

    try:
        async with message.process(requeue=True):
            logger.info("Received job for receipt %s.", receipt_id)
            # Run the blocking processing in a thread.
            await asyncio.to_thread(process_receipt, receipt_id)
    except Exception:
        logger.exception(
            "Error handling worker message.",
            extra={
                "service": "worker",
                "event": "worker_message_failed",
            },
        )


if __name__ == "__main__":
    asyncio.run(main())
