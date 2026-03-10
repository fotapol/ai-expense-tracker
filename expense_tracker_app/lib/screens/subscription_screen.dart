import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:math' as math;

import '../core/api_client.dart';
import '../core/revenuecat_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.currentUserId});

  final String? currentUserId;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  static const bool _showDevTools = bool.fromEnvironment(
    'ENABLE_DEV_BILLING_TOOLS',
    defaultValue: false,
  );
  static const List<_FeatureCardData> _featureCards = [
    _FeatureCardData(
      code: 'premium.receipt_scans.unlimited',
      title: 'Receipt scans',
      description: 'Scan as many receipts as you want',
      freeValue: '3/10',
      proValue: 'INF',
      icon: Icons.receipt_long_rounded,
    ),
    _FeatureCardData(
      code: 'premium.analytics.advanced',
      title: 'Advanced analytics',
      description: 'Get deeper trends and category insights',
      freeValue: 'Basic',
      proValue: 'Advanced',
      icon: Icons.analytics_outlined,
    ),
    _FeatureCardData(
      code: 'premium.exports',
      title: 'Exports',
      description: 'Export your financial data on demand',
      freeValue: 'Limited',
      proValue: 'Full',
      icon: Icons.file_download_outlined,
    ),
  ];

  bool _isLoading = true;
  bool _isDevActionLoading = false;
  bool _isPurchaseLoading = false;
  String? _error;
  int _activePageIndex = 0;
  int _receiptScanUsed = 0;
  int _receiptScanLimit = 10;
  int? _receiptScanRemaining;
  bool _receiptScanUnlimited = false;
  DateTime? _receiptScanResetAtUtc;
  Package? _monthlyPackage;
  Package? _yearlyPackage;
  Package? _selectedPackage;
  String? _targetUserId;
  Map<String, dynamic>? _subscriptionPayload;
  Set<String> _activeFeatures = <String>{};

  @override
  void initState() {
    super.initState();
    _targetUserId = widget.currentUserId?.trim().isNotEmpty == true
        ? widget.currentUserId!.trim()
        : null;
    _loadSubscriptionData();
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
      Map<String, dynamic> entitlementsPayload;
      final shouldSyncRevenueCat = RevenueCatService.isAvailable && !_showDevTools;
      if (shouldSyncRevenueCat) {
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
          (entitlementsPayload['feature_codes'] as List<dynamic>? ?? [])
              .map((value) => value.toString())
              .toSet();
      final usageRaw = subscriptionPayload['receipt_scan_usage'];
      final usage = usageRaw is Map<String, dynamic>
          ? usageRaw
          : const <String, dynamic>{};
      final isUnlimited = usage['is_unlimited'] == true;
      final used = int.tryParse((usage['used'] ?? 0).toString()) ?? 0;
      final limit = int.tryParse((usage['limit'] ?? 10).toString()) ?? 10;
      final remaining = int.tryParse((usage['remaining'] ?? 0).toString());
      final periodEndRaw = usage['period_end_at']?.toString();
      final periodEndAt = periodEndRaw == null
          ? null
          : DateTime.tryParse(periodEndRaw)?.toUtc();

      if (!mounted) return;
      setState(() {
        _subscriptionPayload = subscriptionPayload;
        _activeFeatures = featureCodes;
        _receiptScanUsed = used;
        _receiptScanLimit = limit > 0 ? limit : 10;
        _receiptScanRemaining = remaining;
        _receiptScanUnlimited = isUnlimited;
        _receiptScanResetAtUtc = periodEndAt;
        final packages = offerings?.current?.availablePackages ?? const <Package>[];
        _applyPackageOptions(packages);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _applyDevAction(String action) async {
    if (_isDevActionLoading) return;
    final userId = _targetUserId;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing local user ID for dev action.')),
      );
      return;
    }

    setState(() => _isDevActionLoading = true);
    try {
      await ApiClient.applyDevManualSubscriptionAction(
        targetUserId: userId,
        action: action,
      );
      if (!mounted) return;
      await _loadSubscriptionData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dev action "$action" applied.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dev action failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDevActionLoading = false);
    }
  }

  bool get _hasActiveSubscription =>
      (_subscriptionPayload?['has_active_subscription'] as bool?) ?? false;

  Map<String, dynamic>? get _subscription =>
      _subscriptionPayload?['subscription'] as Map<String, dynamic>?;

  String _statusLabel() {
    final status = (_subscription?['status'] ?? 'inactive').toString();
    return status.replaceAll('_', ' ').toUpperCase();
  }

  String _dateLabel(String fieldName) {
    final raw = _subscription?[fieldName];
    if (raw == null) return '--';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final local = parsed.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$min';
  }

  String _receiptScansFreeValue() {
    final shownUsed = math.min(_receiptScanUsed, _receiptScanLimit);
    return '$shownUsed/$_receiptScanLimit';
  }

  String _receiptScansMonthValue() {
    if (_receiptScanUnlimited) {
      return '$_receiptScanUsed';
    }
    return _receiptScansFreeValue();
  }

  String _monthlyUsageLabel() {
    if (_receiptScanUnlimited) return 'Monthly usage: unlimited';
    final remaining = (_receiptScanRemaining ?? 0).clamp(0, 9999);
    final resetAt = _receiptScanResetAtUtc;
    if (resetAt == null) return 'Remaining this month: $remaining';
    final mm = resetAt.month.toString().padLeft(2, '0');
    final dd = resetAt.day.toString().padLeft(2, '0');
    return 'Remaining: $remaining | resets $mm/$dd UTC';
  }

  String _purchaseCtaLabel() {
    final package = _selectedPackage;
    if (package == null) return 'Upgrade to PRO';
    final priceLabel = package.storeProduct.priceString;
    if (priceLabel.trim().isEmpty) return 'Upgrade to PRO';
    return 'Buy ${_packagePlanLabel(package)} - $priceLabel';
  }

  String _friendlyBillingError(Object error) {
    if (error is PlatformException) {
      final details = error.details;
      String? readableCode;
      String? detailMessage;
      if (details is Map) {
        readableCode = details['readable_error_code']?.toString() ??
            details['readableErrorCode']?.toString();
        detailMessage = details['message']?.toString() ??
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
      if (normalizedCode.contains('storeproblemerror')) {
        return 'Store is temporarily unavailable. Please try again later.';
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
      readableCode = details['readable_error_code']?.toString() ??
          details['readableErrorCode']?.toString();
    }
    final normalizedCode = (readableCode ?? error.code).toLowerCase();
    return normalizedCode.contains('operationalreadyinprogresserror') ||
        error.code == '15';
  }

  String _packagePlanLabel(Package package) {
    if (package.packageType == PackageType.annual) return 'Yearly PRO';
    if (package.packageType == PackageType.monthly) return 'Monthly PRO';

    final identifier = package.identifier.toLowerCase();
    if (identifier.contains('year') || identifier.contains('annual')) {
      return 'Yearly PRO';
    }
    if (identifier.contains('month')) {
      return 'Monthly PRO';
    }
    return 'PRO';
  }

  void _applyPackageOptions(List<Package> packages) {
    Package? monthly;
    Package? yearly;
    Package? fallback;
    final selectedIdentifier = _selectedPackage?.identifier;
    Package? selectedMatch;

    for (final package in packages) {
      fallback ??= package;
      if (selectedIdentifier != null && package.identifier == selectedIdentifier) {
        selectedMatch = package;
      }
      if (package.packageType == PackageType.monthly) {
        monthly ??= package;
        continue;
      }
      if (package.packageType == PackageType.annual) {
        yearly ??= package;
        continue;
      }

      final identifier = package.identifier.toLowerCase();
      if (yearly == null &&
          (identifier.contains('year') || identifier.contains('annual'))) {
        yearly = package;
        continue;
      }
      if (monthly == null && identifier.contains('month')) {
        monthly = package;
      }
    }

    _monthlyPackage = monthly;
    _yearlyPackage = yearly;
    _selectedPackage = selectedMatch ?? yearly ?? monthly ?? fallback;
  }

  Future<void> _purchasePro() async {
    if (_isPurchaseLoading) return;
    if (!RevenueCatService.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('RevenueCat is not configured in this build.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    Package? package = _selectedPackage;
    if (package == null) {
      try {
        final offerings = await RevenueCatService.getOfferings();
        final packages = offerings?.current?.availablePackages ?? const <Package>[];
        if (packages.isNotEmpty) {
          _applyPackageOptions(packages);
          package = _selectedPackage;
          if (mounted) {
            setState(() {
              _selectedPackage = package;
            });
          }
        }
      } catch (_) {}
    }
    if (package == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No purchasable package available right now.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isPurchaseLoading = true);
    try {
      await RevenueCatService.purchasePackage(package);
      await ApiClient.syncRevenueCatSubscription();
      await _loadSubscriptionData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PRO subscription activated.')),
      );
    } catch (e) {
      Object effectiveError = e;
      if (_isOperationInProgressError(e)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          await RevenueCatService.purchasePackage(package);
          await ApiClient.syncRevenueCatSubscription();
          await _loadSubscriptionData();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PRO subscription activated.')),
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
            'Purchase failed: ${_friendlyBillingError(effectiveError)}',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPurchaseLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    if (_isPurchaseLoading) return;
    if (!RevenueCatService.isAvailable) return;
    setState(() => _isPurchaseLoading = true);
    try {
      await RevenueCatService.restorePurchases();
      await ApiClient.syncRevenueCatSubscription();
      await _loadSubscriptionData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Purchases restored.')));
    } catch (e) {
      Object effectiveError = e;
      if (_isOperationInProgressError(e)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          await RevenueCatService.restorePurchases();
          await ApiClient.syncRevenueCatSubscription();
          await _loadSubscriptionData();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Purchases restored.')),
          );
          return;
        } catch (retryError) {
          effectiveError = retryError;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: ${_friendlyBillingError(effectiveError)}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPurchaseLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120A1F),
      appBar: AppBar(
        title: const Text(
          'Subscription',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _isLoading || _isPurchaseLoading
                ? null
                : _loadSubscriptionData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadSubscriptionData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFF5A1AA6), Color(0xFF2A0F5C)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(80),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFF6D54A),
                  size: 42,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Unlock PRO Features',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _hasActiveSubscription
                      ? 'Your premium access is active.'
                      : 'Get unlimited access to all premium tools.',
                  style: TextStyle(
                    color: Colors.white.withAlpha(220),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildStatusChip(),
                const SizedBox(height: 16),
                _buildFeaturePager(),
                const SizedBox(height: 12),
                _buildPagerDots(),
                const SizedBox(height: 18),
                _buildBenefitsRow(),
                const SizedBox(height: 20),
                _buildPurchaseSection(),
                const SizedBox(height: 16),
                _buildSubscriptionMeta(),
              ],
            ),
          ),
          if (_showDevTools) ...[
            const SizedBox(height: 14),
            _buildDevToolsCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    final statusColor = _hasActiveSubscription
        ? const Color(0xFFC084FC)
        : const Color(0xFFFFB74D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: statusColor.withAlpha(190)),
      ),
      child: Text(
        'STATUS: ${_statusLabel()}',
        style: TextStyle(
          color: statusColor,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildFeaturePager() {
    return SizedBox(
      height: 292,
      child: PageView.builder(
        itemCount: _featureCards.length,
        onPageChanged: (index) => setState(() => _activePageIndex = index),
        itemBuilder: (context, index) {
          final card = _featureCards[index];
          final enabled = _activeFeatures.contains(card.code);
          final isReceiptScansCard = card.code == 'premium.receipt_scans.unlimited';
          final freeValue = isReceiptScansCard
              ? _receiptScansFreeValue()
              : card.freeValue;
          final freeColor = isReceiptScansCard && _receiptScanUsed >= _receiptScanLimit
              ? const Color(0xFF8C1D40)
              : Colors.white.withAlpha(220);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withAlpha(20),
              border: Border.all(
                color: enabled
                    ? const Color(0xFFCC9EFF).withAlpha(185)
                    : Colors.white.withAlpha(45),
                width: 1.2,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  card.icon,
                  color: enabled
                      ? const Color(0xFFCC9EFF)
                      : Colors.white.withAlpha(220),
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  card.title,
                  style: TextStyle(
                    color: enabled ? const Color(0xFFCC9EFF) : Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.black.withAlpha(35),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildPriceCol(
                          label: 'FREE',
                          value: freeValue,
                          color: freeColor,
                        ),
                      ),
                      Container(width: 1, height: 42, color: Colors.white24),
                      Expanded(
                        child: _buildPriceCol(
                          label: 'PRO',
                          value: card.proValue,
                          color: const Color(0xFFF7D74B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Center(
                    child: Text(
                      card.description,
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPriceCol({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withAlpha(230),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 44,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 34,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPagerDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_featureCards.length, (index) {
        final active = index == _activePageIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active
                ? const Color(0xFFF7D74B)
                : Colors.white.withAlpha(100),
          ),
        );
      }),
    );
  }

  Widget _buildBenefitsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: const [
        _BenefitPill(
          icon: Icons.verified_user_outlined,
          text: 'Secure & private',
        ),
        _BenefitPill(icon: Icons.update_rounded, text: 'Regular updates'),
        _BenefitPill(
          icon: Icons.support_agent_rounded,
          text: 'Priority support',
        ),
      ],
    );
  }

  Widget _buildSubscriptionMeta() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.black.withAlpha(25),
      ),
      child: Column(
        children: [
          _metaRow('Provider', (_subscription?['provider'] ?? '--').toString()),
          const SizedBox(height: 4),
          _metaRow(
            'Product',
            (_subscription?['product_id'] ?? '--').toString(),
          ),
          const SizedBox(height: 4),
          _metaRow('Scans This Month', _receiptScansMonthValue()),
          const SizedBox(height: 4),
          _metaRow('Quota', _monthlyUsageLabel()),
          const SizedBox(height: 4),
          _metaRow('Valid Until', _dateLabel('expires_at')),
        ],
      ),
    );
  }

  Widget _buildPurchaseSection() {
    if (_hasActiveSubscription) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF1A1230),
          border: Border.all(color: const Color(0xFFB388FF).withAlpha(90)),
        ),
        child: Column(
          children: [
            const Text(
              'PRO is active on your account.',
              style: TextStyle(
                color: Color(0xFFE7D3FF),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isPurchaseLoading ? null : _restorePurchases,
              child: const Text('Restore Purchases'),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF1A1230),
        border: Border.all(color: const Color(0xFFB388FF).withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_monthlyPackage != null || _yearlyPackage != null) ...[
            _buildPlanSelector(),
            const SizedBox(height: 10),
          ],
          ElevatedButton(
            onPressed: _isPurchaseLoading ? null : _purchasePro,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7E57C2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(_purchaseCtaLabel()),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _isPurchaseLoading ? null : _restorePurchases,
            child: const Text('Restore Purchases'),
          ),
          if (_isPurchaseLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanSelector() {
    final options = <Package>[];
    if (_monthlyPackage != null) {
      options.add(_monthlyPackage!);
    }
    if (_yearlyPackage != null &&
        _yearlyPackage!.identifier != _monthlyPackage?.identifier) {
      options.add(_yearlyPackage!);
    }
    if (options.isEmpty && _selectedPackage != null) {
      options.add(_selectedPackage!);
    }
    if (options.length <= 1) {
      return const SizedBox.shrink();
    }

    return Row(
      children: options.map((package) {
        final isYearly = _yearlyPackage?.identifier == package.identifier;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildPlanTile(package: package, isYearly: isYearly),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPlanTile({required Package package, required bool isYearly}) {
    final selected = _selectedPackage?.identifier == package.identifier;
    final borderColor = selected
        ? const Color(0xFFF7D74B)
        : Colors.white.withAlpha(75);
    final backgroundColor = selected
        ? const Color(0xFF5B2E88).withAlpha(210)
        : Colors.black.withAlpha(25);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedPackage = package),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isYearly)
              const Text(
                'BEST VALUE',
                style: TextStyle(
                  color: Color(0xFFF7D74B),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            if (isYearly) const SizedBox(height: 2),
            Text(
              _packagePlanLabel(package),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              package.storeProduct.priceString,
              style: TextStyle(
                color: selected
                    ? const Color(0xFFF7D74B)
                    : Colors.white.withAlpha(220),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(190),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildDevToolsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB388FF).withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Developer simulation',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'User ID: ${_targetUserId ?? "--"}',
            style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _devActionButton('Activate PRO', 'activate', Colors.green),
              _devActionButton('Expire', 'expire', Colors.orange),
              _devActionButton('Revoke', 'revoke', Colors.redAccent),
            ],
          ),
          if (_isDevActionLoading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _devActionButton(String label, String action, Color color) {
    return ElevatedButton(
      onPressed: _isDevActionLoading ? null : () => _applyDevAction(action),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withAlpha(220),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(label),
    );
  }
}

class _FeatureCardData {
  const _FeatureCardData({
    required this.code,
    required this.title,
    required this.description,
    required this.freeValue,
    required this.proValue,
    required this.icon,
  });

  final String code;
  final String title;
  final String description;
  final String freeValue;
  final String proValue;
  final IconData icon;
}

class _BenefitPill extends StatelessWidget {
  const _BenefitPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withAlpha(225), size: 20),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withAlpha(225),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}


