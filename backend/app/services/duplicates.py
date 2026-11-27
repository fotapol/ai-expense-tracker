"""Explainable purchase matching without extra AI calls or automatic deletion."""

import datetime as dt
import re
import unicodedata
import uuid
from collections import defaultdict
from difflib import SequenceMatcher
from itertools import combinations

from fastapi import HTTPException
from sqlalchemy import and_, or_
from sqlmodel import Session, select

from app.models.receipts.receipt import Receipt
from app.models.shared.enums import ReceiptStatus, TransactionSource
from app.models.transactions.duplicate_dismissal import DuplicateDismissal
from app.models.transactions.transaction import Transaction
from app.models.transactions.transaction_item import TransactionItem
from app.schemas.duplicates import DuplicatePageRead, DuplicatePairRead, DuplicateTransactionRead
from app.schemas.shared import quantize_amount


def canonical_pair(first: uuid.UUID, second: uuid.UUID) -> tuple[uuid.UUID, uuid.UUID]:
    if first == second:
        raise HTTPException(status_code=422, detail="Choose two different transactions.")
    return tuple(sorted((first, second), key=lambda value: value.int))


def normalize_name(value: str | None) -> str:
    value = unicodedata.normalize("NFKC", value or "").casefold()
    return " ".join("".join(ch if ch.isalnum() else " " for ch in value).split())


def merchant_similarity(first: str | None, second: str | None) -> float:
    first, second = normalize_name(first), normalize_name(second)
    unknown = {"", "unknown", "unknown store", "manual entry", "imported expense"}
    if first in unknown or second in unknown or min(len(first), len(second)) < 3:
        return 0
    first_digits, second_digits = re.findall(r"\d+", first), re.findall(r"\d+", second)
    if first_digits and second_digits and first_digits != second_digits:
        return 0
    return SequenceMatcher(None, first, second).ratio()


def _item_name(item: TransactionItem) -> str:
    if item.raw_name is not None and normalize_name(item.description) != normalize_name(
        item.raw_name
    ):
        return normalize_name(item.description)
    return normalize_name(
        item.normalized_display_name
        or item.expanded_name
        or item.translatable_name
        or item.raw_name
        or item.description
    )


def matching_items(first: list[TransactionItem], second: list[TransactionItem]) -> int:
    """Consume each line once, preserving quantities and repeated products."""
    remaining = list(second)
    count = 0
    for item in first:
        name = _item_name(item)
        if not name:
            continue
        best_index, best_score = None, 0
        for index, other in enumerate(remaining):
            if quantize_amount(item.amount) != quantize_amount(other.amount):
                continue
            if item.qty is not None and other.qty is not None and item.qty != other.qty:
                continue
            if item.unit and other.unit and item.unit.casefold() != other.unit.casefold():
                continue
            score = SequenceMatcher(None, name, _item_name(other)).ratio()
            if score >= 0.9 and score > best_score:
                best_index, best_score = index, score
        if best_index is not None:
            remaining.pop(best_index)
            count += 1
    return count


def _snippet(transaction: Transaction, items: list[TransactionItem]) -> DuplicateTransactionRead:
    return DuplicateTransactionRead.model_validate(transaction).model_copy(
        update={"item_count": len(items)}
    )


def _pair_result(
    first: Transaction,
    second: Transaction,
    first_items: list[TransactionItem],
    second_items: list[TransactionItem],
    *,
    exact: bool,
) -> DuplicatePairRead | None:
    count = matching_items(first_items, second_items)
    if exact:
        return DuplicatePairRead(
            first=_snippet(first, first_items),
            second=_snippet(second, second_items),
            confidence="exact",
            reasons=["same_image"],
            matching_item_count=count,
        )
    if first.amount_total is None or second.amount_total is None:
        return None
    if first.currency.strip().upper() != second.currency.strip().upper():
        return None
    if quantize_amount(first.amount_total) != quantize_amount(second.amount_total):
        return None
    if first.occurred_at is None or second.occurred_at is None:
        return None
    days = abs((first.occurred_at.date() - second.occurred_at.date()).days)
    if days > 1:
        return None
    similarity = merchant_similarity(first.merchant_name, second.merchant_name)
    coverage = count / max(len(first_items), len(second_items), 1)
    strong_items = count >= 2 and coverage >= 0.8
    if similarity < 0.88 and not (similarity >= 0.6 and strong_items):
        return None
    if days and not strong_items:
        return None
    if (
        first.source == second.source == TransactionSource.RECEIPT
        and min(len(first_items), len(second_items)) >= 2
        and coverage < 0.5
    ):
        return None
    reasons = ["same_total", "same_date" if days == 0 else "nearby_dates", "similar_merchant"]
    if count:
        reasons.append("matching_items")
    return DuplicatePairRead(
        first=_snippet(first, first_items),
        second=_snippet(second, second_items),
        confidence="high" if strong_items else "possible",
        reasons=reasons,
        matching_item_count=count,
    )


def _timestamp(transaction: DuplicateTransactionRead) -> float:
    value = transaction.occurred_at or transaction.created_at
    return (value if value.tzinfo else value.replace(tzinfo=dt.UTC)).timestamp()


def find_duplicates(
    session: Session,
    *,
    user_id: uuid.UUID,
    page: int = 1,
    page_size: int = 20,
    transaction_id: uuid.UUID | None = None,
    only_pair: tuple[uuid.UUID, uuid.UUID] | None = None,
) -> DuplicatePageRead:
    query = select(Transaction, Receipt.sha256, Receipt.sha256_verified)
    if only_pair is not None:
        query = query.where(Transaction.id.in_(only_pair))
    rows = session.exec(
        query.outerjoin(Receipt, Receipt.id == Transaction.receipt_id).where(
            Transaction.user_id == user_id,
            or_(
                Transaction.receipt_id.is_(None),
                and_(Receipt.user_id == user_id, Receipt.status == ReceiptStatus.COMPLETED),
            ),
        )
    ).all()
    transactions = {tx.id: tx for tx, _, _ in rows}
    if transaction_id is not None and transaction_id not in transactions:
        raise HTTPException(
            status_code=404, detail="Transaction not found or receipt is still processing."
        )
    dismissed = {
        (row.first_transaction_id, row.second_transaction_id)
        for row in session.exec(
            select(DuplicateDismissal).where(DuplicateDismissal.user_id == user_id)
        ).all()
    }
    exact_pairs = set()
    candidates = set()

    def add_pair(first, second, *, exact=False):
        pair = canonical_pair(first, second)
        if pair in dismissed or (transaction_id is not None and transaction_id not in pair):
            return
        candidates.add(pair)
        if exact:
            exact_pairs.add(pair)

    hashes = defaultdict(list)
    buckets = defaultdict(list)
    # Bucketing by original currency, cents and purchase day avoids an all-history
    # pairwise comparison. A different photo can match even when its bytes differ.
    for tx, sha256, verified in rows:
        if verified and sha256 and re.fullmatch(r"[0-9a-f]{64}", sha256):
            hashes[sha256].append(tx.id)
        if tx.amount_total is None or tx.amount_total <= 0 or tx.occurred_at is None:
            continue
        amount = quantize_amount(tx.amount_total)
        currency, day = tx.currency.strip().upper(), tx.occurred_at.date()
        for offset in (-1, 0, 1):
            ordinal = day.toordinal() + offset
            if not 1 <= ordinal <= dt.date.max.toordinal():
                continue
            for other in buckets[(currency, amount, dt.date.fromordinal(ordinal))]:
                add_pair(tx.id, other)
        buckets[(currency, amount, day)].append(tx.id)
    for ids in hashes.values():
        for first, second in combinations(ids, 2):
            add_pair(first, second, exact=True)
    needed = {value for pair in candidates for value in pair}
    items = defaultdict(list)
    if needed:
        for item in session.exec(
            select(TransactionItem).where(
                TransactionItem.transaction_id.in_(needed), TransactionItem.is_adjustment.is_(False)
            )
        ).all():
            items[item.transaction_id].append(item)
    pairs = []
    for first, second in candidates:
        pair = _pair_result(
            transactions[first],
            transactions[second],
            items[first],
            items[second],
            exact=(first, second) in exact_pairs,
        )
        if pair is not None:
            pairs.append(pair)
    priority = {"exact": 0, "high": 1, "possible": 2}
    pairs.sort(
        key=lambda pair: (
            priority[pair.confidence],
            -max(_timestamp(pair.first), _timestamp(pair.second)),
            pair.first.id.int,
            pair.second.id.int,
        )
    )
    start = (page - 1) * page_size
    return DuplicatePageRead(
        items=pairs[start : start + page_size],
        page=page,
        page_size=page_size,
        has_more=len(pairs) > start + page_size,
    )
