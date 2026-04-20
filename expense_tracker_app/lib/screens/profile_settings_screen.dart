import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/redesign_system.dart';
import '../core/session_invalidation.dart';
import 'settings_detail_scaffold.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
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
          fallback: 'Your profile could not load right now. Please try again.',
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
    return DateFormat.yMMMMd().format(parsed);
  }

  String _accountTypeLabel() {
    if ((_subscriptionPayload?['has_active_subscription'] as bool?) == true) {
      return 'Premium';
    }
    return 'Free';
  }

  String _receiptUsageLabel() {
    return '$_allTimeReceiptScans scans';
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
    if (_receiptUsageThisMonthUnlimited) return '$used scans used';
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
              fallback:
                  'We could not save your profile right now. Please try again.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
      backgroundColor: ShellStyles.textPrimary(context),
      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
      child: avatarUrl.isEmpty
          ? Text(
              _initials(),
              style: TextStyle(
                color: ShellStyles.surface(context),
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
                      'Scans this month',
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

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: 'Profile',
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
                                            ? 'Your account'
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
                                  'Your email and photo are managed by Google.',
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
                          const _FieldLabel(label: 'Display name'),
                          TextField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: 'Enter display name',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(context, 'Account'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: ShellStyles.cardDecoration(
                        context,
                        radius: 18,
                      ),
                      child: Column(
                        children: [
                          _buildStatRow('Joined', _memberSinceLabel()),
                          _buildStatRow(
                            'Plan',
                            _accountTypeLabel(),
                            hasDivider: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(context, 'Usage'),
                    const SizedBox(height: 8),
                    Container(
                      decoration: ShellStyles.cardDecoration(
                        context,
                        radius: 18,
                      ),
                      child: Column(
                        children: [
                          _buildStatRow('Total scans', _receiptUsageLabel()),
                          _buildMonthlyScanProgress(hasDivider: false),
                        ],
                      ),
                    ),
                    if (_hasPendingChanges || _isSaving) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isSaving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: ShellStyles.textPrimary(context),
                            foregroundColor: ShellStyles.surface(context),
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
                              : const Text('Save changes'),
                        ),
                      ),
                    ],
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
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
