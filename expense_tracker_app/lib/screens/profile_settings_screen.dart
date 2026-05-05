import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_navigation.dart';
import '../core/api_client.dart';
import '../core/app_env.dart';
import '../core/launch_error_copy.dart';
import '../core/localized_dates.dart';
import '../core/redesign_system.dart';
import '../core/revenuecat_service.dart';
import '../core/session_invalidation.dart';
import '../core/subscription_confirmation.dart';
import 'settings_detail_scaffold.dart';
import '../l10n/app_localizations.dart';
import 'login_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;
  String? _error;
  String _initialDisplayName = '';
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _subscriptionPayload;
  int _allTimeReceiptScans = 0;

  bool get _hasPendingChanges =>
      _nameController.text.trim() != _initialDisplayName;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_handleNameChanged);
    _loadData();
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_handleNameChanged)
      ..dispose();
    super.dispose();
  }

  void _handleNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        ApiClient.getMe(),
        ApiClient.getMeSubscription(),
        ApiClient.listTransactions().catchError((_) => <dynamic>[]),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final subscription = results[1] as Map<String, dynamic>;
      final transactions = results[2] as List<dynamic>;
      final rawProfile = profile['profile'];
      final displayName = rawProfile is Map<String, dynamic>
          ? rawProfile['display_name']?.toString().trim() ?? ''
          : '';
      final allTimeReceiptScans = transactions
          .whereType<Map<String, dynamic>>()
          .where((transaction) {
            final receiptId =
                transaction['receipt_id']?.toString().trim() ?? '';
            return receiptId.isNotEmpty;
          })
          .length;
      if (!mounted) return;
      setState(() {
        _profileData = profile;
        _subscriptionPayload = subscription;
        _allTimeReceiptScans = allTimeReceiptScans;
        _initialDisplayName = displayName;
        _nameController.text = displayName;
        _isLoading = false;
      });
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      setState(() {
        _error = friendlyLaunchErrorMessage(
          error,
          fallback: context.tr('profile_load_error'),
        );
        _isLoading = false;
      });
    }
  }

  String _initials() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      if (parts.length == 1) {
        return parts.first.substring(0, 1).toUpperCase();
      }
      return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
          .toUpperCase();
    }
    final email = _email.trim();
    if (email.isNotEmpty) {
      return email.substring(0, 1).toUpperCase();
    }
    return '?';
  }

  String get _email => _profileData?['email']?.toString().trim() ?? '';

  String _memberSinceLabel() {
    final rawProfile = _profileData?['profile'];
    String? raw;
    if (rawProfile is Map<String, dynamic>) {
      raw =
          rawProfile['created_at']?.toString() ??
          _profileData?['created_at']?.toString();
    } else {
      raw = _profileData?['created_at']?.toString();
    }
    if (raw == null || raw.isEmpty) return '--';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    if (parsed == null) return '--';
    return formatLocalizedDayMonthYear(context, parsed);
  }

  String _accountTypeLabel() {
    if ((_subscriptionPayload?['has_active_subscription'] as bool?) == true) {
      return context.tr('settings_account_type_pro');
    }
    return context.tr('settings_account_type_free');
  }

  bool get _hasActiveSubscription =>
      (_subscriptionPayload?['has_active_subscription'] as bool?) == true;

  String _receiptUsageLabel() {
    return context.tr(
      'profile_scans_count',
      params: {'count': _allTimeReceiptScans.toString()},
    );
  }

  Map<String, dynamic>? get _receiptScanUsage {
    final usageRaw = _subscriptionPayload?['receipt_scan_usage'];
    return usageRaw is Map<String, dynamic> ? usageRaw : null;
  }

  int get _receiptUsageThisMonthUsed {
    final usage = _receiptScanUsage;
    if (usage == null) return 0;
    return int.tryParse((usage['used'] ?? 0).toString()) ?? 0;
  }

  int get _receiptUsageThisMonthLimit {
    final usage = _receiptScanUsage;
    if (usage == null) return 10;
    return int.tryParse((usage['limit'] ?? 10).toString()) ?? 10;
  }

  bool get _receiptUsageThisMonthUnlimited =>
      _receiptScanUsage?['is_unlimited'] == true;

  String _receiptUsageThisMonthLabel() {
    if (_receiptScanUsage == null) return '--';
    final used = _receiptUsageThisMonthUsed;
    if (_receiptUsageThisMonthUnlimited) {
      return context.tr(
        'profile_scans_used',
        params: {'count': used.toString()},
      );
    }
    final limit = _receiptUsageThisMonthLimit;
    return '$used / $limit';
  }

  Future<void> _save() async {
    if (_isSaving || _profileData == null || !_hasPendingChanges) return;
    final nextName = _nameController.text.trim();

    setState(() => _isSaving = true);
    try {
      final updated = await ApiClient.updateMe({
        'display_name': nextName.isEmpty ? null : nextName,
      });
      if (!mounted) return;
      setState(() {
        _profileData = updated;
        _initialDisplayName = nextName;
      });
      Navigator.pop(context, true);
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyLaunchErrorMessage(
              error,
              fallback: context.tr('profile_save_error'),
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_isDeleting || _profileData == null) return;
    final email = _email;
    final confirmed = await _showDeleteAccountDialog(email: email);
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      await ApiClient.deleteMe();
      await clearOptimisticPremiumAccess();
      await RevenueCatService.logOut();
      await GoogleSignIn.instance.signOut();
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;
      final successMessage = context.tr('profile_delete_account_success');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      final navigator = appNavigatorKey.currentState ?? Navigator.of(context);
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (error) {
      if (await maybeHandleExpiredSession(error)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'profile_delete_account_error',
              params: {
                'message': friendlyLaunchErrorMessage(
                  error,
                  fallback: context.tr('common_error'),
                ),
              },
            ),
          ),
          backgroundColor: ShellStyles.error(context),
        ),
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<bool?> _showDeleteAccountDialog({required String email}) {
    final confirmationText = email.trim();
    final controller = TextEditingController();
    final hasActiveSubscription = _hasActiveSubscription;
    final dangerColor = ShellStyles.error(context);

    return showDialog<bool>(
      context: context,
      barrierDismissible: !_isDeleting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final typedValue = controller.text.trim();
            final canConfirm =
                confirmationText.isNotEmpty && typedValue == confirmationText;
            return AlertDialog(
              title: Text(context.tr('profile_delete_account_title')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('profile_delete_account_body')),
                    if (hasActiveSubscription) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: dangerColor.withAlpha(18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: dangerColor.withAlpha(90)),
                        ),
                        child: Text(
                          context.tr(
                            'profile_delete_account_subscription_warning',
                          ),
                          style: TextStyle(
                            color: dangerColor,
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      context.tr(
                        'profile_delete_account_confirm_instruction',
                        params: {'email': confirmationText},
                      ),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          'profile_delete_account_email_label',
                        ),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(context.tr('common_cancel')),
                ),
                FilledButton(
                  onPressed: canConfirm
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  style: FilledButton.styleFrom(backgroundColor: dangerColor),
                  child: Text(
                    context.tr('profile_delete_account_confirm_button'),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _openPlaySubscriptionManagement() async {
    final uri = AppEnv.uriFrom(AppEnv.playSubscriptionsUrl);
    var opened = false;
    try {
      opened =
          uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('could_not_open_that_link'))),
      );
    }
  }

  Widget _buildPhotoAvatar() {
    final rawProfile = _profileData?['profile'];
    final backendAvatarUrl = rawProfile is Map<String, dynamic>
        ? rawProfile['avatar_url']?.toString().trim()
        : null;
    final accountPhotoUrl =
        FirebaseAuth.instance.currentUser?.photoURL?.trim() ?? '';
    final avatarUrl = accountPhotoUrl.isNotEmpty
        ? accountPhotoUrl
        : (backendAvatarUrl ?? '');

    // TODO(profile): add avatar upload/change flows when account image
    // management is fully designed and launch-safe.
    return CircleAvatar(
      radius: 30,
      backgroundColor: ShellStyles.accent(context),
      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
      child: avatarUrl.isEmpty
          ? Text(
              _initials(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }

  Widget _buildStatRow(String title, String value, {bool hasDivider = true}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (hasDivider) Divider(height: 1, color: ShellStyles.border(context)),
      ],
    );
  }

  Widget _buildMonthlyScanProgress({bool hasDivider = true}) {
    final hasUsage = _receiptScanUsage != null;
    final used = _receiptUsageThisMonthUsed;
    final limit = _receiptUsageThisMonthLimit;
    final progress = !hasUsage
        ? 0.0
        : _receiptUsageThisMonthUnlimited
        ? 1.0
        : (limit <= 0 ? 0.0 : used / limit).clamp(0.0, 1.0).toDouble();
    final accentTone = ShellStyles.accentTone(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('settings_receipt_usage_this_month'),
                      style: TextStyle(
                        color: ShellStyles.textMuted(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    _receiptUsageThisMonthLabel(),
                    style: TextStyle(
                      color: ShellStyles.textPrimary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 8,
                  color: ShellStyles.border(
                    context,
                  ).withAlpha(ShellStyles.isDark(context) ? 120 : 150),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(color: accentTone.base),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasDivider) Divider(height: 1, color: ShellStyles.border(context)),
      ],
    );
  }

  Widget _buildManageSubscriptionCard() {
    return SettingsDetailCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ShellColors.gold.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CrownIcon(
              color: ShellColors.gold,
              size: 20,
              strokeWidth: 1.7,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('settings_manage_subscription'),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('billing_managed_by_store_note'),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openPlaySubscriptionManagement,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(context.tr('settings_manage_subscription')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteAccountCard() {
    final dangerColor = ShellStyles.error(context);
    return SettingsDetailCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dangerColor.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.delete_outline, color: dangerColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('profile_delete_account_title'),
                  style: TextStyle(
                    color: ShellStyles.textPrimary(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('profile_delete_account_subtitle'),
                  style: TextStyle(
                    color: ShellStyles.textMuted(context),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _isDeleting ? null : _deleteAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: dangerColor,
                    side: BorderSide(color: dangerColor.withAlpha(160)),
                  ),
                  child: _isDeleting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: dangerColor,
                          ),
                        )
                      : Text(
                          context.tr('profile_delete_account_confirm_button'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('settings_profile'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _DetailErrorView(message: _error!, onRetry: _loadData)
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsDetailCard(
                      radius: 22,
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          _buildPhotoAvatar(),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nameController.text.trim().isEmpty
                                      ? (_email.isEmpty
                                            ? context.tr(
                                                'settings_account_section',
                                              )
                                            : _email)
                                      : _nameController.text.trim(),
                                  style: TextStyle(
                                    color: ShellStyles.textPrimary(context),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  context.tr('profile_google_managed'),
                                  style: TextStyle(
                                    color: ShellStyles.textMuted(context),
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SettingsDetailCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(label: context.tr('display_name')),
                          TextField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              hintText: context.tr('display_name'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('settings_account_section'),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: ShellStyles.cardDecoration(
                        context,
                        radius: 18,
                      ),
                      child: Column(
                        children: [
                          _buildStatRow(
                            context.tr('settings_member_since'),
                            _memberSinceLabel(),
                          ),
                          _buildStatRow(
                            context.tr('settings_account_type'),
                            _accountTypeLabel(),
                            hasDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('receipt_scans'),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: ShellStyles.cardDecoration(
                        context,
                        radius: 18,
                      ),
                      child: Column(
                        children: [
                          _buildStatRow(
                            context.tr('receipt_scans'),
                            _receiptUsageLabel(),
                          ),
                          _buildMonthlyScanProgress(hasDivider: false),
                        ],
                      ),
                    ),
                    if (_hasActiveSubscription) ...[
                      const SizedBox(height: 16),
                      _buildManageSubscriptionCard(),
                    ],
                    if (_hasPendingChanges || _isSaving) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isSaving ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(context.tr('save_changes')),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('profile_delete_account_section'),
                    ),
                    const SizedBox(height: 8),
                    _buildDeleteAccountCard(),
                  ],
                ),
              ),
            ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          color: ShellStyles.textPrimary(context),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: ShellStyles.textPrimary(context)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.tr('common_retry')),
            ),
          ],
        ),
      ),
    );
  }
}
