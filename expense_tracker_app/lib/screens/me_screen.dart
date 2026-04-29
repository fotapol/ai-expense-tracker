import 'package:currency_picker/currency_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/redesign_system.dart';
import '../core/revenuecat_service.dart';
import '../core/session_invalidation.dart';
import '../core/subscription_confirmation.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_languages.dart';
import '../main.dart';
import 'about_screen.dart';
import 'appearance_settings_screen.dart';
import 'currency_settings_screen.dart';
import 'feature_request_screen.dart';
import 'help_center_screen.dart';
// TODO(household): re-import household_screen when household feature ships
import 'items_translation_settings_screen.dart';
import 'language_settings_screen.dart';
import 'login_screen.dart';
import 'notifications_settings_screen.dart';
import 'privacy_policy_screen.dart';
import 'profile_settings_screen.dart';
import 'subscription_screen.dart';
import 'terms_of_service_screen.dart';

/// Screen that displays the authenticated user's profile from the backend.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

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
  bool _isBillingLoading = true;
  bool _billingCardReady = false;
  String? _billingError;
  Map<String, dynamic>? _subscriptionPayload;

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
    return '${CurrencyDisplay.labelForCode(currency.code)} ${currency.name}';
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

  bool get _hasActiveSubscription =>
      (_subscriptionPayload?['has_active_subscription'] as bool?) ?? false;

  Map<String, dynamic>? get _subscription =>
      _subscriptionPayload?['subscription'] as Map<String, dynamic>?;

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
            'category_usage': syncPayload['category_usage'],
          };
        } catch (_) {
          subscriptionPayload = await ApiClient.getMeSubscription();
        }
      } else {
        subscriptionPayload = await ApiClient.getMeSubscription();
      }
      await waitForInitialLoadingWindow();
      if (!mounted) return;
      setState(() {
        _subscriptionPayload = subscriptionPayload;
        _isBillingLoading = false;
        _billingCardReady = true;
        _billingError = null;
      });
    } catch (e) {
      if (await maybeHandleExpiredSession(e)) return;
      await waitForInitialLoadingWindow();
      if (!mounted) return;
      setState(() {
        _isBillingLoading = false;
        _billingCardReady = true;
        _billingError = friendlyLaunchErrorMessage(
          e,
          fallback:
              'Subscription details are unavailable right now. Please try again.',
        );
      });
    }
  }

  Future<void> _openSubscriptionDetails() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SubscriptionScreen(currentUserId: _profileData?['id']?.toString()),
      ),
    );
    if (!mounted) return;
    await _refreshSettings();
  }

  Future<void> _openSettingsRoute(
    Widget screen, {
    bool refreshProfile = false,
    bool refreshBilling = false,
    String? successMessage,
  }) async {
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    if (refreshProfile && refreshBilling) {
      await _refreshSettings();
    } else if (refreshProfile) {
      await _fetchProfile();
    } else if (refreshBilling) {
      await _loadBillingData(showLoading: false);
    } else {
      setState(() {});
    }
    if (!mounted) return;
    if (result == true && successMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    }
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
      if (await maybeHandleExpiredSession(e)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          e,
          fallback: 'Your settings could not load right now. Please try again.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await clearOptimisticPremiumAccess();
    await RevenueCatService.logOut();
    await GoogleSignIn.instance.signOut();
    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _refreshSettings() async {
    await Future.wait([_fetchProfile(), _loadBillingData(showLoading: false)]);
  }

  String _profileDisplayName() {
    final profile = _profileData?['profile'];
    final displayName = profile is Map
        ? profile['display_name']?.toString().trim()
        : null;
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return (_profileData?['email']?.toString() ??
            context.tr('settings_unknown_email'))
        .trim();
  }

  String _subscriptionStatusSubtitle() {
    if (_isBillingLoading && !_billingCardReady) {
      return context.tr('settings_subscription_loading');
    }
    if (_hasActiveSubscription) {
      return context.tr(
        'settings_subscription_active_until',
        params: {'date': _validUntilLabel()},
      );
    }
    return context.tr('settings_subscription_inactive');
  }

  String _appearanceSubtitle(BuildContext context) {
    return '${themeProvider.themeModeLabel} - ${themeProvider.accentLabel} - ${themeProvider.scalePercentLabel}%';
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (_isLoading && _profileData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _profileData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _refreshSettings();
                },
                child: Text(context.tr('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    final bottomPadding = MediaQuery.of(context).padding.bottom + 36;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshSettings,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 18, 16, bottomPadding),
          children: [
            Text(
              context.tr('settings_title'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('settings_subtitle'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            _buildSubscriptionBanner(),
            if (_billingError != null) ...[
              const SizedBox(height: 10),
              _buildInfoBanner(_billingError!, color: ShellColors.softRed),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              _buildInfoBanner(_error!, color: ShellColors.softRed),
            ],
            const SizedBox(height: 14),
            _buildSection(
              title: context.tr('settings_account_section'),
              children: [
                _buildSettingsTile(
                  leading: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ShellColors.gold.withAlpha(18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const CrownIcon(
                      color: ShellColors.gold,
                      size: 16,
                      strokeWidth: 1.6,
                    ),
                  ),
                  title: context.tr('settings_subscription'),
                  subtitle: _subscriptionStatusSubtitle(),
                  badge: _hasActiveSubscription
                      ? _buildFeatureTag('PRO', ShellColors.gold)
                      : null,
                  onTap: _openSubscriptionDetails,
                ),
                // TODO(household): restore Household settings tile when household feature ships
                _buildSettingsTile(
                  icon: AppIcons.person,
                  title: context.tr('settings_profile'),
                  subtitle: _profileDisplayName(),
                  onTap: () => _openSettingsRoute(
                    const ProfileSettingsScreen(),
                    refreshProfile: true,
                    refreshBilling: true,
                    successMessage: 'Profile updated.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSection(
              title: context.tr('settings_preferences_section'),
              children: [
                _buildSettingsTile(
                  icon: AppIcons.appearance,
                  title: context.tr('settings_appearance'),
                  subtitle: _appearanceSubtitle(context),
                  onTap: () =>
                      _openSettingsRoute(const AppearanceSettingsScreen()),
                ),
                _buildSettingsTile(
                  icon: AppIcons.notifications,
                  title: context.tr('settings_notifications'),
                  subtitle: context.tr('settings_notifications_subtitle'),
                  onTap: () =>
                      _openSettingsRoute(const NotificationsSettingsScreen()),
                ),
                _buildSettingsTile(
                  icon: AppIcons.language,
                  title: context.tr('settings_language'),
                  subtitle: _currentLanguageSubtitle(),
                  onTap: () =>
                      _openSettingsRoute(const LanguageSettingsScreen()),
                ),
                _buildSettingsTile(
                  icon: AppIcons.currency,
                  title: context.tr('settings_currency'),
                  subtitle: _currencySubtitle(),
                  onTap: () => _openSettingsRoute(
                    CurrencySettingsScreen(initialCode: _currentCurrencyCode()),
                    refreshProfile: true,
                  ),
                ),
                _buildSettingsTile(
                  icon: AppIcons.translate,
                  title: context.tr('settings_items_language'),
                  subtitle: _currentItemsLanguageSubtitle(),
                  onTap: () => _openSettingsRoute(
                    ItemsTranslationSettingsScreen(
                      initialCode: _currentItemsLanguageCode(),
                    ),
                    refreshProfile: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSection(
              title: context.tr('settings_support_section'),
              children: [
                _buildSettingsTile(
                  icon: AppIcons.help,
                  title: context.tr('settings_help_center'),
                  onTap: () => _openSettingsRoute(const HelpCenterScreen()),
                ),
                _buildSettingsTile(
                  icon: AppIcons.feature,
                  title: context.tr('settings_feature_request'),
                  onTap: () => _openSettingsRoute(const FeatureRequestScreen()),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSection(
              title: context.tr('settings_legal_section'),
              children: [
                _buildSettingsTile(
                  icon: AppIcons.privacy,
                  title: context.tr('settings_privacy_policy'),
                  onTap: () => _openSettingsRoute(const PrivacyPolicyScreen()),
                ),
                _buildSettingsTile(
                  icon: AppIcons.document,
                  title: context.tr('settings_terms_of_service'),
                  onTap: () => _openSettingsRoute(const TermsOfServiceScreen()),
                ),
                _buildSettingsTile(
                  icon: AppIcons.info,
                  title: context.tr('settings_about'),
                  onTap: () => _openSettingsRoute(const AboutScreen()),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ShellStyles.sectionLabel(
              context,
              context.tr('settings_session_section'),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: ShellStyles.cardDecoration(
                context,
                radius: 16,
                withShadow: false,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('settings_signed_in_as'),
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _profileData?['email']?.toString() ??
                              context.tr('settings_unknown_email'),
                          style: TextStyle(
                            color: ShellStyles.textPrimary(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: ShellStyles.border(context)),
                  _buildSettingsTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ShellColors.softRed.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        AppIcons.logout,
                        color: ShellColors.softRed,
                        size: 18,
                      ),
                    ),
                    title: context.tr('settings_sign_out'),
                    showChevron: false,
                    titleColor: ShellColors.softRed,
                    onTap: _signOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
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

  Widget _buildSubscriptionBanner() {
    final title = _hasActiveSubscription
        ? context.tr('settings_banner_active_title')
        : context.tr('settings_banner_upgrade_title');
    final subtitle = _hasActiveSubscription
        ? context.tr('settings_banner_active_subtitle')
        : context.tr('settings_banner_upgrade_subtitle');
    final actionLabel = _hasActiveSubscription
        ? context.tr('settings_manage_subscription')
        : context.tr('settings_see_plan');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: ShellStyles.heroCardDecoration(context, radius: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ShellStyles.heroBadgeSurface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ShellStyles.heroBadgeBorder(context)),
            ),
            child: CrownIcon(
              color: ShellStyles.warningPremium(context),
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
                  title,
                  style: TextStyle(
                    color: ShellStyles.heroTextPrimary(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: ShellStyles.heroTextSecondary(context),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _openSubscriptionDetails,
                  style: FilledButton.styleFrom(
                    backgroundColor: ShellStyles.heroBadgeSurface(context),
                    foregroundColor: ShellStyles.heroTextPrimary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: ShellStyles.heroBadgeBorder(context),
                      ),
                    ),
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String message, {required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.info, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: ShellStyles.textMuted(context),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: ShellStyles.cardDecoration(
            context,
            radius: 16,
            withShadow: false,
          ),
          child: Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) _buildDivider(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    IconData? icon,
    Widget? leading,
    required String title,
    String? subtitle,
    Widget? badge,
    Widget? trailing,
    Color? iconColor,
    Color? titleColor,
    bool showChevron = true,
    VoidCallback? onTap,
  }) {
    final defaultTone = ShellStyles.accentTone(context);
    final effectiveIconColor = iconColor ?? defaultTone.base;
    final effectiveTitleColor = titleColor ?? ShellStyles.textPrimary(context);
    final effectiveContainerColor = iconColor != null
        ? iconColor.withAlpha(14)
        : defaultTone.container;

    final leadingWidget =
        leading ??
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: effectiveContainerColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: effectiveIconColor, size: 18),
        );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            if (icon != null || leading != null) ...[
              leadingWidget,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: effectiveTitleColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (badge != null) ...[badge, const SizedBox(width: 8)],
            if (trailing != null)
              trailing
            else if (showChevron)
              Icon(
                AppIcons.chevronRight,
                color: ShellStyles.textMuted(context),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(color: ShellStyles.border(context), height: 1);
  }
}
