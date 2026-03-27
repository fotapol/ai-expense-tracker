"""Transaction API endpoints for editing and viewing ledgers."""

import datetime as dt
import logging
import uuid
from collections import defaultdict
from decimal import Decimal
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import TypeAdapter
from sqlalchemy import and_, func, or_
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.households.household import Household
from app.models.labels.label import Label
from app.models.labels.transaction_label import TransactionLabel
from app.models.receipts.receipt import Receipt
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import CategoryScope, HouseholdMemberRole, TransactionSource
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.translations.item_translation import ItemTranslation
from app.models.users.profile import Profile
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
    AnalyticsCategorySnippetRead,
    AnalyticsHouseholdMemberRead,
    AnalyticsHouseholdSnippetRead,
    AnalyticsHouseholdSummaryRead,
    AnalyticsTrendBucketRead,
    AnalyticsTrendSummaryRead,
    TransactionCreateManual,
    TransactionHouseholdSnippetRead,
    TransactionItemRead,
    TransactionLabelRead,
    TransactionListFilter,
    TransactionRead,
    TransactionUpdateRequest,
    TransactionUserSnippetRead,
)
from app.services.billing.entitlements import user_has_feature
from app.services.billing.features import PREMIUM_ANALYTICS_ADVANCED
from app.services.fx_rates import convert_amount, resolve_conversion_date
from app.services.households.access import get_active_shared_household_id
from app.services.households.membership import get_member_for_user, validate_transaction_attribution

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


def _resolve_active_shared_household_id(
    session: Session,
    current_user: User,
) -> uuid.UUID | None:
    return get_active_shared_household_id(session, current_user.id)


def _build_transaction_read_visibility_predicate(
    session: Session,
    current_user: User,
):
    del session
    # Household sharing is disabled for the single-user launch. Keep all
    # transactions owned by the current user visible, including legacy rows
    # that still carry a historical household_id.
    return Transaction.user_id == current_user.id


def _build_transaction_write_visibility_predicate(
    session: Session,
    current_user: User,
):
    del session
    return Transaction.user_id == current_user.id


def _assert_household_transaction_access(
    session: Session,
    *,
    current_user: User,
    household_id: uuid.UUID | None,
) -> None:
    del session
    del current_user
    del household_id
    # Household flows are disabled for launch. Legacy household-tagged rows stay
    # editable by their owner, but new single-user writes should not depend on
    # household access checks.
    return None


def _get_deleteable_manual_transaction(
    session: Session,
    *,
    transaction_id: uuid.UUID,
    current_user: User,
) -> Transaction:
    """Return a visible manual transaction if the user may delete it."""

    transaction = session.exec(
        select(Transaction).where(
            Transaction.id == transaction_id,
            _build_transaction_read_visibility_predicate(session, current_user),
        )
    ).first()
    if transaction is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transaction not found.",
        )
    if transaction.receipt_id is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Receipt-backed transactions must be deleted via the receipt endpoint.",
        )
    if transaction.user_id == current_user.id:
        return transaction
    if transaction.household_id is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not allowed to delete this transaction.",
        )

    member = get_member_for_user(session, transaction.household_id, current_user.id)
    if member is not None and member.role == HouseholdMemberRole.OWNER:
        return transaction

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Only the creator or household owner can delete this transaction.",
    )


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
    disabled_subquery = select(UserHiddenCategory.category_id).where(
        UserHiddenCategory.user_id == current_user.id,
    )
    return session.exec(
        select(Category).where(
            Category.scope == CategoryScope.ITEM,
            Category.is_active,
            Category.id.notin_(disabled_subquery),
            or_(Category.user_id.is_(None), Category.user_id == current_user.id),
        )
    ).all()


def _get_user_visible_category_by_id(
    session: Session,
    *,
    current_user: User,
    category_id: uuid.UUID,
) -> Category | None:
    disabled_subquery = select(UserHiddenCategory.category_id).where(
        UserHiddenCategory.user_id == current_user.id,
    )
    return session.exec(
        select(Category).where(
            Category.id == category_id,
            Category.scope == CategoryScope.ITEM,
            Category.is_active,
            Category.id.notin_(disabled_subquery),
            or_(Category.user_id.is_(None), Category.user_id == current_user.id),
        )
    ).first()


def _get_user_visible_category_ids(
    session: Session,
    *,
    current_user: User,
    category_ids: set[uuid.UUID],
    scope: CategoryScope,
) -> set[uuid.UUID]:
    """Return the subset of category ids visible to the user for a given scope."""

    if not category_ids:
        return set()

    disabled_subquery = select(UserHiddenCategory.category_id).where(
        UserHiddenCategory.user_id == current_user.id,
    )
    return set(
        session.exec(
            select(Category.id).where(
                Category.id.in_(category_ids),
                Category.scope == scope,
                Category.is_active,
                Category.id.notin_(disabled_subquery),
                or_(Category.user_id.is_(None), Category.user_id == current_user.id),
            )
        ).all()
    )


def _get_or_create_global_category(
    session: Session,
    *,
    scope: CategoryScope,
    code: str,
    name: str,
    parent_id: uuid.UUID | None = None,
) -> Category:
    category = session.exec(
        select(Category).where(
            Category.scope == scope,
            Category.code == code,
            Category.user_id.is_(None),
        )
    ).first()
    if category is not None:
        # Only write if something actually changed to avoid unnecessary DB I/O
        # on every transaction creation (M-7 fix).
        needs_update = (
            category.name != name
            or category.parent_id != parent_id
            or not category.is_active
        )
        if needs_update:
            category.name = name
            category.parent_id = parent_id
            category.is_active = True
            session.add(category)
            session.flush()
        return category

    category = Category(
        scope=scope,
        code=code,
        name=name,
        parent_id=parent_id,
        user_id=None,
        is_custom=False,
    )
    session.add(category)
    session.flush()
    return category


def _get_uncategorized_item_category_id(session: Session) -> uuid.UUID:
    other_item = _get_or_create_global_category(
        session,
        scope=CategoryScope.ITEM,
        code="OTHER",
        name="Other",
    )
    uncategorized = _get_or_create_global_category(
        session,
        scope=CategoryScope.ITEM,
        code="UNCATEGORIZED",
        name="Uncategorized",
        parent_id=other_item.id,
    )
    return uncategorized.id


def _resolve_transaction_category_from_item_category(
    session: Session,
    *,
    item_category_id: uuid.UUID | None,
) -> uuid.UUID | None:
    if item_category_id is None:
        return None

    category = session.exec(
        select(Category).where(Category.id == item_category_id)
    ).first()
    if category is None:
        return None

    top_level = category
    visited: set[uuid.UUID] = set()
    while top_level.parent_id is not None and top_level.parent_id not in visited:
        visited.add(top_level.id)
        parent = session.exec(
            select(Category).where(Category.id == top_level.parent_id)
        ).first()
        if parent is None:
            break
        top_level = parent

    match = session.exec(
        select(Category.id).where(
            Category.scope == CategoryScope.TRANSACTION,
            Category.code == top_level.code,
            Category.is_active,
            Category.user_id.is_(None),
        )
    ).first()
    return match


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
                Category.is_active,
                or_(Category.user_id.is_(None), Category.user_id == current_user.id),
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

    disabled_subquery = select(UserHiddenCategory.category_id).where(
        UserHiddenCategory.user_id == current_user.id,
    )
    valid_subcategory_ids = set(
        session.exec(
            select(Category.id).where(
                Category.scope == CategoryScope.ITEM,
                Category.parent_id.is_not(None),
                Category.is_active,
                Category.id.notin_(disabled_subquery),
                Category.id.in_(requested_ids),
                or_(Category.user_id.is_(None), Category.user_id == current_user.id),
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
    query = select(Transaction.id).where(
        _build_transaction_read_visibility_predicate(session, current_user)
    )

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


def _build_analytics_scope(
    *,
    session: Session,
    current_user: User,
    filters: TransactionListFilter,
    transaction_ids_query=None,
):
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
    base_transaction_ids_query = transaction_ids_query or _build_filtered_transaction_ids_query(
        session=session,
        current_user=current_user,
        filters=filters,
    )
    transaction_ids_subquery = base_transaction_ids_query.subquery()
    item_scope_query, has_item_filters = _build_item_scope_query(
        transaction_ids_subquery=transaction_ids_subquery,
        category_descendant_item_ids=category_descendant_item_ids,
        selected_subcategory_ids=selected_subcategory_ids,
    )
    return (
        target_currency,
        transaction_ids_subquery,
        item_scope_query.subquery(),
        has_item_filters,
    )


def _load_analytics_spend_rows(
    session: Session,
    *,
    transaction_ids_subquery,
    item_scope_subquery,
    has_item_filters: bool,
):
    if has_item_filters:
        return session.exec(
            select(
                item_scope_subquery.c.transaction_id,
                item_scope_subquery.c.amount,
                Transaction.currency,
                Transaction.occurred_at,
                Transaction.created_at,
                Transaction.owner_user_id,
                Transaction.user_id,
            ).join(
                Transaction,
                Transaction.id == item_scope_subquery.c.transaction_id,
            )
        ).all()

    return session.exec(
        select(
            Transaction.id,
            Transaction.amount_total,
            Transaction.currency,
            Transaction.occurred_at,
            Transaction.created_at,
            Transaction.owner_user_id,
            Transaction.user_id,
        ).where(Transaction.id.in_(select(transaction_ids_subquery.c.id)))
    ).all()


def _load_household_category_item_rows(
    session: Session,
    *,
    item_scope_subquery,
):
    return session.exec(
        select(
            Transaction.owner_user_id,
            Transaction.user_id,
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
        .join(item_scope_subquery, item_scope_subquery.c.transaction_id == Transaction.id)
        .join(Category, Category.id == item_scope_subquery.c.category_id)
    ).all()


def _coerce_analytics_datetime(
    value: dt.datetime | None,
    *,
    fallback: dt.datetime | None = None,
) -> dt.datetime | None:
    resolved = value or fallback
    if resolved is None:
        return None
    if resolved.tzinfo is None:
        return resolved.replace(tzinfo=dt.UTC)
    return resolved


def _resolve_analytics_period_bounds(
    filters: TransactionListFilter,
) -> tuple[dt.datetime | None, dt.datetime]:
    now = dt.datetime.now(dt.UTC)
    end_at = _coerce_analytics_datetime(filters.to_occurred_at, fallback=now) or now
    start_at = _coerce_analytics_datetime(filters.from_occurred_at)
    return start_at, end_at


def _build_previous_period_filters(
    filters: TransactionListFilter,
) -> TransactionListFilter | None:
    current_start, current_end = _resolve_analytics_period_bounds(filters)
    if current_start is None:
        return None

    window = current_end - current_start
    if window.total_seconds() <= 0:
        window = dt.timedelta(days=1)
    previous_end = current_start - dt.timedelta(microseconds=1)
    previous_start = previous_end - window
    return filters.model_copy(
        update={
            "from_occurred_at": previous_start,
            "to_occurred_at": previous_end,
        }
    )


def _infer_analytics_bucket_unit(
    filters: TransactionListFilter,
) -> str:
    start_at, end_at = _resolve_analytics_period_bounds(filters)
    if start_at is None:
        return "month"

    span_days = max(1, (end_at.date() - start_at.date()).days + 1)
    if span_days <= 31:
        return "day"
    if span_days <= 184:
        return "week"
    return "month"


def _format_trend_bucket_label(
    *,
    start_date: dt.date,
    end_date: dt.date,
    bucket_unit: str,
) -> str:
    if bucket_unit == "day":
        return start_date.strftime("%d %b")
    if bucket_unit == "week":
        return f"{start_date.strftime('%d %b')} - {end_date.strftime('%d %b')}"
    return start_date.strftime("%b %Y")


def _iter_trend_bucket_ranges(
    *,
    start_date: dt.date,
    end_date: dt.date,
    bucket_unit: str,
) -> list[tuple[dt.date, dt.date]]:
    ranges: list[tuple[dt.date, dt.date]] = []
    cursor = start_date
    while cursor <= end_date:
        if bucket_unit == "day":
            bucket_end = cursor
        elif bucket_unit == "week":
            bucket_end = min(cursor + dt.timedelta(days=6), end_date)
        else:
            if cursor.month == 12:
                next_month = dt.date(cursor.year + 1, 1, 1)
            else:
                next_month = dt.date(cursor.year, cursor.month + 1, 1)
            bucket_end = min(next_month - dt.timedelta(days=1), end_date)

        ranges.append((cursor, bucket_end))
        cursor = bucket_end + dt.timedelta(days=1)
    return ranges


def _convert_analytics_amount(
    *,
    session: Session,
    amount,
    currency: str,
    target_currency: str,
    occurred_at,
    created_at,
) -> Decimal:
    raw_amount = amount if isinstance(amount, Decimal) else Decimal(str(amount or "0"))
    converted = convert_amount(
        amount=raw_amount,
        base_currency=currency,
        target_currency=target_currency,
        target_date=resolve_conversion_date(occurred_at, created_at),
        session=session,
        quantizer=quantize_amount,
    )
    return converted.value if converted.value is not None else quantize_amount(raw_amount)


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
            Label.is_active,
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


def _load_transaction_user_snippets(
    session: Session,
    *,
    user_ids: set[uuid.UUID],
) -> dict[uuid.UUID, TransactionUserSnippetRead]:
    if not user_ids:
        return {}

    rows = session.exec(
        select(User.id, User.email, Profile.display_name, Profile.avatar_url)
        .select_from(User)
        .join(Profile, Profile.user_id == User.id, isouter=True)
        .where(User.id.in_(user_ids))
    ).all()

    return {
        user_id: TransactionUserSnippetRead(
            user_id=user_id,
            email=email,
            display_name=display_name,
            avatar_url=avatar_url,
        )
        for user_id, email, display_name, avatar_url in rows
    }


def _enrich_transaction_attribution_snapshot(
    session: Session,
    *,
    read: TransactionRead,
) -> None:
    """Populate read-only attribution snippets for transaction details."""
    resolved_created_by_user_id = read.created_by_user_id
    if resolved_created_by_user_id is None and read.receipt_id is not None:
        resolved_created_by_user_id = session.exec(
            select(Receipt.user_id).where(Receipt.id == read.receipt_id)
        ).first()
    if resolved_created_by_user_id is None:
        resolved_created_by_user_id = read.user_id

    resolved_owner_user_id = read.owner_user_id or read.user_id
    read.created_by_user_id = resolved_created_by_user_id
    read.owner_user_id = resolved_owner_user_id
    read.household = None
    read.created_by_user = None
    read.owner_user = None

    if read.household_id is not None:
        household_name = session.exec(
            select(Household.name).where(Household.id == read.household_id)
        ).first()
        read.household = TransactionHouseholdSnippetRead(
            household_id=read.household_id,
            name=household_name,
        )

    user_ids: set[uuid.UUID] = set()
    if read.created_by_user_id is not None:
        user_ids.add(read.created_by_user_id)
    if read.owner_user_id is not None:
        user_ids.add(read.owner_user_id)

    user_snippets = _load_transaction_user_snippets(session, user_ids=user_ids)
    if read.created_by_user_id is not None:
        read.created_by_user = user_snippets.get(read.created_by_user_id)
    if read.owner_user_id is not None:
        read.owner_user = user_snippets.get(read.owner_user_id)


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


def _build_transaction_read(
    *,
    session: Session,
    current_user: User,
    transaction: Transaction,
    items: list[TransactionItem] | None = None,
    target_currency: str | None = None,
    item_language: str | None = None,
    app_language: str | None = None,
) -> TransactionRead:
    loaded_items = items
    if loaded_items is None:
        loaded_items = session.exec(
            select(TransactionItem).where(
                TransactionItem.transaction_id == transaction.id,
            ).order_by(TransactionItem.line_no)
        ).all()

    read = TransactionRead.model_validate(transaction)
    read.items = [TransactionItemRead.model_validate(item) for item in loaded_items]
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
    _enrich_transaction_attribution_snapshot(session, read=read)
    _apply_display_conversion(
        read=read,
        session=session,
        target_currency=normalize_currency_code(
            target_currency or current_user.default_currency,
        ),
    )
    return read


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

    # Household attribution is disabled for the single-user launch.
    household_id = None
    _assert_household_transaction_access(
        session,
        current_user=current_user,
        household_id=household_id,
    )
    owner_user_id = payload.owner_user_id or current_user.id
    validate_transaction_attribution(
        session,
        household_id=household_id,
        owner_user_id=owner_user_id,
    )

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
                        item_data.description
                        or payload.merchant_name
                        or "Manual entry"
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
    primary_item_category_id = selected_item_category.id if selected_item_category is not None else (
        item_rows[0]["category_id"] if item_rows else None
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
        ) if primary_item_category_id is not None else None,
        source=TransactionSource.MANUAL,
        status=payload.status,
        household_id=household_id,
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
            read.extraction_warnings = tx_warnings  # H-7: populate warnings body, not just flag
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
                "amount": Decimal("0"),
                "item_count": 0,
                "transaction_ids": set(),
            }
        category_results[cat_id]["amount"] = category_results[cat_id]["amount"] + converted_amount
        category_results[cat_id]["item_count"] = category_results[cat_id]["item_count"] + 1
        category_results[cat_id]["transaction_ids"].add(tx_id)

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
        rolled_up_totals[target_id]["amount"] = rolled_up_totals[target_id]["amount"] + cat_total
        rolled_up_totals[target_id]["item_count"] = rolled_up_totals[target_id]["item_count"] + int(item_count or 0)

    categories_breakdown = []
    for cat_id, data in rolled_up_totals.items():
        amt: Decimal = data["amount"]
        percentage = (amt / total_amount * 100) if total_amount > 0 else Decimal("0")
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
        subcategory_name = data["name"]
        subcategory_code = data["code"]
        # H-4 fix: do NOT compute percentage here; denominator is still growing.
        # The second pass below computes correct percentages once the total is final.
        subcategory_breakdown.append(
            {
                "subcategory_id": cat_id,
                "name": subcategory_name,
                "code": subcategory_code,
                "amount": float(data["amount"]),
                "percentage": 0.0,  # filled in by second pass below
                "item_count": data["item_count"],
                "parent_category_id": parent_id,
                "parent_category_name": parent_name,
                "parent_category_code": parent_code,
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
            quantize_amount(previous_total_amount)
            if previous_total_amount is not None
            else None
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


@router.get("/transactions/summary/household", response_model=AnalyticsHouseholdSummaryRead)
@limiter.limit("30/minute")
async def get_household_analytics_summary(
    request: Request,
    filters: Annotated[TransactionListFilter, Depends()],
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Return per-member household analytics for the active shared household."""

    target_currency = _resolve_target_currency(filters, current_user)
    active_household_id = _resolve_active_shared_household_id(session, current_user)
    if active_household_id is None:
        return AnalyticsHouseholdSummaryRead(
            household=None,
            currency=target_currency,
            total_amount=Decimal("0.00"),
            total_transactions=0,
            members=[],
        )

    household = session.exec(
        select(Household).where(Household.id == active_household_id)
    ).first()
    if household is None:
        return AnalyticsHouseholdSummaryRead(
            household=None,
            currency=target_currency,
            total_amount=Decimal("0.00"),
            total_transactions=0,
            members=[],
        )

    household_transaction_ids_query = _build_filtered_transaction_ids_query(
        session=session,
        current_user=current_user,
        filters=filters,
    ).where(Transaction.household_id == active_household_id)
    (
        _target_currency,
        transaction_ids_subquery,
        item_scope_subquery,
        has_item_filters,
    ) = _build_analytics_scope(
        session=session,
        current_user=current_user,
        filters=filters,
        transaction_ids_query=household_transaction_ids_query,
    )
    spend_rows = _load_analytics_spend_rows(
        session,
        transaction_ids_subquery=transaction_ids_subquery,
        item_scope_subquery=item_scope_subquery,
        has_item_filters=has_item_filters,
    )

    member_totals: dict[uuid.UUID, dict[str, Any]] = {}
    total_amount = Decimal("0.00")
    total_transaction_ids: set[uuid.UUID] = set()
    for (
        tx_id,
        amount,
        tx_currency,
        tx_occurred_at,
        tx_created_at,
        owner_user_id,
        user_id,
    ) in spend_rows:
        resolved_owner_user_id = owner_user_id or user_id
        if resolved_owner_user_id is None:
            continue

        converted_amount = _convert_analytics_amount(
            session=session,
            amount=amount,
            currency=tx_currency,
            target_currency=target_currency,
            occurred_at=tx_occurred_at,
            created_at=tx_created_at,
        )
        total_amount += converted_amount
        total_transaction_ids.add(tx_id)
        member_entry = member_totals.setdefault(
            resolved_owner_user_id,
            {
                "total_amount": Decimal("0.00"),
                "transaction_ids": set(),
            },
        )
        member_entry["total_amount"] += converted_amount
        member_entry["transaction_ids"].add(tx_id)

    category_item_rows = _load_household_category_item_rows(
        session,
        item_scope_subquery=item_scope_subquery,
    )
    parent_ids = {
        parent_id
        for (
            _owner_user_id,
            _user_id,
            _category_id,
            _name,
            _code,
            parent_id,
            _amount,
            _transaction_id,
            _tx_currency,
            _tx_occurred_at,
            _tx_created_at,
        ) in category_item_rows
        if parent_id is not None
    }
    parent_map: dict[uuid.UUID, dict[str, Any]] = {}
    if parent_ids:
        parents = session.exec(select(Category).where(Category.id.in_(parent_ids))).all()
        parent_map = {
            parent.id: {"name": parent.name, "code": parent.code}
            for parent in parents
        }

    top_categories_by_owner: dict[uuid.UUID, dict[uuid.UUID, dict[str, Any]]] = defaultdict(dict)
    for (
        owner_user_id,
        user_id,
        category_id,
        name,
        code,
        parent_id,
        amount,
        _transaction_id,
        tx_currency,
        tx_occurred_at,
        tx_created_at,
    ) in category_item_rows:
        resolved_owner_user_id = owner_user_id or user_id
        if resolved_owner_user_id is None:
            continue

        converted_amount = _convert_analytics_amount(
            session=session,
            amount=amount,
            currency=tx_currency,
            target_currency=target_currency,
            occurred_at=tx_occurred_at,
            created_at=tx_created_at,
        )
        target_category_id = category_id
        target_name = name
        target_code = code
        if parent_id is not None:
            target_category_id = parent_id
            target_name = parent_map.get(parent_id, {}).get("name", name)
            target_code = parent_map.get(parent_id, {}).get("code", code)

        owner_categories = top_categories_by_owner[resolved_owner_user_id]
        category_entry = owner_categories.setdefault(
            target_category_id,
            {
                "category_id": target_category_id,
                "name": target_name,
                "code": target_code,
                "amount": Decimal("0.00"),
            },
        )
        category_entry["amount"] += converted_amount

    user_snippets = _load_transaction_user_snippets(
        session,
        user_ids=set(member_totals.keys()),
    )
    members: list[AnalyticsHouseholdMemberRead] = []
    for owner_user_id, data in member_totals.items():
        member_total_amount: Decimal = data["total_amount"]
        owner_categories = top_categories_by_owner.get(owner_user_id, {})
        top_category_data = None
        if owner_categories:
            top_category_data = max(
                owner_categories.values(),
                key=lambda entry: entry["amount"],
            )
        members.append(
            AnalyticsHouseholdMemberRead(
                owner_user_id=owner_user_id,
                user=user_snippets.get(owner_user_id),
                total_amount=quantize_amount(member_total_amount),
                percentage=float(
                    quantize_amount((member_total_amount / total_amount) * Decimal("100"))
                )
                if total_amount > 0
                else 0.0,
                transaction_count=len(data["transaction_ids"]),
                top_category=(
                    AnalyticsCategorySnippetRead(
                        category_id=top_category_data["category_id"],
                        name=top_category_data["name"],
                        code=top_category_data["code"],
                        amount=quantize_amount(top_category_data["amount"]),
                    )
                    if top_category_data is not None
                    else None
                ),
            )
        )

    members.sort(key=lambda member: member.total_amount, reverse=True)
    return AnalyticsHouseholdSummaryRead(
        household=AnalyticsHouseholdSnippetRead(
            household_id=household.id,
            name=household.name,
        ),
        currency=target_currency,
        total_amount=quantize_amount(total_amount),
        total_transactions=len(total_transaction_ids),
        members=members,
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
        if direct_child is None or direct_child.id == top_level_category.id:
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
            for (description, description_lang) in grouped
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
            _build_transaction_read_visibility_predicate(session, current_user),
        )
    ).first()

    if transaction is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Transaction not found."
        )

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
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Transaction not found."
        )

    # Saving an edited transaction in single-user launch mode should keep it
    # solo even if the stored row still carries a legacy household_id.
    next_household_id = None
    _assert_household_transaction_access(
        session,
        current_user=current_user,
        household_id=next_household_id,
    )
    validate_transaction_attribution(
        session,
        household_id=next_household_id,
        owner_user_id=payload.owner_user_id if payload.owner_user_id is not None else transaction.owner_user_id,
    )

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
        exclude={"items", "household_id"},
    )
    for key, value in update_data.items():
        setattr(transaction, key, value)
    transaction.household_id = None

    session.add(transaction)

    # 2. Update Items if provided
    items = session.exec(
        select(TransactionItem).where(TransactionItem.transaction_id == transaction_id)
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
                    category_id=item_data.category_id, # Must be valid UUID for existing category
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
        select(func.sum(TransactionItem.amount)).where(TransactionItem.transaction_id == transaction_id)
    ).first()
    transaction.amount_total = quantize_amount(remaining_total or Decimal("0.00"))
    session.add(transaction)
    session.commit()
    return None
