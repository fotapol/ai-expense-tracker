"""Transaction route handlers."""

import logging
import uuid
from collections import defaultdict
from decimal import Decimal
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import or_
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.user import User
from app.schemas.item_translations import normalized_source_text_key
from app.schemas.shared import (
    normalize_language_code,
    quantize_amount,
)
from app.schemas.transactions import (
    AnalyticsTrendBucketRead,
    AnalyticsTrendSummaryRead,
    TransactionListFilter,
)
from app.services.billing.entitlements import user_has_feature
from app.services.billing.features import PREMIUM_ANALYTICS_ADVANCED
from app.services.fx_rates import convert_amount, resolve_conversion_date
from app.services.transactions.read_models import (
    _build_analytics_scope,
    _build_filtered_transaction_ids_query,
    _build_item_scope_query,
    _build_previous_period_filters,
    _collect_descendants,
    _convert_analytics_amount,
    _format_trend_bucket_label,
    _get_user_visible_item_categories,
    _infer_analytics_bucket_unit,
    _iter_trend_bucket_ranges,
    _load_analytics_spend_rows,
    _load_translation_lookup,
    _preferred_item_translation_source_values,
    _resolve_analytics_period_bounds,
    _resolve_category_filter_sets,
    _resolve_direct_child_under_top_level,
    _resolve_item_language,
    _resolve_subcategory_filter_ids,
    _resolve_target_currency,
    _resolve_top_level_item_category,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["transactions"])

@router.get("/transactions/summary")
@limiter.limit("30/minute")
async def get_transactions_summary(
    request: Request,
    filters: Annotated[TransactionListFilter, Depends()],
    group_by: str = "category",
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Get aggregated summary of transactions split by category."""
    breakdown_mode = (group_by or "category").strip().lower()
    if breakdown_mode not in {"category", "subcategory"}:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="group_by must be either 'category' or 'subcategory'.",
        )
    if breakdown_mode == "subcategory" and not user_has_feature(
        session,
        current_user.id,
        PREMIUM_ANALYTICS_ADVANCED,
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Advanced analytics is required for subcategory breakdowns.",
        )

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
            total_amount += (
                converted.value if converted.value is not None else quantize_amount(amount)
            )
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
                val = converted.value
                total_amount += val if val is not None else quantize_amount(amount_total)
        total_transactions = len(transaction_rows)

    # 3. Group by category on filtered TransactionItem scope and convert row-by-row
    category_item_rows = session.exec(
        select(
            Category.id,
            Category.name,
            Category.code,
            Category.parent_id,
            Category.color,
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
        cat_color,
        amount,
        tx_id,
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
        val = converted.value
        converted_amount = val if val is not None else quantize_amount(amount)
        if cat_id not in category_results:
            category_results[cat_id] = {
                "name": cat_name,
                "code": cat_code,
                "parent_id": cat_parent_id,
                "color": cat_color,
                "amount": Decimal("0"),
                "item_count": 0,
                "transaction_ids": set(),
            }
        category_results[cat_id]["amount"] = category_results[cat_id]["amount"] + converted_amount
        category_results[cat_id]["item_count"] = category_results[cat_id]["item_count"] + 1
        category_results[cat_id]["transaction_ids"].add(tx_id)

    # Pre-fetch all parent categories to get their names and codes if we need to roll up
    parent_ids = {
        cat_data["parent_id"]
        for cat_data in category_results.values()
        if cat_data["parent_id"] is not None
    }

    parent_map = {}
    if parent_ids:
        parents = session.exec(select(Category).where(Category.id.in_(parent_ids))).all()
        for p in parents:
            parent_map[p.id] = {"name": p.name, "code": p.code, "color": p.color}

    # Roll up totals into parents
    rolled_up_totals = {}
    for cat_id, cat_data in category_results.items():
        cat_name = cat_data["name"]
        cat_code = cat_data["code"]
        cat_parent_id = cat_data["parent_id"]
        cat_color = cat_data["color"]
        cat_total = cat_data["amount"]
        item_count = cat_data["item_count"]
        if cat_parent_id:
            # It's a subcategory, roll it into the parent
            target_id = cat_parent_id
            target_name = parent_map.get(cat_parent_id, {}).get("name", "Unknown Parent")
            target_code = parent_map.get(cat_parent_id, {}).get("code", "OTHER")
            target_color = parent_map.get(cat_parent_id, {}).get("color")
        else:
            # It's already a top-level category
            target_id = cat_id
            target_name = cat_name
            target_code = cat_code
            target_color = cat_color

        if target_id not in rolled_up_totals:
            rolled_up_totals[target_id] = {
                "name": target_name,
                "code": target_code,
                "color": target_color,
                "amount": Decimal("0"),
                "item_count": 0,
            }
        rolled_up_totals[target_id]["amount"] = rolled_up_totals[target_id]["amount"] + cat_total
        rolled_up_totals[target_id]["item_count"] = rolled_up_totals[target_id]["item_count"] + int(
            item_count or 0
        )

    categories_breakdown = []
    for cat_id, data in rolled_up_totals.items():
        amt: Decimal = data["amount"]
        percentage = (amt / total_amount * 100) if total_amount > 0 else Decimal("0")
        categories_breakdown.append(
            {
                "category_id": cat_id,
                "name": data["name"],
                "code": data["code"],
                "color": data.get("color"),
                "amount": float(data["amount"]),
                "percentage": float(percentage),
                "item_count": data["item_count"],
            }
        )

    # Re-sort by amount descending since the rollup might have changed the order
    categories_breakdown.sort(key=lambda x: x["amount"], reverse=True)

    subcategory_breakdown = []
    subcategory_total_amount = Decimal("0")
    subcategory_transaction_ids: set[uuid.UUID] = set()
    for cat_id, data in category_results.items():
        if data["parent_id"] is None:
            continue
        amt: Decimal = data["amount"]
        subcategory_total_amount += amt
        subcategory_transaction_ids.update(data["transaction_ids"])
        parent_id = data["parent_id"]
        parent_name = parent_map.get(data["parent_id"], {}).get("name", data["name"])
        parent_code = parent_map.get(data["parent_id"], {}).get("code", data["code"])
        parent_color = parent_map.get(data["parent_id"], {}).get("color")
        subcategory_name = data["name"]
        subcategory_code = data["code"]
        # H-4 fix: do NOT compute percentage here; denominator is still growing.
        # The second pass below computes correct percentages once the total is final.
        subcategory_breakdown.append(
            {
                "subcategory_id": cat_id,
                "name": subcategory_name,
                "code": subcategory_code,
                "color": data.get("color"),
                "amount": float(data["amount"]),
                "percentage": 0.0,  # filled in by second pass below
                "item_count": data["item_count"],
                "parent_category_id": parent_id,
                "parent_category_name": parent_name,
                "parent_category_code": parent_code,
                "parent_category_color": parent_color,
            }
        )
    if subcategory_breakdown:
        for row in subcategory_breakdown:
            amount_decimal = Decimal(str(row["amount"]))
            row["percentage"] = float(
                (amount_decimal / subcategory_total_amount * 100)
                if subcategory_total_amount > 0
                else Decimal("0")
            )
    subcategory_breakdown.sort(key=lambda x: x["amount"], reverse=True)

    if breakdown_mode == "subcategory":
        total_amount = subcategory_total_amount
        total_transactions = len(subcategory_transaction_ids)

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
        ).join(Transaction, Transaction.id == item_scope_subquery.c.transaction_id)
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
        if (
            effective_discount is None
            and amount_before_discount is not None
            and line_amount is not None
        ):
            derived_discount = quantize_amount(amount_before_discount - line_amount)
            if derived_discount > 0:
                effective_discount = derived_discount
        if (
            effective_discount is None
            and qty is not None
            and unit_price is not None
            and line_amount is not None
        ):
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
            converted_discount.value if converted_discount.value is not None else discount_abs
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
        "breakdown_mode": breakdown_mode,
        "breakdown": (
            subcategory_breakdown if breakdown_mode == "subcategory" else categories_breakdown
        ),
        "categories": categories_breakdown if breakdown_mode == "category" else [],
        "discounts": {
            "total_savings": float(total_savings),
            "items_with_discount": items_with_discount,
            "biggest_discount": biggest_discount_entry,
        },
    }

@router.get("/transactions/summary/trends", response_model=AnalyticsTrendSummaryRead)
@limiter.limit("30/minute")
async def get_transaction_trend_summary(
    request: Request,
    filters: Annotated[TransactionListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return bucketed spend trends for the selected analytics range."""

    bucket_unit = _infer_analytics_bucket_unit(filters)
    current_start_at, current_end_at = _resolve_analytics_period_bounds(filters)
    (
        target_currency,
        transaction_ids_subquery,
        item_scope_subquery,
        has_item_filters,
    ) = _build_analytics_scope(
        session=session,
        current_user=current_user,
        filters=filters,
    )
    current_rows = _load_analytics_spend_rows(
        session,
        transaction_ids_subquery=transaction_ids_subquery,
        item_scope_subquery=item_scope_subquery,
        has_item_filters=has_item_filters,
    )

    previous_total_amount: Decimal | None = None
    previous_filters = _build_previous_period_filters(filters)
    if previous_filters is not None:
        (
            _previous_currency,
            previous_transaction_ids_subquery,
            previous_item_scope_subquery,
            previous_has_item_filters,
        ) = _build_analytics_scope(
            session=session,
            current_user=current_user,
            filters=previous_filters,
        )
        previous_rows = _load_analytics_spend_rows(
            session,
            transaction_ids_subquery=previous_transaction_ids_subquery,
            item_scope_subquery=previous_item_scope_subquery,
            has_item_filters=previous_has_item_filters,
        )
        previous_total_amount = Decimal("0.00")
        for (
            _tx_id,
            amount,
            tx_currency,
            tx_occurred_at,
            tx_created_at,
            _owner_user_id,
            _user_id,
        ) in previous_rows:
            previous_total_amount += _convert_analytics_amount(
                session=session,
                amount=amount,
                currency=tx_currency,
                target_currency=target_currency,
                occurred_at=tx_occurred_at,
                created_at=tx_created_at,
            )

    row_dates = [
        resolve_conversion_date(tx_occurred_at, tx_created_at)
        for (
            _tx_id,
            _amount,
            _tx_currency,
            tx_occurred_at,
            tx_created_at,
            _owner_user_id,
            _user_id,
        ) in current_rows
    ]
    effective_start_date = (
        current_start_at.date()
        if current_start_at is not None
        else (min(row_dates) if row_dates else current_end_at.date())
    )
    effective_end_date = current_end_at.date()
    bucket_ranges = _iter_trend_bucket_ranges(
        start_date=effective_start_date,
        end_date=effective_end_date,
        bucket_unit=bucket_unit,
    )
    bucket_state = [
        {
            "start_date": start_date,
            "end_date": end_date,
            "label": _format_trend_bucket_label(
                start_date=start_date,
                end_date=end_date,
                bucket_unit=bucket_unit,
            ),
            "amount": Decimal("0.00"),
            "transaction_ids": set(),
        }
        for start_date, end_date in bucket_ranges
    ]

    current_total_amount = Decimal("0.00")
    for (
        tx_id,
        amount,
        tx_currency,
        tx_occurred_at,
        tx_created_at,
        _owner_user_id,
        _user_id,
    ) in current_rows:
        converted_amount = _convert_analytics_amount(
            session=session,
            amount=amount,
            currency=tx_currency,
            target_currency=target_currency,
            occurred_at=tx_occurred_at,
            created_at=tx_created_at,
        )
        current_total_amount += converted_amount
        spend_date = resolve_conversion_date(tx_occurred_at, tx_created_at)
        for bucket in bucket_state:
            if bucket["start_date"] <= spend_date <= bucket["end_date"]:
                bucket["amount"] += converted_amount
                bucket["transaction_ids"].add(tx_id)
                break

    change_percentage = None
    if previous_total_amount is not None and previous_total_amount > 0:
        delta_ratio = (
            (current_total_amount - previous_total_amount) / previous_total_amount
        ) * Decimal("100")
        change_percentage = float(quantize_amount(delta_ratio))

    return AnalyticsTrendSummaryRead(
        currency=target_currency,
        bucket_unit=bucket_unit,  # type: ignore[arg-type]
        current_total_amount=quantize_amount(current_total_amount),
        previous_total_amount=(
            quantize_amount(previous_total_amount) if previous_total_amount is not None else None
        ),
        change_percentage=change_percentage,
        buckets=[
            AnalyticsTrendBucketRead(
                start_date=bucket["start_date"],
                end_date=bucket["end_date"],
                label=bucket["label"],
                amount=quantize_amount(bucket["amount"]),
                transaction_count=len(bucket["transaction_ids"]),
            )
            for bucket in bucket_state
        ],
    )

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
        ).join(Transaction, Transaction.id == item_scope_subquery.c.transaction_id)
    ).all()

    rolled_up_subcategories: dict[uuid.UUID, dict] = {}
    for (
        raw_category_id,
        amount,
        _tx_id,
        tx_currency,
        tx_occurred_at,
        tx_created_at,
    ) in category_rows:
        converted = convert_amount(
            amount=amount,
            base_currency=tx_currency,
            target_currency=target_currency,
            target_date=resolve_conversion_date(tx_occurred_at, tx_created_at),
            session=session,
            quantizer=quantize_amount,
        )
        converted_amount = (
            converted.value if converted.value is not None else quantize_amount(amount)
        )
        direct_child = _resolve_direct_child_under_top_level(
            category_id=raw_category_id,
            top_level_id=top_level_category.id,
            category_by_id=category_by_id,
        )
        if direct_child is None or direct_child.id == top_level_category.id:
            continue
        if direct_child.id not in rolled_up_subcategories:
            rolled_up_subcategories[direct_child.id] = {
                "name": direct_child.name,
                "code": direct_child.code,
                "color": direct_child.color,
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
            (data["amount"] / rolled_up_total * 100) if rolled_up_total > 0 else Decimal("0")
        )
        subcategories.append(
            {
                "subcategory_id": subcategory_id,
                "name": data["name"],
                "code": data["code"],
                "color": data.get("color"),
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
        "category_color": top_level_category.color,
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
    """Get purchased item breakdown for one item-category node."""
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
            Category.is_active,
            or_(Category.user_id.is_(None), Category.user_id == current_user.id),
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
            item_scope_subquery.c.raw_name,
            item_scope_subquery.c.translatable_name,
            item_scope_subquery.c.expanded_name,
            item_scope_subquery.c.normalized_display_name,
            item_scope_subquery.c.normalization_base_language,
            item_scope_subquery.c.amount,
            item_scope_subquery.c.qty,
            item_scope_subquery.c.unit,
            Transaction.currency,
            Transaction.occurred_at,
            Transaction.created_at,
        ).join(Transaction, Transaction.id == item_scope_subquery.c.transaction_id)
    ).all()

    total_amount = Decimal("0")
    grouped: dict[tuple[str, str | None], dict[str, Any]] = {}
    for (
        description,
        description_lang,
        raw_name,
        translatable_name,
        expanded_name,
        normalized_display_name,
        normalization_base_language,
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
        converted_amount = (
            converted.value if converted.value is not None else quantize_amount(amount)
        )
        total_amount += converted_amount

        entry = grouped.setdefault(
            (
                clean_description,
                normalize_language_code(description_lang) if description_lang else None,
            ),
            {
                "amount": Decimal("0"),
                "occurrences": 0,
                "total_qty": None,
                "unit": unit,
                "raw_name": raw_name,
                "translatable_name": translatable_name,
                "expanded_name": expanded_name,
                "normalized_display_name": normalized_display_name,
                "normalization_base_language": normalization_base_language,
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
            source_entry
            for (description, description_lang), row in grouped.items()
            if (
                source_entry := _preferred_item_translation_source_values(
                    description=description,
                    description_lang=description_lang,
                    raw_name=row.get("raw_name"),
                    translatable_name=row.get("translatable_name"),
                    normalization_base_language=row.get("normalization_base_language"),
                )
            )
            is not None
        ],
    )

    items = []
    total_item_rows = 0
    for (description, description_lang), row in grouped.items():
        item_total = row["amount"]
        occurrences = int(row["occurrences"] or 0)
        qty_total = row["total_qty"]
        unit = row["unit"]
        raw_name = row.get("raw_name")
        translatable_name = row.get("translatable_name")
        expanded_name = row.get("expanded_name")
        normalized_display_name = row.get("normalized_display_name")
        normalization_base_language = row.get("normalization_base_language")
        qty_value = qty_total if qty_total is not None else None
        avg_unit_price = None
        if qty_value not in (None, 0):
            avg_unit_price = float((item_total or Decimal("0")) / qty_value)

        translated_description = None
        translation_language = None
        translation_source_language = None
        translation_source_text = None
        source_entry = _preferred_item_translation_source_values(
            description=description,
            description_lang=description_lang,
            raw_name=raw_name,
            translatable_name=translatable_name,
            normalization_base_language=normalization_base_language,
        )
        if effective_item_language and source_entry is not None:
            source_text, source_lang = source_entry
            translated_description = translation_lookup.get(
                (
                    normalized_source_text_key(source_text),
                    source_lang,
                    effective_item_language,
                )
            )
            if translated_description is not None:
                translation_language = effective_item_language
                translation_source_language = source_lang
                translation_source_text = source_text

        total_item_rows += occurrences
        items.append(
            {
                "description": description,
                "description_lang": description_lang,
                "raw_name": raw_name,
                "translatable_name": translatable_name,
                "expanded_name": expanded_name,
                "normalized_display_name": normalized_display_name,
                "normalization_base_language": normalization_base_language,
                "amount": float(item_total or Decimal("0")),
                "occurrences": occurrences,
                "total_qty": float(qty_value) if qty_value is not None else None,
                "unit": unit,
                "avg_unit_price": avg_unit_price,
                "translated_description": translated_description,
                "translation_language": translation_language,
                "translation_source_language": translation_source_language,
                "translation_source_text": translation_source_text,
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
