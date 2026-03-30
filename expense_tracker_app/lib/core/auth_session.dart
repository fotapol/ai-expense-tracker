import 'package:flutter/material.dart';

const String expiredSessionMessage =
    'Your session expired. Please sign in again.';

bool isExpiredSessionMessage(String? message) {
  final normalized = message?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) return false;
  return normalized.contains('session expired') ||
      normalized.contains('no authenticated user') ||
      normalized.contains(' 401') ||
      normalized.contains(': 401');
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
                  const Text(
                    'Checking your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Securing your receipts and restoring your session.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
