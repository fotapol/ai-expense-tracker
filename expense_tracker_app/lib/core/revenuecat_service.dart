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
    defaultValue: 'personal_premium',
  );

  static bool _isConfigured = false;
  static bool _operationInProgress = false;

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
    return active.containsKey(premiumEntitlementId);
  }
}
