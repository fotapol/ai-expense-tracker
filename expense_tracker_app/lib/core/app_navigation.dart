import 'package:flutter/material.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();
final appShellTabIndex = ValueNotifier<int>(0);

void selectRootTab(int index) {
  final normalized = index < 0
      ? 0
      : index > 2
      ? 2
      : index;
  if (appShellTabIndex.value != normalized) {
    appShellTabIndex.value = normalized;
  }
}
