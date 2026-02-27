"""Merchant and alias models for normalization workflows."""

import uuid

from sqlalchemy import CHAR, Column, Index, UniqueConstraint
from sqlmodel import Field, SQLModel

from app.models.shared.timestamps import TimestampedModel


class MerchantBase(SQLModel):
    """Canonical merchant attributes shared across merchant schemas."""

    canonical_name: str = Field(max_length=255, nullable=False, unique=True, index=True)
    country: str | None = Field(default=None, sa_column=Column(CHAR(2), nullable=True))


class Merchant(MerchantBase, TimestampedModel, table=True):
    """Canonical merchant entity used across extracted and manual transactions."""

    __tablename__ = "merchants"

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)


class MerchantAliasBase(SQLModel):
    """Alias text attributes captured from parsed receipts and user feedback."""

    alias: str = Field(max_length=255, nullable=False)
    normalized_alias: str = Field(max_length=255, nullable=False)


class MerchantAlias(MerchantAliasBase, TimestampedModel, table=True):
    """Mapping from raw alias text to canonical merchant IDs, global or per-user."""

    __tablename__ = "merchant_aliases"
    __table_args__ = (
        UniqueConstraint(
            "merchant_id",
            "user_id",
            "normalized_alias",
            name="uq_merchant_aliases_merchant_user_normalized",
        ),
        Index("ix_merchant_aliases_user_id", "user_id"),
        Index("ix_merchant_aliases_normalized_alias", "normalized_alias"),
    )

    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    merchant_id: uuid.UUID = Field(nullable=False, index=True, foreign_key="merchants.id")
    user_id: uuid.UUID | None = Field(default=None, foreign_key="users.id")

