import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/launch_error_copy.dart';
import '../core/localized_dates.dart';
import '../core/redesign_system.dart';
import '../l10n/app_localizations.dart';
import 'settings_detail_scaffold.dart';

const _maxFileBytes = 16 * 1024 * 1024;

enum _ImportFormat {
  tracker('.json', 'AI Expense Tracker'),
  moneyManager('.mmbackup', 'Money Manager (Orange Dog)', 'money_manager');

  const _ImportFormat(this.extension, this.name, [this.source]);

  final String extension;
  final String name;
  final String? source;

  static _ImportFormat? forFile(String filename) {
    final lower = filename.toLowerCase();
    for (final format in values) {
      if (lower.endsWith(format.extension)) return format;
    }
    return null;
  }
}

class _SelectedImport {
  const _SelectedImport({
    required this.name,
    required this.payload,
    required this.expenseCount,
    this.external = false,
    this.alreadyImported = 0,
    this.skipped = 0,
    this.totals = const {},
    this.samples = const [],
  });

  final String name;
  final Map<String, dynamic> payload;
  final int expenseCount;
  final bool external;
  final int alreadyImported;
  final int skipped;
  final Map<String, dynamic> totals;
  final List<dynamic> samples;

  int get newExpenses => expenseCount - alreadyImported;

  Map<String, dynamic> get payloadForSave {
    if (!external) return payload;
    return {
      ...payload,
      'expenses': [
        for (final expense
            in (payload['expenses'] as List).cast<Map<String, dynamic>>())
          {
            ...expense,
            'utc_offset_minutes': _localNoon(
              expense['day'] as String,
            ).timeZoneOffset.inMinutes,
          },
      ],
    };
  }

  String? categoryName(Object? uid) {
    if (uid == null) return null;
    for (final category in payload['categories'] as List) {
      if (category['uid'] == uid) return category['name'] as String;
    }
    return null;
  }
}

DateTime _localNoon(String value) {
  final day = DateTime.parse(value);
  return DateTime(day.year, day.month, day.day, 12);
}

class ImportDataScreen extends StatefulWidget {
  const ImportDataScreen({super.key});

  @override
  State<ImportDataScreen> createState() => _ImportDataScreenState();
}

class _ImportDataScreenState extends State<ImportDataScreen> {
  _SelectedImport? _selection;
  Map<String, dynamic>? _result;
  String? _error;
  bool _busy = false;

  Future<Uint8List> _readFile(PlatformFile file) async {
    if (file.size > _maxFileBytes) throw const ExternalImportException(413);
    final content = file.bytes;
    if (content != null) {
      if (content.length > _maxFileBytes) {
        throw const ExternalImportException(413);
      }
      return content;
    }
    final path = file.path;
    if (path == null) throw const FormatException();
    final handle = await File(path).open();
    try {
      final bytes = await handle.read(_maxFileBytes + 1);
      if (bytes.length > _maxFileBytes) {
        throw const ExternalImportException(413);
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Custom extensions may have no registered MIME type on Android.
      final picked = await FilePicker.pickFiles(
        type: FileType.any,
        withData: false,
      );
      if (!mounted || picked == null || picked.files.isEmpty) return;
      setState(() {
        _selection = null;
        _result = null;
      });
      final file = picked.files.single;
      final format = _ImportFormat.forFile(file.name);
      if (format == null) throw const FormatException();

      final bytes = await _readFile(file);
      if (!mounted) return;
      final source = format.source;
      final _SelectedImport selection;
      if (source != null) {
        final preview = await ApiClient.previewExternalImport(bytes, source);
        final plan = preview['plan'] as Map<String, dynamic>;
        selection = _SelectedImport(
          name: file.name,
          payload: plan,
          external: true,
          expenseCount: (plan['expenses'] as List).length,
          alreadyImported: preview['already_imported'] as int,
          skipped: preview['skipped'] as int,
          totals: preview['totals'] as Map<String, dynamic>,
          samples: preview['samples'] as List<dynamic>,
        );
      } else {
        final text = utf8.decode(bytes, allowMalformed: true);
        final decoded = jsonDecode(
          text.startsWith('\uFEFF') ? text.substring(1) : text,
        );
        if (decoded is! Map<String, dynamic> ||
            (decoded['transactions'] is! List &&
                decoded['categories'] is! List)) {
          throw const FormatException();
        }
        selection = _SelectedImport(
          name: file.name,
          payload: decoded,
          expenseCount: (decoded['transactions'] as List?)?.length ?? 0,
        );
      }
      if (mounted) setState(() => _selection = selection);
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error, preview: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error, {bool preview = false}) {
    final key = switch (error) {
      ExternalImportException(statusCode: 413) => 'data_import_large',
      ExternalImportException(statusCode: 422) when preview =>
        'data_import_invalid',
      FormatException() when preview => 'data_import_invalid',
      _ => 'data_import_failed',
    };
    return friendlyLaunchErrorMessage(
      error,
      fallback: context.tr(key),
      languageCode: Localizations.localeOf(context).languageCode,
    );
  }

  Future<void> _confirm(_SelectedImport selection) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = selection.payloadForSave;
      final result = selection.external
          ? await ApiClient.importExternalData(payload)
          : await ApiClient.importData(payload);
      if (!mounted) return;
      setState(() {
        _selection = null;
        _result = result;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _amount(String code, Object? raw) {
    final value = num.parse(raw.toString());
    return NumberFormat.currency(
      locale: Localizations.localeOf(context).toLanguageTag(),
      name: code,
      symbol: code,
      decimalDigits: 2,
    ).format(value);
  }

  Widget _count(String key, int value) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(context.tr(key)),
    trailing: Text(MaterialLocalizations.of(context).formatDecimal(value)),
  );

  Widget _preview(_SelectedImport selection) {
    final theme = Theme.of(context);
    return SettingsDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(selection.name, style: theme.textTheme.titleMedium),
          _count('data_import_new_count', selection.newExpenses),
          if (selection.external) ...[
            _count('data_import_prev_count', selection.alreadyImported),
            _count('data_import_ignored_count', selection.skipped),
            Text(
              context.tr('data_import_expenses_only'),
              style: theme.textTheme.bodySmall,
            ),
            for (final total in selection.totals.entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _amount(total.key, total.value),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            for (final sample in selection.samples.cast<Map<String, dynamic>>())
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  [
                    if (sample['description'] case final String text) text,
                    if (selection.categoryName(sample['category_uid'])
                        case final String category)
                      category,
                    formatLocalizedDayMonthYear(
                      context,
                      _localNoon(sample['day'] as String),
                    ),
                    _amount(sample['currency'] as String, sample['amount']),
                  ].join(' · '),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    final result = _result;
    final error = _error;
    return SettingsDetailScaffold(
      title: context.tr('tools_import_data'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SettingsDetailCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(context.tr('data_import_before_preview')),
                      const SizedBox(height: 8),
                      for (final format in _ImportFormat.values)
                        Text('${format.name} · ${format.extension}'),
                      const SizedBox(height: 8),
                      Text(
                        context.tr('data_import_backup_processing'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickFile,
                        icon: const Icon(AppIcons.importData),
                        label: Text(context.tr('data_import_choose')),
                      ),
                    ],
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  SettingsDetailCard(
                    child: Text(
                      error,
                      style: TextStyle(color: ShellStyles.error(context)),
                    ),
                  ),
                ],
                if (selection != null) ...[
                  const SizedBox(height: 16),
                  _preview(selection),
                ],
                if (result != null) ...[
                  const SizedBox(height: 16),
                  SettingsDetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('tools_import_success')),
                        if (result['imported'] case final int count)
                          _count('data_import_added_count', count),
                        if (result['already_imported'] case final int count)
                          _count('data_import_prev_count', count),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (selection != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _busy || selection.external && selection.newExpenses <= 0
                      ? null
                      : () => _confirm(selection),
                  child: Text(context.tr('tools_import_data')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
