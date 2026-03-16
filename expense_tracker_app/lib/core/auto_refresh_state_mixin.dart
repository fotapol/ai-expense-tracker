import 'dart:async';

import 'package:flutter/widgets.dart';

mixin AutoRefreshStateMixin<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  Timer? _autoRefreshTimer;
  bool _autoRefreshInFlight = false;

  @protected
  Duration get autoRefreshInterval => const Duration(seconds: 10);

  @protected
  bool get autoRefreshEnabled => true;

  @protected
  Future<void> performAutoRefresh();

  void _restartAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    if (!autoRefreshEnabled) return;
    _autoRefreshTimer = Timer.periodic(autoRefreshInterval, (_) {
      unawaited(triggerAutoRefresh());
    });
  }

  @protected
  Future<void> triggerAutoRefresh() async {
    if (!mounted || !autoRefreshEnabled || _autoRefreshInFlight) {
      return;
    }
    _autoRefreshInFlight = true;
    try {
      await performAutoRefresh();
    } finally {
      _autoRefreshInFlight = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restartAutoRefreshTimer();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!autoRefreshEnabled) return;
    if (state == AppLifecycleState.resumed) {
      _restartAutoRefreshTimer();
      unawaited(triggerAutoRefresh());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _autoRefreshTimer?.cancel();
    }
  }
}
