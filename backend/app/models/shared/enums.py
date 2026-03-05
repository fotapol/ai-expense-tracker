"""Shared enum types for ORM models."""

from enum import Enum


class CategoryScope(str, Enum):  # noqa: UP042
    """Category scope used to separate transaction and item taxonomy nodes."""

    TRANSACTION = "TRANSACTION"
    ITEM = "ITEM"


class ReceiptStatus(str, Enum):  # noqa: UP042
    """Receipt processing lifecycle status values."""

    CREATED = "CREATED"
    UPLOADED = "UPLOADED"
    PROCESSING = "PROCESSING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


class TransactionSource(str, Enum):  # noqa: UP042
    """Source of a transaction record."""

    RECEIPT = "RECEIPT"
    MANUAL = "MANUAL"
    IMPORTED = "IMPORTED"
