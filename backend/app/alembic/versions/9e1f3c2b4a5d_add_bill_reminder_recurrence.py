"""Add recurrence to bill reminders.

Revision ID: 9e1f3c2b4a5d
Revises: f4e7b2c9a1d0
Create Date: 2026-03-31 16:30:00.000000
"""

from collections.abc import Sequence
from typing import Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "9e1f3c2b4a5d"
down_revision: Union[str, Sequence[str], None] = "f4e7b2c9a1d0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _column_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {column["name"] for column in insp.get_columns(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "recurrence" in _column_names(insp, "bill_reminders"):
        return

    op.add_column(
        "bill_reminders",
        sa.Column(
            "recurrence",
            sa.String(length=16),
            nullable=False,
            server_default="monthly",
        ),
    )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "recurrence" not in _column_names(insp, "bill_reminders"):
        return

    op.drop_column("bill_reminders", "recurrence")
