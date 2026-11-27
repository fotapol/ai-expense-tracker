"""Add verified receipt fingerprints and remembered duplicate decisions."""

import sqlalchemy as sa
from alembic import op

revision = "a6c8e2f4b9d1"
down_revision = "6f1e2d3c4b5a"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "receipts",
        sa.Column("sha256_verified", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index(
        "ix_receipts_user_verified_sha256", "receipts", ["user_id", "sha256_verified", "sha256"]
    )
    op.create_table(
        "duplicate_dismissals",
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
        ),
        sa.Column(
            "first_transaction_id",
            sa.Uuid(),
            sa.ForeignKey("transactions.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "second_transaction_id",
            sa.Uuid(),
            sa.ForeignKey("transactions.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )


def downgrade() -> None:
    op.drop_table("duplicate_dismissals")
    op.drop_index("ix_receipts_user_verified_sha256", table_name="receipts")
    op.drop_column("receipts", "sha256_verified")
