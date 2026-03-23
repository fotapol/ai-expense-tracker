import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'analytics_tab.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        title: Text(context.tr('tools_analytics')),
        centerTitle: false,
      ),
      body: const AnalyticsTab(showTopBar: false),
    );
  }
}
