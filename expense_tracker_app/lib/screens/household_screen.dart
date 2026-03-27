// TODO(household): disabled for single-user launch

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../core/auto_refresh_state_mixin.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';
import 'subscription_screen.dart';

class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen>
    with WidgetsBindingObserver, AutoRefreshStateMixin<HouseholdScreen> {
  static const String _familyPlanFeatureCode = 'premium.family_plan';

  bool _isLoading = true;
  bool _isActionLoading = false;
  String? _error;

  Map<String, dynamic>? _me;
  Map<String, dynamic>? _household;
  List<dynamic> _members = const [];
  List<dynamic> _invites = const [];
  Set<String> _featureCodes = const {};
  bool _isRefreshingHousehold = false;
  bool _sharedExpensesEnabled = true;
  bool _budgetNotificationsEnabled = true;

  @override
  Duration get autoRefreshInterval => const Duration(seconds: 10);

  @override
  Future<void> performAutoRefresh() => _loadData(showLoader: false);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int? _extractStatusCode(Object error) {
    final text = error.toString();
    final match = RegExp(r'\b([1-5]\d{2})\b').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  bool get _hasFamilyPlan => _featureCodes.contains(_familyPlanFeatureCode);

  String _currentUserId() => _me?['id']?.toString() ?? '';

  Map<String, dynamic>? _currentMembership() {
    final myUserId = _currentUserId();
    if (myUserId.isEmpty) return null;
    for (final raw in _members) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['user_id']?.toString() == myUserId) return raw;
    }
    return null;
  }

  bool get _isOwner => _currentMembership()?['role']?.toString() == 'owner';
  bool get _canManage => _isOwner && _hasFamilyPlan;

  bool _isCurrentMember(Map<String, dynamic> member) =>
      member['user_id']?.toString() == _currentUserId();

  Future<void> _loadData({bool showLoader = true}) async {
    if (_isRefreshingHousehold) return;
    _isRefreshingHousehold = true;
    if (!mounted) {
      _isRefreshingHousehold = false;
      return;
    }
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final meFuture = ApiClient.getMe();
      final entitlementsFuture = ApiClient.getMeEntitlements();
      final me = await meFuture;
      final entitlements = await entitlementsFuture;
      final featureCodes =
          (entitlements['feature_codes'] as List<dynamic>? ?? const <dynamic>[])
              .map((code) => code.toString())
              .toSet();

      Map<String, dynamic>? household;
      List<dynamic> members = const [];
      List<dynamic> invites = const [];

      try {
        household = await ApiClient.getCurrentHousehold();
      } catch (error) {
        if (_extractStatusCode(error) != 404) rethrow;
      }

      if (household != null) {
        members = await ApiClient.listCurrentHouseholdMembers();
        final myUserId = me['id']?.toString() ?? '';
        final myMembership = members
            .whereType<Map<String, dynamic>>()
            .firstWhere(
              (member) => member['user_id']?.toString() == myUserId,
              orElse: () => const <String, dynamic>{},
            );
        if (myMembership['role']?.toString() == 'owner') {
          try {
            invites = await ApiClient.listCurrentHouseholdInvites();
          } catch (error) {
            final statusCode = _extractStatusCode(error);
            if (statusCode != 403 && statusCode != 404) rethrow;
            invites = const [];
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _me = me;
        _household = household;
        _members = members;
        _invites = invites;
        _featureCodes = featureCodes;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (showLoader || _household == null) {
        setState(() {
          _isLoading = false;
          _error = error.toString();
        });
      }
    } finally {
      _isRefreshingHousehold = false;
    }
  }

  Future<void> _createHousehold() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('household_create_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.tr('household_name_label'),
            hintText: context.tr('household_name_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(context.tr('common_create')),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;
    setState(() => _isActionLoading = true);
    try {
      await ApiClient.createHousehold(name: name);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_created_success'))),
      );
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _editHouseholdName() async {
    if (_household == null) return;
    final controller = TextEditingController(
      text: _household?['name']?.toString() ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('household_edit_name_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.tr('household_name_label'),
            hintText: context.tr('household_name_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(context.tr('common_save')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.updateCurrentHousehold(name: name);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_updated_success'))),
      );
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _createInvite() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('household_invite_create_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: context.tr('household_invite_email_label'),
            hintText: context.tr('household_invite_email_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(context.tr('household_invite_send')),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty) return;
    setState(() => _isActionLoading = true);
    try {
      await ApiClient.createHouseholdInvite(invitedEmail: email);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_invite_created'))),
      );
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _revokeInvite(Map<String, dynamic> invite) async {
    final inviteId = invite['id']?.toString() ?? '';
    if (inviteId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('household_invite_revoke_title')),
        content: Text(context.tr('household_invite_revoke_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.revokeHouseholdInvite(inviteId);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_invite_revoked'))),
      );
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final memberId = member['id']?.toString() ?? '';
    if (memberId.isEmpty) return;
    final displayName = _memberName(member);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('household_remove_member_title')),
        content: Text(
          context.tr(
            'household_remove_member_confirm',
            params: {'name': displayName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.removeHouseholdMember(memberId);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_member_removed'))),
      );
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _leaveHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('household_leave_title')),
        content: Text(context.tr('household_leave_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('household_leave_action')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.leaveCurrentHousehold();
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_left_success'))),
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _deleteHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('household_delete_title')),
        content: Text(context.tr('household_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(context.tr('household_delete_action')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.deleteCurrentHousehold();
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_deleted_success'))),
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'accepted':
        return Colors.green;
      case 'revoked':
        return Colors.redAccent;
      case 'expired':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'accepted':
        return context.tr('household_invite_state_accepted');
      case 'revoked':
        return context.tr('household_invite_state_revoked');
      case 'expired':
        return context.tr('household_invite_state_expired');
      default:
        return context.tr('household_invite_state_pending');
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return context.tr('household_role_owner');
      case 'admin':
        return context.tr('household_role_admin');
      default:
        return context.tr('household_role_member');
    }
  }

  void _openSubscriptionScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SubscriptionScreen(currentUserId: _me?['id']?.toString()),
      ),
    );
  }

  String _memberName(Map<String, dynamic> member) {
    final user = member['user'];
    final displayName = user is Map<String, dynamic>
        ? user['display_name']?.toString().trim()
        : null;
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final email = _memberEmail(member);
    if (email.isNotEmpty) return email;
    return context.tr('common_unknown');
  }

  String _memberEmail(Map<String, dynamic> member) {
    final user = member['user'];
    final email = user is Map<String, dynamic>
        ? user['email']?.toString().trim()
        : null;
    return email ?? '';
  }

  String _memberInitials(Map<String, dynamic> member) {
    final name = _memberName(member);
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _copyInviteLink(String inviteLink) async {
    await Clipboard.setData(ClipboardData(text: inviteLink));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('household_invite_link_copied'))),
    );
  }

  Future<void> _handleOverflowAction(String value) async {
    switch (value) {
      case 'edit':
        if (_canManage && !_isActionLoading) await _editHouseholdName();
        break;
      case 'leave':
        if (!_isActionLoading) await _leaveHousehold();
        break;
      case 'delete':
        if (!_isActionLoading) await _deleteHousehold();
        break;
    }
  }

  Widget _buildLockedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD17700), Color(0xFFB55B00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD17700).withAlpha(35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CrownIcon(color: Color(0xFFFFC54D), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('household_family_plan_required'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('household_locked_subtitle'),
                  style: TextStyle(
                    color: Colors.white.withAlpha(230),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _openSubscriptionScreen,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2B1A08),
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(context.tr('household_upgrade_cta')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr(
                  'common_error_with_message',
                  params: {'message': _error!},
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadData,
                child: Text(context.tr('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (_household == null) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            Text(
              context.tr('household_empty_title'),
              style: TextStyle(
                color: ShellStyles.textPrimary(context),
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('household_empty_subtitle'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 16),
            if (!_hasFamilyPlan) ...[
              _buildLockedBanner(),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_hasFamilyPlan && !_isActionLoading)
                    ? _createHousehold
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: ShellStyles.textPrimary(context),
                  foregroundColor: ShellStyles.surface(context),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(context.tr('household_create_cta')),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.tr('household_join_via_link_only'),
              style: TextStyle(
                color: ShellStyles.textMuted(context),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
    }

    final members = _members.whereType<Map<String, dynamic>>().toList();
    final subtitle = _hasFamilyPlan
        ? context.tr(
            'household_member_count_with_limit',
            params: {'count': '${members.length}', 'limit': '5'},
          )
        : context.tr(
            'household_member_count',
            params: {'count': '${members.length}'},
          );

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Text(
            subtitle,
            style: TextStyle(
              color: ShellStyles.textMuted(context),
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 16),
          if (!_hasFamilyPlan) ...[
            _buildLockedBanner(),
            const SizedBox(height: 16),
          ],
          ShellStyles.sectionLabel(
            context,
            context.tr('household_members_title'),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: ShellStyles.cardDecoration(context, radius: 18),
            child: Column(
              children: [
                for (var index = 0; index < members.length; index++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: ShellStyles.textPrimary(context),
                          child: Text(
                            _memberInitials(members[index]),
                            style: TextStyle(
                              color: ShellStyles.surface(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _memberName(members[index]),
                                style: TextStyle(
                                  color: ShellStyles.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _memberEmail(members[index]),
                                style: TextStyle(
                                  color: ShellStyles.textMuted(context),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: ShellStyles.surfaceAlt(context),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _roleLabel(
                              members[index]['role']?.toString() ?? 'member',
                            ),
                            style: TextStyle(
                              color: ShellStyles.textMuted(context),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_canManage &&
                            !_isCurrentMember(members[index]) &&
                            members[index]['role']?.toString() != 'owner')
                          PopupMenuButton<String>(
                            onSelected: (_) => _removeMember(members[index]),
                            itemBuilder: (context) => [
                              PopupMenuItem<String>(
                                value: 'remove',
                                child: Text(
                                  context.tr('household_remove_member_title'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (index != members.length - 1)
                    Divider(
                      height: 1,
                      color: ShellStyles.border(context),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          ShellStyles.sectionLabel(
            context,
            context.tr('settings_preferences_section'),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: ShellStyles.cardDecoration(context, radius: 18),
            child: Column(
              children: [
                SettingsToggleRow(
                  title: context.tr('household_shared_expenses'),
                  subtitle: context.tr('household_shared_expenses_subtitle'),
                  value: _sharedExpensesEnabled,
                  onChanged: (value) =>
                      setState(() => _sharedExpensesEnabled = value),
                ),
                Divider(
                  height: 1,
                  color: ShellStyles.border(context),
                ),
                SettingsToggleRow(
                  title: context.tr('household_budget_notifications'),
                  subtitle: context.tr(
                    'household_budget_notifications_subtitle',
                  ),
                  value: _budgetNotificationsEnabled,
                  onChanged: (value) =>
                      setState(() => _budgetNotificationsEnabled = value),
                ),
              ],
            ),
          ),
          if (_isOwner) ...[
            const SizedBox(height: 16),
            ShellStyles.sectionLabel(
              context,
              context.tr('household_invites_title'),
            ),
            const SizedBox(height: 8),
            if (_invites.isEmpty)
              Text(
                context.tr('household_invites_empty'),
                style: TextStyle(
                  color: ShellStyles.textMuted(context),
                  fontSize: 12.5,
                ),
              )
            else
              ..._invites.whereType<Map<String, dynamic>>().map((invite) {
                final state =
                    invite['effective_state']?.toString() ?? 'pending';
                final inviteLink =
                    invite['invite_link']?.toString().trim() ?? '';
                final invitedUser = invite['invited_user'];
                final invitedEmail = invite['invited_email']?.toString();
                final invitedDisplay = invitedUser is Map<String, dynamic>
                    ? (invitedUser['display_name']?.toString() ??
                          invitedUser['email']?.toString())
                    : invitedEmail;
                final stateColor = _stateColor(state);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SettingsDetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                invitedDisplay ?? context.tr('common_unknown'),
                                style: TextStyle(
                                  color: ShellStyles.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: stateColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _stateLabel(state),
                                style: TextStyle(
                                  color: stateColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr(
                            'household_invite_expires_at',
                            params: {
                              'date': invite['expires_at']?.toString() ?? '--',
                            },
                          ),
                          style: TextStyle(
                            color: ShellStyles.textMuted(context),
                            fontSize: 11.5,
                          ),
                        ),
                        if (state == 'pending' && inviteLink.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _copyInviteLink(inviteLink),
                                icon: const Icon(Icons.copy_outlined),
                                label: Text(
                                  context.tr('household_invite_copy_link'),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => SharePlus.instance.share(
                                  ShareParams(text: inviteLink),
                                ),
                                icon: const Icon(Icons.share_outlined),
                                label: Text(
                                  context.tr('household_invite_share_link'),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: (_canManage && !_isActionLoading)
                                    ? () => _revokeInvite(invite)
                                    : null,
                                icon: const Icon(Icons.block_outlined),
                                label: Text(
                                  context.tr('household_invite_revoke'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: context.tr('household_title'),
      actions: [
        if (_household != null && _canManage)
          IconButton(
            onPressed: _isActionLoading ? null : _createInvite,
            icon: const Icon(AppIcons.add),
          ),
        IconButton(
          onPressed: _isLoading ? null : _loadData,
          icon: const Icon(AppIcons.refresh),
        ),
        if (_household != null)
          PopupMenuButton<String>(
            onSelected: _handleOverflowAction,
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              if (_canManage) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text(context.tr('household_edit_name_title')),
                  ),
                );
              }
              if (!_isOwner) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'leave',
                    child: Text(context.tr('household_leave_action')),
                  ),
                );
              }
              if (_isOwner) {
                items.add(
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(context.tr('household_delete_action')),
                  ),
                );
              }
              return items;
            },
          ),
      ],
      body: Stack(
        children: [
          _buildBody(),
          if (_isActionLoading)
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
}
