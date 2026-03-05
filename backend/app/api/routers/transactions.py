"""Transaction API endpoints for editing and viewing ledgers."""

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
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.user import User
from app.schemas.transactions import TransactionItemRead, TransactionListFilter, TransactionRead, TransactionUpdateRequest

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["transactions"])

@router.get("/transactions", response_model=list[TransactionRead])
@limiter.limit("60/minute")
async def list_transactions(
    request: Request,
    filters: Annotated[TransactionListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """List transactions for the current user."""
    query = select(Transaction).where(Transaction.user_id == current_user.id)

    if filters.from_occurred_at:
        query = query.where(Transaction.occurred_at >= filters.from_occurred_at)
    if filters.to_occurred_at:
        query = query.where(Transaction.occurred_at <= filters.to_occurred_at)
    if filters.merchant_id:
        query = query.where(Transaction.merchant_id == filters.merchant_id)
    if filters.category_ids:
        try:
            cat_ids = [uuid.UUID(uid.strip()) for uid in filters.category_ids.split(",") if uid.strip()]
            if cat_ids:
                query = query.where(Transaction.category_id.in_(cat_ids))
        except ValueError:
            pass # ignore invalid uuids
    if filters.merchant_name_search:
        search_term = f"%{filters.merchant_name_search}%"
        query = query.where(Transaction.merchant_name.ilike(search_term))
    if filters.label_id:
        from app.models.labels.transaction_label import TransactionLabel
        label_subquery = select(TransactionLabel.transaction_id).where(
            TransactionLabel.label_id == filters.label_id
        ).subquery()
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
    if transactions: # Only fetch items if transactions exist to save an empty query
        transaction_ids = [t.id for t in transactions]
        items = session.exec(
            select(TransactionItem).where(TransactionItem.transaction_id.in_(transaction_ids))
        ).all()
        
        items_by_tx = {}
        for item in items:
            items_by_tx.setdefault(item.transaction_id, []).append(item)
            
        for t in transactions:
            read = TransactionRead.model_validate(t)
            tx_items = items_by_tx.get(t.id, [])
            read.items = [TransactionItemRead.model_validate(i) for i in sorted(tx_items, key=lambda x: x.line_no)]
            results.append(read)

    return results


@router.get("/transactions/summary")
@limiter.limit("30/minute")
async def get_transactions_summary(
    request: Request,
    filters: Annotated[TransactionListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Get aggregated summary of transactions split by category."""
    
    # 1. Base Query for the user's transactions in the date range
    base_query = select(Transaction.id).where(Transaction.user_id == current_user.id)
    
    if filters.from_occurred_at:
        base_query = base_query.where(Transaction.occurred_at >= filters.from_occurred_at)
    if filters.to_occurred_at:
        base_query = base_query.where(Transaction.occurred_at <= filters.to_occurred_at)
    if filters.merchant_id:
        base_query = base_query.where(Transaction.merchant_id == filters.merchant_id)
    if filters.category_ids:
        try:
            cat_ids = [uuid.UUID(uid.strip()) for uid in filters.category_ids.split(",") if uid.strip()]
            if cat_ids:
                base_query = base_query.where(Transaction.category_id.in_(cat_ids))
        except ValueError:
            pass
    if filters.merchant_name_search:
        search_term = f"%{filters.merchant_name_search}%"
        base_query = base_query.where(Transaction.merchant_name.ilike(search_term))
    if filters.label_id:
        from app.models.labels.transaction_label import TransactionLabel
        label_subquery = select(TransactionLabel.transaction_id).where(
            TransactionLabel.label_id == filters.label_id
        ).subquery()
        base_query = base_query.where(Transaction.id.in_(select(label_subquery.c.transaction_id)))
    if filters.status:
        base_query = base_query.where(Transaction.status == filters.status)
    if filters.source:
        base_query = base_query.where(Transaction.source == filters.source)
    if filters.currency:
        base_query = base_query.where(Transaction.currency == filters.currency)
        
    transaction_ids_subquery = base_query.subquery()

    # 2. Get total sum and count across all matching transactions
    total_query = select(func.sum(Transaction.amount_total), func.count(Transaction.id)).where(Transaction.id.in_(select(transaction_ids_subquery.c.id)))
    result = session.exec(total_query).first()
    total_amount = result[0] or Decimal("0.00")
    total_transactions = result[1] or 0
    
    # 3. Group by category on TransactionItem
    from app.models.taxonomy.category import Category  # Local import to avoid circular dependencies if any
    
    category_query = (
        select(
            Category.id,
            Category.name,
            Category.code,
            Category.parent_id,
            func.sum(TransactionItem.amount).label("category_total")
        )
        .join(TransactionItem, TransactionItem.category_id == Category.id)
        .where(TransactionItem.transaction_id.in_(select(transaction_ids_subquery.c.id)))
        .group_by(Category.id, Category.name, Category.code, Category.parent_id)
        .order_by(func.sum(TransactionItem.amount).desc())
    )
    
    category_results = session.exec(category_query).all()
    
    # Pre-fetch all parent categories to get their names and codes if we need to roll up
    parent_ids = {cat.parent_id for cat in category_results if cat.parent_id is not None}
    
    parent_map = {}
    if parent_ids:
        parents = session.exec(select(Category).where(Category.id.in_(parent_ids))).all()
        for p in parents:
            parent_map[p.id] = {"name": p.name, "code": p.code}

    # Roll up totals into parents
    rolled_up_totals = {}
    for cat_id, cat_name, cat_code, cat_parent_id, cat_total in category_results:
        if cat_parent_id:
            # It's a subcategory, roll it into the parent
            target_id = cat_parent_id
            target_name = parent_map.get(cat_parent_id, {}).get("name", "Unknown Parent")
            target_code = parent_map.get(cat_parent_id, {}).get("code", "OTHER")
        else:
            # It's already a top-level category
            target_id = cat_id
            target_name = cat_name
            target_code = cat_code
            
        if target_id not in rolled_up_totals:
            rolled_up_totals[target_id] = {
                "name": target_name,
                "code": target_code,
                "amount": Decimal("0")
            }
        rolled_up_totals[target_id]["amount"] += cat_total

    categories_breakdown = []
    for cat_id, data in rolled_up_totals.items():
        percentage = (data["amount"] / total_amount * 100) if total_amount > 0 else Decimal("0")
        categories_breakdown.append({
            "category_id": cat_id,
            "name": data["name"],
            "code": data["code"],
            "amount": float(data["amount"]),
            "percentage": float(percentage)
        })
        
    # Re-sort by amount descending since the rollup might have changed the order
    categories_breakdown.sort(key=lambda x: x["amount"], reverse=True)

    return {
        "total_amount": float(total_amount),
        "total_transactions": total_transactions,
        "currency": "EUR",
        "categories": categories_breakdown
    }


@router.get("/transactions/{transaction_id}", response_model=TransactionRead)
@limiter.limit("30/minute")
async def get_transaction(
    request: Request,
    transaction_id: uuid.UUID,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Get a transaction and its line items."""
    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == transaction_id, 
            Transaction.user_id == current_user.id
        )
    ).first()

    if transaction is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Transaction not found."
        )

    items = session.exec(
        select(TransactionItem).where(TransactionItem.transaction_id == transaction_id)
        .order_by(TransactionItem.line_no)
    ).all()

    # Construct the response model manually to combine models
    read = TransactionRead.model_validate(transaction)
    read.items = [TransactionItemRead.model_validate(item) for item in items]
    return read


@router.put("/transactions/{transaction_id}", response_model=TransactionRead)
@limiter.limit("30/minute")
async def update_transaction(
    request: Request,
    transaction_id: uuid.UUID,
    payload: TransactionUpdateRequest,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Update a transaction. Optionally updates embedded line items."""
    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == transaction_id, 
            Transaction.user_id == current_user.id
        )
    ).first()

    if transaction is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Transaction not found."
        )

    # 1. Update Core Transaction fields
    update_data = payload.model_dump(exclude_unset=True, exclude={"items"})
    for key, value in update_data.items():
        setattr(transaction, key, value)
        
    session.add(transaction)

    # 2. Update Items if provided
    items = session.exec(
        select(TransactionItem).where(TransactionItem.transaction_id == transaction_id)
        .order_by(TransactionItem.line_no)
    ).all()
    
    if payload.items is not None:
        # Simple reconciliation: match by ID.
        existing_items_map = {item.id: item for item in items}
        
        # New list to return
        updated_items_list = []
        max_line_no: int = int(max([i.line_no for i in items] + [0]))
        
        for item_data in payload.items:
            if item_data.id and item_data.id in existing_items_map:
                # Update existing
                existing_item = existing_items_map[item_data.id]
                item_changes = item_data.model_dump(exclude_unset=True, exclude={"id"})
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
                    qty=item_data.qty,
                    unit=item_data.unit,
                    unit_price=item_data.unit_price,
                    amount=item_data.amount or Decimal("0.00"),
                    amount_before_discount=item_data.amount_before_discount,
                    discount_amount=item_data.discount_amount,
                    is_adjustment=item_data.is_adjustment or False,
                    category_id=item_data.category_id, # Must be valid UUID for existing category
                )
                session.add(new_item)
                updated_items_list.append(new_item)
                
        # Optional: You could delete items that were in `existing_items_map` but not in `payload.items`
        # if the UI sends full lists. Leaving them alone for safety right now unless fully built out.
        
        # Re-fetch for response
        items = updated_items_list

    session.commit()
    session.refresh(transaction)

    # Build response
    read = TransactionRead.model_validate(transaction)
    read.items = [TransactionItemRead.model_validate(item) for item in items]
    return read
