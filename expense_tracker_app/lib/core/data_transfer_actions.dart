import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import 'api_client.dart';

class DataTransferActions {
  static Future<void> exportData(BuildContext context) async {
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final data = await ApiClient.exportData();
      final jsonString = jsonEncode(data);
      final directory = await getApplicationDocumentsDirectory();
      final dateStr = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(
        '${directory.path}/ai_expense_tracker_export_$dateStr.json',
      );
      await file.writeAsString(jsonString);

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'AI Expense Tracker Export',
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': error.toString()},
            ),
          ),
        ),
      );
    }
  }

  static Future<void> importData(BuildContext context) async {
    var dialogShown = false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      if (!context.mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      dialogShown = true;

      final pickedFile = result.files.single;
      var fileBytes = pickedFile.bytes;
      if (fileBytes == null && pickedFile.path != null) {
        fileBytes = await File(pickedFile.path!).readAsBytes();
      }
      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception('Failed to read selected JSON file.');
      }

      var content = utf8.decode(fileBytes, allowMalformed: true);
      if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
        content = content.substring(1);
      }

      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid import JSON: root payload must be an object.');
      }

      await ApiClient.importData(decoded);

      if (!context.mounted) return;
      if (dialogShown && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tools_import_success'))),
      );
    } catch (error) {
      if (!context.mounted) return;
      if (dialogShown && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            context.tr(
              'common_error_with_message',
              params: {'message': error.toString()},
            ),
          ),
        ),
      );
    }
  }
}
