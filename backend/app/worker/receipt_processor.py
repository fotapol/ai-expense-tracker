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
import json
import logging
import os
import sys
import time
import traceback
import uuid

import aio_pika
from sqlmodel import Session, select

# ---------------------------------------------------------------------------
# Bootstrap: ensure the *backend* package is importable when invoked with
# ``python -m app.worker.receipt_processor`` from the repo-root workdir.
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Local imports (after path setup)
# ---------------------------------------------------------------------------
from app.core.config import llm_settings, s3_settings  # noqa: E402
from app.core.db import engine  # noqa: E402
from app.core.minio import download_object, ensure_bucket  # noqa: E402
from app.models.receipts.receipt import Receipt  # noqa: E402
from app.models.receipts.receipt_extraction import ReceiptExtraction  # noqa: E402
from app.models.shared.enums import CategoryScope, ReceiptStatus, TransactionSource  # noqa: E402
from app.models.taxonomy.category import Category  # noqa: E402
from app.models.transactions.transaction import Transaction  # noqa: E402
from app.models.transactions.transaction_item import TransactionItem  # noqa: E402
from app.schemas.extraction import ExtractedReceiptData  # noqa: E402

RABBITMQ_URL: str = os.environ.get("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672/")
QUEUE_NAME = "receipt_extraction"


# ---------------------------------------------------------------------------
# Vision LLM call
# ---------------------------------------------------------------------------

def _call_vision_llm(image_bytes: bytes, mime_type: str) -> dict:
    """Send image to Gemini and get structured receipt data back via LangChain structured output.

    Returns the extracted dict from the LLM along with metadata.
    """
    from langchain_google_genai import ChatGoogleGenerativeAI
    from langchain_core.messages import HumanMessage

    model = ChatGoogleGenerativeAI(
        model=llm_settings.MODEL_NAME,
        google_api_key=llm_settings.GOOGLE_API_KEY,
        temperature=0,
    )

    # Use native structured output capability
    structured_llm = model.with_structured_output(ExtractedReceiptData)

    b64_image = base64.b64encode(image_bytes).decode("utf-8")

    prompt = """You are an expert accounting system and receipt parser. 
Analyze this receipt image and extract structured data accurately.

For every single `item` you extract, you MUST provide a `category_code`.
You must choose the best fitting category ONLY from the following list:
- FOOD
- CLOTHING
- TRANSPORT
- UTILITIES
- HEALTH
- ENTERTAINMENT
- HOME
- ELECTRONICS
- EDUCATION
- PERSONAL_CARE
- OTHER
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
    # structured_llm returns the instantiated ExtractedReceiptData Pydantic model directly
    extracted_model: ExtractedReceiptData = structured_llm.invoke([message])
    latency_ms = int((time.monotonic() - start) * 1000)

    return {
        "raw_json": extracted_model.model_dump(mode="json"),
        "provider": "google",
        "model_name": llm_settings.MODEL_NAME,
        "latency_ms": latency_ms,
    }


# ---------------------------------------------------------------------------
# Resolve or create UNCATEGORIZED category
# ---------------------------------------------------------------------------

def _get_uncategorized_category_id(session: Session) -> uuid.UUID:
    """Return the UUID of the UNCATEGORIZED item category, creating it if needed."""
    cat = session.exec(
        select(Category).where(
            Category.scope == CategoryScope.ITEM,
            Category.code == "UNCATEGORIZED",
        )
    ).first()
    if cat is not None:
        return cat.id

    cat = Category(
        scope=CategoryScope.ITEM,
        code="UNCATEGORIZED",
        name="Uncategorized",
    )
    session.add(cat)
    session.commit()
    session.refresh(cat)
    logger.info("Created UNCATEGORIZED item category id=%s.", cat.id)
    return cat.id


def _resolve_category_id(session: Session, code: str | None, fallback_id: uuid.UUID) -> uuid.UUID:
    """Try to find an ITEM-scope category by code; auto-create it if not found."""
    if not code:
        return fallback_id
        
    clean_code = code.strip().upper()
    cat = session.exec(
        select(Category).where(
            Category.scope == CategoryScope.ITEM,
            Category.code == clean_code,
        )
    ).first()
    
    if cat:
        return cat.id
        
    # Standard LLM categories should be auto-created instead of falling back
    name = clean_code.replace("_", " ").title()
    new_cat = Category(
        scope=CategoryScope.ITEM,
        code=clean_code,
        name=name,
    )
    session.add(new_cat)
    session.commit()
    session.refresh(new_cat)
    
    logger.info("Auto-created new category: %s", name)
    return new_cat.id


# ---------------------------------------------------------------------------
# Core processing logic
# ---------------------------------------------------------------------------

def process_receipt(receipt_id: str) -> None:
    """Process a single receipt — called per RabbitMQ message."""
    with Session(engine) as session:
        receipt = session.exec(
            select(Receipt).where(Receipt.id == uuid.UUID(receipt_id))
        ).first()

        if receipt is None:
            logger.error("Receipt %s not found — skipping.", receipt_id)
            return

        # --- Idempotency guard -----------------------------------------------
        existing_extraction = session.exec(
            select(ReceiptExtraction).where(ReceiptExtraction.receipt_id == receipt.id)
        ).first()
        if existing_extraction is not None:
            logger.info("Receipt %s already has an extraction — skipping.", receipt_id)
            return

        if receipt.status in (ReceiptStatus.COMPLETED, ReceiptStatus.PROCESSING):
            existing_tx = session.exec(
                select(Transaction).where(Transaction.receipt_id == receipt.id)
            ).first()
            if existing_tx is not None:
                logger.info("Receipt %s already processed (status=%s) — skipping.", receipt_id, receipt.status.value)
                return

        # --- Mark PROCESSING -------------------------------------------------
        receipt.status = ReceiptStatus.PROCESSING
        receipt.processing_attempt += 1
        session.add(receipt)
        session.commit()

        try:
            # --- Download image from MinIO -----------------------------------
            logger.info("Downloading %s from bucket %s ...", receipt.storage_key, receipt.storage_bucket)
            image_bytes = download_object(key=receipt.storage_key, bucket=receipt.storage_bucket)
            logger.info("Downloaded %d bytes.", len(image_bytes))

            # --- Call Vision LLM ---------------------------------------------
            logger.info("Calling Vision LLM for receipt %s ...", receipt_id)
            llm_result = _call_vision_llm(image_bytes, receipt.mime_type)
            raw_json = llm_result["raw_json"]

            # --- Validate with Pydantic --------------------------------------
            extracted = ExtractedReceiptData.model_validate(raw_json)

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

            # --- Create Transaction ------------------------------------------
            transaction = Transaction(
                user_id=receipt.user_id,
                receipt_id=receipt.id,
                occurred_at=extracted.occurred_at,
                amount_total=extracted.amount_total,
                currency=extracted.currency,
                merchant_name=extracted.merchant_name,
                source=TransactionSource.RECEIPT,
                status="DRAFT",
            )
            session.add(transaction)
            session.commit()
            session.refresh(transaction)

            # --- Create TransactionItems -------------------------------------
            for idx, item in enumerate(extracted.items, start=1):
                cat_id = _resolve_category_id(session, item.category_code, uncategorized_id)
                ti = TransactionItem(
                    transaction_id=transaction.id,
                    line_no=item.line_no or idx,
                    description=item.description,
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
            logger.info(
                "Receipt %s processed → transaction %s with %d items.",
                receipt_id,
                transaction.id,
                len(extracted.items),
            )

        except Exception:
            session.rollback()
            tb = traceback.format_exc()
            logger.exception("Failed to process receipt %s.", receipt_id)
            # Re-open session state after rollback
            session.refresh(receipt)
            receipt.status = ReceiptStatus.FAILED
            receipt.failure_reason = tb[:1000]
            session.add(receipt)
            session.commit()


# ---------------------------------------------------------------------------
# RabbitMQ consumer loop
# ---------------------------------------------------------------------------

async def main() -> None:
    """Connect to RabbitMQ and consume the receipt_extraction queue."""
    logger.info("Worker starting — ensuring S3 bucket exists...")
    ensure_bucket()

    logger.info("Connecting to RabbitMQ at %s ...", RABBITMQ_URL)
    connection = await aio_pika.connect_robust(RABBITMQ_URL)
    channel = await connection.channel()
    await channel.set_qos(prefetch_count=1)

    queue = await channel.declare_queue(QUEUE_NAME, durable=True)
    logger.info("Listening on queue '%s' ...", QUEUE_NAME)

    async with queue.iterator() as queue_iter:
        async for message in queue_iter:
            async with message.process():
                try:
                    body = json.loads(message.body.decode())
                    receipt_id = body["receipt_id"]
                    logger.info("Received job for receipt %s.", receipt_id)
                    # Run the blocking processing in a thread
                    await asyncio.to_thread(process_receipt, receipt_id)
                except Exception:
                    logger.exception("Error handling message: %s", message.body)


if __name__ == "__main__":
    asyncio.run(main())
