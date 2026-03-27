const Set<String> _personalPremiumFeatureCodes = <String>{
  'premium.receipt_scans.unlimited',
  'premium.analytics.advanced',
  'premium.exports',
};

Set<String> _normalizeIdentifiers(Iterable<String> values) {
  return values
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
}

bool syncPayloadConfirmsPremiumAccess(
  Map<String, dynamic> syncPayload, {
  required bool expectsFamilyPlan,
}) {
  if (syncPayload['has_active_subscription'] == true) {
    return true;
  }

  final featureCodes = (syncPayload['feature_codes'] as List<dynamic>? ??
          const <dynamic>[])
      .map((value) => value.toString().trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();

  if (expectsFamilyPlan) {
    return featureCodes.contains('premium.family_plan');
  }

  return featureCodes.any(_personalPremiumFeatureCodes.contains);
}

bool customerInfoConfirmsPremiumAccess({
  required bool hasPremiumEntitlement,
  required Iterable<String> activeSubscriptions,
  required Iterable<String> acceptedProductIds,
}) {
  if (hasPremiumEntitlement) {
    return true;
  }

  final activeSubscriptionIds = _normalizeIdentifiers(activeSubscriptions);
  final expectedIds = _normalizeIdentifiers(acceptedProductIds);
  if (activeSubscriptionIds.isEmpty || expectedIds.isEmpty) {
    return false;
  }

  return activeSubscriptionIds.any(expectedIds.contains);
}

String? resolvePremiumAccessExpiration({
  required String? latestExpirationDate,
  required Iterable<String?> activeEntitlementExpirationDates,
}) {
  for (final expiration in activeEntitlementExpirationDates) {
    final trimmed = expiration?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  final latest = latestExpirationDate?.trim();
  if (latest == null || latest.isEmpty) {
    return null;
  }
  return latest;
}
