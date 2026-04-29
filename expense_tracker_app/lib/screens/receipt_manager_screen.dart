import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../core/period_filter.dart';
import '../l10n/app_localizations.dart';
import 'receipts_tab.dart';

class ReceiptManagerScreen extends StatelessWidget {
  const ReceiptManagerScreen({super.key, this.reviewOnly = false});

  final bool reviewOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        title: Text(context.tr('tools_receipt_manager')),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: ReceiptsTab(
          showTopBar: true,
          includeTopSafeArea: false,
          initialReviewOnly: reviewOnly,
          initialPeriod: reviewOnly ? PeriodFilter.thisMonth : null,
        ),
      ),
    );
  }
}
