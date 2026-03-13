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


class SubscriptionProvider(str, Enum):  # noqa: UP042
    """Billing provider used for a normalized subscription row."""

    GOOGLE_PLAY = "google_play"
    APP_STORE = "app_store"
    REVENUECAT = "revenuecat"
    MANUAL = "manual"


class SubscriptionStatus(str, Enum):  # noqa: UP042
    """Normalized subscription lifecycle status."""

    PENDING = "pending"
    ACTIVE = "active"
    GRACE_PERIOD = "grace_period"
    EXPIRED = "expired"
    CANCELLED = "cancelled"
    REVOKED = "revoked"


class EntitlementScopeType(str, Enum):  # noqa: UP042
    """Scope discriminator for entitlements.

    ``user`` targets a single user; ``household`` targets all active members
    of a household and is used for family plan entitlements.
    """

    USER = "user"
    HOUSEHOLD = "household"


class EntitlementStatus(str, Enum):  # noqa: UP042
    """Entitlement lifecycle status."""

    ACTIVE = "active"
    EXPIRED = "expired"
    REVOKED = "revoked"


class HouseholdMemberRole(str, Enum):  # noqa: UP042
    """Role of a user within a household."""

    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"


class HouseholdMemberStatus(str, Enum):  # noqa: UP042
    """Lifecycle status of a household membership row."""

    INVITED = "invited"
    ACTIVE = "active"
    LEFT = "left"
    REMOVED = "removed"


class HouseholdInviteStatus(str, Enum):  # noqa: UP042
    """Lifecycle status of a household invite token."""

    PENDING = "pending"
    ACCEPTED = "accepted"
    EXPIRED = "expired"
    REVOKED = "revoked"
