"""add icon and color to categories

Revision ID: 84485dd9c1e5
Revises: 97c2cd8a8fc8
Create Date: 2026-03-04 13:12:06.635398

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '84485dd9c1e5'
down_revision: Union[str, Sequence[str], None] = '97c2cd8a8fc8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('categories', sa.Column('icon', sa.String(length=50), nullable=True))
    op.add_column('categories', sa.Column('color', sa.String(length=50), nullable=True))


def downgrade() -> None:
    op.drop_column('categories', 'color')
    op.drop_column('categories', 'icon')
