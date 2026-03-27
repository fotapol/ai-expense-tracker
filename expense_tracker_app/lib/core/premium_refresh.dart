import 'dart:async';

class PremiumRefreshController {
  PremiumRefreshController({
    this.minimumRefreshInterval = const Duration(minutes: 5),
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final Duration minimumRefreshInterval;
  final DateTime Function() _nowProvider;

  DateTime? _lastRefreshStartedAt;
  Future<void>? _inFlightRefresh;

  bool shouldRefreshOnResume({
    required bool isSignedIn,
    required bool isBillingAvailable,
  }) {
    if (!isSignedIn || !isBillingAvailable) {
      return false;
    }

    final lastRefreshStartedAt = _lastRefreshStartedAt;
    if (lastRefreshStartedAt == null) {
      return true;
    }

    return _nowProvider().difference(lastRefreshStartedAt) >=
        minimumRefreshInterval;
  }

  Future<void> refreshOnResume({
    required bool isSignedIn,
    required bool isBillingAvailable,
    required Future<void> Function() refreshAction,
  }) {
    if (!shouldRefreshOnResume(
      isSignedIn: isSignedIn,
      isBillingAvailable: isBillingAvailable,
    )) {
      return _inFlightRefresh ?? Future<void>.value();
    }

    final inFlightRefresh = _inFlightRefresh;
    if (inFlightRefresh != null) {
      return inFlightRefresh;
    }

    _lastRefreshStartedAt = _nowProvider();
    final refresh = Future<void>(() async {
      try {
        await refreshAction();
      } catch (_) {}
    }).whenComplete(() {
      _inFlightRefresh = null;
    });
    _inFlightRefresh = refresh;
    return refresh;
  }
}
