"""Transaction route handlers."""

import logging
import uuid
from decimal import Decimal
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.labels.label import Label
from app.models.labels.transaction_label import TransactionLabel
from app.models.shared.enums import CategoryScope, TransactionSource
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.user import User
from app.schemas.shared import (
    quantize_amount,
)
from app.schemas.transactions import (
    TransactionCreateManual,
    TransactionItemRead,
    TransactionListFilter,
    TransactionRead,
    TransactionUpdateRequest,
)
from app.services.transactions.read_models import (
    _apply_display_conversion,
    _build_category_filter_predicate,
    _build_subcategory_filter_predicate,
    _build_transaction_read,
    _build_transaction_read_visibility_predicate,
    _build_transaction_write_visibility_predicate,
    _clear_extraction_warnings_after_user_confirmation,
    _enrich_transaction_items_with_translations,
    _get_deleteable_manual_transaction,
    _get_uncategorized_item_category_id,
    _get_user_visible_category_by_id,
    _get_user_visible_category_ids,
    _load_category_names_by_id,
    _load_labels_by_transaction_id,
    _load_translation_lookup,
    _load_warnings_by_receipt_id,
    _preferred_item_translation_source,
    _resolve_item_language,
    _resolve_label_filter_ids,
    _resolve_target_currency,
    _resolve_transaction_category_from_item_category,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["transactions"])

@router.post("/transactions", response_model=TransactionRead, status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
async def create_transaction(
    request: Request,
    payload: TransactionCreateManual,
    target_currency: str | None = None,
    item_language: str | None = None,
    app_language: str | None = None,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Create a manual transaction entry."""

    owner_user_id = current_user.id

    selected_item_category: Category | None = None
    if payload.category_id is not None:
        selected_item_category = _get_user_visible_category_by_id(
            session,
            current_user=current_user,
            category_id=payload.category_id,
        )
        if selected_item_category is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Selected category is invalid or disabled.",
            )

    fallback_item_category_id = _get_uncategorized_item_category_id(session)
    item_rows: list[dict[str, Any]] = []

    if payload.items:
        for index, item_data in enumerate(payload.items, start=1):
            resolved_category_id = fallback_item_category_id
            if item_data.category_id is not None:
                item_category = _get_user_visible_category_by_id(
                    session,
                    current_user=current_user,
                    category_id=item_data.category_id,
                )
                if item_category is None:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="One or more item categories are invalid or disabled.",
                    )
                resolved_category_id = item_category.id
            elif selected_item_category is not None:
                resolved_category_id = selected_item_category.id

            item_amount = item_data.amount
            if item_amount is None and len(payload.items) == 1:
                item_amount = payload.amount_total

            item_rows.append(
                {
                    "line_no": index,
                    "description": (
                        item_data.description or payload.merchant_name or "Manual entry"
                    ),
                    "description_lang": item_data.description_lang,
                    "qty": item_data.qty,
                    "unit": item_data.unit,
                    "unit_price": item_data.unit_price,
                    "amount": item_amount or Decimal("0.00"),
                    "amount_before_discount": item_data.amount_before_discount,
                    "discount_amount": item_data.discount_amount,
                    "is_adjustment": item_data.is_adjustment or False,
                    "category_id": resolved_category_id,
                }
            )
    primary_item_category_id = (
        selected_item_category.id
        if selected_item_category is not None
        else (item_rows[0]["category_id"] if item_rows else None)
    )
    transaction = Transaction(
        user_id=current_user.id,
        receipt_id=None,
        occurred_at=payload.occurred_at,
        amount_total=payload.amount_total,
        currency=payload.currency,
        merchant_id=payload.merchant_id,
        merchant_name=payload.merchant_name,
        category_id=_resolve_transaction_category_from_item_category(
            session,
            item_category_id=primary_item_category_id,
        )
        if primary_item_category_id is not None
        else None,
        source=TransactionSource.MANUAL,
        status=payload.status,
        created_by_user_id=current_user.id,
        owner_user_id=owner_user_id,
    )
    session.add(transaction)
    session.flush()

    created_items: list[TransactionItem] = []
    for item_row in item_rows:
        item = TransactionItem(
            transaction_id=transaction.id,
            line_no=item_row["line_no"],
            description=item_row["description"],
            description_lang=item_row["description_lang"],
            qty=item_row["qty"],
            unit=item_row["unit"],
            unit_price=item_row["unit_price"],
            amount=item_row["amount"],
            amount_before_discount=item_row["amount_before_discount"],
            discount_amount=item_row["discount_amount"],
            is_adjustment=item_row["is_adjustment"],
            category_id=item_row["category_id"],
        )
        session.add(item)
        created_items.append(item)

    session.commit()
    session.refresh(transaction)
    return _build_transaction_read(
        session=session,
        current_user=current_user,
        transaction=transaction,
        items=created_items,
        target_currency=target_currency,
        item_language=item_language,
        app_language=app_language,
    )

@router.get("/transactions", response_model=list[TransactionRead])
@limiter.limit("60/minute")
async def list_transactions(
    request: Request,
    filters: Annotated[TransactionListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List transactions for the current user."""
    target_currency = _resolve_target_currency(filters, current_user)
    query = select(Transaction).where(
        _build_transaction_read_visibility_predicate(session, current_user)
    )

    if filters.from_occurred_at:
        query = query.where(Transaction.occurred_at >= filters.from_occurred_at)
    if filters.to_occurred_at:
        query = query.where(Transaction.occurred_at <= filters.to_occurred_at)
    if filters.merchant_id:
        query = query.where(Transaction.merchant_id == filters.merchant_id)
    category_predicate = _build_category_filter_predicate(
        session, current_user, filters.category_ids
    )
    if category_predicate is not None:
        query = query.where(category_predicate)
    subcategory_predicate = _build_subcategory_filter_predicate(
        session, current_user, filters.subcategory_ids
    )
    if subcategory_predicate is not None:
        query = query.where(subcategory_predicate)
    if filters.merchant_name_search:
        search_term = f"%{filters.merchant_name_search}%"
        query = query.where(Transaction.merchant_name.ilike(search_term))
    label_filter_ids = _resolve_label_filter_ids(filters)
    if label_filter_ids:
        label_subquery = (
            select(TransactionLabel.transaction_id)
            .join(Label, Label.id == TransactionLabel.label_id)
            .where(
                TransactionLabel.label_id.in_(label_filter_ids),
                Label.user_id == current_user.id,
                Label.is_active,
            )
            .subquery()
        )
        query = query.where(Transaction.id.in_(select(label_subquery.c.transaction_id)))
    if filters.status:
        query = query.where(Transaction.status == filters.status)
    if filters.source:
        query = query.where(Transaction.source == filters.source)
    if filters.currency:
        query = query.where(Transaction.currency == filters.currency)

    # Apply pagination
    query = query.order_by(Transaction.occurred_at.desc())
    query = query.offset(filters.offset).limit(filters.page_size)

    transactions = session.exec(query).all()

    # We could optionally eagerly load or fetch items here, but a list view
    # typically doesn't need every internal item payload.
    # To keep `TransactionRead` happy, an empty list defaults or we can fetch them.
    # We will fetch them simply to comply with the existing response model
    results = []
    if transactions:  # Only fetch items if transactions exist to save an empty query
        transaction_ids = [t.id for t in transactions]
        receipt_ids = [t.receipt_id for t in transactions if t.receipt_id is not None]
        category_ids = [t.category_id for t in transactions if t.category_id is not None]
        items = session.exec(
            select(TransactionItem).where(TransactionItem.transaction_id.in_(transaction_ids))
        ).all()
        labels_by_tx = _load_labels_by_transaction_id(
            session,
            transaction_ids=transaction_ids,
            current_user=current_user,
        )
        category_names_by_id = _load_category_names_by_id(
            session,
            category_ids=category_ids,
        )
        warnings_by_receipt = _load_warnings_by_receipt_id(
            session,
            receipt_ids=receipt_ids,
        )

        effective_item_language = _resolve_item_language(
            item_language=filters.item_language,
            app_language=filters.app_language,
            current_user=current_user,
        )
        items_by_tx = {}
        for item in items:
            items_by_tx.setdefault(item.transaction_id, []).append(item)

        read_items_by_tx: dict[uuid.UUID, list[TransactionItemRead]] = {}
        for transaction_id, tx_items in items_by_tx.items():
            read_items_by_tx[transaction_id] = [
                TransactionItemRead.model_validate(item)
                for item in sorted(tx_items, key=lambda row: row.line_no)
            ]
        translation_lookup = _load_translation_lookup(
            session,
            current_user=current_user,
            target_language=effective_item_language,
            source_entries=[
                source_entry
                for tx_items in read_items_by_tx.values()
                for item in tx_items
                if (source_entry := _preferred_item_translation_source(item)) is not None
            ],
        )

        for t in transactions:
            read = TransactionRead.model_validate(t)
            read.items = read_items_by_tx.get(t.id, [])
            _enrich_transaction_items_with_translations(
                items=read.items,
                target_language=effective_item_language,
                lookup=translation_lookup,
            )
            read.labels = labels_by_tx.get(t.id, [])
            read.category_name = (
                category_names_by_id.get(t.category_id) if t.category_id is not None else None
            )
            tx_warnings = warnings_by_receipt.get(t.receipt_id, []) if t.receipt_id else []
            read.has_extraction_warnings = len(tx_warnings) > 0
            read.extraction_warnings = tx_warnings  # H-7: populate warnings body, not just flag
            _apply_display_conversion(
                read=read,
                session=session,
                target_currency=target_currency,
            )
            results.append(read)

    return results

@router.get("/transactions/{transaction_id}", response_model=TransactionRead)
@limiter.limit("30/minute")
async def get_transaction(
    request: Request,
    transaction_id: uuid.UUID,
    target_currency: str | None = None,
    item_language: str | None = None,
    app_language: str | None = None,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Get a transaction and its line items."""
    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == transaction_id,
            _build_transaction_read_visibility_predicate(session, current_user),
        )
    ).first()

    if transaction is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found.")

    return _build_transaction_read(
        session=session,
        current_user=current_user,
        transaction=transaction,
        target_currency=target_currency,
        item_language=item_language,
        app_language=app_language,
    )

@router.put("/transactions/{transaction_id}", response_model=TransactionRead)
@limiter.limit("30/minute")
async def update_transaction(
    request: Request,
    transaction_id: uuid.UUID,
    payload: TransactionUpdateRequest,
    target_currency: str | None = None,
    item_language: str | None = None,
    app_language: str | None = None,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Update a transaction. Optionally updates embedded line items."""
    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == transaction_id,
            _build_transaction_write_visibility_predicate(session, current_user),
        )
    ).first()

    if transaction is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found.")

    # Enforce category visibility
    requested_transaction_category_ids: set[uuid.UUID] = set()
    requested_item_category_ids: set[uuid.UUID] = set()
    update_data = payload.model_dump(exclude_unset=True, exclude={"items"})
    if "category_id" in update_data and update_data["category_id"] is not None:
        requested_transaction_category_ids.add(update_data["category_id"])
    if payload.items is not None:
        for item_data in payload.items:
            if item_data.category_id is not None:
                requested_item_category_ids.add(item_data.category_id)
    if requested_transaction_category_ids:
        valid_transaction_category_ids = _get_user_visible_category_ids(
            session,
            current_user=current_user,
            category_ids=requested_transaction_category_ids,
            scope=CategoryScope.TRANSACTION,
        )
        if len(valid_transaction_category_ids) != len(requested_transaction_category_ids):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="One or more categories are invalid or not active.",
            )
    if requested_item_category_ids:
        valid_item_category_ids = _get_user_visible_category_ids(
            session,
            current_user=current_user,
            category_ids=requested_item_category_ids,
            scope=CategoryScope.ITEM,
        )
        if len(valid_item_category_ids) != len(requested_item_category_ids):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="One or more categories are invalid or not active.",
            )

    # 1. Update Core Transaction fields
    update_data = payload.model_dump(
        exclude_unset=True,
        exclude={"items"},
    )
    for key, value in update_data.items():
        setattr(transaction, key, value)
    _clear_extraction_warnings_after_user_confirmation(
        session,
        transaction=transaction,
    )

    session.add(transaction)

    # 2. Update Items if provided
    items = session.exec(
        select(TransactionItem)
        .where(TransactionItem.transaction_id == transaction_id)
        .order_by(TransactionItem.line_no)
    ).all()

    if payload.items is not None:
        # Simple reconciliation: match by ID.
        existing_items_map = {item.id: item for item in items}
        seen_existing_ids: set[uuid.UUID] = set()

        # New list to return
        updated_items_list = []
        max_line_no: int = int(max([i.line_no for i in items] + [0]))

        for item_data in payload.items:
            if item_data.id and item_data.id in existing_items_map:
                # Update existing
                existing_item = existing_items_map[item_data.id]
                seen_existing_ids.add(item_data.id)
                item_changes = item_data.model_dump(exclude_unset=True, exclude={"id"})
                if (
                    "description" in item_changes
                    and "description_lang" not in item_changes
                    and item_changes["description"] != existing_item.description
                ):
                    existing_item.description_lang = None
                for k, v in item_changes.items():
                    setattr(existing_item, k, v)
                session.add(existing_item)
                updated_items_list.append(existing_item)
            else:
                # Create new
                max_line_no += 1
                new_item = TransactionItem(
                    transaction_id=transaction.id,
                    line_no=max_line_no,
                    description=item_data.description or "New Item",
                    description_lang=item_data.description_lang,
                    qty=item_data.qty,
                    unit=item_data.unit,
                    unit_price=item_data.unit_price,
                    amount=item_data.amount or Decimal("0.00"),
                    amount_before_discount=item_data.amount_before_discount,
                    discount_amount=item_data.discount_amount,
                    is_adjustment=item_data.is_adjustment or False,
                    category_id=item_data.category_id,  # Must be valid UUID for existing category
                )
                session.add(new_item)
                updated_items_list.append(new_item)

        omitted_ids = set(existing_items_map) - seen_existing_ids
        for omitted_id in omitted_ids:
            session.delete(existing_items_map[omitted_id])

        # Re-fetch for response
        items = updated_items_list

    session.commit()
    session.refresh(transaction)

    return _build_transaction_read(
        session=session,
        current_user=current_user,
        transaction=transaction,
        items=items,
        target_currency=target_currency,
        item_language=item_language,
        app_language=app_language,
    )

@router.delete("/transactions/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("30/minute")
async def delete_transaction(
    request: Request,
    transaction_id: uuid.UUID,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Delete a manual transaction without an attached receipt."""

    transaction = _get_deleteable_manual_transaction(
        session,
        transaction_id=transaction_id,
        current_user=current_user,
    )

    label_links = session.exec(
        select(TransactionLabel).where(TransactionLabel.transaction_id == transaction_id)
    ).all()
    for row in label_links:
        session.delete(row)

    items = session.exec(
        select(TransactionItem).where(TransactionItem.transaction_id == transaction_id)
    ).all()
    for item in items:
        session.delete(item)

    session.flush()
    session.delete(transaction)
    session.flush()
    session.commit()
    return None

@router.delete(
    "/transactions/{transaction_id}/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT
)
@limiter.limit("30/minute")
async def delete_transaction_item(
    request: Request,
    transaction_id: uuid.UUID,
    item_id: uuid.UUID,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Delete a single item from a transaction and keep transaction total in sync."""
    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == transaction_id,
            _build_transaction_write_visibility_predicate(session, current_user),
        )
    ).first()
    if transaction is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found.",
        )

    item = session.exec(
        select(TransactionItem).where(
            TransactionItem.id == item_id,
            TransactionItem.transaction_id == transaction_id,
        )
    ).first()
    if item is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction item not found.",
        )

    session.delete(item)
    session.flush()

    remaining_total = session.exec(
        select(func.sum(TransactionItem.amount)).where(
            TransactionItem.transaction_id == transaction_id
        )
    ).first()
    transaction.amount_total = quantize_amount(remaining_total or Decimal("0.00"))
    session.add(transaction)
    session.commit()
    return None
