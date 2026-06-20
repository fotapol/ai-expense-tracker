"""Drop removed household schema.

Revision ID: 6f1e2d3c4b5a
Revises: 4d8f2c7b1a6e
Create Date: 2026-06-20 00:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "6f1e2d3c4b5a"
down_revision: str | Sequence[str] | None = "4d8f2c7b1a6e"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _table_names(insp: sa.Inspector) -> set[str]:
    return set(insp.get_table_names())


def _column_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in _table_names(insp):
        return set()
    return {column["name"] for column in insp.get_columns(table_name)}


def _index_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in _table_names(insp):
        return set()
    return {index["name"] for index in insp.get_indexes(table_name)}


def _drop_table_indexes(insp: sa.Inspector, table_name: str) -> None:
    for index_name in sorted(_index_names(insp, table_name)):
        op.drop_index(index_name, table_name=table_name)


def _drop_transaction_household_column(insp: sa.Inspector) -> None:
    if "transactions" not in _table_names(insp):
        return
    if "household_id" not in _column_names(insp, "transactions"):
        return

    for index_name in ["ix_transactions_household_owner", "ix_transactions_household_id"]:
        if index_name in _index_names(insp, "transactions"):
            op.drop_index(index_name, table_name="transactions")

    for fk in insp.get_foreign_keys("transactions"):
        constrained_columns = set(fk.get("constrained_columns") or [])
        if constrained_columns != {"household_id"}:
            continue
        fk_name = fk.get("name")
        if fk_name:
            op.drop_constraint(fk_name, "transactions", type_="foreignkey")

    op.drop_column("transactions", "household_id")


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    _drop_transaction_household_column(insp)

    insp = sa.inspect(bind)
    for table_name in ["household_invites", "household_members", "households"]:
        if table_name not in _table_names(insp):
            continue
        _drop_table_indexes(insp, table_name)
        op.drop_table(table_name)
        insp = sa.inspect(bind)


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = _table_names(insp)

    if "households" not in tables:
        op.create_table(
            "households",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("name", sa.String(length=255), nullable=False),
            sa.Column("owner_user_id", sa.Uuid(), nullable=False),
            sa.ForeignKeyConstraint(["owner_user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index("ix_households_owner_user_id", "households", ["owner_user_id"])

    insp = sa.inspect(bind)
    if "household_members" not in _table_names(insp):
        op.create_table(
            "household_members",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("household_id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column("role", sa.String(length=16), nullable=False),
            sa.Column("status", sa.String(length=16), nullable=False),
            sa.Column("joined_at", sa.DateTime(timezone=True), nullable=True),
            sa.ForeignKeyConstraint(["household_id"], ["households.id"]),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "household_id",
                "user_id",
                name="uq_household_members_household_user",
            ),
        )
        op.create_index(
            "ix_household_members_household_id",
            "household_members",
            ["household_id"],
        )
        op.create_index("ix_household_members_user_id", "household_members", ["user_id"])
        op.create_index(
            "ix_household_members_household_status",
            "household_members",
            ["household_id", "status"],
        )
        op.create_index(
            "ix_household_members_user_status",
            "household_members",
            ["user_id", "status"],
        )

    insp = sa.inspect(bind)
    if "household_invites" not in _table_names(insp):
        op.create_table(
            "household_invites",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("household_id", sa.Uuid(), nullable=False),
            sa.Column("invited_by_user_id", sa.Uuid(), nullable=False),
            sa.Column("invited_email", sa.String(length=320), nullable=True),
            sa.Column("invited_user_id", sa.Uuid(), nullable=True),
            sa.Column("token", sa.String(length=64), nullable=False),
            sa.Column("status", sa.String(length=16), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
            sa.ForeignKeyConstraint(["household_id"], ["households.id"]),
            sa.ForeignKeyConstraint(["invited_by_user_id"], ["users.id"]),
            sa.ForeignKeyConstraint(["invited_user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("token", name="uq_household_invites_token"),
        )
        op.create_index("ix_household_invites_token", "household_invites", ["token"], unique=True)
        op.create_index(
            "ix_household_invites_household_status",
            "household_invites",
            ["household_id", "status"],
        )
        op.create_index(
            "ix_household_invites_invited_user_id",
            "household_invites",
            ["invited_user_id"],
        )

    insp = sa.inspect(bind)
    if "transactions" in _table_names(insp) and "household_id" not in _column_names(
        insp, "transactions"
    ):
        op.add_column(
            "transactions",
            sa.Column("household_id", sa.Uuid(), sa.ForeignKey("households.id"), nullable=True),
        )
        op.create_index("ix_transactions_household_id", "transactions", ["household_id"])
        op.create_index(
            "ix_transactions_household_owner",
            "transactions",
            ["household_id", "owner_user_id"],
        )
