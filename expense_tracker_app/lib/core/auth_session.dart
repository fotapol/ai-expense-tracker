import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

const String expiredSessionMessage =
    'Your session expired. Please sign in again.';

/// Returns true only when [message] clearly signals an auth failure.
///
/// Patterns are matched against the exact strings that the backend
/// returns in its 401 `detail` field (see `backend/app/auth/deps.py`) and
/// the sentinel values used internally by the app itself.  The old broad
/// `" 401"` match has been intentionally removed: it matched any error body
/// that happened to contain those characters (e.g. "status: 401" inside a
/// 500-error response) and caused false-positive sign-outs.
bool isExpiredSessionMessage(String? message) {
  final normalized = message?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return false;
  // Internal app sentinel.
  if (normalized.contains('session expired')) return true;
  if (normalized.contains('no authenticated user')) return true;
  // Exact backend 401 detail strings from deps.py.
  if (normalized.contains('token has expired')) return true;
  if (normalized.contains('token has been revoked')) return true;
  if (normalized.contains('invalid authentication token')) return true;
  if (normalized.contains('authentication failed')) return true;
  if (normalized.contains('token does not contain a valid uid')) return true;
  // HTTP status marker — require a word boundary so "401" inside a body
  // does not match (e.g. "returned 4010 items").
  if (normalized.contains(': 401')) return true;
  if (normalized.endsWith(' 401')) return true;
  if (normalized.contains(' 401 ')) return true;
  return false;
}

bool isExpiredSessionError(Object error) {
  return isExpiredSessionMessage(error.toString());
}

String requireAuthenticatedSessionToken(String? token) {
  final normalized = token?.trim() ?? '';
  if (normalized.isEmpty) {
    throw StateError(expiredSessionMessage);
  }
  return normalized;
}

bool shouldForceSessionTokenRefresh(
  DateTime? expirationTime, {
  DateTime Function()? nowProvider,
  Duration refreshWindow = const Duration(minutes: 5),
}) {
  if (expirationTime == null) return true;
  final now = (nowProvider ?? DateTime.now)().toUtc();
  return expirationTime.toUtc().difference(now) <= refreshWindow;
}

class SessionRestoreGate<T> extends StatelessWidget {
  const SessionRestoreGate({
    super.key,
    required this.stream,
    required this.initialValue,
    required this.isAuthenticated,
    required this.authenticatedBuilder,
    required this.unauthenticatedBuilder,
    this.loadingBuilder,
  });

  final Stream<T?> stream;
  final T? initialValue;
  final bool Function(T? value) isAuthenticated;
  final WidgetBuilder authenticatedBuilder;
  final WidgetBuilder unauthenticatedBuilder;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T?>(
      stream: stream,
      initialData: initialValue,
      builder: (context, snapshot) {
        final currentValue = snapshot.data;
        final isWaitingForFirstAuthValue =
            snapshot.connectionState == ConnectionState.waiting &&
            currentValue == null;
        if (isWaitingForFirstAuthValue) {
          return loadingBuilder?.call(context) ??
              const SizedBox.expand(child: ColoredBox(color: Colors.black));
        }
        if (isAuthenticated(currentValue)) {
          return authenticatedBuilder(context);
        }
        return unauthenticatedBuilder(context);
      },
    );
  }
}

class SessionRestoreLoadingScreen extends StatelessWidget {
  const SessionRestoreLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12031F), Color(0xFF26103A), Color(0xFF06010C)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF7D74B), Color(0xFFF59E0B)],
                      ),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      size: 36,
                      color: Color(0xFF200532),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    context.tr('session_restore_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('session_restore_body'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFF7D74B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
