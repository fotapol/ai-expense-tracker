"""Add expense attribution columns to transactions table.

Adds ``created_by_user_id`` and ``owner_user_id`` columns to the
``transactions`` table and backfills existing rows so that:
    created_by_user_id = user_id
    owner_user_id      = user_id

Revision ID: b2c3d4e5f6a7
Revises: 8a6b4f21c3de
Create Date: 2026-03-11 10:51:30.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "b2c3d4e5f6a7"
down_revision: str | Sequence[str] | None = "8a6b4f21c3de"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _index_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {index["name"] for index in insp.get_indexes(table_name)}


def _column_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {column["name"] for column in insp.get_columns(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    existing_cols = _column_names(insp, "transactions")

    # Add created_by_user_id ---------------------------------------------
    if "created_by_user_id" not in existing_cols:
        op.add_column(
            "transactions",
            sa.Column(
                "created_by_user_id",
                sa.Uuid(),
                sa.ForeignKey("users.id"),
                nullable=True,
            ),
        )

    # Add owner_user_id --------------------------------------------------
    if "owner_user_id" not in existing_cols:
        op.add_column(
            "transactions",
            sa.Column(
                "owner_user_id",
                sa.Uuid(),
                sa.ForeignKey("users.id"),
                nullable=True,
            ),
        )

    # Backfill: set created_by_user_id and owner_user_id = user_id -------
    op.execute(
        sa.text(
            """
            UPDATE transactions
               SET created_by_user_id = user_id
             WHERE created_by_user_id IS NULL
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE transactions
               SET owner_user_id = user_id
             WHERE owner_user_id IS NULL
            """
        )
    )

    # Indexes ------------------------------------------------------------
    insp = sa.inspect(bind)
    existing_indexes = _index_names(insp, "transactions")

    if "ix_transactions_created_by_user_id" not in existing_indexes:
        op.create_index(
            "ix_transactions_created_by_user_id",
            "transactions",
            ["created_by_user_id"],
            unique=False,
        )
    if "ix_transactions_owner_user_id" not in existing_indexes:
        op.create_index(
            "ix_transactions_owner_user_id",
            "transactions",
            ["owner_user_id"],
            unique=False,
        )
    if "ix_transactions_owner_occurred_at" not in existing_indexes:
        op.create_index(
            "ix_transactions_owner_occurred_at",
            "transactions",
            ["owner_user_id", "occurred_at"],
            unique=False,
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    existing_indexes = _index_names(insp, "transactions")
    existing_cols = _column_names(insp, "transactions")

    for idx in [
        "ix_transactions_owner_occurred_at",
        "ix_transactions_owner_user_id",
        "ix_transactions_created_by_user_id",
    ]:
        if idx in existing_indexes:
            op.drop_index(idx, table_name="transactions")

    for col in ["owner_user_id", "created_by_user_id"]:
        if col in existing_cols:
            op.drop_column("transactions", col)
