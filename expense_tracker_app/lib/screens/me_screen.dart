import 'package:currency_picker/currency_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/revenuecat_service.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_languages.dart';
import '../main.dart';
import 'categories_screen.dart';
import 'household_screen.dart';
import 'labels_screen.dart';
import 'login_screen.dart';
import 'subscription_screen.dart';

/// Screen that displays the authenticated user's profile from the backend.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

enum _PackageAudience { individual, family }

class _MeScreenState extends State<MeScreen> {
  static const Duration _billingInitialLoadMinDuration = Duration(
    milliseconds: 350,
  );
  static const bool _showDevBillingTools = bool.fromEnvironment(
    'ENABLE_DEV_BILLING_TOOLS',
    defaultValue: false,
  );

  Map<String, dynamic>? _profileData;
  bool _isLoading = true;
  String? _error;
  bool _isUpdatingCurrency = false;
  bool _isUpdatingItemsLanguage = false;
  bool _isBillingLoading = true;
  bool _billingCardReady = false;
  bool _isBillingActionInProgress = false;
  String? _billingError;
  Map<String, dynamic>? _subscriptionPayload;
  Package? _monthlyPackage;
  Package? _yearlyPackage;
  Package? _selectedPackage;
  List<Package> _availablePackages = const <Package>[];
  _PackageAudience _selectedPackageAudience = _PackageAudience.individual;

  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _loadBillingData();
  }

  String _currentCurrencyCode() {
    return (_profileData?['default_currency'] ?? 'EUR')
        .toString()
        .toUpperCase();
  }

  String _currencySubtitle() {
    final currency = CurrencyService().findByCode(_currentCurrencyCode());
    if (currency == null) return _currentCurrencyCode();
    return '${currency.symbol} ${currency.name}';
  }

  String _languageNameForCode(String code) {
    final normalized = code.toLowerCase();
    for (final language in appLanguages) {
      if (language.code == normalized) {
        return language.nativeName;
      }
    }
    return code.toUpperCase();
  }

  String _currentLanguageSubtitle() {
    return _languageNameForCode(localeProvider.locale.languageCode);
  }

  String _currentItemsLanguageCode() {
    final saved = _profileData?['items_language']?.toString().trim();
    if (saved != null && saved.isNotEmpty) {
      return saved.toLowerCase();
    }
    return localeProvider.locale.languageCode.toLowerCase();
  }

  String _currentItemsLanguageSubtitle() {
    return _languageNameForCode(_currentItemsLanguageCode());
  }

  Future<void> _updateDefaultCurrency(String code) async {
    if (_isUpdatingCurrency) return;

    setState(() => _isUpdatingCurrency = true);
    try {
      final updated = await ApiClient.updateMe({
        'default_currency': code.toUpperCase(),
      });
      if (!mounted) return;
      setState(() => _profileData = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'settings_currency_updated',
              params: {'code': code.toUpperCase()},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'settings_currency_update_failed',
              params: {'error': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingCurrency = false);
    }
  }

  void _openCurrencyPicker() {
    final currentCode = _currentCurrencyCode();
    showCurrencyPicker(
      context: context,
      showSearchField: true,
      showFlag: false,
      favorite: [currentCode],
      onSelect: (currency) {
        final selectedCode = currency.code.toUpperCase();
        if (selectedCode == currentCode) return;
        _updateDefaultCurrency(selectedCode);
      },
    );
  }

  Future<void> _updateLanguage(String code) async {
    await localeProvider.setLocale(Locale(code));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'settings_language_updated',
            params: {'language': _languageNameForCode(code)},
          ),
        ),
      ),
    );
  }

  Future<void> _updateItemsLanguage(String code) async {
    if (_isUpdatingItemsLanguage) return;
    final normalized = code.toLowerCase();
    if (normalized == _currentItemsLanguageCode()) return;

    setState(() => _isUpdatingItemsLanguage = true);
    try {
      final updated = await ApiClient.updateMe({'items_language': normalized});
      if (!mounted) return;
      setState(() => _profileData = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'settings_language_updated',
              params: {'language': _languageNameForCode(normalized)},
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingItemsLanguage = false);
    }
  }

  void _showItemsLanguageBetaInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature is in development.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildBetaTag() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _showItemsLanguageBetaInfo,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(30),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.orange.withAlpha(140)),
          ),
          child: const Text(
            'BETA',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasActiveSubscription =>
      (_subscriptionPayload?['has_active_subscription'] as bool?) ?? false;

  Map<String, dynamic>? get _subscription =>
      _subscriptionPayload?['subscription'] as Map<String, dynamic>?;

  String _billingStatusLabel() {
    final status = (_subscription?['status'] ?? 'inactive').toString();
    return status.replaceAll('_', ' ').toUpperCase();
  }

  String _validUntilLabel() {
    final raw = _subscription?['expires_at'];
    if (raw == null) return '--';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    final local = parsed.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }

  String _usageSummaryLabel() {
    final usageRaw = _subscriptionPayload?['receipt_scan_usage'];
    if (usageRaw is! Map<String, dynamic>) return 'Monthly scans: --';
    final isUnlimited = usageRaw['is_unlimited'] == true;
    final used = int.tryParse((usageRaw['used'] ?? 0).toString()) ?? 0;
    if (isUnlimited) {
      return 'Monthly scans: $used (unlimited)';
    }
    final limit = int.tryParse((usageRaw['limit'] ?? 10).toString()) ?? 10;
    final remaining =
        int.tryParse((usageRaw['remaining'] ?? 0).toString()) ?? 0;
    return 'Monthly scans: $used/$limit, remaining: $remaining';
  }

  String _packagePlanLabel(Package package) {
    final isFamily = RevenueCatService.isFamilyPackage(package);
    final audienceLabel = isFamily ? 'Family' : 'Individual';
    if (RevenueCatService.isYearlyPackage(package)) {
      return 'Yearly $audienceLabel';
    }
    if (RevenueCatService.isMonthlyPackage(package)) {
      return 'Monthly $audienceLabel';
    }
    return '$audienceLabel Plan';
  }

  String _purchaseCtaLabel() {
    final package = _selectedPackage;
    if (package == null) return 'Upgrade to PRO';
    final priceLabel = package.storeProduct.priceString;
    if (priceLabel.trim().isEmpty) return 'Upgrade to PRO';
    return 'Buy ${_packagePlanLabel(package)} - $priceLabel';
  }

  void _applyPackageOptions(List<Package> packages) {
    _availablePackages = List<Package>.from(packages);
    Package? monthly;
    Package? yearly;
    Package? fallback;
    final selectedIdentifier = _selectedPackage?.identifier;
    Package? selectedMatch;
    final hasFamily = packages.any(RevenueCatService.isFamilyPackage);
    final hasIndividual = packages.any(
      (package) => !RevenueCatService.isFamilyPackage(package),
    );

    if (!hasFamily) {
      _selectedPackageAudience = _PackageAudience.individual;
    } else if (!hasIndividual) {
      _selectedPackageAudience = _PackageAudience.family;
    }

    final scopedPackages = packages.where((package) {
      if (_selectedPackageAudience == _PackageAudience.family) {
        return RevenueCatService.isFamilyPackage(package);
      }
      return !RevenueCatService.isFamilyPackage(package);
    }).toList();
    final sourcePackages = scopedPackages.isNotEmpty
        ? scopedPackages
        : packages;

    for (final package in sourcePackages) {
      fallback ??= package;
      if (selectedIdentifier != null &&
          package.identifier == selectedIdentifier) {
        selectedMatch = package;
      }
      if (RevenueCatService.isMonthlyPackage(package)) {
        monthly ??= package;
        continue;
      }
      if (RevenueCatService.isYearlyPackage(package)) {
        yearly ??= package;
        continue;
      }
    }

    _monthlyPackage = monthly;
    _yearlyPackage = yearly;
    _selectedPackage = selectedMatch ?? yearly ?? monthly ?? fallback;
  }

  bool _hasFamilyPackages() =>
      _availablePackages.any(RevenueCatService.isFamilyPackage);

  bool _hasIndividualPackages() => _availablePackages.any(
    (package) => !RevenueCatService.isFamilyPackage(package),
  );

  Widget _buildPackageAudienceSelector() {
    final canChooseAudience = _hasFamilyPackages() && _hasIndividualPackages();
    if (!canChooseAudience) return const SizedBox.shrink();

    Widget audienceChip({
      required String label,
      required _PackageAudience audience,
    }) {
      final isSelected = _selectedPackageAudience == audience;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            if (_selectedPackageAudience == audience) return;
            setState(() {
              _selectedPackageAudience = audience;
              _applyPackageOptions(_availablePackages);
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: isSelected
                  ? const Color(0xFF5B2E88).withAlpha(210)
                  : Colors.black.withAlpha(25),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFF7D74B)
                    : Colors.white.withAlpha(90),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        audienceChip(
          label: 'Individual',
          audience: _PackageAudience.individual,
        ),
        const SizedBox(width: 8),
        audienceChip(label: 'Family', audience: _PackageAudience.family),
      ],
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
        return 'Another billing operation is in progress. Please try again in a few seconds.';
      }
      if (normalizedCode.contains('purchasecancellederror')) {
        return 'Purchase canceled.';
      }
      if (normalizedCode.contains('networkerror')) {
        return 'Network error while contacting the store.';
      }
      if (normalizedCode.contains('storeproblemerror')) {
        return 'Store is temporarily unavailable.';
      }
      final message = detailMessage ?? error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }
    return error.toString();
  }

  Future<void> _loadBillingData({bool showLoading = true}) async {
    final isInitialLoad = !_billingCardReady;
    final loadStartedAt = DateTime.now();
    final shouldSyncRevenueCat =
        RevenueCatService.isAvailable && !_showDevBillingTools;

    Future<void> waitForInitialLoadingWindow() async {
      if (!isInitialLoad) return;
      final elapsed = DateTime.now().difference(loadStartedAt);
      final remaining = _billingInitialLoadMinDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }

    if (showLoading) {
      setState(() {
        _isBillingLoading = true;
        _billingError = null;
      });
    }
    try {
      Map<String, dynamic> subscriptionPayload;
      if (shouldSyncRevenueCat) {
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
      await waitForInitialLoadingWindow();
      if (!mounted) return;
      setState(() {
        _subscriptionPayload = subscriptionPayload;
        final packages = RevenueCatService.flattenAvailablePackages(offerings);
        for (final package in packages) {
          debugPrint(
            '[RC][Me] package=${package.storeProduct.identifier} '
            'pkgId=${package.identifier} '
            'family=${RevenueCatService.isFamilyPackage(package)}',
          );
        }
        _applyPackageOptions(packages);
        _isBillingLoading = false;
        _billingCardReady = true;
        _billingError = null;
      });
    } catch (e) {
      await waitForInitialLoadingWindow();
      if (!mounted) return;
      setState(() {
        _isBillingLoading = false;
        _billingCardReady = true;
        _billingError = e.toString();
      });
    }
  }

  Future<void> _purchasePro() async {
    if (_isBillingActionInProgress) return;
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
        final packages = RevenueCatService.flattenAvailablePackages(offerings);
        if (packages.isNotEmpty) {
          _applyPackageOptions(packages);
          package = _selectedPackage;
          if (mounted) setState(() => _selectedPackage = package);
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

    setState(() => _isBillingActionInProgress = true);
    try {
      await RevenueCatService.purchasePackage(package);
      await ApiClient.syncRevenueCatSubscription();
      await _loadBillingData(showLoading: false);
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
          await _loadBillingData(showLoading: false);
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
      if (mounted) setState(() => _isBillingActionInProgress = false);
    }
  }

  Future<void> _restorePurchases() async {
    if (_isBillingActionInProgress) return;
    if (!RevenueCatService.isAvailable) return;
    setState(() => _isBillingActionInProgress = true);
    try {
      await RevenueCatService.restorePurchases();
      await ApiClient.syncRevenueCatSubscription();
      await _loadBillingData(showLoading: false);
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
          await _loadBillingData(showLoading: false);
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Purchases restored.')));
          return;
        } catch (retryError) {
          effectiveError = retryError;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restore failed: ${_friendlyBillingError(effectiveError)}',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBillingActionInProgress = false);
    }
  }

  Future<void> _applyDevRevokeSubscription() async {
    if (_isBillingActionInProgress) return;
    final targetUserId = _profileData?['id']?.toString().trim() ?? '';
    if (targetUserId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing user ID for dev revoke action.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isBillingActionInProgress = true);
    try {
      await ApiClient.applyDevManualSubscriptionAction(
        targetUserId: targetUserId,
        action: 'revoke',
      );
      await _loadBillingData(showLoading: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dev revoke subscription applied.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dev revoke failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBillingActionInProgress = false);
    }
  }

  void _openSubscriptionDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SubscriptionScreen(currentUserId: _profileData?['id']?.toString()),
      ),
    );
  }

  void _openLanguagePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        final currentCode = localeProvider.locale.languageCode;
        return StatefulBuilder(
          builder: (context, setModalState) {
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = appLanguages.where((language) {
              if (normalizedQuery.isEmpty) return true;
              if (language.nativeName.toLowerCase().contains(normalizedQuery)) {
                return true;
              }
              if (language.code.toLowerCase().contains(normalizedQuery)) {
                return true;
              }
              for (final keyword in language.searchKeywords) {
                if (keyword.toLowerCase().contains(normalizedQuery)) {
                  return true;
                }
              }
              return false;
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.tr('language_picker_title'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => setModalState(() => query = value),
                      decoration: InputDecoration(
                        hintText: context.tr('language_picker_search'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final language = filtered[index];
                          final code = language.code;
                          final selected = code == currentCode;
                          return ListTile(
                            title: Text(language.nativeName),
                            trailing: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade500,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _updateLanguage(code);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openItemsLanguagePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        final currentCode = _currentItemsLanguageCode();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = appLanguages.where((language) {
              if (normalizedQuery.isEmpty) return true;
              if (language.nativeName.toLowerCase().contains(normalizedQuery)) {
                return true;
              }
              if (language.code.toLowerCase().contains(normalizedQuery)) {
                return true;
              }
              for (final keyword in language.searchKeywords) {
                if (keyword.toLowerCase().contains(normalizedQuery)) {
                  return true;
                }
              }
              return false;
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade600,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.tr('language_picker_title'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => setModalState(() => query = value),
                      decoration: InputDecoration(
                        hintText: context.tr('language_picker_search'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.55,
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final language = filtered[index];
                          final code = language.code;
                          final selected = code == currentCode;
                          return ListTile(
                            title: Text(language.nativeName),
                            trailing: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey.shade500,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _updateItemsLanguage(code);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await ApiClient.getMe();
      if (!mounted) return;
      setState(() {
        _profileData = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr(
          'settings_failed_load_profile',
          params: {'error': e.toString()},
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await RevenueCatService.logOut();
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _exportData() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      final data = await ApiClient.exportData();
      final jsonString = jsonEncode(data);

      final directory = await getApplicationDocumentsDirectory();
      final dateStr = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final file = File(
        '${directory.path}/ai_expense_tracker_export_$dateStr.json',
      );
      await file.writeAsString(jsonString);

      if (!mounted) return;
      Navigator.pop(context);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'AI Expense Tracker Export');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _importData() async {
    var dialogShown = false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      dialogShown = true;

      final pickedFile = result.files.single;
      var fileBytes = pickedFile.bytes;
      if (fileBytes == null && pickedFile.path != null) {
        fileBytes = await File(pickedFile.path!).readAsBytes();
      }
      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception('Failed to read selected JSON file.');
      }

      var content = utf8.decode(fileBytes, allowMalformed: true);
      if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
        content = content.substring(1);
      }

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid import JSON: root payload must be an object.');
      }

      final payload = decoded;
      await ApiClient.importData(payload);

      if (!mounted) return;
      if (dialogShown && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data imported successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      if (dialogShown && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      String errBody = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': errBody},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr('nav_profile'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _fetchProfile();
              },
              child: Text(context.tr('common_retry')),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileCard(),
          const SizedBox(height: 32),
          const Text(
            'Subscription',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _buildPremiumCard(),
          const SizedBox(height: 16),
          const Text(
            'Settings',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _buildSettingsTile(
                  icon: Icons.attach_money,
                  title: context.tr('settings_currency'),
                  subtitle: _currencySubtitle(),
                  trailing: _isUpdatingCurrency
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _openCurrencyPicker,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.translate,
                  title: context.tr('settings_language'),
                  subtitle: _currentLanguageSubtitle(),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _openLanguagePicker,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.g_translate,
                  title: context.tr('settings_items_language'),
                  subtitle: _currentItemsLanguageSubtitle(),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildBetaTag(),
                      const SizedBox(width: 10),
                      _isUpdatingItemsLanguage
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  onTap: _openItemsLanguagePicker,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.list,
                  title: context.tr('settings_categories_subcategories'),
                  subtitle: context.tr(
                    'settings_manage_categories_subcategories',
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CategoriesScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.label_outline,
                  title: context.tr('settings_labels'),
                  subtitle: context.tr('settings_manage_labels'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LabelsScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.file_download_outlined,
                  title: 'Export Data',
                  subtitle: 'Save categories and transactions to a JSON file',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _exportData,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.file_upload_outlined,
                  title: 'Import Data',
                  subtitle:
                      'Restore categories and transactions from a JSON file',
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: _importData,
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.group_add_outlined,
                  title: context.tr('household_settings_title'),
                  subtitle: context.tr('household_settings_subtitle'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildFeatureTag('PREMIUM', const Color(0xFFF7D74B)),
                      const SizedBox(width: 6),
                      _buildFeatureTag('BETA', Colors.orangeAccent),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HouseholdScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.notifications_off_outlined,
                  title: context.tr('settings_notifications'),
                  onTap: () {
                    setState(() {
                      _notificationsEnabled = !_notificationsEnabled;
                    });
                  },
                  trailing: Switch(
                    value: _notificationsEnabled,
                    onChanged: (val) {
                      setState(() {
                        _notificationsEnabled = val;
                      });
                    },
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: context.tr('settings_dark_mode'),
                  onTap: () => themeProvider.toggle(),
                  trailing: Switch(
                    value: themeProvider.isDarkMode,
                    onChanged: (val) => themeProvider.toggle(),
                    activeThumbColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_profileData != null) ...[
                  Text(
                    context.tr('settings_signed_in_as'),
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _profileData!['email'] ??
                        context.tr('settings_unknown_email'),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: Text(
                      context.tr('settings_sign_out'),
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _editProfile() async {
    final profile = _profileData?['profile'];
    final currentName =
        (profile is Map ? profile['display_name'] as String? : null) ?? '';
    final controller = TextEditingController(text: currentName);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter your name',
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.tr('common_save')),
          ),
        ],
      ),
    );

    if (result != null && result != currentName) {
      try {
        final updated = await ApiClient.updateMe({
          'display_name': result.isEmpty ? null : result,
        });
        if (!mounted) return;
        setState(() => _profileData = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildProfileCard() {
    final email =
        _profileData?['email']?.toString() ??
        context.tr('settings_unknown_email');
    final profile = _profileData?['profile'];
    final displayName = profile is Map
        ? profile['display_name'] as String?
        : null;
    final avatarUrl = profile is Map ? profile['avatar_url'] as String? : null;

    final nameInitial = (displayName != null && displayName.isNotEmpty)
        ? displayName.substring(0, 1).toUpperCase()
        : (email.isNotEmpty ? email.substring(0, 1).toUpperCase() : '?');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.1),
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    nameInitial,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName ?? 'Add a display name',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: displayName == null ? Colors.grey : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _editProfile,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumCard() {
    final showInitialLoading = !_billingCardReady;
    final hasBillingSnapshot =
        _billingCardReady && _subscriptionPayload != null;
    final statusColor = showInitialLoading
        ? Colors.blueGrey.shade300
        : (_hasActiveSubscription
              ? const Color(0xFFB388FF)
              : const Color(0xFFF7D74B));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF5A1AA6), Color(0xFF2A0F5C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withAlpha(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFFF7D74B),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Premium Subscription',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showInitialLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withAlpha(220)),
                  ),
                  child: Text(
                    _billingStatusLabel(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            showInitialLoading
                ? 'Loading subscription status...'
                : (_hasActiveSubscription
                      ? 'PRO features are active on your account.'
                      : 'Unlock unlimited scans and premium features.'),
            style: TextStyle(
              color: Colors.white.withAlpha(220),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasBillingSnapshot ? _usageSummaryLabel() : 'Monthly scans: --',
            style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Valid until: ${hasBillingSnapshot ? _validUntilLabel() : "--"}',
            style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13),
          ),
          if (_billingError != null) ...[
            const SizedBox(height: 10),
            Text(
              _billingError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          if (hasBillingSnapshot && !_hasActiveSubscription) ...[
            if (_monthlyPackage != null || _yearlyPackage != null) ...[
              _buildPackageAudienceSelector(),
              if (_hasFamilyPackages() && _hasIndividualPackages())
                const SizedBox(height: 8),
              _buildPlanSelector(),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isBillingLoading || _isBillingActionInProgress)
                        ? null
                        : _purchasePro,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(_purchaseCtaLabel()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else if (hasBillingSnapshot) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(70)),
              ),
              child: const Text(
                'PRO is already active on this account.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: hasBillingSnapshot
                      ? _openSubscriptionDetails
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withAlpha(120)),
                  ),
                  child: const Text('Details'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      (!hasBillingSnapshot ||
                          _isBillingLoading ||
                          _isBillingActionInProgress)
                      ? null
                      : _restorePurchases,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withAlpha(120)),
                  ),
                  child: const Text('Restore Purchases'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: (_isBillingLoading || _isBillingActionInProgress)
                    ? null
                    : () => _loadBillingData(showLoading: true),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ],
          ),
          if (_showDevBillingTools) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed:
                    (!hasBillingSnapshot ||
                        _isBillingLoading ||
                        _isBillingActionInProgress)
                    ? null
                    : _applyDevRevokeSubscription,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Dev Revoke'),
              ),
            ),
          ],
          if (_isBillingLoading || _isBillingActionInProgress) ...[
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
        : Colors.white.withAlpha(80);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedPackage = package),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF5B2E88).withAlpha(210)
              : Colors.black.withAlpha(20),
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
                  letterSpacing: 0.4,
                ),
              ),
            if (isYearly) const SizedBox(height: 2),
            Text(
              _packagePlanLabel(package),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
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
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withAlpha(24),
        border: Border.all(color: color.withAlpha(180)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.primary,
        size: 28,
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 60, right: 16),
      child: Divider(color: Colors.grey.shade800, height: 1),
    );
  }
}
