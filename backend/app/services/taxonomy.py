"""Helpers for user-specific category availability."""

from __future__ import annotations

import uuid
from collections import defaultdict

from sqlmodel import Session, select

from app.models.shared.enums import CategoryScope
from app.models.taxonomy.category import Category
from app.models.taxonomy.category_hidden import UserHiddenCategory


def get_user_disabled_category_ids(
    session: Session,
    user_id: uuid.UUID,
) -> set[uuid.UUID]:
    """Return category IDs disabled for the given user."""

    rows = session.exec(
        select(UserHiddenCategory.category_id).where(
            UserHiddenCategory.user_id == user_id,
        )
    ).all()
    return set(rows)


def collect_disable_target_ids(
    session: Session,
    category: Category,
) -> set[uuid.UUID]:
    """Return all category IDs affected by disabling/restoring one category."""

    target_ids = {category.id}

    # Disabling a built-in top-level ITEM category also disables built-in
    # descendants plus the matching TRANSACTION category code used by the worker.
    if (
        category.user_id is None
        and category.scope == CategoryScope.ITEM
        and category.parent_id is None
    ):
        rows = session.exec(
            select(Category.id, Category.parent_id).where(
                Category.scope == CategoryScope.ITEM,
                Category.user_id.is_(None),
                Category.is_active,
            )
        ).all()
        children_by_parent: dict[uuid.UUID, set[uuid.UUID]] = defaultdict(set)
        for child_id, parent_id in rows:
            if parent_id is None:
                continue
            children_by_parent[parent_id].add(child_id)

        stack = [category.id]
        while stack:
            current = stack.pop()
            for child_id in children_by_parent.get(current, set()):
                if child_id in target_ids:
                    continue
                target_ids.add(child_id)
                stack.append(child_id)

        transaction_rows = session.exec(
            select(Category.id).where(
                Category.scope == CategoryScope.TRANSACTION,
                Category.user_id.is_(None),
                Category.code == category.code,
                Category.is_active,
            )
        ).all()
        target_ids.update(transaction_rows)

    return target_ids


def disable_category_ids_for_user(
    session: Session,
    *,
    user_id: uuid.UUID,
    category_ids: set[uuid.UUID],
) -> None:
    """Persist disabled category IDs for a user."""

    if not category_ids:
        return

    existing_ids = set(
        session.exec(
            select(UserHiddenCategory.category_id).where(
                UserHiddenCategory.user_id == user_id,
                UserHiddenCategory.category_id.in_(category_ids),
            )
        ).all()
    )
    for category_id in sorted(category_ids - existing_ids):
        session.add(UserHiddenCategory(user_id=user_id, category_id=category_id))
    session.commit()


def restore_category_ids_for_user(
    session: Session,
    *,
    user_id: uuid.UUID,
    category_ids: set[uuid.UUID],
) -> int:
    """Delete disabled category rows for a user and return count removed."""

    if not category_ids:
        return 0

    rows = session.exec(
        select(UserHiddenCategory).where(
            UserHiddenCategory.user_id == user_id,
            UserHiddenCategory.category_id.in_(category_ids),
        )
    ).all()
    for row in rows:
        session.delete(row)
    if rows:
        session.commit()
    return len(rows)
