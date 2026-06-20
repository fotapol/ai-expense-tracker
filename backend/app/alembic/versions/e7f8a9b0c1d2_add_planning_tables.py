"""Add budget settings, budget category limits, and bill reminders.

Revision ID: e7f8a9b0c1d2
Revises: 47d19b7f6184
Create Date: 2026-03-23 12:10:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "e7f8a9b0c1d2"
down_revision: str | Sequence[str] | None = "47d19b7f6184"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _index_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {index["name"] for index in insp.get_indexes(table_name)}


def _unique_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {constraint["name"] for constraint in insp.get_unique_constraints(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "budget_settings" not in tables:
        op.create_table(
            "budget_settings",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column("currency", sa.CHAR(length=3), nullable=False),
            sa.Column("monthly_income", sa.Numeric(precision=12, scale=2), nullable=True),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("user_id", name="uq_budget_settings_user_id"),
        )

    insp = sa.inspect(bind)
    budget_settings_indexes = _index_names(insp, "budget_settings")
    budget_settings_uniques = _unique_names(insp, "budget_settings")
    if "ix_budget_settings_user_id" not in budget_settings_indexes:
        op.create_index("ix_budget_settings_user_id", "budget_settings", ["user_id"], unique=False)
    if "uq_budget_settings_user_id" not in budget_settings_uniques:
        op.create_unique_constraint("uq_budget_settings_user_id", "budget_settings", ["user_id"])

    insp = sa.inspect(bind)
    if "budget_category_limits" not in set(insp.get_table_names()):
        op.create_table(
            "budget_category_limits",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("budget_settings_id", sa.Uuid(), nullable=False),
            sa.Column("category_id", sa.Uuid(), nullable=False),
            sa.Column("limit_amount", sa.Numeric(precision=12, scale=2), nullable=False),
            sa.ForeignKeyConstraint(["budget_settings_id"], ["budget_settings.id"]),
            sa.ForeignKeyConstraint(["category_id"], ["categories.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "budget_settings_id",
                "category_id",
                name="uq_budget_category_limits_budget_category",
            ),
        )

    insp = sa.inspect(bind)
    budget_limit_indexes = _index_names(insp, "budget_category_limits")
    budget_limit_uniques = _unique_names(insp, "budget_category_limits")
    if "ix_budget_category_limits_budget_settings_id" not in budget_limit_indexes:
        op.create_index(
            "ix_budget_category_limits_budget_settings_id",
            "budget_category_limits",
            ["budget_settings_id"],
            unique=False,
        )
    if "ix_budget_category_limits_category_id" not in budget_limit_indexes:
        op.create_index(
            "ix_budget_category_limits_category_id",
            "budget_category_limits",
            ["category_id"],
            unique=False,
        )
    if "uq_budget_category_limits_budget_category" not in budget_limit_uniques:
        op.create_unique_constraint(
            "uq_budget_category_limits_budget_category",
            "budget_category_limits",
            ["budget_settings_id", "category_id"],
        )

    insp = sa.inspect(bind)
    if "bill_reminders" not in set(insp.get_table_names()):
        op.create_table(
            "bill_reminders",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column("name", sa.String(length=120), nullable=False),
            sa.Column("amount", sa.Numeric(precision=12, scale=2), nullable=False),
            sa.Column("currency", sa.CHAR(length=3), nullable=False),
            sa.Column("first_due_date", sa.Date(), nullable=False),
            sa.Column("last_paid_due_date", sa.Date(), nullable=True),
            sa.Column("remind_days_before", sa.Integer(), nullable=False),
            sa.Column("is_active", sa.Boolean(), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )

    insp = sa.inspect(bind)
    bill_indexes = _index_names(insp, "bill_reminders")
    if "ix_bill_reminders_user_id" not in bill_indexes:
        op.create_index("ix_bill_reminders_user_id", "bill_reminders", ["user_id"], unique=False)
    if "ix_bill_reminders_user_active" not in bill_indexes:
        op.create_index(
            "ix_bill_reminders_user_active",
            "bill_reminders",
            ["user_id", "is_active"],
            unique=False,
        )
    if "ix_bill_reminders_user_first_due_date" not in bill_indexes:
        op.create_index(
            "ix_bill_reminders_user_first_due_date",
            "bill_reminders",
            ["user_id", "first_due_date"],
            unique=False,
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "bill_reminders" in tables:
        for index_name in list(_index_names(insp, "bill_reminders")):
            op.drop_index(index_name, table_name="bill_reminders")
        op.drop_table("bill_reminders")

    insp = sa.inspect(bind)
    if "budget_category_limits" in set(insp.get_table_names()):
        for index_name in list(_index_names(insp, "budget_category_limits")):
            op.drop_index(index_name, table_name="budget_category_limits")
        op.drop_table("budget_category_limits")

    insp = sa.inspect(bind)
    if "budget_settings" in set(insp.get_table_names()):
        for index_name in list(_index_names(insp, "budget_settings")):
            op.drop_index(index_name, table_name="budget_settings")
        op.drop_table("budget_settings")
