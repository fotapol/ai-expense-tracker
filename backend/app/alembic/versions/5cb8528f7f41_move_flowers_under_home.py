"""move flowers category under home

Revision ID: 5cb8528f7f41
Revises: 24f215cbe72a
Create Date: 2026-03-05 15:44:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime, timezone

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "5cb8528f7f41"
down_revision: str | Sequence[str] | None = "24f215cbe72a"
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

    conn.execute(
        sa.text(
            """
            UPDATE categories
            SET parent_id = :home_id,
                updated_at = :updated_at
            WHERE id = :flowers_id
            """
        ),
        {
            "home_id": home_id,
            "flowers_id": flowers_id,
            "updated_at": datetime.now(timezone.utc),
        },
    )


def downgrade() -> None:
    """Downgrade schema."""
    conn = op.get_bind()
    flowers_id = _get_global_item_category_id(conn, "FLOWERS")
    if flowers_id is None:
        return

    conn.execute(
        sa.text(
            """
            UPDATE categories
            SET parent_id = NULL,
                updated_at = :updated_at
            WHERE id = :flowers_id
            """
        ),
        {
            "flowers_id": flowers_id,
            "updated_at": datetime.now(timezone.utc),
        },
    )
