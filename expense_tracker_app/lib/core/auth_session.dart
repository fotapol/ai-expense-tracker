import 'package:flutter/widgets.dart';

const String expiredSessionMessage =
    'Your session expired. Please sign in again.';

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
  });

  final Stream<T?> stream;
  final T? initialValue;
  final bool Function(T? value) isAuthenticated;
  final WidgetBuilder authenticatedBuilder;
  final WidgetBuilder unauthenticatedBuilder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T?>(
      stream: stream,
      initialData: initialValue,
      builder: (context, snapshot) {
        final currentValue = snapshot.data;
        if (isAuthenticated(currentValue)) {
          return authenticatedBuilder(context);
        }
        return unauthenticatedBuilder(context);
      },
    );
  }
}
