"""Add skip tracking to bill reminders.

Revision ID: ab39d4f7c2e1
Revises: 9e1f3c2b4a5d
Create Date: 2026-04-06 20:15:00.000000
"""

from collections.abc import Sequence
from typing import Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "ab39d4f7c2e1"
down_revision: Union[str, Sequence[str], None] = "9e1f3c2b4a5d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _column_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {column["name"] for column in insp.get_columns(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "last_skipped_due_date" in _column_names(insp, "bill_reminders"):
        return

    op.add_column(
        "bill_reminders",
        sa.Column("last_skipped_due_date", sa.Date(), nullable=True),
    )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "last_skipped_due_date" not in _column_names(insp, "bill_reminders"):
        return

    op.drop_column("bill_reminders", "last_skipped_due_date")
