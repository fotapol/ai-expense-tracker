import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app_navigation.dart';
import 'auth_session.dart';
import 'revenuecat_service.dart';
import 'subscription_confirmation.dart';

String? _pendingLoginNotice;
bool _isInvalidatingSession = false;

void primePendingLoginNotice(String message) {
  final normalized = message.trim();
  _pendingLoginNotice = normalized.isEmpty ? expiredSessionMessage : normalized;
}

String? consumePendingLoginNotice() {
  final pending = _pendingLoginNotice;
  _pendingLoginNotice = null;
  return pending;
}

void _popToRootRoute() {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.popUntil((route) => route.isFirst);
}

Future<void> invalidateExpiredSession({
  String message = expiredSessionMessage,
}) async {
  primePendingLoginNotice(message);
  _popToRootRoute();
  if (_isInvalidatingSession) return;

  _isInvalidatingSession = true;
  try {
    await clearOptimisticPremiumAccess();
    try {
      await RevenueCatService.logOut();
    } catch (_) {}
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  } finally {
    _isInvalidatingSession = false;
  }
}

Future<bool> maybeHandleExpiredSession(Object error) async {
  if (!isExpiredSessionError(error)) return false;
  await invalidateExpiredSession();
  return true;
}
