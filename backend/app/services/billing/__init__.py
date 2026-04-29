"""Billing service exports."""

from app.services.billing.category_usage import (
    CategoryUsage,
    count_user_active_custom_categories,
    resolve_category_usage,
)
from app.services.billing.contracts import (
    BillingEventHandler,
    BillingProvider,
    NormalizedSubscriptionEvent,
)
from app.services.billing.entitlements import (
    EntitlementDecision,
    decide_entitlement_state,
    resolve_effective_entitlements,
    resolve_user_entitlements,
    sync_subscription_entitlements,
    user_has_feature,
)
from app.services.billing.features import (
    FAMILY_PREMIUM_PRODUCT_ID,
    FREE_PLAN_CUSTOM_CATEGORY_LIMIT,
    FREE_PLAN_CUSTOM_SUBCATEGORY_LIMIT,
    FREE_PLAN_RECEIPT_SCAN_LIMIT,
    PERSONAL_PREMIUM_FEATURE_CODES,
    PERSONAL_PREMIUM_PRODUCT_ID,
    PREMIUM_ANALYTICS_ADVANCED,
    PREMIUM_CATEGORIES_UNLIMITED,
    PREMIUM_EXPORTS,
    PREMIUM_FAMILY_PLAN,
    PREMIUM_RECEIPT_SCANS_UNLIMITED,
    feature_codes_for_product,
)
from app.services.billing.revenuecat import (
    RevenueCatClient,
    RevenueCatProvider,
    sync_revenuecat_subscription,
    sync_revenuecat_subscription_for_user,
)
from app.services.billing.subscriptions import (
    SubscriptionSyncService,
    build_manual_subscription_event,
    resolve_effective_subscription,
    select_effective_subscription,
    subscription_grants_premium_access,
    subscription_priority_tier,
)
from app.services.billing.usage import (
    ReceiptScanUsage,
    count_user_processed_receipts_in_window,
    receipt_scan_limit_reached,
    resolve_receipt_scan_usage,
    rolling_30_day_window,
)
from app.services.billing.webhooks import process_revenuecat_webhook

__all__ = [
    "FAMILY_PREMIUM_PRODUCT_ID",
    "FREE_PLAN_CUSTOM_CATEGORY_LIMIT",
    "FREE_PLAN_CUSTOM_SUBCATEGORY_LIMIT",
    "FREE_PLAN_RECEIPT_SCAN_LIMIT",
    "PERSONAL_PREMIUM_FEATURE_CODES",
    "PERSONAL_PREMIUM_PRODUCT_ID",
    "PREMIUM_ANALYTICS_ADVANCED",
    "PREMIUM_CATEGORIES_UNLIMITED",
    "PREMIUM_EXPORTS",
    "PREMIUM_FAMILY_PLAN",
    "PREMIUM_RECEIPT_SCANS_UNLIMITED",
    "BillingEventHandler",
    "BillingProvider",
    "CategoryUsage",
    "EntitlementDecision",
    "NormalizedSubscriptionEvent",
    "ReceiptScanUsage",
    "RevenueCatClient",
    "RevenueCatProvider",
    "SubscriptionSyncService",
    "build_manual_subscription_event",
    "count_user_active_custom_categories",
    "count_user_processed_receipts_in_window",
    "decide_entitlement_state",
    "feature_codes_for_product",
    "process_revenuecat_webhook",
    "receipt_scan_limit_reached",
    "resolve_category_usage",
    "resolve_effective_entitlements",
    "resolve_effective_subscription",
    "resolve_receipt_scan_usage",
    "resolve_user_entitlements",
    "rolling_30_day_window",
    "select_effective_subscription",
    "subscription_grants_premium_access",
    "subscription_priority_tier",
    "sync_revenuecat_subscription",
    "sync_revenuecat_subscription_for_user",
    "sync_subscription_entitlements",
    "user_has_feature",
]
