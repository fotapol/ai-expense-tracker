"""Add households, household_members, household_invites tables.

Revision ID: a1b2c3d4e5f6
Revises: 8a6b4f21c3de
Create Date: 2026-03-11 10:51:29.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "a1b2c3d4e5f6"
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
    tables = set(insp.get_table_names())

    # ------------------------------------------------------------------ #
    # households                                                           #
    # ------------------------------------------------------------------ #
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

    insp = sa.inspect(bind)
    household_indexes = _index_names(insp, "households")
    if "ix_households_owner_user_id" not in household_indexes:
        op.create_index(
            "ix_households_owner_user_id",
            "households",
            ["owner_user_id"],
            unique=False,
        )

    # ------------------------------------------------------------------ #
    # household_members                                                    #
    # ------------------------------------------------------------------ #
    insp = sa.inspect(bind)
    if "household_members" not in set(insp.get_table_names()):
        op.create_table(
            "household_members",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("household_id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column(
                "role",
                sa.Enum(
                    "owner",
                    "admin",
                    "member",
                    name="household_member_role",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column(
                "status",
                sa.Enum(
                    "invited",
                    "active",
                    "left",
                    "removed",
                    name="household_member_status",
                    native_enum=False,
                ),
                nullable=False,
            ),
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

    insp = sa.inspect(bind)
    member_indexes = _index_names(insp, "household_members")
    if "ix_household_members_household_id" not in member_indexes:
        op.create_index(
            "ix_household_members_household_id",
            "household_members",
            ["household_id"],
            unique=False,
        )
    if "ix_household_members_user_id" not in member_indexes:
        op.create_index(
            "ix_household_members_user_id",
            "household_members",
            ["user_id"],
            unique=False,
        )
    if "ix_household_members_household_status" not in member_indexes:
        op.create_index(
            "ix_household_members_household_status",
            "household_members",
            ["household_id", "status"],
            unique=False,
        )
    if "ix_household_members_user_status" not in member_indexes:
        op.create_index(
            "ix_household_members_user_status",
            "household_members",
            ["user_id", "status"],
            unique=False,
        )

    # ------------------------------------------------------------------ #
    # household_invites                                                    #
    # ------------------------------------------------------------------ #
    insp = sa.inspect(bind)
    if "household_invites" not in set(insp.get_table_names()):
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
            sa.Column(
                "status",
                sa.Enum(
                    "pending",
                    "accepted",
                    "expired",
                    "revoked",
                    name="household_invite_status",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True),
            sa.ForeignKeyConstraint(["household_id"], ["households.id"]),
            sa.ForeignKeyConstraint(["invited_by_user_id"], ["users.id"]),
            sa.ForeignKeyConstraint(["invited_user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("token", name="uq_household_invites_token"),
        )

    insp = sa.inspect(bind)
    invite_indexes = _index_names(insp, "household_invites")
    if "ix_household_invites_token" not in invite_indexes:
        op.create_index(
            "ix_household_invites_token",
            "household_invites",
            ["token"],
            unique=True,
        )
    if "ix_household_invites_household_status" not in invite_indexes:
        op.create_index(
            "ix_household_invites_household_status",
            "household_invites",
            ["household_id", "status"],
            unique=False,
        )
    if "ix_household_invites_invited_user_id" not in invite_indexes:
        op.create_index(
            "ix_household_invites_invited_user_id",
            "household_invites",
            ["invited_user_id"],
            unique=False,
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "household_invites" in tables:
        for index_name in list(_index_names(insp, "household_invites")):
            op.drop_index(index_name, table_name="household_invites")
        op.drop_table("household_invites")

    insp = sa.inspect(bind)
    if "household_members" in set(insp.get_table_names()):
        for index_name in list(_index_names(insp, "household_members")):
            op.drop_index(index_name, table_name="household_members")
        op.drop_table("household_members")

    insp = sa.inspect(bind)
    if "households" in set(insp.get_table_names()):
        for index_name in list(_index_names(insp, "households")):
            op.drop_index(index_name, table_name="households")
        op.drop_table("households")
