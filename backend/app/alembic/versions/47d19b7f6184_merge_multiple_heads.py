"""Merge multiple heads

Revision ID: 47d19b7f6184
Revises: 2c65a6a7d32f, b2c3d4e5f6a7
Create Date: 2026-03-11 12:28:39.509446

"""
from collections.abc import Sequence

# revision identifiers, used by Alembic.
revision: str = '47d19b7f6184'
down_revision: str | Sequence[str] | None = ('2c65a6a7d32f', 'b2c3d4e5f6a7')
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
