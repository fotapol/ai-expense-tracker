import 'package:flutter/material.dart';

import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'receipts_tab.dart';

class ReceiptManagerScreen extends StatelessWidget {
  const ReceiptManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      appBar: AppBar(
        title: Text(context.tr('tools_receipt_manager')),
        centerTitle: false,
      ),
      body: const ReceiptsTab(showTopBar: false),
    );
  }
}
