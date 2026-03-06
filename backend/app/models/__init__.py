"""ORM model package exports for metadata registration and app imports."""

from app.models.merchants.merchant import Merchant, MerchantAlias, MerchantAliasBase, MerchantBase
from app.models.overrides.user_category import UserCategoryOverride, UserItemCategoryOverride
from app.models.receipts.receipt import Receipt, ReceiptBase
from app.models.receipts.receipt_extraction import ReceiptExtraction
from app.models.shared.enums import CategoryScope, ReceiptStatus, TransactionSource
from app.models.shared.timestamps import TimestampedModel
from app.models.taxonomy.category import Category, CategoryBase
from app.models.transactions.transaction import Transaction, TransactionBase
from app.models.transactions.transaction_item import TransactionItem
from app.models.users.profile import Profile, ProfileBase
from app.models.users.user import User, UserBase
from app.models.labels.label import Label, LabelBase
from app.models.labels.transaction_label import TransactionLabel
from app.models.fx.exchange_rate import ExchangeRate

__all__ = [
    "Category",
    "CategoryBase",
    "CategoryScope",
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
    "TimestampedModel",
    "Transaction",
    "TransactionBase",
    "TransactionItem",
    "TransactionSource",
    "User",
    "UserBase",
    "UserCategoryOverride",
    "UserItemCategoryOverride",
    "Label",
    "LabelBase",
    "TransactionLabel",
    "ExchangeRate",
]

# Suggested DB indexes and unique constraints:
# - Seed a category row with scope ITEM and code UNCATEGORIZED for fallback item assignment.
# - Consider a partial unique index on merchant_aliases for normalized_alias when user_id IS NULL.
# - Consider an index on transactions(status, occurred_at) for status-filtered reporting queries.
