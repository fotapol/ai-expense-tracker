"""ORM model package exports for metadata registration and app imports."""

from app.models.billing.entitlement import Entitlement
from app.models.billing.subscription import Subscription
from app.models.billing.webhook_event import BillingWebhookEvent
from app.models.feature_requests.feature_request import FeatureRequest, FeatureRequestBase
from app.models.feature_requests.feature_request_vote import FeatureRequestVote
from app.models.fx.exchange_rate import ExchangeRate
from app.models.households.household import Household, HouseholdBase
from app.models.households.household_invite import HouseholdInvite
from app.models.households.household_member import HouseholdMember
from app.models.labels.label import Label, LabelBase
from app.models.labels.transaction_label import TransactionLabel
from app.models.merchants.merchant import Merchant, MerchantAlias, MerchantAliasBase, MerchantBase
from app.models.overrides.user_category import UserCategoryOverride, UserItemCategoryOverride
from app.models.planning.bill_reminder import BillReminder
from app.models.planning.budget import BudgetCategoryLimit, BudgetSettings
from app.models.receipts.receipt import Receipt, ReceiptBase
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import (
    CategoryScope,
    EntitlementScopeType,
    EntitlementStatus,
    FeatureRequestCategory,
    FeatureRequestModerationState,
    FeatureRequestPublicStatus,
    HouseholdInviteStatus,
    HouseholdMemberRole,
    HouseholdMemberStatus,
    ReceiptStatus,
    SubscriptionProvider,
    SubscriptionStatus,
    TransactionSource,
)
from app.models.shared.timestamps import TimestampedModel
from app.models.taxonomy.category import Category, CategoryBase
from app.models.transactions.transaction import Transaction, TransactionBase
from app.models.transactions.transaction_item import TransactionItem
from app.models.translations.item_translation import ItemTranslation
from app.models.users.profile import Profile, ProfileBase
from app.models.users.user import User, UserBase

__all__ = [
    "BillReminder",
    "BillingWebhookEvent",
    "BudgetCategoryLimit",
    "BudgetSettings",
    "Category",
    "CategoryBase",
    "CategoryScope",
    "Entitlement",
    "EntitlementScopeType",
    "EntitlementStatus",
    "ExchangeRate",
    "FeatureRequest",
    "FeatureRequestBase",
    "FeatureRequestCategory",
    "FeatureRequestModerationState",
    "FeatureRequestPublicStatus",
    "FeatureRequestVote",
    "Household",
    "HouseholdBase",
    "HouseholdInvite",
    "HouseholdInviteStatus",
    "HouseholdMember",
    "HouseholdMemberRole",
    "HouseholdMemberStatus",
    "ItemTranslation",
    "Label",
    "LabelBase",
    "Merchant",
    "MerchantAlias",
    "MerchantAliasBase",
    "MerchantBase",
    "Profile",
    "ProfileBase",
    "Receipt",
    "ReceiptBase",
    "ReceiptExtraction",
    "ReceiptStatus",
    "Subscription",
    "SubscriptionProvider",
    "SubscriptionStatus",
    "TimestampedModel",
    "Transaction",
    "TransactionBase",
    "TransactionItem",
    "TransactionLabel",
    "TransactionSource",
    "User",
    "UserBase",
    "UserCategoryOverride",
    "UserItemCategoryOverride",
]

# Suggested DB indexes and unique constraints:
# - Seed a category row with scope ITEM and code UNCATEGORIZED for fallback item assignment.
# - Consider a partial unique index on merchant_aliases for normalized_alias when user_id IS NULL.
# - Consider an index on transactions(status, occurred_at) for status-filtered reporting queries.
