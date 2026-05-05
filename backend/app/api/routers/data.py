"""Data import and export API endpoints."""

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.user import User
from app.schemas.data import (
    CategoryExportData,
    DataExportPayload,
    DataImportPayload,
    TransactionExportData,
    TransactionItemExportData,
)
from app.services.billing.entitlements import user_has_feature
from app.services.billing.features import PREMIUM_EXPORTS

router = APIRouter(prefix="/v1/data", tags=["data"])


def _normalize_category_scope(raw_scope: str) -> CategoryScope:
    """Parse category scope from payload with case-insensitive compatibility."""
    try:
        return CategoryScope(raw_scope.strip().upper())
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unsupported category scope: {raw_scope}",
        ) from exc


def _resolve_default_item_category_id(session: Session) -> uuid.UUID | None:
    """Return fallback ITEM category id used when payload item category is missing."""
    for code in ("UNCATEGORIZED", "OTHER"):
        fallback_id = session.exec(
            select(Category.id).where(
                Category.scope == CategoryScope.ITEM,
                Category.user_id.is_(None),
                Category.code == code,
            )
        ).first()
        if fallback_id is not None:
            return fallback_id
    return None


@router.get("/export", response_model=DataExportPayload)
@limiter.limit("5/minute")
async def export_data(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Export user's categories and transactions as JSON."""

    can_export_unlimited = user_has_feature(session, current_user.id, PREMIUM_EXPORTS)
    date_limit = None
    if not can_export_unlimited:
        date_limit = dt.datetime.now(dt.UTC) - dt.timedelta(days=30)

    # 1. Fetch categories
    # Only export categories owned by the user (exclude built-ins) to avoid conflicts on import
    user_categories = session.exec(
        select(Category).where(Category.user_id == current_user.id)
    ).all()
    categories_export = [
        CategoryExportData(
            id=cat.id,
            parent_id=cat.parent_id,
            name=cat.name,
            code=cat.code,
            is_active=cat.is_active,
            scope=cat.scope.value,
        )
        for cat in user_categories
    ]

    # 2. Fetch transactions and items
    tx_query = select(Transaction).where(Transaction.user_id == current_user.id)
    if date_limit:
        tx_query = tx_query.where(Transaction.occurred_at >= date_limit)

    transactions = session.exec(tx_query.order_by(Transaction.occurred_at.desc())).all()
    tx_ids = [tx.id for tx in transactions]

    items = []
    if tx_ids:
        # Note: In SQLite, large IN() clauses can fail, but since free tier limits to 30 days,
        # and pro tier should be reasonable, we load in a single batch.
        items = session.exec(
            select(TransactionItem).where(TransactionItem.transaction_id.in_(tx_ids))
        ).all()

    items_by_tx = {}
    for item in items:
        if item.transaction_id not in items_by_tx:
            items_by_tx[item.transaction_id] = []
        items_by_tx[item.transaction_id].append(
            TransactionItemExportData(
                id=item.id,
                line_no=int(item.line_no) if item.line_no else 0,
                description=item.description,
                description_lang=item.description_lang,
                qty=float(item.qty) if item.qty is not None else None,
                unit=item.unit,
                unit_price=float(item.unit_price) if item.unit_price is not None else None,
                amount=float(item.amount),
                amount_before_discount=float(item.amount_before_discount) if item.amount_before_discount is not None else None,
                discount_amount=float(item.discount_amount) if item.discount_amount is not None else None,
                is_adjustment=bool(item.is_adjustment),
                category_id=item.category_id,
            )
        )

    transactions_export = [
        TransactionExportData(
            id=tx.id,
            merchant_name=tx.merchant_name,
            occurred_at=tx.occurred_at,
            amount_total=float(tx.amount_total),
            currency=tx.currency,
            category_id=tx.category_id,
            items=items_by_tx.get(tx.id, []),
        )
        for tx in transactions
    ]

    return DataExportPayload(
        version=1,
        exported_at=dt.datetime.now(dt.UTC),
        categories=categories_export,
        transactions=transactions_export,
    )


@router.post("/import", status_code=status.HTTP_201_CREATED)
@limiter.limit("2/minute")
async def import_data(
    payload: DataImportPayload,
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
    current_user: User = Depends(get_current_user),  # noqa: B008
):
    """Import categories and transactions from a JSON payload.

    This performs an upsert. Missing children (TransactionItems) for an existing transaction
    will be safely replaced.
    """

    try:
        user_id = current_user.id

        # Preload existing ownership for incoming IDs to support cross-account imports.
        payload_category_ids = [category.id for category in payload.categories]
        payload_transaction_ids = [transaction.id for transaction in payload.transactions]
        payload_item_ids = [
            item.id for transaction in payload.transactions for item in transaction.items
        ]

        category_owner_by_id: dict[uuid.UUID, uuid.UUID | None] = {}
        if payload_category_ids:
            for category_id, owner_id in session.exec(
                select(Category.id, Category.user_id).where(
                    Category.id.in_(payload_category_ids)
                )
            ).all():
                category_owner_by_id[category_id] = owner_id

        transaction_owner_by_id: dict[uuid.UUID, uuid.UUID] = {}
        if payload_transaction_ids:
            for transaction_id, owner_id in session.exec(
                select(Transaction.id, Transaction.user_id).where(
                    Transaction.id.in_(payload_transaction_ids)
                )
            ).all():
                transaction_owner_by_id[transaction_id] = owner_id

        item_transaction_by_id: dict[uuid.UUID, uuid.UUID] = {}
        if payload_item_ids:
            for item_id, transaction_id in session.exec(
                select(TransactionItem.id, TransactionItem.transaction_id).where(
                    TransactionItem.id.in_(payload_item_ids)
                )
            ).all():
                item_transaction_by_id[item_id] = transaction_id

        user_categories = session.exec(
            select(Category).where(Category.user_id == user_id)
        ).all()
        user_category_by_scope_code = {
            (category.scope, category.code): category for category in user_categories
        }

        # 1) Build a category ID map (source -> target) that avoids PK collisions.
        category_id_map: dict[uuid.UUID, uuid.UUID] = {}
        used_target_category_ids: set[uuid.UUID] = set()
        for cat_data in payload.categories:
            scope = _normalize_category_scope(cat_data.scope)
            owner_id = category_owner_by_id.get(cat_data.id)
            has_existing_row = cat_data.id in category_owner_by_id

            if owner_id == user_id:
                target_category_id = cat_data.id
            else:
                by_code = user_category_by_scope_code.get((scope, cat_data.code))
                if by_code is not None:
                    target_category_id = by_code.id
                elif not has_existing_row:
                    target_category_id = cat_data.id
                else:
                    target_category_id = uuid.uuid4()

            while target_category_id in used_target_category_ids:
                target_category_id = uuid.uuid4()

            used_target_category_ids.add(target_category_id)
            category_id_map[cat_data.id] = target_category_id

        # 2) Upsert categories without parent links first.
        category_parent_by_target_id: dict[uuid.UUID, uuid.UUID | None] = {}
        for cat_data in payload.categories:
            scope = _normalize_category_scope(cat_data.scope)
            target_category_id = category_id_map[cat_data.id]
            category = session.get(Category, target_category_id)

            if category is not None and category.user_id != user_id:
                remapped_category_id = uuid.uuid4()
                while remapped_category_id in used_target_category_ids:
                    remapped_category_id = uuid.uuid4()
                used_target_category_ids.add(remapped_category_id)
                category_id_map[cat_data.id] = remapped_category_id
                target_category_id = remapped_category_id
                category = None

            if category is None:
                category = Category(
                    id=target_category_id,
                    user_id=user_id,
                    parent_id=None,
                    name=cat_data.name,
                    code=cat_data.code,
                    is_active=cat_data.is_active,
                    scope=scope,
                )
            else:
                category.name = cat_data.name
                category.code = cat_data.code
                category.is_active = cat_data.is_active
                category.scope = scope
                category.parent_id = None

            session.add(category)
            category_parent_by_target_id[target_category_id] = cat_data.parent_id

        session.flush()

        # 3) Resolve parent links after all categories are present.
        external_parent_ids = {
            parent_id
            for parent_id in category_parent_by_target_id.values()
            if parent_id is not None and parent_id not in category_id_map
        }
        existing_external_parent_ids: set[uuid.UUID] = set()
        if external_parent_ids:
            existing_external_parent_ids = set(
                session.exec(
                    select(Category.id).where(Category.id.in_(list(external_parent_ids)))
                ).all()
            )

        if category_parent_by_target_id:
            for category in session.exec(
                select(Category).where(
                    Category.id.in_(list(category_parent_by_target_id.keys())),
                    Category.user_id == user_id,
                )
            ).all():
                source_parent_id = category_parent_by_target_id.get(category.id)
                resolved_parent_id: uuid.UUID | None = None
                if source_parent_id is not None:
                    if source_parent_id in category_id_map:
                        resolved_parent_id = category_id_map[source_parent_id]
                    elif source_parent_id in existing_external_parent_ids:
                        resolved_parent_id = source_parent_id

                category.parent_id = resolved_parent_id
                session.add(category)

        session.flush()

        # 4) Build a transaction ID map (source -> target) to avoid PK collisions.
        transaction_id_map: dict[uuid.UUID, uuid.UUID] = {}
        used_target_transaction_ids: set[uuid.UUID] = set()
        for tx_data in payload.transactions:
            owner_id = transaction_owner_by_id.get(tx_data.id)
            target_transaction_id = tx_data.id
            if owner_id is not None and owner_id != user_id:
                target_transaction_id = uuid.uuid4()

            while target_transaction_id in used_target_transaction_ids:
                target_transaction_id = uuid.uuid4()

            used_target_transaction_ids.add(target_transaction_id)
            transaction_id_map[tx_data.id] = target_transaction_id

        # 5) Resolve category references used by transactions/items.
        referenced_external_category_ids: set[uuid.UUID] = set()
        for tx_data in payload.transactions:
            if (
                tx_data.category_id is not None
                and tx_data.category_id not in category_id_map
            ):
                referenced_external_category_ids.add(tx_data.category_id)
            for item_data in tx_data.items:
                if (
                    item_data.category_id is not None
                    and item_data.category_id not in category_id_map
                ):
                    referenced_external_category_ids.add(item_data.category_id)

        existing_external_category_ids: set[uuid.UUID] = set()
        if referenced_external_category_ids:
            existing_external_category_ids = set(
                session.exec(
                    select(Category.id).where(
                        Category.id.in_(list(referenced_external_category_ids))
                    )
                ).all()
            )

        fallback_item_category_id = _resolve_default_item_category_id(session)

        def resolve_category_id(
            source_category_id: uuid.UUID | None, *, is_item: bool
        ) -> uuid.UUID | None:
            if source_category_id is None:
                return fallback_item_category_id if is_item else None
            if source_category_id in category_id_map:
                return category_id_map[source_category_id]
            if source_category_id in existing_external_category_ids:
                return source_category_id
            return fallback_item_category_id if is_item else None

        # 6) Upsert transactions and replace items.
        for tx_data in payload.transactions:
            target_transaction_id = transaction_id_map[tx_data.id]
            existing_tx = session.exec(
                select(Transaction).where(
                    Transaction.id == target_transaction_id,
                    Transaction.user_id == user_id,
                )
            ).first()

            actual_merchant_name = tx_data.merchant_name or tx_data.title
            resolved_tx_category_id = resolve_category_id(
                tx_data.category_id, is_item=False
            )

            if existing_tx:
                existing_tx.merchant_name = actual_merchant_name
                existing_tx.occurred_at = tx_data.occurred_at
                existing_tx.amount_total = tx_data.amount_total
                existing_tx.currency = tx_data.currency
                existing_tx.category_id = resolved_tx_category_id
                session.add(existing_tx)
            else:
                session.add(
                    Transaction(
                        id=target_transaction_id,
                        user_id=user_id,
                        merchant_name=actual_merchant_name,
                        occurred_at=tx_data.occurred_at,
                        amount_total=tx_data.amount_total,
                        currency=tx_data.currency,
                        category_id=resolved_tx_category_id,
                    )
                )

            session.exec(
                TransactionItem.__table__.delete().where(
                    TransactionItem.transaction_id == target_transaction_id
                )
            )

            used_line_numbers: set[int] = set()
            used_item_ids: set[uuid.UUID] = set()
            for idx, item_data in enumerate(tx_data.items, start=1):
                line_no = item_data.line_no if item_data.line_no > 0 else idx
                while line_no in used_line_numbers:
                    line_no += 1
                used_line_numbers.add(line_no)

                resolved_item_category_id = resolve_category_id(
                    item_data.category_id, is_item=True
                )
                if resolved_item_category_id is None:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail="Import failed: could not resolve item category.",
                    )

                target_item_id = item_data.id
                existing_item_tx_id = item_transaction_by_id.get(item_data.id)
                if (
                    existing_item_tx_id is not None
                    and existing_item_tx_id != target_transaction_id
                ):
                    target_item_id = uuid.uuid4()

                while target_item_id in used_item_ids:
                    target_item_id = uuid.uuid4()
                used_item_ids.add(target_item_id)

                session.add(
                    TransactionItem(
                        id=target_item_id,
                        transaction_id=target_transaction_id,
                        line_no=line_no,
                        description=item_data.description or "Imported item",
                        description_lang=item_data.description_lang,
                        qty=item_data.qty,
                        unit=item_data.unit,
                        unit_price=item_data.unit_price,
                        amount=item_data.amount,
                        amount_before_discount=item_data.amount_before_discount,
                        discount_amount=item_data.discount_amount,
                        is_adjustment=item_data.is_adjustment,
                        category_id=resolved_item_category_id,
                    )
                )

        session.commit()
        return {"message": "Import successful"}
    except HTTPException:
        session.rollback()
        raise
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Import failed due to invalid or conflicting references in JSON payload.",
        ) from exc
    except Exception:
        session.rollback()
        raise
