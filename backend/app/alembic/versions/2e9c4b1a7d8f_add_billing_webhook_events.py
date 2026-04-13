"""Add billing webhook delivery records for idempotent RevenueCat processing.

Revision ID: 2e9c4b1a7d8f
Revises: f7a3c8d1e2b4
Create Date: 2026-04-13 14:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "2e9c4b1a7d8f"
down_revision: str | Sequence[str] | None = "f7a3c8d1e2b4"
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

    if "billing_webhook_events" not in tables:
        op.create_table(
            "billing_webhook_events",
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("provider", sa.String(length=32), nullable=False),
            sa.Column("event_id", sa.String(length=255), nullable=False),
            sa.Column("event_type", sa.String(length=128), nullable=False),
            sa.Column("app_user_id", sa.String(length=255), nullable=True),
            sa.Column("status", sa.String(length=64), nullable=False),
            sa.Column(
                "delivery_attempts",
                sa.Integer(),
                nullable=False,
                server_default=sa.text("1"),
            ),
            sa.Column("processed_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("last_error", sa.String(length=500), nullable=True),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint(
                "provider",
                "event_id",
                name="uq_billing_webhook_events_provider_event",
            ),
        )

    insp = sa.inspect(bind)
    indexes = _index_names(insp, "billing_webhook_events")
    uniques = _unique_names(insp, "billing_webhook_events")
    if "ix_billing_webhook_events_status" not in indexes:
        op.create_index(
            "ix_billing_webhook_events_status",
            "billing_webhook_events",
            ["status"],
            unique=False,
        )
    if "ix_billing_webhook_events_app_user_id" not in indexes:
        op.create_index(
            "ix_billing_webhook_events_app_user_id",
            "billing_webhook_events",
            ["app_user_id"],
            unique=False,
        )
    if "ix_billing_webhook_events_processed_at" not in indexes:
        op.create_index(
            "ix_billing_webhook_events_processed_at",
            "billing_webhook_events",
            ["processed_at"],
            unique=False,
        )
    if "uq_billing_webhook_events_provider_event" not in uniques:
        op.create_unique_constraint(
            "uq_billing_webhook_events_provider_event",
            "billing_webhook_events",
            ["provider", "event_id"],
        )


def downgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    if "billing_webhook_events" in set(insp.get_table_names()):
        for index_name in list(_index_names(insp, "billing_webhook_events")):
            op.drop_index(index_name, table_name="billing_webhook_events")
        unique_names = _unique_names(insp, "billing_webhook_events")
        if "uq_billing_webhook_events_provider_event" in unique_names:
            op.drop_constraint(
                "uq_billing_webhook_events_provider_event",
                "billing_webhook_events",
                type_="unique",
            )
        op.drop_table("billing_webhook_events")
