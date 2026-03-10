"""Data import and export API endpoints."""

import datetime as dt
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from pydantic import ValidationError
from sqlmodel import Session, select, func

from app.auth.deps import get_current_user
from app.core.db import get_session
from app.core.rate_limiter import limiter
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


@router.get("/export", response_model=DataExportPayload)
@limiter.limit("5/minute")
async def export_data(
    request: Request,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
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
            title=tx.title,
            occurred_at=tx.occurred_at,
            amount_total=float(tx.amount_total),
            currency=tx.currency,
            category_id=tx.category_id,
            notes=tx.notes,
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
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Import categories and transactions from a JSON payload.

    This performs an upsert. Missing children (TransactionItems) for an existing transaction
    will be safely replaced.
    """

    # 1. Upsert categories
    for cat_data in payload.categories:
        existing_cat = session.exec(
            select(Category).where(
                Category.id == cat_data.id,
                Category.user_id == current_user.id,
            )
        ).first()
        if existing_cat:
            existing_cat.name = cat_data.name
            existing_cat.code = cat_data.code
            existing_cat.is_active = cat_data.is_active
            existing_cat.parent_id = cat_data.parent_id
            session.add(existing_cat)
        else:
            from app.models.taxonomy.category import CategoryScope

            new_cat = Category(
                id=cat_data.id,
                user_id=current_user.id,
                parent_id=cat_data.parent_id,
                name=cat_data.name,
                code=cat_data.code,
                is_active=cat_data.is_active,
                scope=CategoryScope(cat_data.scope),
            )
            session.add(new_cat)

    # Commit categories so they are available as foreign keys
    session.commit()

    # 2. Upsert transactions
    for tx_data in payload.transactions:
        # Check if transaction exists
        existing_tx = session.exec(
            select(Transaction).where(
                Transaction.id == tx_data.id,
                Transaction.user_id == current_user.id,
            )
        ).first()

        if existing_tx:
            existing_tx.title = tx_data.title
            existing_tx.occurred_at = tx_data.occurred_at
            existing_tx.amount_total = tx_data.amount_total
            existing_tx.currency = tx_data.currency
            existing_tx.category_id = tx_data.category_id
            existing_tx.notes = tx_data.notes
            session.add(existing_tx)
        else:
            new_tx = Transaction(
                id=tx_data.id,
                user_id=current_user.id,
                title=tx_data.title,
                occurred_at=tx_data.occurred_at,
                amount_total=tx_data.amount_total,
                currency=tx_data.currency,
                category_id=tx_data.category_id,
                notes=tx_data.notes,
            )
            session.add(new_tx)

        # Delete existing items for simplicity during upsert
        session.exec(
            TransactionItem.__table__.delete().where(
                TransactionItem.transaction_id == tx_data.id
            )
        )

        for item_data in tx_data.items:
            new_item = TransactionItem(
                id=item_data.id,
                transaction_id=tx_data.id,
                line_no=item_data.line_no,
                description=item_data.description,
                description_lang=item_data.description_lang,
                qty=item_data.qty,
                unit=item_data.unit,
                unit_price=item_data.unit_price,
                amount=item_data.amount,
                amount_before_discount=item_data.amount_before_discount,
                discount_amount=item_data.discount_amount,
                is_adjustment=item_data.is_adjustment,
                category_id=item_data.category_id,
            )
            session.add(new_item)

    session.commit()
    return {"message": "Import successful"}
