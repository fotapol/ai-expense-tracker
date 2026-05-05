"""Add feature request and vote tables.

Revision ID: d7a9c2e4f6b1
Revises: c4d5e6f7a8b9, f1c8c4d7a2b9
Create Date: 2026-03-23 15:10:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "d7a9c2e4f6b1"
down_revision: str | Sequence[str] | None = ("c4d5e6f7a8b9", "f1c8c4d7a2b9")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _index_names(insp: sa.Inspector, table_name: str) -> set[str]:
    if table_name not in insp.get_table_names():
        return set()
    return {idx["name"] for idx in insp.get_indexes(table_name)}


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "feature_requests" not in tables:
        op.create_table(
            "feature_requests",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("title", sa.String(length=120), nullable=False),
            sa.Column("description", sa.String(length=2000), nullable=False),
            sa.Column(
                "category",
                sa.Enum(
                    "analytics_reports",
                    "receipts_scanning",
                    "budgets_planning",
                    "household_sharing",
                    "design_accessibility",
                    "other",
                    name="feature_request_category",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column(
                "moderation_state",
                sa.Enum(
                    "pending",
                    "approved",
                    "rejected",
                    name="feature_request_moderation_state",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column(
                "public_status",
                sa.Enum(
                    "under_review",
                    "planned",
                    "in_progress",
                    "completed",
                    name="feature_request_public_status",
                    native_enum=False,
                ),
                nullable=True,
            ),
            sa.Column("moderation_note", sa.String(length=2000), nullable=True),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("creator_user_id", sa.Uuid(), nullable=False),
            sa.Column("reviewed_by_user_id", sa.Uuid(), nullable=True),
            sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
            sa.CheckConstraint(
                """
                (
                    moderation_state = 'approved'
                    AND public_status IS NOT NULL
                )
                OR (
                    moderation_state IN ('pending', 'rejected')
                    AND public_status IS NULL
                )
                """,
                name="ck_feature_requests_public_state_consistency",
            ),
            sa.ForeignKeyConstraint(["creator_user_id"], ["users.id"]),
            sa.ForeignKeyConstraint(["reviewed_by_user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
        )
        op.create_index(
            "ix_feature_requests_creator_user_id",
            "feature_requests",
            ["creator_user_id"],
            unique=False,
        )
        op.create_index(
            "ix_feature_requests_moderation_state",
            "feature_requests",
            ["moderation_state"],
            unique=False,
        )
        op.create_index(
            "ix_feature_requests_public_status",
            "feature_requests",
            ["public_status"],
            unique=False,
        )

    insp = sa.inspect(bind)
    if "feature_request_votes" not in set(insp.get_table_names()):
        op.create_table(
            "feature_request_votes",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("feature_request_id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.ForeignKeyConstraint(["feature_request_id"], ["feature_requests.id"]),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "feature_request_id",
                "user_id",
                name="uq_feature_request_votes_request_user",
            ),
        )
        op.create_index(
            "ix_feature_request_votes_feature_request_id",
            "feature_request_votes",
            ["feature_request_id"],
            unique=False,
        )
        op.create_index(
            "ix_feature_request_votes_user_id",
            "feature_request_votes",
            ["user_id"],
            unique=False,
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "feature_request_votes" in tables:
        for index_name in _index_names(insp, "feature_request_votes"):
            op.drop_index(index_name, table_name="feature_request_votes")
        op.drop_table("feature_request_votes")

    insp = sa.inspect(bind)
    if "feature_requests" in set(insp.get_table_names()):
        for index_name in _index_names(insp, "feature_requests"):
            op.drop_index(index_name, table_name="feature_requests")
        op.drop_table("feature_requests")
