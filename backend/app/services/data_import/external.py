"""Preview and append expense records from supported import adapters."""

import datetime as dt
import uuid
from collections import defaultdict
from decimal import Decimal

from sqlmodel import Session, select

from app.models.shared.enums import CategoryScope, TransactionSource
from app.models.taxonomy.category import Category
from app.models.transactions.transaction import Transaction
from app.models.users.user import User
from app.schemas.external_import import (
    MAX_IMPORT_FILE_BYTES,
    ExternalImportPlan,
    ExternalImportPreview,
    ExternalImportResult,
    ImportSource,
)
from app.services.data_import.money_manager import BackupLimitError, read_money_manager_backup

_READERS = {ImportSource.MONEY_MANAGER: read_money_manager_backup}


def read_external_import(source: ImportSource, content: bytes) -> tuple[ExternalImportPlan, int]:
    categories, expenses, skipped = _READERS[source](content)
    plan = ExternalImportPlan(source=source, categories=categories, expenses=expenses)
    # Leave room for the local UTC offsets the client adds before confirmation.
    if len(plan.model_dump_json().encode("utf-8")) + 4 * len(expenses) > MAX_IMPORT_FILE_BYTES:
        raise BackupLimitError
    return plan, skipped


def _record_id(user_id: uuid.UUID, source: ImportSource, kind: str, uid: str) -> uuid.UUID:
    return uuid.uuid5(user_id, f"expense-import/{source}/{kind}/{uid}")


def _expense_ids(user_id: uuid.UUID, plan: ExternalImportPlan) -> list[uuid.UUID]:
    return [_record_id(user_id, plan.source, "expense", expense.uid) for expense in plan.expenses]


def _known_expenses(session: Session, owner: uuid.UUID, ids: list[uuid.UUID]) -> set[uuid.UUID]:
    if not ids:
        return set()
    return set(
        session.exec(
            select(Transaction.id).where(Transaction.user_id == owner, Transaction.id.in_(ids))
        ).all()
    )


def preview_external_import(
    session: Session,
    user_id: uuid.UUID,
    plan: ExternalImportPlan,
    skipped: int,
) -> ExternalImportPreview:
    ids = _expense_ids(user_id, plan)
    existing = _known_expenses(session, user_id, ids)
    new_expenses = [
        expense
        for expense, expense_id in zip(plan.expenses, ids, strict=True)
        if expense_id not in existing
    ]
    totals = defaultdict(Decimal)
    for expense in new_expenses:
        totals[expense.currency] += expense.amount

    return ExternalImportPreview(
        plan=plan,
        already_imported=len(existing),
        skipped=skipped,
        totals=dict(sorted(totals.items())),
        samples=new_expenses[:5],
    )


def save_external_import(
    session: Session, user_id: uuid.UUID, plan: ExternalImportPlan
) -> ExternalImportResult:
    # Serialize imports per account so a simultaneous retry observes committed rows.
    session.exec(select(User.id).where(User.id == user_id).with_for_update()).one()
    ids = _expense_ids(user_id, plan)
    existing = _known_expenses(session, user_id, ids)
    new_expenses = [
        (expense, expense_id)
        for expense, expense_id in zip(plan.expenses, ids, strict=True)
        if expense_id not in existing
    ]
    used_categories = {expense.category_uid for expense, _ in new_expenses if expense.category_uid}
    category_ids = {
        uid: _record_id(user_id, plan.source, "category", uid) for uid in used_categories
    }
    existing_categories = (
        set(
            session.exec(
                select(Category.id).where(
                    Category.user_id == user_id,
                    Category.id.in_(list(category_ids.values())),
                )
            ).all()
        )
        if category_ids
        else set()
    )
    for category in plan.categories:
        target_id = category_ids.get(category.uid)
        if target_id is not None and target_id not in existing_categories:
            session.add(
                Category(
                    id=target_id,
                    user_id=user_id,
                    scope=CategoryScope.TRANSACTION,
                    code=f"IMPORT_{target_id.hex.upper()}",
                    name=category.name,
                    is_custom=True,
                )
            )
    if category_ids:
        session.flush()

    for expense, expense_id in new_expenses:
        time_zone = dt.timezone(dt.timedelta(minutes=expense.utc_offset_minutes))
        occurred_at = dt.datetime.combine(expense.day, dt.time(12), tzinfo=time_zone)
        session.add(
            Transaction(
                id=expense_id,
                user_id=user_id,
                created_by_user_id=user_id,
                owner_user_id=user_id,
                source=TransactionSource.IMPORTED,
                status="CONFIRMED",
                occurred_at=occurred_at.astimezone(dt.UTC),
                amount_total=expense.amount,
                currency=expense.currency,
                merchant_name=expense.description,
                category_id=category_ids.get(expense.category_uid)
                if expense.category_uid
                else None,
            )
        )
    session.commit()
    return ExternalImportResult(imported=len(new_expenses), already_imported=len(existing))
