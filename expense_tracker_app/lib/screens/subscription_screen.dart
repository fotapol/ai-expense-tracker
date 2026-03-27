import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/api_client.dart';
import '../core/redesign_system.dart';
import '../core/revenuecat_service.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.currentUserId});

  final String? currentUserId;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

enum _BillingPeriod { monthly, yearly }

class _HouseholdPurchaseContext {
  const _HouseholdPurchaseContext({
    required this.hasHousehold,
    required this.isOwner,
  });

  final bool hasHousehold;
  final bool isOwner;
}

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
  Set<String> _activeFeatures = <String>{};
  List<Package> _availablePackages = const <Package>[];
  Package? _selectedPackage;
  _BillingPeriod _selectedPeriod = _BillingPeriod.monthly;
  int _receiptScanLimit = 10;
  int? _receiptScanRemaining;
  bool _receiptScanUnlimited = false;
  DateTime? _receiptScanResetAtUtc;

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

  bool get _hasFamilyPlan => _activeFeatures.contains('premium.family_plan');

  Map<String, dynamic>? get _subscription =>
      _subscriptionPayload?['subscription'] as Map<String, dynamic>?;

  bool get _selectedIsFamily =>
      _selectedPackage != null &&
      RevenueCatService.isFamilyPackage(_selectedPackage!);

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
      Map<String, dynamic> entitlementsPayload;
      if (RevenueCatService.isAvailable && !_showDevTools) {
        try {
          final syncPayload = await ApiClient.syncRevenueCatSubscription();
          subscriptionPayload = <String, dynamic>{
            'has_active_subscription': syncPayload['has_active_subscription'],
            'subscription': syncPayload['subscription'],
            'receipt_scan_usage': syncPayload['receipt_scan_usage'],
          };
          entitlementsPayload = <String, dynamic>{
            'feature_codes': syncPayload['feature_codes'] ?? const <dynamic>[],
          };
        } catch (_) {
          final fallback = await Future.wait<dynamic>([
            ApiClient.getMeSubscription(),
            ApiClient.getMeEntitlements(),
          ]);
          subscriptionPayload = fallback[0] as Map<String, dynamic>;
          entitlementsPayload = fallback[1] as Map<String, dynamic>;
        }
      } else {
        final fallback = await Future.wait<dynamic>([
          ApiClient.getMeSubscription(),
          ApiClient.getMeEntitlements(),
        ]);
        subscriptionPayload = fallback[0] as Map<String, dynamic>;
        entitlementsPayload = fallback[1] as Map<String, dynamic>;
      }

      Offerings? offerings;
      try {
        offerings = await RevenueCatService.getOfferings();
      } catch (_) {}

      final featureCodes =
          (entitlementsPayload['feature_codes'] as List<dynamic>? ??
                  const <dynamic>[])
              .map((value) => value.toString())
              .toSet();
      final usageRaw = subscriptionPayload['receipt_scan_usage'];
      final usage = usageRaw is Map<String, dynamic>
          ? usageRaw
          : const <String, dynamic>{};
      final packages = RevenueCatService.flattenAvailablePackages(offerings);

      if (!mounted) return;
      setState(() {
        _subscriptionPayload = subscriptionPayload;
        _activeFeatures = featureCodes;
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
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _syncSelectedPackage(List<Package> packages) {
    _availablePackages = List<Package>.from(packages);
    final previousIdentifier = _selectedPackage?.identifier;
    Package? selected;
    if (previousIdentifier != null) {
      for (final package in packages) {
        if (package.identifier == previousIdentifier) {
          selected = package;
          break;
        }
      }
    }
    selected ??=
        _packageFor(false, _selectedPeriod, packages: packages) ??
        _packageFor(true, _selectedPeriod, packages: packages) ??
        _packageFor(false, _BillingPeriod.monthly, packages: packages) ??
        _packageFor(true, _BillingPeriod.monthly, packages: packages) ??
        _packageFor(false, _BillingPeriod.yearly, packages: packages) ??
        _packageFor(true, _BillingPeriod.yearly, packages: packages);
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
    final preferFamily = _selectedIsFamily;
    setState(() {
      _selectedPeriod = period;
      _selectedPackage =
          _packageFor(preferFamily, period) ??
          _packageFor(!preferFamily, period);
    });
  }

  Future<_HouseholdPurchaseContext> _loadHouseholdPurchaseContext() async {
    try {
      final household = await ApiClient.getCurrentHousehold();
      final members = await ApiClient.listCurrentHouseholdMembers();
      final targetUserId = (_targetUserId ?? '').trim();
      final currentMembership = members
          .whereType<Map<String, dynamic>>()
          .firstWhere(
            (member) => member['user_id']?.toString() == targetUserId,
            orElse: () => const <String, dynamic>{},
          );
      return _HouseholdPurchaseContext(
        hasHousehold: household.isNotEmpty,
        isOwner: currentMembership['role']?.toString() == 'owner',
      );
    } catch (error) {
      if (RegExp(r'\b404\b').hasMatch(error.toString())) {
        return const _HouseholdPurchaseContext(
          hasHousehold: false,
          isOwner: false,
        );
      }
      rethrow;
    }
  }

  Future<bool> _prepareIndividualPurchaseContext() async {
    final householdContext = await _loadHouseholdPurchaseContext();
    if (!householdContext.hasHousehold) return true;
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('billing_household_purchase_block_title')),
        content: Text(
          context.tr(
            householdContext.isOwner
                ? 'billing_household_purchase_block_owner'
                : 'billing_household_purchase_block_member',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              context.tr(
                householdContext.isOwner
                    ? 'household_delete_action'
                    : 'household_leave_action',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    if (householdContext.isOwner) {
      await ApiClient.deleteCurrentHousehold();
    } else {
      await ApiClient.leaveCurrentHousehold();
    }
    return true;
  }

  bool _syncConfirmsExpectedPurchase(
    Map<String, dynamic> syncPayload,
    Package package,
  ) {
    final featureCodes =
        (syncPayload['feature_codes'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toSet();
    if (RevenueCatService.isFamilyPackage(package)) {
      return featureCodes.contains('premium.family_plan');
    }
    return syncPayload['has_active_subscription'] == true;
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
        return rawMessage;
      }
    }
    return error.toString();
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
          content: Text('RevenueCat is not configured in this build.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isPurchaseLoading = true);
    try {
      if (!RevenueCatService.isFamilyPackage(package)) {
        final canProceed = await _prepareIndividualPurchaseContext();
        if (!canProceed) return;
      }
      await RevenueCatService.purchasePackage(package);
      var syncPayload = await ApiClient.syncRevenueCatSubscription();
      int retries = 0;
      while (!_syncConfirmsExpectedPurchase(syncPayload, package) &&
          retries < 3) {
        await Future<void>.delayed(const Duration(seconds: 2));
        syncPayload = await ApiClient.syncRevenueCatSubscription();
        retries++;
      }
      if (!_syncConfirmsExpectedPurchase(syncPayload, package)) {
        throw Exception(purchaseNotConfirmedMessage);
      }
      await _loadSubscriptionData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('billing_purchase_confirmed'))),
      );
    } catch (error) {
      Object effectiveError = error;
      if (_isOperationInProgressError(error)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          await RevenueCatService.purchasePackage(package);
          var syncPayload = await ApiClient.syncRevenueCatSubscription();
          int retries = 0;
          while (!_syncConfirmsExpectedPurchase(syncPayload, package) &&
              retries < 3) {
            await Future<void>.delayed(const Duration(seconds: 2));
            syncPayload = await ApiClient.syncRevenueCatSubscription();
            retries++;
          }
          if (!_syncConfirmsExpectedPurchase(syncPayload, package)) {
            throw Exception(purchaseNotConfirmedMessage);
          }
          await _loadSubscriptionData();
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
    setState(() => _isPurchaseLoading = true);
    try {
      await RevenueCatService.restorePurchases();
      await ApiClient.syncRevenueCatSubscription();
      await _loadSubscriptionData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('billing_restore_success'))),
      );
    } catch (error) {
      Object effectiveError = error;
      if (_isOperationInProgressError(error)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          await RevenueCatService.restorePurchases();
          await ApiClient.syncRevenueCatSubscription();
          await _loadSubscriptionData();
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
    if (_activeFeatures.contains('premium.family_plan')) return 'Family Plan';
    if (_hasActiveSubscription) return 'Pro Plan';
    return context.tr('billing_plan_free');
  }

  String _currentPlanSubtitle(BuildContext context) {
    if (!_hasActiveSubscription) {
      return context.tr(
        'billing_free_plan_subtitle',
        params: {'limit': '$_receiptScanLimit'},
      );
    }
    return context.tr(
      'billing_active_until_compact',
      params: {'date': _formatDate(_subscription?['expires_at']?.toString())},
    );
  }

  Widget _buildActivePlanHero(BuildContext context) {
    final usageValue = _receiptScanUnlimited
        ? 'Unlimited'
        : '${_receiptScanRemaining ?? 0} left';
    final renewalValue = _receiptScanResetAtUtc != null
        ? _formatDate(_receiptScanResetAtUtc!.toIso8601String())
        : _formatDate(_subscription?['expires_at']?.toString());

    Widget metric({required String label, required String value}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withAlpha(170),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181716), Color(0xFF36312D)],
        ),
        border: Border.all(color: ShellColors.gold.withAlpha(55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const CrownIcon(
                  color: ShellColors.gold,
                  size: 24,
                  strokeWidth: 1.8,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentPlanTitle(context),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentPlanSubtitle(context),
                      style: TextStyle(
                        color: Colors.white.withAlpha(210),
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
                  color: ShellColors.gold.withAlpha(20),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: ShellColors.gold.withAlpha(80)),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(
                    color: ShellColors.gold,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              metric(label: 'Receipt scans', value: usageValue),
              const SizedBox(width: 12),
              metric(label: 'Billing date', value: renewalValue),
            ],
          ),
          if (_receiptScanResetAtUtc != null) ...[
            const SizedBox(height: 12),
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
                color: Colors.white.withAlpha(170),
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentPlanCard(BuildContext context) {
    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShellStyles.sectionLabel(context, context.tr('billing_current_plan')),
          const SizedBox(height: 8),
          Text(
            _currentPlanTitle(context),
            style: TextStyle(
              color: ShellStyles.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentPlanSubtitle(context),
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _receiptScanUnlimited
                ? 'Unlimited receipt scans'
                : '${_receiptScanRemaining ?? 0} scans remaining this month',
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 11.5,
            ),
          ),
          if (_receiptScanResetAtUtc != null) ...[
            const SizedBox(height: 4),
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
                color: ShellStyles.textMuted(context),
                fontSize: 11.5,
              ),
            ),
          ],
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
        'plan': RevenueCatService.isFamilyPackage(package)
            ? 'Family'
            : 'Individual',
        'price': package.storeProduct.priceString,
        'unit': RevenueCatService.isYearlyPackage(package) ? '/yr' : '/mo',
      },
    );
  }

  bool _canPurchasePackage(Package? package) {
    if (package == null) return false;
    if (RevenueCatService.isFamilyPackage(package)) {
      return !_hasFamilyPlan;
    }
    return !_hasActiveSubscription;
  }

  List<String> _featuresForPackage(Package package) {
    if (RevenueCatService.isFamilyPackage(package)) {
      return const [
        'Everything in Individual',
        'Up to 5 family members',
        'Shared household budgets',
        'Family spending insights',
        'Household management',
        'Individual privacy controls',
      ];
    }
    return const [
      'Unlimited receipt scans',
      'AI-powered insights',
      'Advanced analytics',
      'Export reports',
      'Priority support',
    ];
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
    final isFamily = RevenueCatService.isFamilyPackage(package);
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
                    color: isFamily
                        ? ShellColors.gold
                        : ShellStyles.textPrimary(context),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isFamily ? 'Family' : 'Individual',
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isFamily)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ShellColors.gold.withAlpha(20),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      context.tr('billing_best_value'),
                      style: const TextStyle(
                        color: ShellColors.gold,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
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
            child: const Text('Activate PRO'),
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
                        backgroundColor: ShellStyles.textPrimary(context),
                        foregroundColor: ShellStyles.surface(context),
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
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _isPurchaseLoading ? null : _restorePurchases,
                    child: Text(context.tr('billing_restore_purchases')),
                  ),
                ),
                if (!_hasActiveSubscription) ...[
                  const SizedBox(height: 8),
                  _buildCurrentPlanCard(context),
                ],
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
    return SettingsDetailScaffold(
      title: context.tr('settings_subscription'),
      actions: [
        IconButton(
          onPressed: _isLoading || _isPurchaseLoading
              ? null
              : _loadSubscriptionData,
          icon: const Icon(AppIcons.refresh),
        ),
      ],
      body: _buildBody(),
    );
  }
}
