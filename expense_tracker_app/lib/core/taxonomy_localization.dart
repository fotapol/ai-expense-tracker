import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

String _normalizeTaxonomyToken(String value) {
  final lowered = value.trim().toLowerCase().replaceAll('&', ' and ');
  final underscored = lowered.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return underscored
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String localizeCategoryByCode(
  BuildContext context, {
  String? code,
  String? fallbackName,
}) {
  String? normalized = code?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    final fallback = fallbackName?.trim();
    if (fallback != null && fallback.isNotEmpty) {
      normalized = _normalizeTaxonomyToken(fallback);
    }
  }

  if (normalized != null && normalized.isNotEmpty) {
    final localizations = AppLocalizations.of(context);
    final key = 'taxonomy_$normalized';
    final translated = localizations.tr(key);
    if (translated != key) return translated;

    final codeKey = 'taxonomy_${normalized.toUpperCase().toLowerCase()}';
    final translatedCode = localizations.tr(codeKey);
    if (translatedCode != codeKey) return translatedCode;
  }

  final trimmed = fallbackName?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return AppLocalizations.of(context).tr('common_unknown');
}
