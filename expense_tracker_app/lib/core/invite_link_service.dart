// TODO(household): disabled for single-user launch

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks household invite links and persists the latest pending token.
class InviteLinkService extends ChangeNotifier {
  InviteLinkService._();

  static final InviteLinkService instance = InviteLinkService._();
  static const String _pendingInviteTokenKey = 'pending_household_invite_token';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  bool _initialized = false;
  String? _pendingInviteToken;

  String? get pendingInviteToken => _pendingInviteToken;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_pendingInviteTokenKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _pendingInviteToken = stored.trim();
    }

    final initialUri = await _appLinks.getInitialLink();
    await _ingestUri(initialUri);

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) async => _ingestUri(uri),
      onError: (_) {},
    );
  }

  Future<void> _ingestUri(Uri? uri) async {
    if (uri == null) return;
    final token = _extractToken(uri);
    if (token == null) return;
    await setPendingInviteToken(token);
  }

  String? _extractToken(Uri uri) {
    final normalizedPath = uri.path.toLowerCase().replaceFirst(RegExp(r'/$'), '');
    if (normalizedPath != '/household-invite') return null;

    final token = uri.queryParameters['token']?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> setPendingInviteToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) return;
    if (_pendingInviteToken == normalized) return;

    _pendingInviteToken = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInviteTokenKey, normalized);
    notifyListeners();
  }

  Future<void> clearPendingInviteToken() async {
    if (_pendingInviteToken == null) return;
    _pendingInviteToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInviteTokenKey);
    notifyListeners();
  }

  Future<void> disposeService() async {
    await _linkSubscription?.cancel();
    _linkSubscription = null;
  }
}
