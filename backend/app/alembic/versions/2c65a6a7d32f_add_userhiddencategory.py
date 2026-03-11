"""Add UserHiddenCategory

Revision ID: 2c65a6a7d32f
Revises: 8a6b4f21c3de
Create Date: 2026-03-11 07:44:16.256892

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '2c65a6a7d32f'
down_revision: Union[str, Sequence[str], None] = '8a6b4f21c3de'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table('user_hidden_categories',
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('category_id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['category_id'], ['categories.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('user_id', 'category_id')
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('user_hidden_categories')
