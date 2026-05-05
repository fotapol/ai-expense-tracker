"""Add item translation cache and item language fields.

Revision ID: f1c8c4d7a2b9
Revises: c9e6e4b9f2c1
Create Date: 2026-03-07 12:30:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "f1c8c4d7a2b9"
down_revision: str | Sequence[str] | None = "c9e6e4b9f2c1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _column_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {column["name"] for column in insp.get_columns(table_name)}


def _index_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {index["name"] for index in insp.get_indexes(table_name)}


def _unique_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {uq["name"] for uq in insp.get_unique_constraints(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "users" in tables:
        user_columns = _column_names(insp, "users")
        if "items_language" not in user_columns:
            op.add_column("users", sa.Column("items_language", sa.String(length=16), nullable=True))

    if "transaction_items" in tables:
        item_columns = _column_names(insp, "transaction_items")
        if "description_lang" not in item_columns:
            op.add_column(
                "transaction_items",
                sa.Column("description_lang", sa.String(length=16), nullable=True),
            )
        index_names = _index_names(insp, "transaction_items")
        if op.f("ix_transaction_items_description_lang") not in index_names:
            op.create_index(
                op.f("ix_transaction_items_description_lang"),
                "transaction_items",
                ["description_lang"],
                unique=False,
            )

    if "item_translations" not in tables:
        op.create_table(
            "item_translations",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column("source_text", sa.String(length=500), nullable=False),
            sa.Column("normalized_source_text", sa.String(length=500), nullable=False),
            sa.Column("source_language", sa.String(length=16), nullable=False),
            sa.Column("target_language", sa.String(length=16), nullable=False),
            sa.Column("translated_text", sa.String(length=500), nullable=False),
            sa.Column("provider", sa.String(length=32), nullable=False, server_default="mlkit"),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "user_id",
                "normalized_source_text",
                "source_language",
                "target_language",
                name="uq_item_translations_user_source_lang_target",
            ),
        )
        op.create_index(op.f("ix_item_translations_user_id"), "item_translations", ["user_id"], unique=False)
        op.create_index(
            op.f("ix_item_translations_normalized_source_text"),
            "item_translations",
            ["normalized_source_text"],
            unique=False,
        )
        op.create_index(
            op.f("ix_item_translations_target_language"),
            "item_translations",
            ["target_language"],
            unique=False,
        )
    else:
        index_names = _index_names(insp, "item_translations")
        unique_names = _unique_names(insp, "item_translations")
        if op.f("ix_item_translations_user_id") not in index_names:
            op.create_index(op.f("ix_item_translations_user_id"), "item_translations", ["user_id"], unique=False)
        if op.f("ix_item_translations_normalized_source_text") not in index_names:
            op.create_index(
                op.f("ix_item_translations_normalized_source_text"),
                "item_translations",
                ["normalized_source_text"],
                unique=False,
            )
        if op.f("ix_item_translations_target_language") not in index_names:
            op.create_index(
                op.f("ix_item_translations_target_language"),
                "item_translations",
                ["target_language"],
                unique=False,
            )
        if "uq_item_translations_user_source_lang_target" not in unique_names:
            op.create_unique_constraint(
                "uq_item_translations_user_source_lang_target",
                "item_translations",
                ["user_id", "normalized_source_text", "source_language", "target_language"],
            )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "item_translations" in tables:
        for index_name in list(_index_names(insp, "item_translations")):
            op.drop_index(index_name, table_name="item_translations")
        op.drop_table("item_translations")

    if "transaction_items" in tables:
        item_columns = _column_names(insp, "transaction_items")
        index_names = _index_names(insp, "transaction_items")
        if op.f("ix_transaction_items_description_lang") in index_names:
            op.drop_index(op.f("ix_transaction_items_description_lang"), table_name="transaction_items")
        if "description_lang" in item_columns:
            op.drop_column("transaction_items", "description_lang")

    if "users" in tables:
        user_columns = _column_names(insp, "users")
        if "items_language" in user_columns:
            op.drop_column("users", "items_language")
