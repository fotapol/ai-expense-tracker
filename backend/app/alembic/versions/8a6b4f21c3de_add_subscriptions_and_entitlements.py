"""Add subscriptions and entitlements foundation tables.

Revision ID: 8a6b4f21c3de
Revises: f1c8c4d7a2b9
Create Date: 2026-03-09 12:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "8a6b4f21c3de"
down_revision: str | Sequence[str] | None = "f1c8c4d7a2b9"
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

    if "users" in tables and "is_admin" not in _column_names(insp, "users"):
        op.add_column(
            "users",
            sa.Column(
                "is_admin",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )

    if "subscriptions" not in tables:
        op.create_table(
            "subscriptions",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column(
                "provider",
                sa.Enum(
                    "google_play",
                    "app_store",
                    "revenuecat",
                    "manual",
                    name="subscription_provider",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column("product_id", sa.String(length=128), nullable=False),
            sa.Column(
                "status",
                sa.Enum(
                    "pending",
                    "active",
                    "grace_period",
                    "expired",
                    "cancelled",
                    "revoked",
                    name="subscription_status",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("auto_renew", sa.Boolean(), nullable=True),
            sa.Column("external_customer_id", sa.String(length=255), nullable=True),
            sa.Column("external_subscription_id", sa.String(length=255), nullable=True),
            sa.Column("external_purchase_id", sa.String(length=255), nullable=True),
            sa.Column("latest_event_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("raw_payload", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
            sa.Column(
                "internal_metadata",
                postgresql.JSONB(astext_type=sa.Text()),
                nullable=True,
            ),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "user_id",
                "provider",
                "product_id",
                name="uq_subscriptions_user_provider_product",
            ),
        )

    insp = sa.inspect(bind)
    subscription_indexes = _index_names(insp, "subscriptions")
    if "ix_subscriptions_user_id" not in subscription_indexes:
        op.create_index(
            "ix_subscriptions_user_id",
            "subscriptions",
            ["user_id"],
            unique=False,
        )
    if "ix_subscriptions_user_status_expires_at" not in subscription_indexes:
        op.create_index(
            "ix_subscriptions_user_status_expires_at",
            "subscriptions",
            ["user_id", "status", "expires_at"],
            unique=False,
        )
    if "ix_subscriptions_user_latest_event_at" not in subscription_indexes:
        op.create_index(
            "ix_subscriptions_user_latest_event_at",
            "subscriptions",
            ["user_id", "latest_event_at"],
            unique=False,
        )
    if "ix_subscriptions_external_subscription_id" not in subscription_indexes:
        op.create_index(
            "ix_subscriptions_external_subscription_id",
            "subscriptions",
            ["external_subscription_id"],
            unique=False,
        )
    if "ix_subscriptions_external_purchase_id" not in subscription_indexes:
        op.create_index(
            "ix_subscriptions_external_purchase_id",
            "subscriptions",
            ["external_purchase_id"],
            unique=False,
        )

    insp = sa.inspect(bind)
    if "entitlements" not in set(insp.get_table_names()):
        op.create_table(
            "entitlements",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column(
                "scope_type",
                sa.Enum(
                    "user",
                    name="entitlement_scope_type",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column("scope_id", sa.Uuid(), nullable=False),
            sa.Column("feature_code", sa.String(length=128), nullable=False),
            sa.Column(
                "status",
                sa.Enum(
                    "active",
                    "expired",
                    "revoked",
                    name="entitlement_status",
                    native_enum=False,
                ),
                nullable=False,
            ),
            sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("source_subscription_id", sa.Uuid(), nullable=True),
            sa.ForeignKeyConstraint(
                ["source_subscription_id"],
                ["subscriptions.id"],
            ),
            sa.PrimaryKeyConstraint("id"),
        )

    insp = sa.inspect(bind)
    entitlement_indexes = _index_names(insp, "entitlements")
    if "ix_entitlements_source_subscription_id" not in entitlement_indexes:
        op.create_index(
            "ix_entitlements_source_subscription_id",
            "entitlements",
            ["source_subscription_id"],
            unique=False,
        )
    if "ix_entitlements_scope_status_window" not in entitlement_indexes:
        op.create_index(
            "ix_entitlements_scope_status_window",
            "entitlements",
            ["scope_type", "scope_id", "status", "starts_at", "expires_at"],
            unique=False,
        )
    if "ix_entitlements_scope_feature_status" not in entitlement_indexes:
        op.create_index(
            "ix_entitlements_scope_feature_status",
            "entitlements",
            ["scope_type", "scope_id", "feature_code", "status"],
            unique=False,
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)
    tables = set(insp.get_table_names())

    if "entitlements" in tables:
        for index_name in list(_index_names(insp, "entitlements")):
            op.drop_index(index_name, table_name="entitlements")
        op.drop_table("entitlements")

    insp = sa.inspect(bind)
    if "subscriptions" in set(insp.get_table_names()):
        for index_name in list(_index_names(insp, "subscriptions")):
            op.drop_index(index_name, table_name="subscriptions")
        op.drop_table("subscriptions")

    insp = sa.inspect(bind)
    if "users" in set(insp.get_table_names()) and "is_admin" in _column_names(insp, "users"):
        op.drop_column("users", "is_admin")
