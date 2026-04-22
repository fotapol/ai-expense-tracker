import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/redesign_system.dart';
import '../core/revenuecat_service.dart';
import '../core/session_invalidation.dart';
import '../core/single_user_launch.dart';
import '../core/subscription_confirmation.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import 'settings_detail_scaffold.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.currentUserId});

  final String? currentUserId;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

enum _BillingPeriod { monthly, yearly }

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  static const bool _showDevTools = bool.fromEnvironment(
    'ENABLE_DEV_BILLING_TOOLS',
    defaultValue: false,
  );

  bool _isLoading = true;
  bool _isPurchaseLoading = false;
  bool _isDevActionLoading = false;
  String? _error;
  String? _targetUserId;
  Map<String, dynamic>? _subscriptionPayload;
  List<Package> _availablePackages = const <Package>[];
  Package? _selectedPackage;
  _BillingPeriod _selectedPeriod = _BillingPeriod.monthly;
  int _receiptScanLimit = 10;
  int? _receiptScanRemaining;
  bool _receiptScanUnlimited = false;
  DateTime? _receiptScanResetAtUtc;
  bool _didChangeBillingState = false;

  @override
  void initState() {
    super.initState();
    _targetUserId = widget.currentUserId?.trim().isNotEmpty == true
        ? widget.currentUserId!.trim()
        : null;
    _loadSubscriptionData();
  }

  bool get _hasActiveSubscription =>
      (_subscriptionPayload?['has_active_subscription'] as bool?) ?? false;

  Map<String, dynamic>? get _subscription =>
      _subscriptionPayload?['subscription'] as Map<String, dynamic>?;

  void _markBillingStateChanged() {
    _didChangeBillingState = true;
  }

  String? _premiumExpirationFromCustomerInfo(CustomerInfo customerInfo) {
    return resolvePremiumAccessExpiration(
      latestExpirationDate: customerInfo.latestExpirationDate,
      activeEntitlementExpirationDates: customerInfo.entitlements.active.values
          .map((entitlement) => entitlement.expirationDate),
    );
  }

  Map<String, dynamic> _buildOptimisticPremiumPayload({
    required Map<String, dynamic>? currentPayload,
    String? expiration,
  }) {
    final currentSubscription = currentPayload?['subscription'];
    final currentUsage = currentPayload?['receipt_scan_usage'];
    return <String, dynamic>{
      ...?currentPayload,
      'has_active_subscription': true,
      'subscription': <String, dynamic>{
        ...?(currentSubscription is Map<String, dynamic>
            ? currentSubscription
            : null),
        ...?(expiration == null
            ? null
            : <String, dynamic>{'expires_at': expiration}),
      },
      'receipt_scan_usage': <String, dynamic>{
        ...?(currentUsage is Map<String, dynamic> ? currentUsage : null),
        'limit': null,
        'remaining': null,
        'is_unlimited': true,
        ...?(expiration == null
            ? null
            : <String, dynamic>{'period_end_at': expiration}),
      },
    };
  }

  void _applyOptimisticUsageState(String? expiration) {
    _receiptScanUnlimited = true;
    _receiptScanRemaining = null;
    if (expiration != null) {
      _receiptScanResetAtUtc = DateTime.tryParse(expiration)?.toUtc();
    }
  }

  Future<void> _persistOptimisticPremiumAccess(CustomerInfo customerInfo) {
    return persistOptimisticPremiumAccess(
      expirationDate: _premiumExpirationFromCustomerInfo(customerInfo),
    );
  }

  Future<void> _loadSubscriptionData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_targetUserId == null || _targetUserId!.isEmpty) {
        final me = await ApiClient.getMe();
        _targetUserId = (me['id'] ?? '').toString();
      }

      Map<String, dynamic> subscriptionPayload;
      if (RevenueCatService.isAvailable && !_showDevTools) {
        try {
          final syncPayload = await ApiClient.syncRevenueCatSubscription();
          subscriptionPayload = <String, dynamic>{
            'has_active_subscription': syncPayload['has_active_subscription'],
            'subscription': syncPayload['subscription'],
            'receipt_scan_usage': syncPayload['receipt_scan_usage'],
          };
        } catch (_) {
          subscriptionPayload = await ApiClient.getMeSubscription();
        }
      } else {
        subscriptionPayload = await ApiClient.getMeSubscription();
      }

      Offerings? offerings;
      try {
        offerings = await RevenueCatService.getOfferings();
      } catch (_) {}

      final optimisticPremium = await hasOptimisticPremiumAccess();
      final optimisticExpiration =
          await readOptimisticPremiumAccessExpiration();
      if (optimisticPremium &&
          subscriptionPayload['has_active_subscription'] != true) {
        subscriptionPayload = _buildOptimisticPremiumPayload(
          currentPayload: subscriptionPayload,
          expiration: optimisticExpiration,
        );
      }

      final usageRaw = subscriptionPayload['receipt_scan_usage'];
      final usage = usageRaw is Map<String, dynamic>
          ? usageRaw
          : const <String, dynamic>{};
      final packages = RevenueCatService.flattenAvailablePackages(offerings);

      if (!mounted) return;
      setState(() {
        _subscriptionPayload = subscriptionPayload;
        final parsedLimit =
            int.tryParse((usage['limit'] ?? 10).toString()) ?? 10;
        _receiptScanLimit = parsedLimit > 0 ? parsedLimit : 10;
        _receiptScanRemaining = int.tryParse(
          (usage['remaining'] ?? 0).toString(),
        );
        _receiptScanUnlimited = usage['is_unlimited'] == true;
        final periodEndRaw = usage['period_end_at']?.toString();
        _receiptScanResetAtUtc = periodEndRaw == null
            ? null
            : DateTime.tryParse(periodEndRaw)?.toUtc();
        _syncSelectedPackage(packages);
        _isLoading = false;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback:
              'We could not load your subscription details right now. Please try again.',
        );
        _isLoading = false;
      });
    }
  }

  void _syncSelectedPackage(List<Package> packages) {
    final launchPackages = filterSingleUserLaunchPackages(
      packages,
      isFamilyPackage: RevenueCatService.isFamilyPackage,
    );
    _availablePackages = List<Package>.from(launchPackages);
    final previousIdentifier = _selectedPackage?.identifier;
    Package? selected;
    if (previousIdentifier != null) {
      for (final package in _availablePackages) {
        if (package.identifier == previousIdentifier) {
          selected = package;
          break;
        }
      }
    }
    selected ??=
        _packageFor(false, _selectedPeriod, packages: _availablePackages) ??
        _packageFor(
          false,
          _BillingPeriod.monthly,
          packages: _availablePackages,
        ) ??
        _packageFor(false, _BillingPeriod.yearly, packages: _availablePackages);
    _selectedPackage = selected;
    if (selected != null) {
      _selectedPeriod = RevenueCatService.isYearlyPackage(selected)
          ? _BillingPeriod.yearly
          : _BillingPeriod.monthly;
    }
  }

  Package? _packageFor(
    bool family,
    _BillingPeriod period, {
    List<Package>? packages,
  }) {
    final source = packages ?? _availablePackages;
    for (final package in source) {
      final matchesFamily =
          RevenueCatService.isFamilyPackage(package) == family;
      final matchesPeriod = period == _BillingPeriod.yearly
          ? RevenueCatService.isYearlyPackage(package)
          : RevenueCatService.isMonthlyPackage(package);
      if (matchesFamily && matchesPeriod) return package;
    }
    return null;
  }

  void _selectPeriod(_BillingPeriod period) {
    setState(() {
      _selectedPeriod = period;
      _selectedPackage = _packageFor(false, period);
    });
  }

  bool _customerInfoConfirmsExpectedPurchase(
    CustomerInfo customerInfo,
    Package package,
  ) {
    return customerInfoConfirmsPremiumAccess(
      hasPremiumEntitlement: RevenueCatService.hasPremiumEntitlement(
        customerInfo,
      ),
      activeSubscriptions: customerInfo.activeSubscriptions,
      acceptedProductIds: <String>[
        package.storeProduct.identifier,
        package.identifier,
      ],
    );
  }

  bool _customerInfoConfirmsKnownPremiumAccess(CustomerInfo customerInfo) {
    final acceptedProductIds = <String>{
      for (final package in _availablePackages) package.storeProduct.identifier,
      for (final package in _availablePackages) package.identifier,
    };
    return customerInfoConfirmsPremiumAccess(
      hasPremiumEntitlement: RevenueCatService.hasPremiumEntitlement(
        customerInfo,
      ),
      activeSubscriptions: customerInfo.activeSubscriptions,
      acceptedProductIds: acceptedProductIds,
    );
  }

  void _applyOptimisticPremiumState(CustomerInfo customerInfo) {
    final expiration = _premiumExpirationFromCustomerInfo(customerInfo);
    _subscriptionPayload = _buildOptimisticPremiumPayload(
      currentPayload: _subscriptionPayload,
      expiration: expiration,
    );
    _applyOptimisticUsageState(expiration);
  }

  Future<bool> _confirmPurchaseWithBackend({
    required bool expectsFamilyPlan,
  }) async {
    Map<String, dynamic>? lastPayload;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        lastPayload = await ApiClient.syncRevenueCatSubscription();
      } catch (_) {
        lastPayload = null;
      }
      if (lastPayload != null &&
          syncPayloadConfirmsPremiumAccess(
            lastPayload,
            expectsFamilyPlan: expectsFamilyPlan,
          )) {
        return true;
      }
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return false;
  }

  String _friendlyBillingError(Object error) {
    if (error is PlatformException) {
      final details = error.details;
      String? readableCode;
      String? detailMessage;
      if (details is Map) {
        readableCode =
            details['readable_error_code']?.toString() ??
            details['readableErrorCode']?.toString();
        detailMessage =
            details['message']?.toString() ??
            details['underlyingErrorMessage']?.toString();
      }
      final normalizedCode = (readableCode ?? error.code).toLowerCase();
      if (normalizedCode.contains('operationalreadyinprogresserror') ||
          error.code == '15') {
        return 'Another billing operation is still in progress. Please wait a few seconds and try again.';
      }
      if (normalizedCode.contains('purchasecancellederror')) {
        return 'Purchase canceled.';
      }
      if (normalizedCode.contains('networkerror')) {
        return 'Network error while contacting the store. Please try again.';
      }
      final rawMessage = detailMessage ?? error.message;
      if (rawMessage != null && rawMessage.trim().isNotEmpty) {
        return friendlyLaunchErrorMessage(
          rawMessage,
          fallback:
              'We could not update premium access right now. Please try again.',
        );
      }
    }
    return friendlyLaunchErrorMessage(
      error,
      fallback:
          'We could not update premium access right now. Please try again.',
    );
  }

  bool _isOperationInProgressError(Object error) {
    if (error is! PlatformException) return false;
    final details = error.details;
    String? readableCode;
    if (details is Map) {
      readableCode =
          details['readable_error_code']?.toString() ??
          details['readableErrorCode']?.toString();
    }
    final normalizedCode = (readableCode ?? error.code).toLowerCase();
    return normalizedCode.contains('operationalreadyinprogresserror') ||
        error.code == '15';
  }

  Future<void> _purchasePro() async {
    if (_isPurchaseLoading || _selectedPackage == null) return;
    final package = _selectedPackage!;
    final purchaseNotConfirmedMessage = context.tr(
      'billing_purchase_not_confirmed',
    );
    if (!RevenueCatService.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(context.tr('revenuecat_is_not_configured_in_this_bui')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isPurchaseLoading = true);
    try {
      if (RevenueCatService.isFamilyPackage(package)) {
        throw Exception(
          'This subscription option is unavailable in this launch.',
        );
      }
      final purchaseResult = await RevenueCatService.purchasePackage(package);
      final sdkConfirmed = _customerInfoConfirmsExpectedPurchase(
        purchaseResult.customerInfo,
        package,
      );
      final backendConfirmed = await _confirmPurchaseWithBackend(
        expectsFamilyPlan: RevenueCatService.isFamilyPackage(package),
      );
      if (!sdkConfirmed && !backendConfirmed) {
        throw Exception(purchaseNotConfirmedMessage);
      }
      if (backendConfirmed) {
        await _loadSubscriptionData();
      } else if (mounted) {
        setState(() {
          _applyOptimisticPremiumState(purchaseResult.customerInfo);
        });
      }
      await _persistOptimisticPremiumAccess(purchaseResult.customerInfo);
      _markBillingStateChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('billing_purchase_confirmed'))),
      );
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      Object effectiveError = error;
      if (_isOperationInProgressError(error)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          final purchaseResult = await RevenueCatService.purchasePackage(
            package,
          );
          final sdkConfirmed = _customerInfoConfirmsExpectedPurchase(
            purchaseResult.customerInfo,
            package,
          );
          final backendConfirmed = await _confirmPurchaseWithBackend(
            expectsFamilyPlan: RevenueCatService.isFamilyPackage(package),
          );
          if (!sdkConfirmed && !backendConfirmed) {
            throw Exception(purchaseNotConfirmedMessage);
          }
          if (backendConfirmed) {
            await _loadSubscriptionData();
          } else if (mounted) {
            setState(() {
              _applyOptimisticPremiumState(purchaseResult.customerInfo);
            });
          }
          await _persistOptimisticPremiumAccess(purchaseResult.customerInfo);
          _markBillingStateChanged();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('billing_purchase_confirmed'))),
          );
          return;
        } catch (retryError) {
          effectiveError = retryError;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'billing_purchase_failed',
              params: {'message': _friendlyBillingError(effectiveError)},
            ),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPurchaseLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    if (_isPurchaseLoading || !RevenueCatService.isAvailable) return;
    final purchaseNotConfirmedMessage = context.tr(
      'billing_purchase_not_confirmed',
    );
    setState(() => _isPurchaseLoading = true);
    try {
      final customerInfo = await RevenueCatService.restorePurchases();
      final sdkConfirmed = _customerInfoConfirmsKnownPremiumAccess(
        customerInfo,
      );
      final backendConfirmed = await _confirmPurchaseWithBackend(
        expectsFamilyPlan: false,
      );
      if (!sdkConfirmed && !backendConfirmed) {
        throw Exception(purchaseNotConfirmedMessage);
      }
      if (backendConfirmed) {
        await _loadSubscriptionData();
      } else if (mounted) {
        setState(() {
          _applyOptimisticPremiumState(customerInfo);
        });
      }
      await _persistOptimisticPremiumAccess(customerInfo);
      _markBillingStateChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('billing_restore_success'))),
      );
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      Object effectiveError = error;
      if (_isOperationInProgressError(error)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          final customerInfo = await RevenueCatService.restorePurchases();
          final sdkConfirmed = _customerInfoConfirmsKnownPremiumAccess(
            customerInfo,
          );
          final backendConfirmed = await _confirmPurchaseWithBackend(
            expectsFamilyPlan: false,
          );
          if (!sdkConfirmed && !backendConfirmed) {
            throw Exception(purchaseNotConfirmedMessage);
          }
          if (backendConfirmed) {
            await _loadSubscriptionData();
          } else if (mounted) {
            setState(() {
              _applyOptimisticPremiumState(customerInfo);
            });
          }
          await _persistOptimisticPremiumAccess(customerInfo);
          _markBillingStateChanged();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('billing_restore_success'))),
          );
          return;
        } catch (retryError) {
          effectiveError = retryError;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'billing_restore_failed',
              params: {'message': _friendlyBillingError(effectiveError)},
            ),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPurchaseLoading = false);
    }
  }

  Future<void> _applyDevAction(String action) async {
    if (_isDevActionLoading) return;
    final userId = _targetUserId;
    if (userId == null || userId.isEmpty) return;
    setState(() => _isDevActionLoading = true);
    try {
      await ApiClient.applyDevManualSubscriptionAction(
        targetUserId: userId,
        action: action,
      );
      await _loadSubscriptionData();
      _markBillingStateChanged();
    } finally {
      if (mounted) setState(() => _isDevActionLoading = false);
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '--';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return raw;
    final mm = parsed.month.toString().padLeft(2, '0');
    final dd = parsed.day.toString().padLeft(2, '0');
    return '$mm/$dd/${parsed.year}';
  }

  String _currentPlanTitle(BuildContext context) {
    if (_hasActiveSubscription) return 'Premium';
    return context.tr('billing_plan_free');
  }

  String _currentPlanSubtitle(BuildContext context) {
    if (!_hasActiveSubscription) {
      return 'You are currently on the Free plan for this account.';
    }
    return 'Premium is active for this account.';
  }

  List<String> _currentAccessLines() {
    if (_hasActiveSubscription) {
      return const [
        'Unlimited receipt scans',
        'Advanced analytics breakdowns',
        'Full data export history',
      ];
    }
    return <String>[
      '$_receiptScanLimit receipt scans in each rolling 30-day window',
      'Core tools stay available: labels, categories, budgets, and bill reminders',
      'Data export includes your last 30 days on the Free plan',
    ];
  }

  String _currentPlanFootnote() {
    if (_hasActiveSubscription) {
      if (_receiptScanResetAtUtc != null) {
        return context.tr(
          'billing_resets_on',
          params: {
            'date': _formatDate(_receiptScanResetAtUtc!.toIso8601String()),
          },
        );
      }
      return 'Restore Purchases is available if Premium does not sync after reinstalling or changing devices.';
    }
    return 'Upgrade only if you need more scans, deeper analytics, or the full export range.';
  }

  Widget _buildAccessLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              AppIcons.checkCircle,
              color: ShellColors.softGreen,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePlanHero(BuildContext context) {
    final uiScale = themeProvider.fontSizeFactor.clamp(0.75, 1.15).toDouble();
    final usageValue = _receiptScanUnlimited
        ? 'Unlimited'
        : '${_receiptScanRemaining ?? 0} left';
    final renewalValue = _receiptScanResetAtUtc != null
        ? _formatDate(_receiptScanResetAtUtc!.toIso8601String())
        : _formatDate(_subscription?['expires_at']?.toString());

    Widget metric({required String label, required String value}) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.all(14 * uiScale),
          decoration: BoxDecoration(
            color: ShellStyles.heroBadgeSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ShellStyles.heroBadgeBorder(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: ShellStyles.heroTextSecondary(context),
                  fontSize: 10.5 * uiScale,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(height: 6 * uiScale),
              Text(
                value,
                style: TextStyle(
                  color: ShellStyles.heroTextPrimary(context),
                  fontSize: 16 * uiScale,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(20 * uiScale),
      decoration: ShellStyles.heroCardDecoration(
        context,
        radius: 24,
        highlight: ShellStyles.warningPremium(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46 * uiScale,
                height: 46 * uiScale,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ShellStyles.heroBadgeSurface(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: ShellStyles.heroBadgeBorder(context),
                  ),
                ),
                child: CrownIcon(
                  color: ShellStyles.warningPremium(context),
                  size: 24 * uiScale,
                  strokeWidth: 1.8,
                ),
              ),
              SizedBox(width: 14 * uiScale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentPlanTitle(context),
                      style: TextStyle(
                        color: ShellStyles.heroTextPrimary(context),
                        fontSize: 20 * uiScale,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4 * uiScale),
                    Text(
                      _currentPlanSubtitle(context),
                      style: TextStyle(
                        color: ShellStyles.heroTextSecondary(context),
                        fontSize: 12.5 * uiScale,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * uiScale,
                  vertical: 6 * uiScale,
                ),
                decoration: BoxDecoration(
                  color: ShellStyles.warningPremium(context).withAlpha(18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ShellStyles.warningPremium(context).withAlpha(90),
                  ),
                ),
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: ShellStyles.warningPremium(context),
                    fontSize: 10.5 * uiScale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 18 * uiScale),
          Row(
            children: [
              metric(label: context.tr('receipt_scans'), value: usageValue),
              SizedBox(width: 12 * uiScale),
              metric(label: context.tr('billing_date'), value: renewalValue),
            ],
          ),
          SizedBox(height: 16 * uiScale),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16 * uiScale),
            decoration: BoxDecoration(
              color: ShellStyles.heroBadgeSurface(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ShellStyles.heroBadgeBorder(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Included with Premium',
                  style: TextStyle(
                    color: ShellStyles.heroTextSecondary(context),
                    fontSize: 11.5 * uiScale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
                SizedBox(height: 10 * uiScale),
                ..._currentAccessLines().map((text) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 8 * uiScale),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 2 * uiScale),
                          child: Icon(
                            AppIcons.checkCircle,
                            color: ShellStyles.success(context),
                            size: 16 * uiScale,
                          ),
                        ),
                        SizedBox(width: 8 * uiScale),
                        Expanded(
                          child: Text(
                            text,
                            style: TextStyle(
                              color: ShellStyles.heroTextPrimary(context),
                              fontSize: 13 * uiScale,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          if (_receiptScanResetAtUtc != null) ...[
            SizedBox(height: 12 * uiScale),
            Text(
              context.tr(
                'billing_resets_on',
                params: {
                  'date': _formatDate(
                    _receiptScanResetAtUtc!.toIso8601String(),
                  ),
                },
              ),
              style: TextStyle(
                color: ShellStyles.heroTextSecondary(context),
                fontSize: 11.5 * uiScale,
              ),
            ),
          ],
          SizedBox(height: 8 * uiScale),
          Text(
            'Restore Purchases is only needed if Premium does not sync on this device right away.',
            style: TextStyle(
              color: ShellStyles.heroTextSecondary(context),
              fontSize: 11.5 * uiScale,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPlanCard(BuildContext context) {
    return SettingsDetailCard(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('billing_current_plan'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _currentPlanTitle(context),
                      style: TextStyle(
                        color: ShellStyles.textPrimary(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentPlanSubtitle(context),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: _hasActiveSubscription
                      ? ShellColors.gold.withAlpha(18)
                      : ShellStyles.surfaceAlt(context),
                  border: Border.all(
                    color: _hasActiveSubscription
                        ? ShellColors.gold.withAlpha(80)
                        : ShellStyles.border(context),
                  ),
                ),
                child: Text(
                  _hasActiveSubscription ? 'ACTIVE' : 'FREE',
                  style: TextStyle(
                    color: _hasActiveSubscription
                        ? ShellColors.gold
                        : ShellStyles.textPrimary(context),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ShellStyles.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _receiptScanUnlimited
                      ? 'Receipt scans: unlimited'
                      : 'Receipt scans remaining: ${_receiptScanRemaining ?? 0}',
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasActiveSubscription
                      ? 'Premium limits are already applied to this account.'
                      : 'Free plan limits stay active until you upgrade.',
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._currentAccessLines().map(_buildAccessLine),
          const SizedBox(height: 6),
          Text(
            _currentPlanFootnote(),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _freeVsPremiumNote() {
    if (_hasActiveSubscription) {
      return 'Premium stays managed by your app store for this account.';
    }
    return 'Everything else in the app stays available on Free. Premium only expands limits where it is already wired.';
  }

  String _restorePurchasesHint() {
    if (_hasActiveSubscription) {
      return 'Already active? Restore Purchases is only needed if this device does not pick Premium up right away.';
    }
    return 'Already subscribed on this account? Restore Purchases will sync Premium on this device.';
  }

  Widget _buildRestorePurchasesCard() {
    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Restore Purchases',
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _restorePurchasesHint(),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _isPurchaseLoading ? null : _restorePurchases,
              child: Text(context.tr('billing_restore_purchases')),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _featuresForPackage(Package _) {
    return const [
      'Unlimited receipt scans',
      'Advanced analytics breakdowns',
      'Full data export history',
    ];
  }

  Widget _buildBillingTrustNote() {
    return SettingsDetailCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, color: ShellStyles.textMuted(context), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _freeVsPremiumNote(),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _purchaseCtaLabel() {
    final package = _selectedPackage;
    if (package == null) return context.tr('billing_subscribe_unavailable');
    return context.tr(
      'billing_subscribe_to_plan',
      params: {
        'plan': 'Premium',
        'price': package.storeProduct.priceString,
        'unit': RevenueCatService.isYearlyPackage(package) ? '/yr' : '/mo',
      },
    );
  }

  bool _canPurchasePackage(Package? package) {
    return package != null && !_hasActiveSubscription;
  }

  Widget _buildPeriodSelector() {
    Widget chip(_BillingPeriod period) {
      final selected = _selectedPeriod == period;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectPeriod(period),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? ShellStyles.surface(context)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            child: Text(
              period == _BillingPeriod.monthly
                  ? context.tr('billing_period_monthly')
                  : context.tr('billing_period_yearly'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('billing_period_title'),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ShellStyles.surfaceAlt(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ShellStyles.border(context)),
            ),
            child: Row(
              children: [
                chip(_BillingPeriod.monthly),
                const SizedBox(width: 6),
                chip(_BillingPeriod.yearly),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Package package) {
    final selected = _selectedPackage?.identifier == package.identifier;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _selectedPackage = package;
          _selectedPeriod = RevenueCatService.isYearlyPackage(package)
              ? _BillingPeriod.yearly
              : _BillingPeriod.monthly;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ShellStyles.surface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? ShellStyles.textPrimary(context)
                : ShellStyles.border(context),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: ShellStyles.iconBadgeDecoration(
                    context,
                    radius: 12,
                  ),
                  child: CrownIcon(
                    color: ShellStyles.textPrimary(context),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Premium',
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  package.storeProduct.priceString,
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    RevenueCatService.isYearlyPackage(package)
                        ? '/year'
                        : '/month',
                    style: TextStyle(
                      color: ShellStyles.textMuted(context),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._featuresForPackage(package).map((feature) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        AppIcons.checkCircle,
                        color: Color(0xFF79D9A1),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feature,
                        style: TextStyle(
                          color: ShellStyles.textPrimary(context),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDevToolsCard() {
    return SettingsDetailCard(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _isDevActionLoading
                ? null
                : () => _applyDevAction('activate'),
            child: const Text(context.tr('activate_pro')),
          ),
          FilledButton(
            onPressed: _isDevActionLoading
                ? null
                : () => _applyDevAction('expire'),
            child: const Text('Expire'),
          ),
          FilledButton(
            onPressed: _isDevActionLoading
                ? null
                : () => _applyDevAction('revoke'),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadSubscriptionData,
                child: Text(context.tr('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    final individualPackage = _packageFor(false, _selectedPeriod);
    // TODO(household): restore familyPackage lookup when household feature ships
    // final familyPackage = _packageFor(true, _selectedPeriod);
    Package? familyPackage;
    final showIndividualOffer = _canPurchasePackage(individualPackage);
    final showFamilyOffer = _canPurchasePackage(familyPackage);
    final showPlanOffers = showIndividualOffer || showFamilyOffer;

    return SafeArea(
      top: false,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hasActiveSubscription) ...[
                  _buildActivePlanHero(context),
                  const SizedBox(height: 16),
                ] else ...[
                  _buildCurrentPlanCard(context),
                  const SizedBox(height: 16),
                ],
                if (showPlanOffers) ...[
                  _buildPeriodSelector(),
                  const SizedBox(height: 16),
                ],
                if (showIndividualOffer && individualPackage != null)
                  _buildPlanCard(individualPackage),
                if (showIndividualOffer && showFamilyOffer)
                  const SizedBox(height: 14),
                if (showFamilyOffer) _buildPlanCard(familyPackage!),
                if (!showPlanOffers && !_hasActiveSubscription)
                  SettingsDetailCard(
                    child: Text(context.tr('billing_subscribe_unavailable')),
                  ),
                if (showPlanOffers) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          !_canPurchasePackage(_selectedPackage) ||
                              _isPurchaseLoading
                          ? null
                          : _purchasePro,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isPurchaseLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_purchaseCtaLabel()),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _buildBillingTrustNote(),
                const SizedBox(height: 8),
                _buildRestorePurchasesCard(),
                if (_showDevTools) ...[
                  const SizedBox(height: 16),
                  _buildDevToolsCard(),
                ],
              ],
            ),
          ),
          if (_isPurchaseLoading)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailTextScale = themeProvider.fontSizeFactor < 0.9
        ? 0.9
        : themeProvider.fontSizeFactor;
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_didChangeBillingState);
      },
      child: SettingsDetailScaffold(
        title: context.tr('settings_subscription'),
        actions: [
          IconButton(
            onPressed: _isLoading || _isPurchaseLoading
                ? null
                : _loadSubscriptionData,
            icon: const Icon(AppIcons.refresh),
          ),
        ],
        body: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(detailTextScale)),
          child: _buildBody(),
        ),
      ),
    );
  }
}
