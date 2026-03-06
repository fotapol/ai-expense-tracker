"""Add exchange_rates table and ensure labels tables exist.

Revision ID: c9e6e4b9f2c1
Revises: b3f95c0e7c11
Create Date: 2026-03-06 11:20:00.000000
"""

from collections.abc import Sequence
from typing import Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "c9e6e4b9f2c1"
down_revision: Union[str, Sequence[str], None] = "b3f95c0e7c11"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _index_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {idx["name"] for idx in insp.get_indexes(table_name)}


def _unique_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {uq["name"] for uq in insp.get_unique_constraints(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "labels" not in tables:
        op.create_table(
            "labels",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("color", sa.String(length=7), nullable=True),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column("is_active", sa.Boolean(), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index(op.f("ix_labels_user_id"), "labels", ["user_id"], unique=False)

    insp = sa.inspect(bind)
    index_names = _index_names(insp, "labels")
    if op.f("ix_labels_user_id") not in index_names:
        op.create_index(op.f("ix_labels_user_id"), "labels", ["user_id"], unique=False)

    if "transaction_labels" not in set(insp.get_table_names()):
        op.create_table(
            "transaction_labels",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("transaction_id", sa.Uuid(), nullable=False),
            sa.Column("label_id", sa.Uuid(), nullable=False),
            sa.ForeignKeyConstraint(["label_id"], ["labels.id"]),
            sa.ForeignKeyConstraint(["transaction_id"], ["transactions.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "transaction_id",
                "label_id",
                name="uq_transaction_labels_transaction_id_label_id",
            ),
        )
        op.create_index(
            op.f("ix_transaction_labels_transaction_id"),
            "transaction_labels",
            ["transaction_id"],
            unique=False,
        )
        op.create_index(
            op.f("ix_transaction_labels_label_id"),
            "transaction_labels",
            ["label_id"],
            unique=False,
        )

    insp = sa.inspect(bind)
    index_names = _index_names(insp, "transaction_labels")
    unique_names = _unique_names(insp, "transaction_labels")
    if op.f("ix_transaction_labels_transaction_id") not in index_names:
        op.create_index(
            op.f("ix_transaction_labels_transaction_id"),
            "transaction_labels",
            ["transaction_id"],
            unique=False,
        )
    if op.f("ix_transaction_labels_label_id") not in index_names:
        op.create_index(
            op.f("ix_transaction_labels_label_id"),
            "transaction_labels",
            ["label_id"],
            unique=False,
        )
    if "uq_transaction_labels_transaction_id_label_id" not in unique_names:
        op.execute(
            sa.text(
                """
                DELETE FROM transaction_labels
                WHERE id IN (
                    SELECT id
                    FROM (
                        SELECT
                            id,
                            ROW_NUMBER() OVER (
                                PARTITION BY transaction_id, label_id
                                ORDER BY created_at, id
                            ) AS rn
                        FROM transaction_labels
                    ) dedup
                    WHERE dedup.rn > 1
                )
                """
            )
        )
        op.create_unique_constraint(
            "uq_transaction_labels_transaction_id_label_id",
            "transaction_labels",
            ["transaction_id", "label_id"],
        )

    if "exchange_rates" not in set(insp.get_table_names()):
        op.create_table(
            "exchange_rates",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("provider", sa.String(length=32), nullable=False),
            sa.Column("base_currency", sa.String(length=3), nullable=False),
            sa.Column("quote_currency", sa.String(length=3), nullable=False),
            sa.Column("rate_date", sa.Date(), nullable=False),
            sa.Column("rate", sa.Numeric(precision=18, scale=8), nullable=False),
            sa.Column("fetched_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("is_fallback", sa.Boolean(), nullable=False),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "provider",
                "base_currency",
                "quote_currency",
                "rate_date",
                name="uq_exchange_rates_provider_pair_date",
            ),
        )
        op.create_index(
            "ix_exchange_rates_provider_pair_date",
            "exchange_rates",
            ["provider", "base_currency", "quote_currency", "rate_date"],
            unique=False,
        )
        op.create_index(
            "ix_exchange_rates_pair_date",
            "exchange_rates",
            ["base_currency", "quote_currency", "rate_date"],
            unique=False,
        )
        op.create_index(
            op.f("ix_exchange_rates_provider"),
            "exchange_rates",
            ["provider"],
            unique=False,
        )
        op.create_index(
            op.f("ix_exchange_rates_base_currency"),
            "exchange_rates",
            ["base_currency"],
            unique=False,
        )
        op.create_index(
            op.f("ix_exchange_rates_quote_currency"),
            "exchange_rates",
            ["quote_currency"],
            unique=False,
        )
        op.create_index(
            op.f("ix_exchange_rates_rate_date"),
            "exchange_rates",
            ["rate_date"],
            unique=False,
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "exchange_rates" in tables:
        for idx in list(_index_names(insp, "exchange_rates")):
            op.drop_index(idx, table_name="exchange_rates")
        op.drop_table("exchange_rates")
