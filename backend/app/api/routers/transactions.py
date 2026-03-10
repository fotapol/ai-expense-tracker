"""Transaction API endpoints for editing and viewing ledgers."""

import logging
import uuid
from collections import defaultdict
from decimal import Decimal
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import TypeAdapter
from sqlalchemy import func, or_
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.labels.label import Label
from app.models.labels.transaction_label import TransactionLabel
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.translations.item_translation import ItemTranslation
from app.models.users.user import User
from app.schemas.extraction import ExtractionWarning
from app.schemas.item_translations import normalized_source_text_key
from app.schemas.shared import (
    normalize_currency_code,
    normalize_language_code,
    quantize_amount,
    quantize_unit_price,
)
from app.schemas.transactions import (
    TransactionItemRead,
    TransactionLabelRead,
    TransactionListFilter,
    TransactionRead,
    TransactionUpdateRequest,
)
from app.services.fx_rates import convert_amount, resolve_conversion_date

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["transactions"])
_warnings_adapter = TypeAdapter(list[ExtractionWarning])


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


def _resolve_label_filter_ids(filters: TransactionListFilter) -> set[uuid.UUID]:
    label_ids = set(_parse_uuid_csv(filters.label_ids))
    if filters.label_id is not None:
        label_ids.add(filters.label_id)
    return label_ids


def _resolve_target_currency(filters: TransactionListFilter, current_user: User) -> str:
    return normalize_currency_code(filters.target_currency or current_user.default_currency)


def _resolve_item_language(
    *,
    item_language: str | None,
    app_language: str | None,
    current_user: User,
) -> str | None:
    for candidate in (item_language, current_user.items_language, app_language):
        if not candidate:
            continue
        normalized = normalize_language_code(candidate)
        if normalized:
            return normalized
    return None


def _load_translation_lookup(
    session: Session,
    *,
    current_user: User,
    target_language: str | None,
    source_entries: list[tuple[str, str]],
) -> dict[tuple[str, str, str], str]:
    if not target_language or not source_entries:
        return {}

    normalized_texts = {normalized_source_text_key(text) for text, _ in source_entries if text.strip()}
    source_languages = {normalize_language_code(lang) for _, lang in source_entries if lang.strip()}
    if not normalized_texts or not source_languages:
        return {}

    rows = session.exec(
        select(ItemTranslation).where(
            ItemTranslation.user_id == current_user.id,
            ItemTranslation.target_language == target_language,
            ItemTranslation.normalized_source_text.in_(normalized_texts),
            ItemTranslation.source_language.in_(source_languages),
        )
    ).all()

    return {
        (row.normalized_source_text, row.source_language, row.target_language): row.translated_text
        for row in rows
    }


def _enrich_transaction_items_with_translations(
    *,
    items: list[TransactionItemRead],
    target_language: str | None,
    lookup: dict[tuple[str, str, str], str],
) -> None:
    for item in items:
        item.translated_description = None
        item.translation_language = None
        item.translation_source_language = None
        if not target_language:
            continue
        if item.description_lang is None or not item.description_lang.strip():
            continue

        source_language = normalize_language_code(item.description_lang)
        key = (
            normalized_source_text_key(item.description),
            source_language,
            target_language,
        )
        translated = lookup.get(key)
        if translated is None:
            continue

        item.translated_description = translated
        item.translation_language = target_language
        item.translation_source_language = source_language


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
    label_filter_ids = _resolve_label_filter_ids(filters)
    if label_filter_ids:
        label_subquery = (
            select(TransactionLabel.transaction_id)
            .join(Label, Label.id == TransactionLabel.label_id)
            .where(
                TransactionLabel.label_id.in_(label_filter_ids),
                Label.user_id == current_user.id,
                Label.is_active == True,
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


def _extract_warnings_from_structured_json(structured_json: dict[str, Any] | None) -> list[ExtractionWarning]:
    if not isinstance(structured_json, dict):
        return []
    raw_warnings = structured_json.get("warnings")
    if not isinstance(raw_warnings, list):
        return []
    try:
        return _warnings_adapter.validate_python(raw_warnings)
    except Exception:
        logger.warning("Failed to parse extraction warnings payload.", exc_info=True)
        return []


def _load_labels_by_transaction_id(
    session: Session,
    *,
    transaction_ids: list[uuid.UUID],
    current_user: User,
) -> dict[uuid.UUID, list[TransactionLabelRead]]:
    if not transaction_ids:
        return {}

    rows = session.exec(
        select(
            TransactionLabel.transaction_id,
            Label.id,
            Label.name,
            Label.color,
        )
        .join(Label, Label.id == TransactionLabel.label_id)
        .where(
            TransactionLabel.transaction_id.in_(transaction_ids),
            Label.user_id == current_user.id,
            Label.is_active == True,
        )
        .order_by(Label.name.asc())
    ).all()

    labels_by_tx: dict[uuid.UUID, list[TransactionLabelRead]] = defaultdict(list)
    for transaction_id, label_id, name, color in rows:
        labels_by_tx[transaction_id].append(
            TransactionLabelRead(id=label_id, name=name, color=color)
        )
    return labels_by_tx


def _load_category_names_by_id(
    session: Session,
    *,
    category_ids: list[uuid.UUID],
) -> dict[uuid.UUID, str]:
    if not category_ids:
        return {}

    rows = session.exec(
        select(Category.id, Category.name).where(Category.id.in_(category_ids))
    ).all()
    return {category_id: name for category_id, name in rows}


def _load_warnings_by_receipt_id(
    session: Session,
    *,
    receipt_ids: list[uuid.UUID],
) -> dict[uuid.UUID, list[ExtractionWarning]]:
    if not receipt_ids:
        return {}

    rows = session.exec(
        select(ReceiptExtraction.receipt_id, ReceiptExtraction.structured_json).where(
            ReceiptExtraction.receipt_id.in_(receipt_ids)
        )
    ).all()

    warnings_by_receipt: dict[uuid.UUID, list[ExtractionWarning]] = {}
    for receipt_id, structured_json in rows:
        warnings_by_receipt[receipt_id] = _extract_warnings_from_structured_json(structured_json)
    return warnings_by_receipt


def _apply_display_conversion(
    *,
    read: TransactionRead,
    session: Session,
    target_currency: str,
) -> None:
    conversion_date = resolve_conversion_date(read.occurred_at, read.created_at)
    tx_converted = convert_amount(
        amount=read.amount_total,
        base_currency=read.currency,
        target_currency=target_currency,
        target_date=conversion_date,
        session=session,
        quantizer=quantize_amount,
    )

    read.display_currency = tx_converted.currency
    read.display_amount_total = tx_converted.value
    read.display_rate_date = tx_converted.rate_date
    read.display_rate_fallback = tx_converted.rate_fallback

    for item in read.items:
        amount_converted = convert_amount(
            amount=item.amount,
            base_currency=read.currency,
            target_currency=target_currency,
            target_date=conversion_date,
            session=session,
            quantizer=quantize_amount,
        )
        unit_price_converted = convert_amount(
            amount=item.unit_price,
            base_currency=read.currency,
            target_currency=target_currency,
            target_date=conversion_date,
            session=session,
            quantizer=quantize_unit_price,
        )
        item.display_amount = amount_converted.value
        item.display_unit_price = unit_price_converted.value

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
    label_filter_ids = _resolve_label_filter_ids(filters)
    if label_filter_ids:
        label_subquery = (
            select(TransactionLabel.transaction_id)
            .join(Label, Label.id == TransactionLabel.label_id)
            .where(
                TransactionLabel.label_id.in_(label_filter_ids),
                Label.user_id == current_user.id,
                Label.is_active == True,
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
    if transactions: # Only fetch items if transactions exist to save an empty query
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
        
        items_by_tx = {}
        for item in items:
            items_by_tx.setdefault(item.transaction_id, []).append(item)
            
        for t in transactions:
            read = TransactionRead.model_validate(t)
            tx_items = items_by_tx.get(t.id, [])
            read.items = [TransactionItemRead.model_validate(i) for i in sorted(tx_items, key=lambda x: x.line_no)]
            read.labels = labels_by_tx.get(t.id, [])
            read.category_name = (
                category_names_by_id.get(t.category_id) if t.category_id is not None else None
            )
            tx_warnings = warnings_by_receipt.get(t.receipt_id, []) if t.receipt_id else []
            read.has_extraction_warnings = len(tx_warnings) > 0
            _apply_display_conversion(
                read=read,
                session=session,
                target_currency=target_currency,
            )
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
    target_currency = _resolve_target_currency(filters, current_user)
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
        total_item_rows = session.exec(
            select(
                item_scope_subquery.c.transaction_id,
                item_scope_subquery.c.amount,
                Transaction.currency,
                Transaction.occurred_at,
                Transaction.created_at,
            ).join(
                Transaction,
                Transaction.id == item_scope_subquery.c.transaction_id,
            )
        ).all()
        total_amount = Decimal("0.00")
        tx_ids: set[uuid.UUID] = set()
        for tx_id, amount, tx_currency, tx_occurred_at, tx_created_at in total_item_rows:
            tx_ids.add(tx_id)
            converted = convert_amount(
                amount=amount,
                base_currency=tx_currency,
                target_currency=target_currency,
                target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
                session=session,
                quantizer=quantize_amount,
            )
            total_amount += converted.value if converted.value is not None else quantize_amount(amount)
        total_transactions = len(tx_ids)
    else:
        transaction_rows = session.exec(
            select(
                Transaction.amount_total,
                Transaction.currency,
                Transaction.occurred_at,
                Transaction.created_at,
            ).where(Transaction.id.in_(select(transaction_ids_subquery.c.id)))
        ).all()
        total_amount = Decimal("0.00")
        for amount_total, tx_currency, tx_occurred_at, tx_created_at in transaction_rows:
            converted = convert_amount(
                amount=amount_total,
                base_currency=tx_currency,
                target_currency=target_currency,
                target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
                session=session,
                quantizer=quantize_amount,
            )
            if amount_total is not None:
                total_amount += (
                    converted.value if converted.value is not None else quantize_amount(amount_total)
                )
        total_transactions = len(transaction_rows)

    # 3. Group by category on filtered TransactionItem scope and convert row-by-row
    category_item_rows = session.exec(
        select(
            Category.id,
            Category.name,
            Category.code,
            Category.parent_id,
            item_scope_subquery.c.amount,
            item_scope_subquery.c.transaction_id,
            Transaction.currency,
            Transaction.occurred_at,
            Transaction.created_at,
        )
        .join(item_scope_subquery, item_scope_subquery.c.category_id == Category.id)
        .join(Transaction, Transaction.id == item_scope_subquery.c.transaction_id)
    ).all()

    category_results: dict[uuid.UUID, dict[str, Any]] = {}
    for (
        cat_id,
        cat_name,
        cat_code,
        cat_parent_id,
        amount,
        _tx_id,
        tx_currency,
        tx_occurred_at,
        tx_created_at,
    ) in category_item_rows:
        converted = convert_amount(
            amount=amount,
            base_currency=tx_currency,
            target_currency=target_currency,
            target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
            session=session,
            quantizer=quantize_amount,
        )
        converted_amount = converted.value if converted.value is not None else quantize_amount(amount)
        if cat_id not in category_results:
            category_results[cat_id] = {
                "name": cat_name,
                "code": cat_code,
                "parent_id": cat_parent_id,
                "amount": Decimal("0"),
                "item_count": 0,
            }
        category_results[cat_id]["amount"] += converted_amount
        category_results[cat_id]["item_count"] += 1

    # Pre-fetch all parent categories to get their names and codes if we need to roll up
    parent_ids = {cat_data["parent_id"] for cat_data in category_results.values() if cat_data["parent_id"] is not None}

    parent_map = {}
    if parent_ids:
        parents = session.exec(select(Category).where(Category.id.in_(parent_ids))).all()
        for p in parents:
            parent_map[p.id] = {"name": p.name, "code": p.code}

    # Roll up totals into parents
    rolled_up_totals = {}
    for cat_id, cat_data in category_results.items():
        cat_name = cat_data["name"]
        cat_code = cat_data["code"]
        cat_parent_id = cat_data["parent_id"]
        cat_total = cat_data["amount"]
        item_count = cat_data["item_count"]
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

    # 4. Discount analytics on filtered TransactionItem scope
    discount_rows = session.exec(
        select(
            item_scope_subquery.c.description,
            item_scope_subquery.c.discount_amount,
            item_scope_subquery.c.amount_before_discount,
            item_scope_subquery.c.qty,
            item_scope_subquery.c.unit_price,
            item_scope_subquery.c.amount,
            Transaction.currency,
            Transaction.occurred_at,
            Transaction.created_at,
        )
        .join(Transaction, Transaction.id == item_scope_subquery.c.transaction_id)
    ).all()

    total_savings = Decimal("0")
    items_with_discount = 0
    biggest_discount_entry: dict[str, Any] | None = None
    biggest_discount_amount = Decimal("0")

    for (
        description,
        discount_amount,
        amount_before_discount,
        qty,
        unit_price,
        line_amount,
        tx_currency,
        tx_occurred_at,
        tx_created_at,
    ) in discount_rows:
        effective_discount = discount_amount
        if effective_discount is None and amount_before_discount is not None and line_amount is not None:
            derived_discount = quantize_amount(amount_before_discount - line_amount)
            if derived_discount > 0:
                effective_discount = derived_discount
        if effective_discount is None and qty is not None and unit_price is not None and line_amount is not None:
            derived_discount = quantize_amount((qty * unit_price) - line_amount)
            if derived_discount > 0:
                effective_discount = derived_discount

        if effective_discount is None:
            continue

        discount_abs = quantize_amount(abs(effective_discount))
        if discount_abs <= 0:
            continue

        items_with_discount += 1
        converted_discount = convert_amount(
            amount=discount_abs,
            base_currency=tx_currency,
            target_currency=target_currency,
            target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
            session=session,
            quantizer=quantize_amount,
        )
        converted_discount_value = (
            converted_discount.value
            if converted_discount.value is not None
            else discount_abs
        )
        total_savings += converted_discount_value

        base_before = amount_before_discount
        if base_before is None and line_amount is not None:
            base_before = quantize_amount(line_amount + discount_abs)

        percentage = None
        if base_before is not None and base_before > 0:
            converted_before = convert_amount(
                amount=base_before,
                base_currency=tx_currency,
                target_currency=target_currency,
                target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
                session=session,
                quantizer=quantize_amount,
            )
            converted_before_value = (
                converted_before.value
                if converted_before.value is not None
                else quantize_amount(base_before)
            )
            if converted_before_value > 0:
                percentage = float(
                    quantize_amount((converted_discount_value / converted_before_value) * 100)
                )

        if converted_discount_value > biggest_discount_amount:
            biggest_discount_amount = converted_discount_value
            biggest_discount_entry = {
                "description": (description or "").strip() or "Unknown item",
                "amount": float(converted_discount_value),
                "percentage": percentage,
            }

    return {
        "total_amount": float(total_amount),
        "total_transactions": total_transactions,
        "currency": target_currency,
        "categories": categories_breakdown,
        "discounts": {
            "total_savings": float(total_savings),
            "items_with_discount": items_with_discount,
            "biggest_discount": biggest_discount_entry,
        },
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
    target_currency = _resolve_target_currency(filters, current_user)
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
            item_scope_subquery.c.amount,
            item_scope_subquery.c.transaction_id,
            Transaction.currency,
            Transaction.occurred_at,
            Transaction.created_at,
        )
        .join(Transaction, Transaction.id == item_scope_subquery.c.transaction_id)
    ).all()

    rolled_up_subcategories: dict[uuid.UUID, dict] = {}
    for raw_category_id, amount, _tx_id, tx_currency, tx_occurred_at, tx_created_at in category_rows:
        converted = convert_amount(
            amount=amount,
            base_currency=tx_currency,
            target_currency=target_currency,
            target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
            session=session,
            quantizer=quantize_amount,
        )
        converted_amount = converted.value if converted.value is not None else quantize_amount(amount)
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
        rolled_up_subcategories[direct_child.id]["amount"] += converted_amount
        rolled_up_subcategories[direct_child.id]["item_count"] += 1

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
        "currency": target_currency,
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
    target_currency = _resolve_target_currency(filters, current_user)
    effective_item_language = _resolve_item_language(
        item_language=filters.item_language,
        app_language=filters.app_language,
        current_user=current_user,
    )
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

    item_rows = session.exec(
        select(
            item_scope_subquery.c.description,
            item_scope_subquery.c.description_lang,
            item_scope_subquery.c.amount,
            item_scope_subquery.c.qty,
            item_scope_subquery.c.unit,
            Transaction.currency,
            Transaction.occurred_at,
            Transaction.created_at,
        )
        .join(Transaction, Transaction.id == item_scope_subquery.c.transaction_id)
    ).all()

    total_amount = Decimal("0")
    grouped: dict[tuple[str, str | None], dict[str, Any]] = {}
    for (
        description,
        description_lang,
        amount,
        qty,
        unit,
        tx_currency,
        tx_occurred_at,
        tx_created_at,
    ) in item_rows:
        clean_description = (description or "").strip() or "Unknown item"
        converted = convert_amount(
            amount=amount,
            base_currency=tx_currency,
            target_currency=target_currency,
            target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
            session=session,
            quantizer=quantize_amount,
        )
        converted_amount = converted.value if converted.value is not None else quantize_amount(amount)
        total_amount += converted_amount

        entry = grouped.setdefault(
            (clean_description, normalize_language_code(description_lang) if description_lang else None),
            {
                "amount": Decimal("0"),
                "occurrences": 0,
                "total_qty": None,
                "unit": unit,
            },
        )
        entry["amount"] += converted_amount
        entry["occurrences"] += 1
        if entry["unit"] is None and unit is not None:
            entry["unit"] = unit

        if qty is not None:
            if entry["total_qty"] is None:
                entry["total_qty"] = qty
            else:
                entry["total_qty"] += qty

    translation_lookup = _load_translation_lookup(
        session,
        current_user=current_user,
        target_language=effective_item_language,
        source_entries=[
            (description, description_lang)
            for (description, description_lang) in grouped.keys()
            if description_lang is not None
        ],
    )

    items = []
    total_item_rows = 0
    for (description, description_lang), row in grouped.items():
        item_total = row["amount"]
        occurrences = int(row["occurrences"] or 0)
        qty_total = row["total_qty"]
        unit = row["unit"]
        qty_value = qty_total if qty_total is not None else None
        avg_unit_price = None
        if qty_value not in (None, 0):
            avg_unit_price = float((item_total or Decimal("0")) / qty_value)

        translated_description = None
        translation_language = None
        translation_source_language = None
        if effective_item_language and description_lang:
            source_lang = normalize_language_code(description_lang)
            translated_description = translation_lookup.get(
                (
                    normalized_source_text_key(description),
                    source_lang,
                    effective_item_language,
                )
            )
            if translated_description is not None:
                translation_language = effective_item_language
                translation_source_language = source_lang

        total_item_rows += occurrences
        items.append(
            {
                "description": description,
                "description_lang": description_lang,
                "amount": float(item_total or Decimal("0")),
                "occurrences": occurrences,
                "total_qty": float(qty_value) if qty_value is not None else None,
                "unit": unit,
                "avg_unit_price": avg_unit_price,
                "translated_description": translated_description,
                "translation_language": translation_language,
                "translation_source_language": translation_source_language,
            }
        )
    items.sort(key=lambda row: row["amount"], reverse=True)

    return {
        "subcategory_id": subcategory.id,
        "subcategory_name": subcategory.name,
        "subcategory_code": subcategory.code,
        "total_amount": float(total_amount),
        "currency": target_currency,
        "total_items": total_item_rows,
        "items": items,
    }


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
    effective_item_language = _resolve_item_language(
        item_language=item_language,
        app_language=app_language,
        current_user=current_user,
    )
    translation_lookup = _load_translation_lookup(
        session,
        current_user=current_user,
        target_language=effective_item_language,
        source_entries=[
            (item.description, item.description_lang)
            for item in read.items
            if item.description_lang is not None
        ],
    )
    _enrich_transaction_items_with_translations(
        items=read.items,
        target_language=effective_item_language,
        lookup=translation_lookup,
    )
    read.category_name = (
        session.exec(
            select(Category.name).where(Category.id == transaction.category_id)
        ).first()
        if transaction.category_id is not None
        else None
    )
    read.labels = _load_labels_by_transaction_id(
        session,
        transaction_ids=[transaction.id],
        current_user=current_user,
    ).get(transaction.id, [])
    tx_warnings = []
    if transaction.receipt_id is not None:
        tx_warnings = _load_warnings_by_receipt_id(
            session,
            receipt_ids=[transaction.receipt_id],
        ).get(transaction.receipt_id, [])
    read.has_extraction_warnings = len(tx_warnings) > 0
    read.extraction_warnings = tx_warnings
    _apply_display_conversion(
        read=read,
        session=session,
        target_currency=normalize_currency_code(target_currency or current_user.default_currency),
    )
    return read


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
    effective_item_language = _resolve_item_language(
        item_language=item_language,
        app_language=app_language,
        current_user=current_user,
    )
    translation_lookup = _load_translation_lookup(
        session,
        current_user=current_user,
        target_language=effective_item_language,
        source_entries=[
            (item.description, item.description_lang)
            for item in read.items
            if item.description_lang is not None
        ],
    )
    _enrich_transaction_items_with_translations(
        items=read.items,
        target_language=effective_item_language,
        lookup=translation_lookup,
    )
    read.category_name = (
        session.exec(
            select(Category.name).where(Category.id == transaction.category_id)
        ).first()
        if transaction.category_id is not None
        else None
    )
    read.labels = _load_labels_by_transaction_id(
        session,
        transaction_ids=[transaction.id],
        current_user=current_user,
    ).get(transaction.id, [])
    tx_warnings = []
    if transaction.receipt_id is not None:
        tx_warnings = _load_warnings_by_receipt_id(
            session,
            receipt_ids=[transaction.receipt_id],
        ).get(transaction.receipt_id, [])
    read.has_extraction_warnings = len(tx_warnings) > 0
    read.extraction_warnings = tx_warnings
    _apply_display_conversion(
        read=read,
        session=session,
        target_currency=normalize_currency_code(target_currency or current_user.default_currency),
    )
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
