"""Label API endpoints for creating, listing, and managing user labels."""

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.labels.label import Label
from app.models.labels.transaction_label import TransactionLabel
from app.models.users.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["labels"])


class LabelCreateRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    color: str | None = None  # Hex color, e.g. "#FF5733"


class LabelAssignRequest(BaseModel):
    transaction_id: uuid.UUID
    label_id: uuid.UUID


# ---------------------------------------------------------------------------
# LIST
# ---------------------------------------------------------------------------

@router.get("/labels")
@limiter.limit("60/minute")
async def list_labels(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List all labels for the current user."""
    labels = session.exec(
        select(Label)
        .where(Label.user_id == current_user.id, Label.is_active == True)
        .order_by(Label.name)
    ).all()

    return [
        {"id": str(l.id), "name": l.name, "color": l.color}
        for l in labels
    ]


# ---------------------------------------------------------------------------
# CREATE
# ---------------------------------------------------------------------------

@router.post("/labels", status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
async def create_label(
    payload: LabelCreateRequest,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create a new label."""
    label = Label(
        user_id=current_user.id,
        name=payload.name.strip(),
        color=payload.color,
    )
    session.add(label)
    session.commit()
    session.refresh(label)

    return {"id": str(label.id), "name": label.name, "color": label.color}


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
    session.commit()
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
