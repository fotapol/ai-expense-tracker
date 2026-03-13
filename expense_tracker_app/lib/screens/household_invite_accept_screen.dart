import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/invite_link_service.dart';
import '../l10n/app_localizations.dart';
import 'household_screen.dart';
import 'main_screen.dart';

class HouseholdInviteAcceptScreen extends StatefulWidget {
  const HouseholdInviteAcceptScreen({
    super.key,
    required this.inviteToken,
    this.launchedFromLink = false,
  });

  final String inviteToken;
  final bool launchedFromLink;

  @override
  State<HouseholdInviteAcceptScreen> createState() =>
      _HouseholdInviteAcceptScreenState();
}

class _HouseholdInviteAcceptScreenState extends State<HouseholdInviteAcceptScreen> {
  bool _isLoading = true;
  bool _isSuccess = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _acceptInvite();
  }

  bool _isTerminalInviteFailure(String errorText) {
    final lower = errorText.toLowerCase();
    return lower.contains(' 404 ') ||
        lower.contains(' 409 ') ||
        lower.contains(' 410 ') ||
        lower.contains('invite not found') ||
        lower.contains('already belong to another household') ||
        lower.contains('already been used') ||
        lower.contains('expired') ||
        lower.contains('revoked');
  }

  Future<void> _acceptInvite() async {
    setState(() {
      _isLoading = true;
      _isSuccess = false;
      _message = null;
    });

    try {
      await ApiClient.acceptHouseholdInvite(widget.inviteToken);
      await InviteLinkService.instance.clearPendingInviteToken();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = true;
        _message = context.tr('household_invite_accept_success');
      });
    } catch (e) {
      final errorText = e.toString();
      if (_isTerminalInviteFailure(errorText)) {
        await InviteLinkService.instance.clearPendingInviteToken();
      }
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = false;
        _message = errorText;
      });
    }
  }

  void _openHousehold() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HouseholdScreen()),
    );
  }

  void _continueToApp() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('household_invite_title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isLoading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(context.tr('household_invite_accepting')),
                  ] else ...[
                    Icon(
                      _isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                      color: _isSuccess ? Colors.green : Colors.redAccent,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _message ?? '',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _acceptInvite,
                            child: Text(context.tr('common_retry')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isSuccess ? _openHousehold : _continueToApp,
                            child: Text(
                              _isSuccess
                                  ? context.tr('household_open_screen')
                                  : context.tr('household_continue_app'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
