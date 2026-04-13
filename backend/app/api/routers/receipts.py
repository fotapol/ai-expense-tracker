"""Receipt API endpoints.

Provides the presigned-upload flow:
1. POST /v1/receipts -> create receipt row + presigned PUT URL
2. POST /v1/receipts/{id}/confirm-upload -> verify upload via HEAD, enqueue extraction
3. GET  /v1/receipts/{id} -> poll receipt status + linked transaction
"""

import datetime as dt
import json
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.config import app_settings
from app.core.db import get_session
from app.core.minio import generate_presigned_get, generate_presigned_put, head_object
from app.core.rabbitmq import get_rabbitmq_connection
from app.core.rate_limiter import limiter
from app.models.receipts.receipt import Receipt
from app.models.shared.enums import ReceiptStatus
from app.models.transactions.transaction import Transaction
from app.models.users.user import User
from app.schemas.receipts import (
    ReceiptConfirmResponse,
    ReceiptCreateRequest,
    ReceiptCreateResponse,
    ReceiptRead,
    ReceiptViewUrlResponse,
)
from app.services.billing import receipt_scan_limit_reached, resolve_receipt_scan_usage

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["receipts"])

_ALLOWED_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
    "image/heif",
    "application/pdf",
}

# Server-side file size ceiling — slightly above the client-side 10 MB limit
# to account for encoding overhead, but prevents abuse via direct presigned uploads.
_MAX_RECEIPT_FILE_BYTES = app_settings.MAX_RECEIPT_FILE_BYTES


def _get_visible_receipt_and_transaction(
    session: Session,
    *,
    receipt_id: uuid.UUID,
    current_user: User,
) -> tuple[Receipt | None, Transaction | None]:
    receipt = session.exec(select(Receipt).where(Receipt.id == receipt_id)).first()
    if receipt is None:
        return None, None

    transaction = session.exec(
        select(Transaction).where(Transaction.receipt_id == receipt_id)
    ).first()

    # Household sharing is disabled for launch. Always let the uploader see
    # their own receipt and any linked legacy transaction.
    if receipt.user_id == current_user.id:
        return receipt, transaction

    return None, None


def _revert_receipt_after_failed_enqueue(
    session: Session,
    *,
    receipt: Receipt,
) -> None:
    """Restore a retryable CREATED state when queue handoff fails."""

    receipt.status = ReceiptStatus.CREATED
    receipt.uploaded_at = None
    session.add(receipt)
    session.commit()
    session.refresh(receipt)


@router.post("/receipts", response_model=ReceiptCreateResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")
async def create_receipt(
    payload: ReceiptCreateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create a new receipt row and return a presigned upload URL."""

    if payload.mime_type not in _ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported mime_type. Allowed: {sorted(_ALLOWED_MIME_TYPES)}",
        )

    receipt_id = uuid.uuid4()
    filename = payload.original_filename or f"{receipt_id}"
    storage_bucket = "receipts"
    storage_key = f"receipts/{current_user.id}/{receipt_id}/{filename}"

    receipt = Receipt(
        id=receipt_id,
        user_id=current_user.id,
        status=ReceiptStatus.CREATED,
        storage_bucket=storage_bucket,
        storage_key=storage_key,
        mime_type=payload.mime_type,
        original_filename=filename,
        sha256=payload.sha256 or "",
        size_bytes=payload.size_bytes or 0,
    )
    session.add(receipt)
    session.commit()
    session.refresh(receipt)

    presigned = generate_presigned_put(key=storage_key, content_type=payload.mime_type)

    logger.info("Upload accepted for receipt %s.", receipt.id)

    return ReceiptCreateResponse(
        receipt_id=receipt.id,
        storage_bucket=storage_bucket,
        storage_key=storage_key,
        upload_url=presigned["url"],
        required_headers=presigned["required_headers"],
    )


@router.post(
    "/receipts/{receipt_id}/confirm-upload",
    response_model=ReceiptConfirmResponse,
)
@limiter.limit("10/minute")
async def confirm_upload(
    receipt_id: uuid.UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Verify upload and enqueue extraction without stranding receipt state."""

    receipt = session.exec(
        select(Receipt)
        .where(Receipt.id == receipt_id, Receipt.user_id == current_user.id)
        .with_for_update()
    ).first()

    if receipt is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receipt not found.",
        )

    if receipt.status != ReceiptStatus.CREATED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Receipt status is '{receipt.status.value}', expected 'CREATED'.",
        )

    try:
        obj_info = head_object(key=receipt.storage_key, bucket=receipt.storage_bucket)
    except Exception as exc:
        logger.warning("HEAD failed for %s: %s", receipt.storage_key, exc)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File not found in storage. Please upload the file first.",
        ) from None

    actual_size = obj_info.get("size_bytes", 0)
    if actual_size > _MAX_RECEIPT_FILE_BYTES:
        max_mb = _MAX_RECEIPT_FILE_BYTES // (1024 * 1024)
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Uploaded file exceeds the {max_mb} MB server limit.",
        )

    session.exec(
        select(User.id).where(User.id == current_user.id).with_for_update()
    ).first()
    usage = resolve_receipt_scan_usage(session, current_user.id)
    if receipt_scan_limit_reached(usage):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "free_rolling_scan_limit_reached",
                "message": (
                    f"Free plan allows up to {usage.limit} AI scans per 30-day rolling window. "
                    "Upgrade to PRO for unlimited receipt scans."
                ),
                "used": usage.used,
                "limit": usage.limit,
                "remaining": usage.remaining,
                "period_start_at": usage.period_start_at.isoformat(),
                "period_end_at": usage.period_end_at.isoformat(),
            },
        )

    connection = get_rabbitmq_connection()
    if connection is None:
        logger.error(
            "RabbitMQ unavailable - cannot enqueue extraction for receipt %s.",
            receipt_id,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Message queue unavailable. Please try again later.",
        )

    receipt.status = ReceiptStatus.UPLOADED
    receipt.uploaded_at = dt.datetime.now(dt.UTC)
    receipt.size_bytes = obj_info["size_bytes"]
    if obj_info.get("content_type"):
        receipt.mime_type = obj_info["content_type"]
    session.add(receipt)
    session.commit()
    session.refresh(receipt)

    try:
        import aio_pika

        channel = await connection.channel()
        await channel.default_exchange.publish(
            aio_pika.Message(
                body=json.dumps({"receipt_id": str(receipt_id)}).encode(),
                content_type="application/json",
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
            ),
            routing_key="receipt_extraction",
        )
        logger.info("Enqueued extraction job for receipt %s.", receipt_id)
    except Exception:
        logger.exception("Failed to enqueue extraction for receipt %s.", receipt_id)
        _revert_receipt_after_failed_enqueue(session, receipt=receipt)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to enqueue extraction job.",
        ) from None

    return ReceiptConfirmResponse(receipt_id=receipt.id, status=receipt.status)


@router.get("/receipts/{receipt_id}", response_model=ReceiptRead)
@limiter.limit("30/minute")
async def get_receipt(
    receipt_id: uuid.UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return receipt status, failure reason, and linked transaction id."""

    receipt, transaction = _get_visible_receipt_and_transaction(
        session,
        receipt_id=receipt_id,
        current_user=current_user,
    )

    if receipt is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receipt not found.",
        )

    read = ReceiptRead.model_validate(receipt)
    read.transaction_id = transaction.id if transaction else None
    return read


@router.get("/receipts/{receipt_id}/view-url", response_model=ReceiptViewUrlResponse)
@limiter.limit("30/minute")
async def get_receipt_view_url(
    receipt_id: uuid.UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return a short-lived URL for viewing an uploaded receipt file."""

    receipt, _transaction = _get_visible_receipt_and_transaction(
        session,
        receipt_id=receipt_id,
        current_user=current_user,
    )

    if receipt is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receipt not found.",
        )

    return ReceiptViewUrlResponse(
        receipt_id=receipt.id,
        view_url=generate_presigned_get(
            key=receipt.storage_key,
            bucket=receipt.storage_bucket,
        ),
        mime_type=receipt.mime_type,
        original_filename=receipt.original_filename,
    )


@router.delete("/receipts/{receipt_id}", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def delete_receipt(
    receipt_id: uuid.UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Delete a receipt and its associated transaction + items."""

    from app.models.labels.transaction_label import TransactionLabel
    from app.models.receipts.receipt_extraction import ReceiptExtraction
    from app.models.transactions.transaction_item import TransactionItem

    receipt = session.exec(
        select(Receipt).where(Receipt.id == receipt_id, Receipt.user_id == current_user.id)
    ).first()

    if receipt is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Receipt not found.",
        )

    transaction = session.exec(
        select(Transaction).where(Transaction.receipt_id == receipt_id)
    ).first()
    if transaction:
        for link in session.exec(
            select(TransactionLabel).where(TransactionLabel.transaction_id == transaction.id)
        ).all():
            session.delete(link)
        for item in session.exec(
            select(TransactionItem).where(TransactionItem.transaction_id == transaction.id)
        ).all():
            session.delete(item)
        session.flush()
        session.delete(transaction)
        session.flush()

    for extraction in session.exec(
        select(ReceiptExtraction).where(ReceiptExtraction.receipt_id == receipt_id)
    ).all():
        session.delete(extraction)
    session.flush()

    session.delete(receipt)
    session.commit()
    return None
