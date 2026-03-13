import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_client.dart';
import '../l10n/app_localizations.dart';
import 'subscription_screen.dart';

class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  static const String _familyPlanFeatureCode = 'premium.family_plan';

  bool _isLoading = true;
  bool _isActionLoading = false;
  String? _error;

  Map<String, dynamic>? _me;
  Map<String, dynamic>? _household;
  List<dynamic> _members = const [];
  List<dynamic> _invites = const [];
  Set<String> _featureCodes = const {};

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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

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
      } catch (e) {
        if (_extractStatusCode(e) != 404) rethrow;
      }

      if (household != null) {
        members = await ApiClient.listCurrentHouseholdMembers();
        final myUserId = me['id']?.toString() ?? '';
        final myMembership = members.whereType<Map<String, dynamic>>().firstWhere(
          (member) => member['user_id']?.toString() == myUserId,
          orElse: () => const <String, dynamic>{},
        );
        final myRole = myMembership['role']?.toString() ?? '';
        if (myRole == 'owner') {
          try {
            invites = await ApiClient.listCurrentHouseholdInvites();
          } catch (e) {
            final statusCode = _extractStatusCode(e);
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createHousehold() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
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
      builder: (ctx) => AlertDialog(
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
    if (name == null || name.isEmpty) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.updateCurrentHousehold(name: name);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_updated_success'))),
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _createInvite() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(context.tr('household_invite_send')),
          ),
        ],
      ),
    );

    if (email == null || email.isEmpty) return;
    setState(() => _isActionLoading = true);
    try {
      final invite = await ApiClient.createHouseholdInvite(invitedEmail: email);
      if (!mounted) return;
      final inviteLink = invite['invite_link']?.toString().trim() ?? '';
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_invite_created'))),
      );
      if (inviteLink.isNotEmpty) {
        await showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('household_invite_share_title'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: inviteLink));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.tr('household_invite_link_copied')),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(context.tr('household_invite_copy_link')),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(text: inviteLink),
                    ),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(context.tr('household_invite_share_link')),
                  ),
                ],
              ),
            ),
          ),
        );
      }
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _revokeInvite(Map<String, dynamic> invite) async {
    final inviteId = invite['id']?.toString() ?? '';
    if (inviteId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('household_invite_revoke_title')),
        content: Text(context.tr('household_invite_revoke_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.revokeHouseholdInvite(inviteId);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_invite_revoked'))),
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
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final memberId = member['id']?.toString() ?? '';
    if (memberId.isEmpty) return;

    final user = member['user'];
    final displayName = (user is Map<String, dynamic>
            ? user['display_name']?.toString()
            : null) ??
        (user is Map<String, dynamic> ? user['email']?.toString() : null) ??
        context.tr('common_unknown');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('household_remove_member_title')),
        content: Text(
          context.tr(
            'household_remove_member_confirm',
            params: {'name': displayName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('common_delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isActionLoading = true);
    try {
      await ApiClient.removeHouseholdMember(memberId);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('household_member_removed'))),
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

  Widget _buildLockedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('household_locked_title'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(context.tr('household_locked_subtitle')),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubscriptionScreen(
                    currentUserId: _me?['id']?.toString(),
                  ),
                ),
              );
            },
            child: Text(context.tr('household_upgrade_cta')),
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
              ElevatedButton(
                onPressed: _loadData,
                child: Text(context.tr('common_retry')),
              ),
            ],
          ),
        ),
      );
    }

    if (_household == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr('household_empty_title'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(context.tr('household_empty_subtitle')),
          const SizedBox(height: 16),
          if (!_hasFamilyPlan) ...[
            _buildLockedBanner(),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: (_hasFamilyPlan && !_isActionLoading) ? _createHousehold : null,
            icon: const Icon(Icons.group_add_outlined),
            label: Text(context.tr('household_create_cta')),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('household_join_via_link_only'),
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      );
    }

    final householdName = _household?['name']?.toString() ?? context.tr('common_unknown');
    final role = _currentMembership()?['role']?.toString() ?? 'member';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        householdName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_isOwner)
                      IconButton(
                        onPressed: (_canManage && !_isActionLoading)
                            ? _editHouseholdName
                            : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                  ],
                ),
                Text(
                  context.tr(
                    'household_role_label',
                    params: {'role': _roleLabel(role)},
                  ),
                ),
                if (_isOwner && !_hasFamilyPlan) ...[
                  const SizedBox(height: 12),
                  _buildLockedBanner(),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('household_members_title'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._members.whereType<Map<String, dynamic>>().map((member) {
            final user = member['user'];
            final name = user is Map<String, dynamic>
                ? user['display_name']?.toString()
                : null;
            final email = user is Map<String, dynamic>
                ? user['email']?.toString()
                : null;
            final display = (name != null && name.trim().isNotEmpty)
                ? name.trim()
                : (email ?? context.tr('common_unknown'));
            final memberRole = member['role']?.toString() ?? 'member';
            final removable = _canManage && memberRole != 'owner';
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    display.isNotEmpty ? display.substring(0, 1).toUpperCase() : '?',
                  ),
                ),
                title: Text(display),
                subtitle: Text(_roleLabel(memberRole)),
                trailing: removable
                    ? IconButton(
                        onPressed: _isActionLoading ? null : () => _removeMember(member),
                        icon: const Icon(Icons.person_remove_alt_1_outlined),
                      )
                    : null,
              ),
            );
          }),
          if (_isOwner) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('household_invites_title'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: (_canManage && !_isActionLoading) ? _createInvite : null,
                  icon: const Icon(Icons.mail_outline),
                  label: Text(context.tr('household_invite_add')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_invites.isEmpty)
              Text(
                context.tr('household_invites_empty'),
                style: TextStyle(color: Colors.grey.shade500),
              )
            else
              ..._invites.whereType<Map<String, dynamic>>().map((invite) {
                final state = invite['effective_state']?.toString() ?? 'pending';
                final stateColor = _stateColor(state);
                final invitedEmail = invite['invited_email']?.toString();
                final invitedUser = invite['invited_user'];
                final invitedDisplay = invitedUser is Map<String, dynamic>
                    ? (invitedUser['display_name']?.toString() ??
                        invitedUser['email']?.toString())
                    : invitedEmail;
                final inviteLink = invite['invite_link']?.toString().trim() ?? '';

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                invitedDisplay ?? context.tr('common_unknown'),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: stateColor.withAlpha(25),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: stateColor.withAlpha(120)),
                              ),
                              child: Text(
                                _stateLabel(state),
                                style: TextStyle(color: stateColor, fontSize: 12),
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
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                        ),
                        if (state == 'pending' && inviteLink.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: inviteLink),
                                  );
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context.tr('household_invite_link_copied'),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_outlined),
                                label: Text(context.tr('household_invite_copy_link')),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => SharePlus.instance.share(
                                  ShareParams(text: inviteLink),
                                ),
                                icon: const Icon(Icons.share_outlined),
                                label: Text(context.tr('household_invite_share_link')),
                              ),
                              OutlinedButton.icon(
                                onPressed: (_canManage && !_isActionLoading)
                                    ? () => _revokeInvite(invite)
                                    : null,
                                icon: const Icon(Icons.block_outlined),
                                label: Text(context.tr('household_invite_revoke')),
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
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('household_title')),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
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
