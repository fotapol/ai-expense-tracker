"""Merge feature request and planning heads.

Revision ID: f4e7b2c9a1d0
Revises: d7a9c2e4f6b1, e7f8a9b0c1d2
Create Date: 2026-03-24 13:05:00.000000
"""

from collections.abc import Sequence

# revision identifiers, used by Alembic.
revision: str = "f4e7b2c9a1d0"
down_revision: str | Sequence[str] | None = ("d7a9c2e4f6b1", "e7f8a9b0c1d2")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Merge the two active heads without schema changes."""


def downgrade() -> None:
    """Split the merged migration graph back into two heads."""
