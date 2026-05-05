"""deactivate hortenzije subcategory

Revision ID: b3f95c0e7c11
Revises: 0b45a4d5cc6c
Create Date: 2026-03-05 20:05:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import UTC, datetime

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "b3f95c0e7c11"
down_revision: str | Sequence[str] | None = "0b45a4d5cc6c"
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

    if home_id is not None:
        conn.execute(
            sa.text(
                """
                UPDATE transaction_items
                SET category_id = :home_id
                WHERE category_id IN (
                    SELECT id
                    FROM categories
                    WHERE scope = 'ITEM'
                      AND (
                          UPPER(code) = 'HORTENZIJE'
                          OR LOWER(name) = 'hortenzije'
                      )
                )
                """
            ),
            {"home_id": home_id},
        )

    conn.execute(
        sa.text(
            """
            UPDATE categories
            SET is_active = FALSE,
                updated_at = :updated_at
            WHERE scope = 'ITEM'
              AND (
                  UPPER(code) = 'HORTENZIJE'
                  OR LOWER(name) = 'hortenzije'
              )
            """
        ),
        {"updated_at": datetime.now(UTC)},
    )


def downgrade() -> None:
    """Downgrade schema."""
    conn = op.get_bind()
    conn.execute(
        sa.text(
            """
            UPDATE categories
            SET is_active = TRUE,
                updated_at = :updated_at
            WHERE scope = 'ITEM'
              AND (
                  UPPER(code) = 'HORTENZIJE'
                  OR LOWER(name) = 'hortenzije'
              )
            """
        ),
        {"updated_at": datetime.now(UTC)},
    )
