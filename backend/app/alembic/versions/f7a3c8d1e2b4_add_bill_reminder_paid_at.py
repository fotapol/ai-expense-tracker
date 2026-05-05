"""Add paid timestamp to bill reminders.

Revision ID: f7a3c8d1e2b4
Revises: ab39d4f7c2e1
Create Date: 2026-04-07 22:40:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "f7a3c8d1e2b4"
down_revision: str | Sequence[str] | None = "ab39d4f7c2e1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _column_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {column["name"] for column in insp.get_columns(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "last_paid_at" in _column_names(insp, "bill_reminders"):
        return

    op.add_column(
        "bill_reminders",
        sa.Column("last_paid_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "last_paid_at" not in _column_names(insp, "bill_reminders"):
        return

    op.drop_column("bill_reminders", "last_paid_at")
