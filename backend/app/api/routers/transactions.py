"""Transaction API endpoints for editing and viewing ledgers."""

import logging
import uuid
from collections import defaultdict
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, or_
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.user import User
from app.schemas.transactions import TransactionItemRead, TransactionListFilter, TransactionRead, TransactionUpdateRequest

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["transactions"])


def _parse_uuid_csv(raw: str | None) -> list[uuid.UUID]:
    if not raw:
        return []
    parsed: list[uuid.UUID] = []
    for value in raw.split(","):
        value = value.strip()
        if not value:
            continue
        try:
            parsed.append(uuid.UUID(value))
        except ValueError:
            continue
    return parsed


def _get_user_visible_item_categories(session: Session, current_user: User) -> list[Category]:
    return session.exec(
        select(Category).where(
            Category.scope == CategoryScope.ITEM,
            Category.is_active == True,
            or_(Category.user_id == None, Category.user_id == current_user.id),
        )
    ).all()


def _resolve_top_level_item_category(
    category_id: uuid.UUID,
    category_by_id: dict[uuid.UUID, Category],
) -> Category | None:
    current = category_by_id.get(category_id)
    if current is None:
        return None

    visited: set[uuid.UUID] = set()
    while current.parent_id is not None and current.parent_id in category_by_id:
        if current.id in visited:
            break
        visited.add(current.id)
        current = category_by_id[current.parent_id]
    return current


def _collect_descendants(
    root_ids: set[uuid.UUID],
    children_by_parent: dict[uuid.UUID, set[uuid.UUID]],
) -> set[uuid.UUID]:
    descendants = set(root_ids)
    stack = list(root_ids)
    while stack:
        current = stack.pop()
        for child_id in children_by_parent.get(current, set()):
            if child_id in descendants:
                continue
            descendants.add(child_id)
            stack.append(child_id)
    return descendants


def _resolve_direct_child_under_top_level(
    *,
    category_id: uuid.UUID,
    top_level_id: uuid.UUID,
    category_by_id: dict[uuid.UUID, Category],
) -> Category | None:
    current = category_by_id.get(category_id)
    if current is None or current.id == top_level_id:
        return None

    visited: set[uuid.UUID] = set()
    while current.parent_id is not None and current.parent_id != top_level_id:
        if current.id in visited:
            return None
        visited.add(current.id)
        parent = category_by_id.get(current.parent_id)
        if parent is None:
            return None
        current = parent
    if current.parent_id != top_level_id:
        return None
    return current


def _build_category_filter_predicate(
    session: Session,
    current_user: User,
    category_ids_csv: str | None,
):
    descendant_item_ids, tx_category_ids = _resolve_category_filter_sets(
        session=session,
        current_user=current_user,
        category_ids_csv=category_ids_csv,
    )
    predicates = []
    if tx_category_ids:
        predicates.append(Transaction.category_id.in_(tx_category_ids))
    if descendant_item_ids:
        predicates.append(
            select(TransactionItem.transaction_id)
            .where(
                TransactionItem.transaction_id == Transaction.id,
                TransactionItem.category_id.in_(descendant_item_ids),
            )
            .exists()
        )
    if not predicates:
        return None
    return or_(*predicates)


def _resolve_category_filter_sets(
    session: Session,
    current_user: User,
    category_ids_csv: str | None,
) -> tuple[set[uuid.UUID], list[uuid.UUID]]:
    requested_ids = _parse_uuid_csv(category_ids_csv)
    if not requested_ids:
        return set(), []

    item_categories = _get_user_visible_item_categories(session, current_user)
    category_by_id = {cat.id: cat for cat in item_categories}

    selected_top_level_ids: set[uuid.UUID] = set()
    selected_codes: set[str] = set()
    for cat_id in requested_ids:
        top_level = _resolve_top_level_item_category(cat_id, category_by_id)
        if top_level is None:
            continue
        selected_top_level_ids.add(top_level.id)
        selected_codes.add(top_level.code)

    if not selected_top_level_ids and not selected_codes:
        return set(), []

    children_by_parent: dict[uuid.UUID, set[uuid.UUID]] = defaultdict(set)
    for category in item_categories:
        if category.parent_id is None:
            continue
        children_by_parent[category.parent_id].add(category.id)
    descendant_item_ids = _collect_descendants(selected_top_level_ids, children_by_parent)

    tx_category_ids: list[uuid.UUID] = []
    if selected_codes:
        tx_category_ids = session.exec(
            select(Category.id).where(
                Category.scope == CategoryScope.TRANSACTION,
                Category.code.in_(selected_codes),
                Category.is_active == True,
                or_(Category.user_id == None, Category.user_id == current_user.id),
            )
        ).all()

    return descendant_item_ids, tx_category_ids


def _build_subcategory_filter_predicate(
    session: Session,
    current_user: User,
    subcategory_ids_csv: str | None,
):
    valid_subcategory_ids = _resolve_subcategory_filter_ids(
        session=session,
        current_user=current_user,
        subcategory_ids_csv=subcategory_ids_csv,
    )
    if not valid_subcategory_ids:
        return None

    return (
        select(TransactionItem.transaction_id)
        .where(
            TransactionItem.transaction_id == Transaction.id,
            TransactionItem.category_id.in_(valid_subcategory_ids),
        )
        .exists()
    )


def _resolve_subcategory_filter_ids(
    session: Session,
    current_user: User,
    subcategory_ids_csv: str | None,
) -> set[uuid.UUID]:
    requested_ids = _parse_uuid_csv(subcategory_ids_csv)
    if not requested_ids:
        return set()

    valid_subcategory_ids = set(
        session.exec(
            select(Category.id).where(
                Category.scope == CategoryScope.ITEM,
                Category.parent_id != None,
                Category.is_active == True,
                Category.id.in_(requested_ids),
                or_(Category.user_id == None, Category.user_id == current_user.id),
            )
        ).all()
    )
    return valid_subcategory_ids


def _build_filtered_transaction_ids_query(
    *,
    session: Session,
    current_user: User,
    filters: TransactionListFilter,
):
    query = select(Transaction.id).where(Transaction.user_id == current_user.id)

    if filters.from_occurred_at:
        query = query.where(Transaction.occurred_at >= filters.from_occurred_at)
    if filters.to_occurred_at:
        query = query.where(Transaction.occurred_at <= filters.to_occurred_at)
    if filters.merchant_id:
        query = query.where(Transaction.merchant_id == filters.merchant_id)

    category_predicate = _build_category_filter_predicate(
        session,
        current_user,
        filters.category_ids,
    )
    if category_predicate is not None:
        query = query.where(category_predicate)

    subcategory_predicate = _build_subcategory_filter_predicate(
        session,
        current_user,
        filters.subcategory_ids,
    )
    if subcategory_predicate is not None:
        query = query.where(subcategory_predicate)

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

    return query


def _build_item_scope_query(
    *,
    transaction_ids_subquery,
    category_descendant_item_ids: set[uuid.UUID],
    selected_subcategory_ids: set[uuid.UUID],
):
    query = select(TransactionItem).where(
        TransactionItem.transaction_id.in_(select(transaction_ids_subquery.c.id))
    )

    has_item_filters = bool(category_descendant_item_ids or selected_subcategory_ids)
    if has_item_filters:
        if category_descendant_item_ids:
            query = query.where(TransactionItem.category_id.in_(category_descendant_item_ids))
        if selected_subcategory_ids:
            query = query.where(TransactionItem.category_id.in_(selected_subcategory_ids))

    return query, has_item_filters

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
    category_predicate = _build_category_filter_predicate(session, current_user, filters.category_ids)
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
    category_descendant_item_ids, _ = _resolve_category_filter_sets(
        session=session,
        current_user=current_user,
        category_ids_csv=filters.category_ids,
    )
    selected_subcategory_ids = _resolve_subcategory_filter_ids(
        session=session,
        current_user=current_user,
        subcategory_ids_csv=filters.subcategory_ids,
    )
    transaction_ids_subquery = _build_filtered_transaction_ids_query(
        session=session,
        current_user=current_user,
        filters=filters,
    ).subquery()

    item_scope_query, has_item_filters = _build_item_scope_query(
        transaction_ids_subquery=transaction_ids_subquery,
        category_descendant_item_ids=category_descendant_item_ids,
        selected_subcategory_ids=selected_subcategory_ids,
    )

    item_scope_subquery = item_scope_query.subquery()

    # 2. Totals
    if has_item_filters:
        total_amount_query = select(func.sum(item_scope_subquery.c.amount))
        total_amount_result = session.exec(total_amount_query).first()
        total_amount = total_amount_result or Decimal("0.00")
        total_transactions_query = select(func.count(func.distinct(item_scope_subquery.c.transaction_id)))
        total_transactions_result = session.exec(total_transactions_query).first()
        total_transactions = int(total_transactions_result or 0)
    else:
        total_query = select(
            func.sum(Transaction.amount_total),
            func.count(Transaction.id),
        ).where(Transaction.id.in_(select(transaction_ids_subquery.c.id)))
        result = session.exec(total_query).first()
        total_amount = result[0] or Decimal("0.00")
        total_transactions = result[1] or 0

    # 3. Group by category on filtered TransactionItem scope
    category_query = (
        select(
            Category.id,
            Category.name,
            Category.code,
            Category.parent_id,
            func.sum(item_scope_subquery.c.amount).label("category_total"),
            func.count(item_scope_subquery.c.id).label("item_count"),
        )
        .join(item_scope_subquery, item_scope_subquery.c.category_id == Category.id)
        .group_by(Category.id, Category.name, Category.code, Category.parent_id)
        .order_by(func.sum(item_scope_subquery.c.amount).desc())
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
    for cat_id, cat_name, cat_code, cat_parent_id, cat_total, item_count in category_results:
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
                "amount": Decimal("0"),
                "item_count": 0,
            }
        rolled_up_totals[target_id]["amount"] += cat_total
        rolled_up_totals[target_id]["item_count"] += int(item_count or 0)

    categories_breakdown = []
    for cat_id, data in rolled_up_totals.items():
        percentage = (data["amount"] / total_amount * 100) if total_amount > 0 else Decimal("0")
        categories_breakdown.append({
            "category_id": cat_id,
            "name": data["name"],
            "code": data["code"],
            "amount": float(data["amount"]),
            "percentage": float(percentage),
            "item_count": data["item_count"],
        })

    # Re-sort by amount descending since the rollup might have changed the order
    categories_breakdown.sort(key=lambda x: x["amount"], reverse=True)

    return {
        "total_amount": float(total_amount),
        "total_transactions": total_transactions,
        "currency": "EUR",
        "categories": categories_breakdown,
    }


@router.get("/transactions/summary/categories/{category_id}/subcategories")
@limiter.limit("30/minute")
async def get_category_subcategory_summary(
    request: Request,
    category_id: uuid.UUID,
    filters: Annotated[TransactionListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Get subcategory breakdown for a single top-level category."""
    item_categories = _get_user_visible_item_categories(session, current_user)
    category_by_id = {cat.id: cat for cat in item_categories}

    top_level_category = _resolve_top_level_item_category(category_id, category_by_id)
    if top_level_category is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found.",
        )

    children_by_parent: dict[uuid.UUID, set[uuid.UUID]] = defaultdict(set)
    for category in item_categories:
        if category.parent_id is None:
            continue
        children_by_parent[category.parent_id].add(category.id)
    descendant_ids = _collect_descendants({top_level_category.id}, children_by_parent)

    category_descendant_item_ids, _ = _resolve_category_filter_sets(
        session=session,
        current_user=current_user,
        category_ids_csv=filters.category_ids,
    )
    selected_subcategory_ids = _resolve_subcategory_filter_ids(
        session=session,
        current_user=current_user,
        subcategory_ids_csv=filters.subcategory_ids,
    )

    transaction_ids_subquery = _build_filtered_transaction_ids_query(
        session=session,
        current_user=current_user,
        filters=filters,
    ).subquery()
    item_scope_query, _ = _build_item_scope_query(
        transaction_ids_subquery=transaction_ids_subquery,
        category_descendant_item_ids=category_descendant_item_ids,
        selected_subcategory_ids=selected_subcategory_ids,
    )
    item_scope_query = item_scope_query.where(TransactionItem.category_id.in_(descendant_ids))
    item_scope_subquery = item_scope_query.subquery()

    category_rows = session.exec(
        select(
            item_scope_subquery.c.category_id,
            func.sum(item_scope_subquery.c.amount).label("subcategory_total"),
            func.count(item_scope_subquery.c.id).label("item_count"),
        )
        .group_by(item_scope_subquery.c.category_id)
        .order_by(func.sum(item_scope_subquery.c.amount).desc())
    ).all()

    rolled_up_subcategories: dict[uuid.UUID, dict] = {}
    for raw_category_id, amount, item_count in category_rows:
        direct_child = _resolve_direct_child_under_top_level(
            category_id=raw_category_id,
            top_level_id=top_level_category.id,
            category_by_id=category_by_id,
        )
        if direct_child is None:
            continue
        if direct_child.id not in rolled_up_subcategories:
            rolled_up_subcategories[direct_child.id] = {
                "name": direct_child.name,
                "code": direct_child.code,
                "amount": Decimal("0"),
                "item_count": 0,
            }
        rolled_up_subcategories[direct_child.id]["amount"] += amount or Decimal("0")
        rolled_up_subcategories[direct_child.id]["item_count"] += int(item_count or 0)

    rolled_up_total = sum(
        (entry["amount"] for entry in rolled_up_subcategories.values()),
        Decimal("0"),
    )

    subcategories = []
    for subcategory_id, data in rolled_up_subcategories.items():
        percentage = (
            (data["amount"] / rolled_up_total * 100)
            if rolled_up_total > 0
            else Decimal("0")
        )
        subcategories.append(
            {
                "subcategory_id": subcategory_id,
                "name": data["name"],
                "code": data["code"],
                "amount": float(data["amount"]),
                "percentage": float(percentage),
                "item_count": data["item_count"],
            }
        )
    subcategories.sort(key=lambda row: row["amount"], reverse=True)

    return {
        "category_id": top_level_category.id,
        "category_name": top_level_category.name,
        "category_code": top_level_category.code,
        "total_amount": float(rolled_up_total),
        "currency": "EUR",
        "subcategories": subcategories,
    }


@router.get("/transactions/summary/subcategories/{subcategory_id}/items")
@limiter.limit("30/minute")
async def get_subcategory_item_summary(
    request: Request,
    subcategory_id: uuid.UUID,
    filters: Annotated[TransactionListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Get purchased item breakdown for one subcategory."""
    subcategory = session.exec(
        select(Category).where(
            Category.id == subcategory_id,
            Category.scope == CategoryScope.ITEM,
            Category.parent_id != None,
            Category.is_active == True,
            or_(Category.user_id == None, Category.user_id == current_user.id),
        )
    ).first()
    if subcategory is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Subcategory not found.",
        )

    category_descendant_item_ids, _ = _resolve_category_filter_sets(
        session=session,
        current_user=current_user,
        category_ids_csv=filters.category_ids,
    )
    selected_subcategory_ids = _resolve_subcategory_filter_ids(
        session=session,
        current_user=current_user,
        subcategory_ids_csv=filters.subcategory_ids,
    )

    transaction_ids_subquery = _build_filtered_transaction_ids_query(
        session=session,
        current_user=current_user,
        filters=filters,
    ).subquery()
    item_scope_query, _ = _build_item_scope_query(
        transaction_ids_subquery=transaction_ids_subquery,
        category_descendant_item_ids=category_descendant_item_ids,
        selected_subcategory_ids=selected_subcategory_ids,
    )
    item_scope_query = item_scope_query.where(TransactionItem.category_id == subcategory_id)
    item_scope_subquery = item_scope_query.subquery()

    total_amount_result = session.exec(select(func.sum(item_scope_subquery.c.amount))).first()
    total_amount = total_amount_result or Decimal("0")

    description_expr = func.coalesce(
        func.nullif(func.trim(item_scope_subquery.c.description), ""),
        "Unknown item",
    )
    item_rows = session.exec(
        select(
            description_expr.label("description"),
            func.sum(item_scope_subquery.c.amount).label("item_total"),
            func.count(item_scope_subquery.c.id).label("occurrences"),
            func.sum(item_scope_subquery.c.qty).label("qty_total"),
            func.max(item_scope_subquery.c.unit).label("unit"),
        )
        .group_by(description_expr)
        .order_by(func.sum(item_scope_subquery.c.amount).desc())
    ).all()

    items = []
    total_item_rows = 0
    for description, item_total, occurrences, qty_total, unit in item_rows:
        qty_value = qty_total if qty_total is not None else None
        avg_unit_price = None
        if qty_value not in (None, 0):
            avg_unit_price = float((item_total or Decimal("0")) / qty_value)

        total_item_rows += int(occurrences or 0)
        items.append(
            {
                "description": description,
                "amount": float(item_total or Decimal("0")),
                "occurrences": int(occurrences or 0),
                "total_qty": float(qty_value) if qty_value is not None else None,
                "unit": unit,
                "avg_unit_price": avg_unit_price,
            }
        )

    return {
        "subcategory_id": subcategory.id,
        "subcategory_name": subcategory.name,
        "subcategory_code": subcategory.code,
        "total_amount": float(total_amount),
        "currency": "EUR",
        "total_items": total_item_rows,
        "items": items,
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


@router.delete("/transactions/{transaction_id}/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
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
            Transaction.user_id == current_user.id,
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
        select(func.sum(TransactionItem.amount)).where(TransactionItem.transaction_id == transaction_id)
    ).first()
    transaction.amount_total = remaining_total or Decimal("0.00")
    session.add(transaction)
    session.commit()
    return None
