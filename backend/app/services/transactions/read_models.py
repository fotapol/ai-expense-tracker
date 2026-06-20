"""Shared transaction query, category, analytics, and read-model helpers."""

import datetime as dt
import logging
import uuid
from collections import defaultdict
from decimal import Decimal
from typing import Any

from fastapi import HTTPException, status
from pydantic import TypeAdapter
from sqlalchemy import or_
from sqlmodel import Session, select

from app.models.households.household import Household
from app.models.labels.label import Label
from app.models.labels.transaction_label import TransactionLabel
from app.models.receipts.receipt import Receipt
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import CategoryScope, HouseholdMemberRole
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
    TransactionHouseholdSnippetRead,
    TransactionItemRead,
    TransactionLabelRead,
    TransactionListFilter,
    TransactionRead,
    TransactionUserSnippetRead,
)
from app.services.fx_rates import convert_amount, resolve_conversion_date
from app.services.households.access import get_active_shared_household_id
from app.services.households.membership import get_member_for_user

logger = logging.getLogger(__name__)

_warnings_adapter = TypeAdapter(list[ExtractionWarning])



__all__ = [
    "_apply_display_conversion",
    "_assert_household_transaction_access",
    "_build_analytics_scope",
    "_build_category_filter_predicate",
    "_build_filtered_transaction_ids_query",
    "_build_item_scope_query",
    "_build_previous_period_filters",
    "_build_subcategory_filter_predicate",
    "_build_transaction_read",
    "_build_transaction_read_visibility_predicate",
    "_build_transaction_write_visibility_predicate",
    "_clear_extraction_warnings_after_user_confirmation",
    "_coerce_analytics_datetime",
    "_collect_descendants",
    "_convert_analytics_amount",
    "_enrich_transaction_attribution_snapshot",
    "_enrich_transaction_items_with_translations",
    "_extract_warnings_from_structured_json",
    "_format_trend_bucket_label",
    "_get_deleteable_manual_transaction",
    "_get_or_create_global_category",
    "_get_uncategorized_item_category_id",
    "_get_user_visible_category_by_id",
    "_get_user_visible_category_ids",
    "_get_user_visible_item_categories",
    "_infer_analytics_bucket_unit",
    "_item_description_user_edited",
    "_item_description_user_edited_values",
    "_iter_trend_bucket_ranges",
    "_load_analytics_spend_rows",
    "_load_category_names_by_id",
    "_load_household_category_item_rows",
    "_load_labels_by_transaction_id",
    "_load_transaction_user_snippets",
    "_load_translation_lookup",
    "_load_warnings_by_receipt_id",
    "_normalized_item_name_text",
    "_parse_uuid_csv",
    "_preferred_item_translation_source",
    "_preferred_item_translation_source_values",
    "_resolve_active_shared_household_id",
    "_resolve_analytics_period_bounds",
    "_resolve_category_filter_sets",
    "_resolve_direct_child_under_top_level",
    "_resolve_item_language",
    "_resolve_label_filter_ids",
    "_resolve_subcategory_filter_ids",
    "_resolve_target_currency",
    "_resolve_top_level_item_category",
    "_resolve_transaction_category_from_item_category",
]

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

    normalized_texts = {
        normalized_source_text_key(text) for text, _ in source_entries if text.strip()
    }
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


def _normalized_item_name_text(value: str | None, *, casefold: bool = False) -> str:
    normalized = " ".join((value or "").strip().split())
    return normalized.casefold() if casefold else normalized


def _item_description_user_edited_values(
    *,
    description: str | None,
    raw_name: str | None,
) -> bool:
    if raw_name is None:
        return False
    normalized_raw_name = _normalized_item_name_text(raw_name, casefold=True)
    normalized_description = _normalized_item_name_text(description, casefold=True)
    if not normalized_raw_name or not normalized_description:
        return False
    return normalized_raw_name != normalized_description


def _preferred_item_translation_source_values(
    *,
    description: str | None,
    description_lang: str | None,
    raw_name: str | None,
    translatable_name: str | None,
    normalization_base_language: str | None,
) -> tuple[str, str] | None:
    if _item_description_user_edited_values(description=description, raw_name=raw_name):
        if description_lang is None or not description_lang.strip():
            return None
        return (_normalized_item_name_text(description), normalize_language_code(description_lang))

    if translatable_name and normalization_base_language:
        source_language = normalize_language_code(normalization_base_language)
        if source_language:
            return (_normalized_item_name_text(translatable_name), source_language)

    if description_lang is None or not description_lang.strip():
        return None
    return (_normalized_item_name_text(description), normalize_language_code(description_lang))


def _item_description_user_edited(item: TransactionItemRead) -> bool:
    return _item_description_user_edited_values(
        description=item.description,
        raw_name=item.raw_name,
    )


def _preferred_item_translation_source(item: TransactionItemRead) -> tuple[str, str] | None:
    return _preferred_item_translation_source_values(
        description=item.description,
        description_lang=item.description_lang,
        raw_name=item.raw_name,
        translatable_name=item.translatable_name,
        normalization_base_language=item.normalization_base_language,
    )


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
        item.translation_source_text = None
        if not target_language:
            continue
        source_entry = _preferred_item_translation_source(item)
        if source_entry is None:
            continue

        source_text, source_language = source_entry
        key = (
            normalized_source_text_key(source_text),
            source_language,
            target_language,
        )
        translated = lookup.get(key)
        if translated is None:
            continue

        item.translated_description = translated
        item.translation_language = target_language
        item.translation_source_language = source_language
        item.translation_source_text = source_text


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
            category.name != name or category.parent_id != parent_id or not category.is_active
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

    category = session.exec(select(Category).where(Category.id == item_category_id)).first()
    if category is None:
        return None

    top_level = category
    visited: set[uuid.UUID] = set()
    while top_level.parent_id is not None and top_level.parent_id not in visited:
        visited.add(top_level.id)
        parent = session.exec(select(Category).where(Category.id == top_level.parent_id)).first()
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


def _extract_warnings_from_structured_json(
    structured_json: dict[str, Any] | None,
) -> list[ExtractionWarning]:
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


def _clear_extraction_warnings_after_user_confirmation(
    session: Session,
    *,
    transaction: Transaction,
) -> None:
    """Treat a confirmed user save as the authoritative review result."""

    if transaction.status != "CONFIRMED" or transaction.receipt_id is None:
        return

    extraction = session.exec(
        select(ReceiptExtraction).where(
            ReceiptExtraction.receipt_id == transaction.receipt_id,
        )
    ).first()
    if extraction is None or not isinstance(extraction.structured_json, dict):
        return

    warnings = extraction.structured_json.get("warnings")
    if not isinstance(warnings, list) or not warnings:
        return

    updated_structured_json = dict(extraction.structured_json)
    updated_structured_json["warnings"] = []
    extraction.structured_json = updated_structured_json
    session.add(extraction)


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
            select(TransactionItem)
            .where(
                TransactionItem.transaction_id == transaction.id,
            )
            .order_by(TransactionItem.line_no)
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
            source_entry
            for item in read.items
            if (source_entry := _preferred_item_translation_source(item)) is not None
        ],
    )
    _enrich_transaction_items_with_translations(
        items=read.items,
        target_language=effective_item_language,
        lookup=translation_lookup,
    )
    read.category_name = (
        session.exec(select(Category.name).where(Category.id == transaction.category_id)).first()
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
