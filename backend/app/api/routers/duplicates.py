"""Owned duplicate review and explicit resolution; available on every plan."""

import datetime as dt
import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.minio import delete_object
from app.core.rate_limiter import limiter
from app.models.labels.transaction_label import TransactionLabel
from app.models.receipts.receipt import Receipt
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.transactions.duplicate_dismissal import DuplicateDismissal
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.user import User
from app.schemas.duplicates import (
    DuplicateListFilter,
    DuplicatePageRead,
    DuplicatePairRequest,
    DuplicateResolveRead,
    DuplicateResolveRequest,
)
from app.services.duplicates import canonical_pair, find_duplicates

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/v1/duplicates", tags=["duplicates"])


def _owned_pair(session, user_id, first, second, *, lock=False):
    ids = canonical_pair(first, second)
    query = (
        select(Transaction)
        .where(Transaction.user_id == user_id, Transaction.id.in_(ids))
        .order_by(Transaction.id)
    )
    if lock:
        query = query.with_for_update()
    rows = session.exec(query).all()
    if len(rows) != 2:
        raise HTTPException(status_code=404, detail="Transaction not found.")
    return {row.id: row for row in rows}


@router.get("", response_model=DuplicatePageRead)
@limiter.limit("30/minute")
async def list_duplicates(
    request: Request,
    filters: Annotated[DuplicateListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    return find_duplicates(session, user_id=current_user.id, **filters.model_dump())


@router.post("/dismiss", status_code=204, response_class=Response)
@limiter.limit("60/minute")
async def dismiss_duplicates(
    request: Request,
    payload: DuplicatePairRequest,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    _owned_pair(
        session, current_user.id, payload.first_transaction_id, payload.second_transaction_id
    )
    first, second = canonical_pair(payload.first_transaction_id, payload.second_transaction_id)
    key = (current_user.id, first, second)
    if session.get(DuplicateDismissal, key) is None:
        session.add(
            DuplicateDismissal(
                user_id=current_user.id, first_transaction_id=first, second_transaction_id=second
            )
        )
        try:
            session.commit()
        except IntegrityError:
            session.rollback()
            if session.get(DuplicateDismissal, key) is None:
                raise HTTPException(
                    status_code=409, detail="The receipts changed. Reload and try again."
                ) from None
    return Response(status_code=204)


def _utc(value: dt.datetime) -> dt.datetime:
    return value.replace(tzinfo=dt.UTC) if value.tzinfo is None else value.astimezone(dt.UTC)


@router.post("/resolve", response_model=DuplicateResolveRead)
@limiter.limit("20/minute")
async def resolve_duplicates(
    request: Request,
    payload: DuplicateResolveRequest,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    rows = _owned_pair(
        session,
        current_user.id,
        payload.keep_transaction_id,
        payload.discard_transaction_id,
        lock=True,
    )
    keep, discard = rows[payload.keep_transaction_id], rows[payload.discard_transaction_id]
    if _utc(keep.updated_at) != _utc(payload.keep_updated_at) or _utc(discard.updated_at) != _utc(
        payload.discard_updated_at
    ):
        raise HTTPException(status_code=409, detail="The receipts changed. Reload and try again.")
    # Recheck the match while holding the record locks. A stale comparison must
    # never remove an edited or previously dismissed legitimate purchase.
    matches = find_duplicates(
        session,
        user_id=current_user.id,
        only_pair=canonical_pair(keep.id, discard.id),
        page_size=1,
    )
    if not matches.items:
        raise HTTPException(status_code=409, detail="This duplicate match is no longer available.")
    receipt = None
    if discard.receipt_id:
        receipt = session.exec(
            select(Receipt)
            .where(Receipt.id == discard.receipt_id, Receipt.user_id == current_user.id)
            .with_for_update()
        ).first()
        if receipt is None:
            raise HTTPException(
                status_code=409, detail="The receipt changed. Reload and try again."
            )
        try:
            delete_object(receipt.storage_key, bucket=receipt.storage_bucket)
        except Exception:
            logger.warning("Duplicate receipt storage cleanup failed.", exc_info=True)
            raise HTTPException(
                status_code=503, detail="Receipt storage cleanup failed. Please try again."
            ) from None
    for model in (TransactionLabel, TransactionItem):
        for row in session.exec(select(model).where(model.transaction_id == discard.id)).all():
            session.delete(row)
    # Explicit cleanup also works for existing databases/test stores without FK
    # cascades enabled. Only this user's decisions can reference their records.
    for row in session.exec(
        select(DuplicateDismissal).where(
            DuplicateDismissal.user_id == current_user.id,
            (DuplicateDismissal.first_transaction_id == discard.id)
            | (DuplicateDismissal.second_transaction_id == discard.id),
        )
    ).all():
        session.delete(row)
    session.flush()
    session.delete(discard)
    session.flush()
    if receipt:
        for extraction in session.exec(
            select(ReceiptExtraction).where(ReceiptExtraction.receipt_id == receipt.id)
        ).all():
            session.delete(extraction)
        session.flush()
        session.delete(receipt)
    session.commit()
    return DuplicateResolveRead(
        kept_transaction_id=keep.id, deleted_transaction_id=payload.discard_transaction_id
    )
