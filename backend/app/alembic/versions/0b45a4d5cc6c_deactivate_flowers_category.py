"""deactivate legacy flowers category

Revision ID: 0b45a4d5cc6c
Revises: 5cb8528f7f41
Create Date: 2026-03-05 18:10:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import UTC, datetime

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "0b45a4d5cc6c"
down_revision: str | Sequence[str] | None = "5cb8528f7f41"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _get_global_item_category_id(conn: sa.Connection, code: str):
    return conn.execute(
        sa.text(
            """
            SELECT id
            FROM categories
            WHERE scope = 'ITEM'
              AND user_id IS NULL
              AND code = :code
            ORDER BY updated_at DESC
            LIMIT 1
            """
        ),
        {"code": code},
    ).scalar_one_or_none()


def upgrade() -> None:
    """Upgrade schema."""
    conn = op.get_bind()
    home_id = _get_global_item_category_id(conn, "HOME")
    flowers_id = _get_global_item_category_id(conn, "FLOWERS")
    if home_id is None or flowers_id is None or home_id == flowers_id:
        return

    now = datetime.now(UTC)
    # Preserve custom subcategories that were nested under FLOWERS by reparenting to HOME.
    conn.execute(
        sa.text(
            """
            UPDATE categories
            SET parent_id = :home_id,
                updated_at = :updated_at
            WHERE scope = 'ITEM'
              AND parent_id = :flowers_id
            """
        ),
        {"home_id": home_id, "flowers_id": flowers_id, "updated_at": now},
    )

    # If any historical items used FLOWERS directly, map them to HOME.
    conn.execute(
        sa.text(
            """
            UPDATE transaction_items
            SET category_id = :home_id
            WHERE category_id = :flowers_id
            """
        ),
        {"home_id": home_id, "flowers_id": flowers_id},
    )

    conn.execute(
        sa.text(
            """
            UPDATE categories
            SET is_active = FALSE,
                updated_at = :updated_at
            WHERE id = :flowers_id
            """
        ),
        {"flowers_id": flowers_id, "updated_at": now},
    )


def downgrade() -> None:
    """Downgrade schema."""
    conn = op.get_bind()
    home_id = _get_global_item_category_id(conn, "HOME")
    flowers_id = _get_global_item_category_id(conn, "FLOWERS")
    if home_id is None or flowers_id is None:
        return

    conn.execute(
        sa.text(
            """
            UPDATE categories
            SET is_active = TRUE,
                parent_id = :home_id,
                updated_at = :updated_at
            WHERE id = :flowers_id
            """
        ),
        {
            "home_id": home_id,
            "flowers_id": flowers_id,
            "updated_at": datetime.now(UTC),
        },
    )
