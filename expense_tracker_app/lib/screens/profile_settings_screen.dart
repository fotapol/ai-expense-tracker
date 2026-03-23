import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _subscriptionPayload;
  Set<String> _featureCodes = const <String>{};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
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
        ApiClient.getMeEntitlements(),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final subscription = results[1] as Map<String, dynamic>;
      final entitlements = results[2] as Map<String, dynamic>;
      final rawProfile = profile['profile'];
      final displayName = rawProfile is Map<String, dynamic>
          ? rawProfile['display_name']?.toString().trim() ?? ''
          : '';
      if (!mounted) return;
      setState(() {
        _profileData = profile;
        _subscriptionPayload = subscription;
        _featureCodes =
            (entitlements['feature_codes'] as List<dynamic>? ??
                    const <dynamic>[])
                .map((value) => value.toString())
                .toSet();
        _nameController.text = displayName;
        _emailController.text = profile['email']?.toString() ?? '';
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
    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      return email.substring(0, 1).toUpperCase();
    }
    return '?';
  }

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

  String _accountTypeLabel(BuildContext context) {
    if (_featureCodes.contains('premium.family_plan')) {
      return context.tr('settings_account_type_family');
    }
    if ((_subscriptionPayload?['has_active_subscription'] as bool?) == true) {
      return context.tr('settings_account_type_pro');
    }
    return context.tr('settings_account_type_free');
  }

  String _receiptUsageLabel() {
    final usageRaw = _subscriptionPayload?['receipt_scan_usage'];
    if (usageRaw is! Map<String, dynamic>) return '--';
    final used = int.tryParse((usageRaw['used'] ?? 0).toString()) ?? 0;
    if (usageRaw['is_unlimited'] == true) return '$used';
    final limit = int.tryParse((usageRaw['limit'] ?? 10).toString()) ?? 10;
    return '$used / $limit';
  }

  Future<void> _save() async {
    if (_isSaving || _profileData == null) return;
    final rawProfile = _profileData?['profile'];
    final currentName = rawProfile is Map<String, dynamic>
        ? rawProfile['display_name']?.toString().trim() ?? ''
        : '';
    final nextName = _nameController.text.trim();
    if (nextName == currentName) {
      if (mounted) Navigator.pop(context, false);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = await ApiClient.updateMe({
        'display_name': nextName.isEmpty ? null : nextName,
      });
      if (!mounted) return;
      setState(() => _profileData = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('settings_profile_saved'))),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': error.toString()},
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
    final avatarUrl = rawProfile is Map<String, dynamic>
        ? rawProfile['avatar_url']?.toString()
        : null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: ShellStyles.textPrimary(context),
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  _initials(),
                  style: TextStyle(
                    color: ShellStyles.surface(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: ShellStyles.textPrimary(context),
              shape: BoxShape.circle,
              border: Border.all(color: ShellStyles.surface(context), width: 2),
            ),
            child: Icon(
              AppIcons.photo,
              color: ShellStyles.surface(context),
              size: 12,
            ),
          ),
        ),
      ],
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
        if (hasDivider)
          Divider(
            height: 1,
            color: ShellStyles.border(context),
          ),
      ],
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
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => ShellStyles.showComingSoon(context),
                        child: Row(
                          children: [
                            _buildPhotoAvatar(),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('settings_profile_photo'),
                                    style: TextStyle(
                                      color: ShellStyles.textPrimary(context),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    context.tr(
                                      'settings_profile_photo_subtitle',
                                    ),
                                    style: TextStyle(
                                      color: ShellStyles.textMuted(context),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('settings_personal_information'),
                    ),
                    const SizedBox(height: 8),
                    SettingsDetailCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FieldLabel(label: context.tr('settings_full_name')),
                          TextField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                          ),
                          const SizedBox(height: 12),
                          _FieldLabel(label: context.tr('settings_email')),
                          TextField(
                            controller: _emailController,
                            readOnly: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShellStyles.sectionLabel(
                      context,
                      context.tr('settings_account_details'),
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
                            _accountTypeLabel(context),
                          ),
                          _buildStatRow(
                            context.tr('settings_receipt_usage_this_month'),
                            _receiptUsageLabel(),
                            hasDivider: false,
                          ),
                        ],
                      ),
                    ),
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
                            : Text(context.tr('common_save')),
                      ),
                    ),
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
