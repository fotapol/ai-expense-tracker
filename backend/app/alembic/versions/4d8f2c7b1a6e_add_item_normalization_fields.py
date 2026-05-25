"""Add receipt item normalization fields.

Revision ID: 4d8f2c7b1a6e
Revises: 2e9c4b1a7d8f
Create Date: 2026-05-06 12:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "4d8f2c7b1a6e"
down_revision: str | Sequence[str] | None = "2e9c4b1a7d8f"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _column_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {column["name"] for column in insp.get_columns(table_name)}


def _add_column_if_missing(
    *,
    item_columns: set[str],
    column_name: str,
    column: sa.Column,
) -> None:
    if column_name not in item_columns:
        op.add_column("transaction_items", column)


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "transaction_items" not in insp.get_table_names():
        return

    item_columns = _column_names(insp, "transaction_items")
    jsonb_type = postgresql.JSONB(astext_type=sa.Text())

    _add_column_if_missing(
        item_columns=item_columns,
        column_name="raw_name",
        column=sa.Column("raw_name", sa.String(length=500), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="translatable_name",
        column=sa.Column("translatable_name", sa.String(length=500), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="expanded_name",
        column=sa.Column("expanded_name", sa.String(length=500), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="normalized_display_name",
        column=sa.Column("normalized_display_name", sa.String(length=500), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="normalization_base_language",
        column=sa.Column(
            "normalization_base_language",
            sa.String(length=16),
            nullable=True,
            server_default="en",
        ),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="brand_name",
        column=sa.Column("brand_name", sa.String(length=255), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="product_type",
        column=sa.Column("product_type", sa.String(length=255), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="category_hint",
        column=sa.Column("category_hint", sa.String(length=255), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="item_attributes_json",
        column=sa.Column("item_attributes_json", jsonb_type, nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="preserve_terms_json",
        column=sa.Column("preserve_terms_json", jsonb_type, nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="normalization_source",
        column=sa.Column("normalization_source", sa.String(length=32), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="normalization_status",
        column=sa.Column("normalization_status", sa.String(length=32), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="normalization_confidence",
        column=sa.Column("normalization_confidence", sa.Float(), nullable=True),
    )
    _add_column_if_missing(
        item_columns=item_columns,
        column_name="normalization_warnings_json",
        column=sa.Column("normalization_warnings_json", jsonb_type, nullable=True),
    )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    if "transaction_items" not in insp.get_table_names():
        return

    item_columns = _column_names(insp, "transaction_items")
    for column_name in (
        "normalization_warnings_json",
        "normalization_confidence",
        "normalization_status",
        "normalization_source",
        "preserve_terms_json",
        "item_attributes_json",
        "category_hint",
        "product_type",
        "brand_name",
        "normalization_base_language",
        "normalized_display_name",
        "expanded_name",
        "translatable_name",
        "raw_name",
    ):
        if column_name in item_columns:
            op.drop_column("transaction_items", column_name)
