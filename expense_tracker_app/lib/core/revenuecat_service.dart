import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  static const String androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
    defaultValue: '',
  );
  static const String iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_API_KEY',
    defaultValue: '',
  );
  static const String premiumEntitlementId = String.fromEnvironment(
    'REVENUECAT_PREMIUM_ENTITLEMENT_ID',
    defaultValue: String.fromEnvironment(
      'REVENUECAT_PERSONAL_PREMIUM_ENTITLEMENT_ID',
      defaultValue: 'personal_premium',
    ),
  );
  static bool _isConfigured = false;
  static bool _operationInProgress = false;

  static String _normalizeId(String value) => value.trim().toLowerCase();

  static bool isYearlyPackage(Package package) {
    if (package.packageType == PackageType.annual) return true;
    final identifier = _normalizeId(
      '${package.identifier} ${package.storeProduct.identifier}',
    );
    return identifier.contains('year') || identifier.contains('annual');
  }

  static bool isMonthlyPackage(Package package) {
    if (package.packageType == PackageType.monthly) return true;
    final identifier = _normalizeId(
      '${package.identifier} ${package.storeProduct.identifier}',
    );
    return identifier.contains('month');
  }

  static List<Package> flattenAvailablePackages(Offerings? offerings) {
    if (offerings == null) return const <Package>[];

    final unique = <Package>[];
    final seen = <String>{};

    void addPackages(Iterable<Package> packages) {
      for (final package in packages) {
        final key = _normalizeId(
          '${package.identifier}::${package.storeProduct.identifier}',
        );
        if (seen.add(key)) {
          unique.add(package);
        }
      }
    }

    addPackages(offerings.current?.availablePackages ?? const <Package>[]);
    final allOfferings = offerings.all.values.toList()
      ..sort((a, b) => a.identifier.compareTo(b.identifier));
    for (final offering in allOfferings) {
      addPackages(offering.availablePackages);
    }
    return unique;
  }

  static bool get isAvailable {
    if (Platform.isAndroid) return androidApiKey.trim().isNotEmpty;
    if (Platform.isIOS) return iosApiKey.trim().isNotEmpty;
    return false;
  }

  static String _platformApiKey() {
    if (Platform.isAndroid) return androidApiKey.trim();
    if (Platform.isIOS) return iosApiKey.trim();
    return '';
  }

  static Future<void> _waitForIdle() async {
    while (_operationInProgress) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  static Future<T> _runExclusive<T>(Future<T> Function() action) async {
    await _waitForIdle();
    _operationInProgress = true;
    try {
      return await action();
    } finally {
      _operationInProgress = false;
    }
  }

  static Future<void> _configureForCurrentUserUnsafe() async {
    if (!isAvailable || _isConfigured) return;
    final apiKey = _platformApiKey();
    if (apiKey.isEmpty) return;

    final appUserId = FirebaseAuth.instance.currentUser?.uid;
    if (appUserId == null || appUserId.isEmpty) return;
    final config = PurchasesConfiguration(apiKey)..appUserID = appUserId;
    await Purchases.setLogLevel(LogLevel.warn);
    await Purchases.configure(config);
    _isConfigured = true;
  }

  static Future<void> configureForCurrentUser() async {
    await _runExclusive(_configureForCurrentUserUnsafe);
  }

  static Future<void> logInCurrentUser() async {
    await _runExclusive(() async {
      if (!isAvailable) return;
      await _configureForCurrentUserUnsafe();
      final appUserId = FirebaseAuth.instance.currentUser?.uid;
      if (appUserId == null || appUserId.isEmpty) return;
      try {
        await Purchases.logIn(appUserId);
      } catch (_) {}
    });
  }

  static Future<void> logOut() async {
    await _runExclusive(() async {
      if (!isAvailable || !_isConfigured) return;
      try {
        await Purchases.logOut();
      } catch (_) {}
      _isConfigured = false;
    });
  }

  static Future<Offerings?> getOfferings() async {
    return _runExclusive(() async {
      if (!isAvailable) return null;
      await _configureForCurrentUserUnsafe();
      return Purchases.getOfferings();
    });
  }

  static Future<PurchaseResult> purchasePackage(Package package) async {
    return _runExclusive(() async {
      await _configureForCurrentUserUnsafe();
      return Purchases.purchase(PurchaseParams.package(package));
    });
  }

  static Future<CustomerInfo> restorePurchases() async {
    return _runExclusive(() async {
      await _configureForCurrentUserUnsafe();
      return Purchases.restorePurchases();
    });
  }

  static bool hasPremiumEntitlement(CustomerInfo info) {
    final active = info.entitlements.active;
    final personalId = premiumEntitlementId.trim();
    if (personalId.isNotEmpty && active.containsKey(personalId)) {
      return true;
    }
    return false;
  }
}
