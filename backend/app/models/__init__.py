"""ORM model package exports for metadata registration and app imports."""

from app.models.category import Category, CategoryBase
from app.models.enums import CategoryScope, ReceiptStatus, TransactionSource
from app.models.merchant import Merchant, MerchantAlias, MerchantAliasBase, MerchantBase
from app.models.profile import Profile, ProfileBase
from app.models.receipt import Receipt, ReceiptBase
from app.models.receipt_extraction import ReceiptExtraction
from app.models.timestamps import TimestampedModel
from app.models.transaction import Transaction, TransactionBase
from app.models.transaction_item import TransactionItem
from app.models.user import User, UserBase
from app.models.user_category import UserCategoryOverride, UserItemCategoryOverride

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
]

# Suggested DB indexes and unique constraints:
# - Seed a category row with scope ITEM and code UNCATEGORIZED for fallback item assignment.
# - Consider a partial unique index on merchant_aliases for normalized_alias when user_id IS NULL.
# - Consider an index on transactions(status, occurred_at) for status-filtered reporting queries.
