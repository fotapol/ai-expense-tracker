"""Feature-code constants for premium entitlement checks.

Family plan readiness
---------------------
A future family subscription will:
1. Create a ``Subscription`` row for the purchasing user (as today).
2. Create an ``Entitlement`` row with ``scope_type=HOUSEHOLD``, ``scope_id=household.id``.
3. ``resolve_effective_entitlements`` will merge this into the feature-code set
   for every active member of that household.

Example creation of a household-scoped entitlement::

    from app.models.billing.entitlement import Entitlement
    from app.models.shared.enums import EntitlementScopeType, EntitlementStatus

    ent = Entitlement(
        scope_type=EntitlementScopeType.HOUSEHOLD,
        scope_id=household.id,
        feature_code=PREMIUM_FAMILY_PLAN,
        source_subscription_id=subscription.id,
        starts_at=subscription.started_at,
        expires_at=subscription.expires_at,
        status=EntitlementStatus.ACTIVE,
    )
    session.add(ent)
    session.commit()
"""

PREMIUM_RECEIPT_SCANS_UNLIMITED = "premium.receipt_scans.unlimited"
PREMIUM_ANALYTICS_ADVANCED = "premium.analytics.advanced"
PREMIUM_EXPORTS = "premium.exports"
PREMIUM_CATEGORIES_UNLIMITED = "premium.categories.unlimited"
PREMIUM_FAMILY_PLAN = "premium.family_plan"

PERSONAL_PREMIUM_PRODUCT_ID = "personal_premium"
FAMILY_PREMIUM_PRODUCT_ID = "family_premium"
FREE_PLAN_RECEIPT_SCAN_LIMIT = 10
FREE_PLAN_CUSTOM_CATEGORY_LIMIT = 3
FREE_PLAN_CUSTOM_SUBCATEGORY_LIMIT = 10

PERSONAL_PREMIUM_FEATURE_CODES = frozenset(
    {
        PREMIUM_RECEIPT_SCANS_UNLIMITED,
        PREMIUM_ANALYTICS_ADVANCED,
        PREMIUM_EXPORTS,
        PREMIUM_CATEGORIES_UNLIMITED,
    }
)

# Family plan grants everything in personal plus household sharing access.
FAMILY_PREMIUM_FEATURE_CODES = frozenset(PERSONAL_PREMIUM_FEATURE_CODES | {PREMIUM_FAMILY_PLAN})


def feature_codes_for_product(product_id: str) -> set[str]:
    """Resolve feature codes for a normalized subscription product id."""

    normalized_product_id = (product_id or "").strip().lower()
    if normalized_product_id == PERSONAL_PREMIUM_PRODUCT_ID:
        return set(PERSONAL_PREMIUM_FEATURE_CODES)
    if normalized_product_id == FAMILY_PREMIUM_PRODUCT_ID:
        return set(FAMILY_PREMIUM_FEATURE_CODES)
    return set()
