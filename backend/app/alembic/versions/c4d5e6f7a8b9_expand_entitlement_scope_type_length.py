"""Expand entitlements.scope_type length for household-scoped billing.

Revision ID: c4d5e6f7a8b9
Revises: 47d19b7f6184
Create Date: 2026-03-16 09:05:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "c4d5e6f7a8b9"
down_revision: str | Sequence[str] | None = "47d19b7f6184"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _column_length(insp: sa.Inspector, table_name: str, column_name: str) -> int | None:
    for column in insp.get_columns(table_name):
        if column.get("name") != column_name:
            continue
        return getattr(column.get("type"), "length", None)
    return None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "entitlements" not in set(insp.get_table_names()):
        return

    existing_length = _column_length(insp, "entitlements", "scope_type")
    if existing_length is not None and existing_length >= 9:
        return

    op.alter_column(
        "entitlements",
        "scope_type",
        existing_type=sa.String(length=existing_length or 4),
        type_=sa.String(length=32),
        existing_nullable=False,
    )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "entitlements" not in set(insp.get_table_names()):
        return

    existing_length = _column_length(insp, "entitlements", "scope_type")
    if existing_length == 4:
        return

    op.alter_column(
        "entitlements",
        "scope_type",
        existing_type=sa.String(length=existing_length or 32),
        type_=sa.String(length=4),
        existing_nullable=False,
    )
