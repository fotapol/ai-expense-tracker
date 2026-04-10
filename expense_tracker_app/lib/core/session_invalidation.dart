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

/// Clears the local Firebase session and RevenueCat state without touching
/// the Google Sign-In account association.
///
/// Use this for 401s that are likely caused by transient backend issues after
/// a failed token-refresh retry.  The user will be returned to the login
/// screen but the Google account remains linked, so the next sign-in attempt
/// can use [GoogleSignIn.instance.attemptSilentSignIn] instead of showing the
/// full account picker.
Future<void> clearFirebaseSession({
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
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  } finally {
    _isInvalidatingSession = false;
  }
}

/// Full sign-out: clears Firebase session AND the Google account association.
///
/// Use this for user-initiated sign-outs and confirmed truly-revoked sessions.
/// After this call the user must interact with the Google account picker to
/// sign back in.
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
