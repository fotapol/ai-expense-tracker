"""Label API endpoints for creating, listing, and managing user labels."""

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.labels.label import Label
from app.models.labels.transaction_label import TransactionLabel
from app.models.transactions.transaction import Transaction
from app.models.users.user import User
from app.schemas.labels import LabelAssignRequest, LabelCreateRequest, LabelRead

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["labels"])


# ---------------------------------------------------------------------------
# LIST
# ---------------------------------------------------------------------------


@router.get("/labels", response_model=list[LabelRead])
@limiter.limit("60/minute")
async def list_labels(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List all labels for the current user."""
    labels = session.exec(
        select(Label)
        .where(Label.user_id == current_user.id, Label.is_active.is_(True))
        .order_by(Label.name)
    ).all()

    return labels


# ---------------------------------------------------------------------------
# CREATE
# ---------------------------------------------------------------------------

@router.post("/labels", response_model=LabelRead, status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
async def create_label(
    payload: LabelCreateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create a new label."""
    label_name = payload.name.strip()
    existing = session.exec(
        select(Label).where(
            Label.user_id == current_user.id,
            Label.name == label_name,
            Label.is_active.is_(True),
        )
    ).first()
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Label already exists.",
        )

    label = Label(
        user_id=current_user.id,
        name=label_name,
        color=payload.color,
    )
    session.add(label)
    session.commit()
    session.refresh(label)

    return label


# ---------------------------------------------------------------------------
# DELETE
# ---------------------------------------------------------------------------

@router.delete("/labels/{label_id}", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("30/minute")
async def delete_label(
    label_id: uuid.UUID,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Delete a label and remove all transaction associations."""
    label = session.exec(
        select(Label).where(Label.id == label_id, Label.user_id == current_user.id)
    ).first()

    if label is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Label not found.")

    # Remove all junction entries
    links = session.exec(
        select(TransactionLabel).where(TransactionLabel.label_id == label_id)
    ).all()
    for link in links:
        session.delete(link)

    label.is_active = False
    session.add(label)
    session.commit()

    return None


# ---------------------------------------------------------------------------
# ASSIGN / UNASSIGN label to a transaction
# ---------------------------------------------------------------------------

@router.post("/labels/assign", status_code=status.HTTP_201_CREATED)
@limiter.limit("60/minute")
async def assign_label(
    payload: LabelAssignRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Assign a label to a transaction."""
    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == payload.transaction_id,
            Transaction.user_id == current_user.id,
        )
    ).first()
    if transaction is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found.")

    label = session.exec(
        select(Label).where(
            Label.id == payload.label_id,
            Label.user_id == current_user.id,
            Label.is_active.is_(True),
        )
    ).first()
    if label is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Label not found.")

    # Check if already assigned
    existing = session.exec(
        select(TransactionLabel).where(
            TransactionLabel.transaction_id == payload.transaction_id,
            TransactionLabel.label_id == payload.label_id,
        )
    ).first()
    if existing:
        return {"status": "already_assigned"}

    link = TransactionLabel(
        transaction_id=payload.transaction_id,
        label_id=payload.label_id,
    )
    session.add(link)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        return {"status": "already_assigned"}
    return {"status": "assigned"}


@router.post("/labels/unassign", status_code=status.HTTP_200_OK)
@limiter.limit("60/minute")
async def unassign_label(
    payload: LabelAssignRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Remove a label from a transaction."""
    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == payload.transaction_id,
            Transaction.user_id == current_user.id,
        )
    ).first()
    if transaction is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found.")

    label = session.exec(
        select(Label).where(
            Label.id == payload.label_id,
            Label.user_id == current_user.id,
            Label.is_active.is_(True),
        )
    ).first()
    if label is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Label not found.")

    link = session.exec(
        select(TransactionLabel).where(
            TransactionLabel.transaction_id == payload.transaction_id,
            TransactionLabel.label_id == payload.label_id,
        )
    ).first()
    if link:
        session.delete(link)
        session.commit()
    return {"status": "unassigned"}
