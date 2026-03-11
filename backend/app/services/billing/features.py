"""Feature-code constants for premium entitlement checks."""

PREMIUM_RECEIPT_SCANS_UNLIMITED = "premium.receipt_scans.unlimited"
PREMIUM_ANALYTICS_ADVANCED = "premium.analytics.advanced"
PREMIUM_EXPORTS = "premium.exports"
PREMIUM_FAMILY_PLAN = "premium.family_plan"

PERSONAL_PREMIUM_PRODUCT_ID = "personal_premium"
FREE_PLAN_RECEIPT_SCAN_LIMIT = 10

PERSONAL_PREMIUM_FEATURE_CODES = frozenset(
    {
        PREMIUM_RECEIPT_SCANS_UNLIMITED,
        PREMIUM_ANALYTICS_ADVANCED,
        PREMIUM_EXPORTS,
    }
)


def feature_codes_for_product(product_id: str) -> set[str]:
    """Resolve feature codes for a normalized subscription product id."""

    normalized_product_id = (product_id or "").strip().lower()
    if normalized_product_id == PERSONAL_PREMIUM_PRODUCT_ID:
        return set(PERSONAL_PREMIUM_FEATURE_CODES)
    return set()
