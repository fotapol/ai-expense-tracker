import 'package:shared_preferences/shared_preferences.dart';

const Set<String> _personalPremiumFeatureCodes = <String>{
  'premium.receipt_scans.unlimited',
  'premium.analytics.advanced',
  'premium.exports',
};
const String _optimisticPremiumStoredAtKey =
    'optimistic_premium_access_stored_at';
const String _optimisticPremiumExpiresAtKey =
    'optimistic_premium_access_expires_at';
const Duration _optimisticPremiumFallbackWindow = Duration(hours: 2);

class _OptimisticPremiumState {
  const _OptimisticPremiumState({required this.expiresAt});

  final String? expiresAt;
}

Set<String> _normalizeIdentifiers(Iterable<String> values) {
  return values
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
}

Future<void> persistOptimisticPremiumAccess({String? expirationDate}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _optimisticPremiumStoredAtKey,
    DateTime.now().toUtc().toIso8601String(),
  );

  final normalizedExpiration = expirationDate?.trim();
  if (normalizedExpiration == null || normalizedExpiration.isEmpty) {
    await prefs.remove(_optimisticPremiumExpiresAtKey);
    return;
  }

  await prefs.setString(_optimisticPremiumExpiresAtKey, normalizedExpiration);
}

Future<void> clearOptimisticPremiumAccess() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_optimisticPremiumStoredAtKey);
  await prefs.remove(_optimisticPremiumExpiresAtKey);
}

Future<_OptimisticPremiumState?> _readOptimisticPremiumState({
  DateTime Function()? nowProvider,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final now = (nowProvider ?? DateTime.now)().toUtc();
  final storedAtRaw = prefs.getString(_optimisticPremiumStoredAtKey)?.trim();
  if (storedAtRaw == null || storedAtRaw.isEmpty) {
    return null;
  }

  final storedAt = DateTime.tryParse(storedAtRaw)?.toUtc();
  if (storedAt == null ||
      now.difference(storedAt) > _optimisticPremiumFallbackWindow) {
    await clearOptimisticPremiumAccess();
    return null;
  }

  final expiresAtRaw = prefs.getString(_optimisticPremiumExpiresAtKey)?.trim();
  if (expiresAtRaw == null || expiresAtRaw.isEmpty) {
    return const _OptimisticPremiumState(expiresAt: null);
  }

  final expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
  if (expiresAt == null) {
    return _OptimisticPremiumState(expiresAt: expiresAtRaw);
  }
  if (!expiresAt.isAfter(now)) {
    await clearOptimisticPremiumAccess();
    return null;
  }
  return _OptimisticPremiumState(expiresAt: expiresAtRaw);
}

Future<bool> hasOptimisticPremiumAccess({
  DateTime Function()? nowProvider,
}) async {
  return (await _readOptimisticPremiumState(nowProvider: nowProvider)) != null;
}

Future<String?> readOptimisticPremiumAccessExpiration({
  DateTime Function()? nowProvider,
}) async {
  return (await _readOptimisticPremiumState(
    nowProvider: nowProvider,
  ))?.expiresAt;
}

Future<Set<String>> featureCodesWithOptimisticPremiumAccess(
  Iterable<String> featureCodes, {
  DateTime Function()? nowProvider,
}) async {
  final normalizedCodes = featureCodes
      .map((code) => code.trim().toLowerCase())
      .where((code) => code.isNotEmpty)
      .toSet();

  if (await hasOptimisticPremiumAccess(nowProvider: nowProvider)) {
    normalizedCodes.addAll(_personalPremiumFeatureCodes);
  }
  return normalizedCodes;
}

bool syncPayloadConfirmsPremiumAccess(
  Map<String, dynamic> syncPayload, {
  required bool expectsFamilyPlan,
}) {
  if (syncPayload['has_active_subscription'] == true) {
    return true;
  }

  final featureCodes =
      (syncPayload['feature_codes'] as List<dynamic>? ?? const <dynamic>[])
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
