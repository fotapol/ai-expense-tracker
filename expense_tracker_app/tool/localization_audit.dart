import 'dart:io';

void main(List<String> args) {
  final appRoot = _findAppRoot();
  final localizationFile = File(
    '${appRoot.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}l10n'
    '${Platform.pathSeparator}app_localizations.dart',
  );
  if (!localizationFile.existsSync()) {
    stderr.writeln('Could not find lib/l10n/app_localizations.dart.');
    exitCode = 1;
    return;
  }

  final source = localizationFile.readAsStringSync();
  final locales = _extractSupportedLocales(source);
  final translationKeys = _extractTranslationKeys(source);
  final englishKeys = translationKeys['en'] ?? const <String>{};
  final usedKeys = _extractRuntimeKeys(Directory('${appRoot.path}/lib'));
  final usedEnglishKeys = usedKeys.intersection(englishKeys);
  final unknownUsedKeys = usedKeys.difference(englishKeys);
  final showMissing = args.contains('--show-missing');
  final failOnMissingUsed = args.contains('--fail-on-missing-used');
  final strict = args.contains('--strict');
  final qualityIssues = _collectQualityIssues(
    locales,
    translationKeys,
    source,
    englishKeys,
  );

  stdout.writeln('Localization coverage');
  stdout.writeln('App root: ${appRoot.path}');
  stdout.writeln('English keys: ${englishKeys.length}');
  stdout.writeln('Runtime keys: ${usedEnglishKeys.length}');
  stdout.writeln('Supported locales: ${locales.length}');
  stdout.writeln('');

  _printTable([
    [
      'Locale',
      'Runtime keys',
      'Missing runtime',
      'Runtime %',
      'All keys',
      'Missing all',
      'All %',
    ],
    for (final locale in locales)
      _coverageRow(
        locale,
        translationKeys[locale] ?? const {},
        englishKeys,
        usedEnglishKeys,
      ),
  ]);

  if (unknownUsedKeys.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Warning: runtime keys missing from English:');
    for (final key in unknownUsedKeys.toList()..sort()) {
      stdout.writeln('- $key');
    }
  }

  if (showMissing) {
    stdout.writeln('');
    stdout.writeln('Missing runtime keys by locale');
    for (final locale in locales) {
      final keys = translationKeys[locale] ?? const <String>{};
      final missing = usedEnglishKeys.difference(keys).toList()..sort();
      if (missing.isEmpty) {
        stdout.writeln('$locale: none');
        continue;
      }
      stdout.writeln('$locale: ${missing.length}');
      for (final key in missing) {
        stdout.writeln('  - $key');
      }
    }
  }

  if (strict || args.contains('--show-quality')) {
    stdout.writeln('');
    stdout.writeln('Quality checks');
    if (qualityIssues.isEmpty) {
      stdout.writeln('No quality issues found.');
    } else {
      for (final issue in qualityIssues) {
        stdout.writeln('- $issue');
      }
    }
  }

  if (failOnMissingUsed || strict) {
    final hasMissing = locales.any((locale) {
      final keys = translationKeys[locale] ?? const <String>{};
      return usedEnglishKeys.difference(keys).isNotEmpty;
    });
    if (hasMissing || unknownUsedKeys.isNotEmpty || qualityIssues.isNotEmpty) {
      exitCode = 1;
    }
  }
}

Directory _findAppRoot() {
  final current = Directory.current;
  if (File('${current.path}/lib/l10n/app_localizations.dart').existsSync()) {
    return current;
  }
  final nested = Directory('${current.path}/expense_tracker_app');
  if (File('${nested.path}/lib/l10n/app_localizations.dart').existsSync()) {
    return nested;
  }
  return current;
}

List<String> _extractSupportedLocales(String source) {
  final match = RegExp(
    r'static const supportedLocales = <Locale>\[(.*?)\];',
    dotAll: true,
  ).firstMatch(source);
  if (match == null) return const ['en'];
  return RegExp(
    r"Locale\('([a-z]{2})'\)",
  ).allMatches(match.group(1)!).map((match) => match.group(1)!).toList();
}

Map<String, Set<String>> _extractTranslationKeys(String source) {
  return _extractTranslationValues(
    source,
  ).map((locale, values) => MapEntry(locale, values.keys.toSet()));
}

Map<String, Map<String, String>> _extractTranslationValues(String source) {
  final translationsStart = source.indexOf(
    'static const Map<String, Map<String, String>> _translations = {',
  );
  if (translationsStart == -1) return const {};

  final body = source.substring(translationsStart);
  final result = <String, Map<String, String>>{};
  final languagePattern = RegExp(r"\n\s*'([a-z]{2})':\s*\{");
  for (final match in languagePattern.allMatches(body)) {
    final locale = match.group(1)!;
    final blockStart = match.end - 1;
    final blockEnd = _findMatchingBrace(body, blockStart);
    if (blockEnd == -1) continue;
    final block = body.substring(blockStart + 1, blockEnd);
    result[locale] = _parseEntries(block);
  }
  return result;
}

Map<String, String> _parseEntries(String block) {
  final matches = RegExp(r"\n\s*'([^']+)':").allMatches(block).toList();
  final entries = <String, String>{};
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final key = match.group(1)!;
    final start = match.end;
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : block.length;
    final expression = block
        .substring(start, end)
        .trim()
        .replaceFirst(RegExp(r',$'), '');
    entries[key] = _decodeDartStringExpression(expression);
  }
  return entries;
}

String _decodeDartStringExpression(String expression) {
  final pieces = RegExp(
    r"'((?:\\.|[^'\\])*)'",
    dotAll: true,
  ).allMatches(expression);
  return pieces.map((match) => _decodeDartEscapes(match.group(1)!)).join();
}

String _decodeDartEscapes(String value) {
  return value
      .replaceAll(r"\'", "'")
      .replaceAll(r'\"', '"')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\\', '\\');
}

Set<String> _extractRuntimeKeys(Directory libDirectory) {
  if (!libDirectory.existsSync()) return const {};
  final keys = <String>{};
  final dartFiles = libDirectory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  final trPattern = RegExp(r"(?:\.tr|AppLocalizations\.lookup)\(\s*'([^']+)'");
  for (final file in dartFiles) {
    final source = file.readAsStringSync();
    for (final match in trPattern.allMatches(source)) {
      keys.add(match.group(1)!);
    }
  }
  return keys;
}

int _findMatchingBrace(String source, int openBraceIndex) {
  var depth = 0;
  var inString = false;
  var quote = '';
  var escaped = false;

  for (var index = openBraceIndex; index < source.length; index++) {
    final char = source[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == quote) {
        inString = false;
      }
      continue;
    }

    if (char == "'" || char == '"') {
      inString = true;
      quote = char;
    } else if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return index;
    }
  }
  return -1;
}

List<String> _coverageRow(
  String locale,
  Set<String> localeKeys,
  Set<String> englishKeys,
  Set<String> usedEnglishKeys,
) {
  final missingRuntime = usedEnglishKeys.difference(localeKeys).length;
  final translatedRuntime = usedEnglishKeys.length - missingRuntime;
  final missingAll = englishKeys.difference(localeKeys).length;
  final translatedAll = englishKeys.length - missingAll;
  return [
    locale,
    '$translatedRuntime/${usedEnglishKeys.length}',
    '$missingRuntime',
    _percent(translatedRuntime, usedEnglishKeys.length),
    '$translatedAll/${englishKeys.length}',
    '$missingAll',
    _percent(translatedAll, englishKeys.length),
  ];
}

String _percent(int value, int total) {
  if (total == 0) return '100.0%';
  return '${(value * 100 / total).toStringAsFixed(1)}%';
}

List<String> _collectQualityIssues(
  List<String> locales,
  Map<String, Set<String>> translationKeys,
  String source,
  Set<String> englishKeys,
) {
  final valuesByLocale = _extractTranslationValues(source);
  final englishValues = valuesByLocale['en'] ?? const <String, String>{};
  final issues = <String>[];

  for (final locale in locales) {
    final keys = translationKeys[locale] ?? const <String>{};
    final values = valuesByLocale[locale] ?? const <String, String>{};
    final missing = englishKeys.difference(keys);
    if (missing.isNotEmpty) {
      issues.add('$locale: missing ${missing.length} keys');
    }

    final duplicates = _duplicateKeysForLocale(source, locale);
    if (duplicates.isNotEmpty) {
      issues.add('$locale: duplicate keys ${duplicates.take(10).join(', ')}');
    }

    for (final key in keys.intersection(englishKeys)) {
      final english = englishValues[key] ?? '';
      final localized = values[key] ?? '';
      final placeholderMismatch = _placeholderSet(
        english,
      ).symmetricDifference(_placeholderSet(localized));
      if (placeholderMismatch.isNotEmpty) {
        issues.add(
          '$locale/$key: placeholder mismatch ${placeholderMismatch.join(', ')}',
        );
      }

      if (locale != 'en' &&
          localized == english &&
          !_isAllowedSharedValue(key, localized)) {
        issues.add('$locale/$key: untranslated English value');
      }

      final mojibake = _mojibakeTokens(localized);
      if (mojibake.isNotEmpty) {
        issues.add('$locale/$key: mojibake tokens ${mojibake.join(', ')}');
      }

      if (_hasSuspiciousQuestionMarks(localized)) {
        issues.add('$locale/$key: suspicious replacement question marks');
      }

      final scriptIssue = _scriptIssue(locale, key, localized);
      if (scriptIssue != null) {
        issues.add('$locale/$key: $scriptIssue');
      }
    }
  }

  return issues;
}

Set<String> _duplicateKeysForLocale(String source, String locale) {
  final translationsStart = source.indexOf(
    'static const Map<String, Map<String, String>> _translations = {',
  );
  if (translationsStart == -1) return const {};
  final body = source.substring(translationsStart);
  final match = RegExp(r"\n\s*'" + locale + r"':\s*\{").firstMatch(body);
  if (match == null) return const {};
  final blockStart = match.end - 1;
  final blockEnd = _findMatchingBrace(body, blockStart);
  if (blockEnd == -1) return const {};
  final block = body.substring(blockStart + 1, blockEnd);
  final seen = <String>{};
  final duplicates = <String>{};
  for (final keyMatch in RegExp(r"\n\s*'([^']+)':").allMatches(block)) {
    final key = keyMatch.group(1)!;
    if (!seen.add(key)) duplicates.add(key);
  }
  return duplicates;
}

Set<String> _placeholderSet(String value) {
  return {
    for (final match in RegExp(r'\{[^}]+\}').allMatches(value)) match.group(0)!,
  };
}

extension _SetCompare<T> on Set<T> {
  Set<T> symmetricDifference(Set<T> other) {
    return {...difference(other), ...other.difference(this)};
  }
}

bool _isAllowedSharedValue(String key, String value) {
  if (value.trim().isEmpty) return true;
  if (RegExp(r'^month_(?:full|short)_\d{2}$').hasMatch(key)) return true;
  if (RegExp(r'^\{[^}]+\}$').hasMatch(value.trim())) return true;
  if (RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  ).hasMatch(value.trim())) {
    return true;
  }
  if (RegExp(r'^[A-Z0-9 .:+\-/&]+$').hasMatch(value)) return true;
  const sharedKeys = {
    'app_title',
    'common_no',
    'settings_account_type_pro',
    'settings_beta_feature',
    'settings_theme_auto',
    'settings_accent_neutral',
    'settings_accent_blue',
    'settings_accent_violet',
    'settings_accent_green',
    'settings_accent_amber',
    'settings_accent_red',
    'billing_best_value',
    'billing_period_monthly',
    'billing_period_yearly',
    'transaction_item',
    'upload_camera',
  };
  return sharedKeys.contains(key);
}

Set<String> _mojibakeTokens(String value) {
  final tokens = <String>{};
  const suspiciousCodePoints = {
    0x00C3: 'Ã',
    0x00D0: 'Ð',
    0x00D1: 'Ñ',
    0xFFFD: '�',
  };
  for (final entry in suspiciousCodePoints.entries) {
    if (value.runes.contains(entry.key)) tokens.add(entry.value);
  }
  if (value.contains('â€') || value.contains('â€™') || value.contains('â€œ')) {
    tokens.add('â€');
  }
  if (RegExp(r'Â(?:[¿¡«»©®]|\s|$)').hasMatch(value)) {
    tokens.add('Â');
  }
  return tokens;
}

bool _hasSuspiciousQuestionMarks(String value) {
  if (RegExp(r'\?{2,}').hasMatch(value)) return true;
  for (var index = 0; index < value.length; index++) {
    if (value[index] != '?') continue;
    final previous = index > 0 ? value[index - 1] : '';
    final next = index + 1 < value.length ? value[index + 1] : '';
    if (_isLetter(next)) return true;
    if (_isLetter(previous) &&
        next.isNotEmpty &&
        !RegExp(r'[\s\]})"”».,;:!?]').hasMatch(next)) {
      return true;
    }
  }
  return false;
}

bool _isLetter(String value) {
  if (value.isEmpty) return false;
  return RegExp(r'[A-Za-zÀ-ž\u0400-\u04FF]').hasMatch(value);
}

String? _scriptIssue(String locale, String key, String value) {
  final normalized = _stripAllowedLatin(value);
  final latin = _countMatches(normalized, RegExp(r'[A-Za-z]'));
  final cyrillic = _countMatches(normalized, RegExp(r'[\u0400-\u04FF]'));
  final arabic = _countMatches(normalized, RegExp(r'[\u0600-\u06FF]'));
  final devanagari = _countMatches(normalized, RegExp(r'[\u0900-\u097F]'));
  final cjk = _countMatches(normalized, RegExp(r'[\u4E00-\u9FFF]'));
  final kana = _countMatches(normalized, RegExp(r'[\u3040-\u30FF]'));
  final hangul = _countMatches(normalized, RegExp(r'[\uAC00-\uD7AF]'));

  if (locale == 'uk' || locale == 'ru') {
    if (latin > 24 && cyrillic == 0 && !_isMostlyTechnical(value)) {
      return 'looks Latin-only for a Cyrillic locale';
    }
    return null;
  }

  if (locale == 'zh' && latin > 12 && cjk == 0 && !_isMostlyTechnical(value)) {
    return 'looks Latin-only for Chinese';
  }
  if (locale == 'ja' &&
      latin > 12 &&
      cjk + kana == 0 &&
      !_isMostlyTechnical(value)) {
    return 'looks Latin-only for Japanese';
  }
  if (locale == 'ko' &&
      latin > 12 &&
      hangul == 0 &&
      !_isMostlyTechnical(value)) {
    return 'looks Latin-only for Korean';
  }
  if (locale == 'hi' &&
      latin > 12 &&
      devanagari == 0 &&
      !_isMostlyTechnical(value)) {
    return 'looks Latin-only for Hindi';
  }
  if (locale == 'ar' &&
      latin > 12 &&
      arabic == 0 &&
      !_isMostlyTechnical(value)) {
    return 'looks Latin-only for Arabic';
  }

  const latinLocales = {
    'de',
    'fr',
    'it',
    'pl',
    'sr',
    'pt',
    'tr',
    'nl',
    'sv',
    'cs',
    'ro',
    'hu',
    'id',
    'ms',
    'vi',
    'es',
  };
  if (latinLocales.contains(locale) && cyrillic > 0) {
    return 'contains Cyrillic in a Latin-script locale';
  }
  return null;
}

String _stripAllowedLatin(String value) {
  return value
      .replaceAll(RegExp(r'\{[^}]+\}'), ' ')
      .replaceAll(
        RegExp(
          r'\b(AI|Pro|Premium|RevenueCat|Google|JPG|PNG|GIF|PDF|CSV|EUR|USD|RSD|HTTP|URL)\b',
        ),
        ' ',
      )
      .replaceAll(
        RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
        ' ',
      );
}

bool _isMostlyTechnical(String value) {
  final stripped = _stripAllowedLatin(value).trim();
  if (stripped.isEmpty) return true;
  return RegExp(r'^[0-9\s.,:+\-/&()]+$').hasMatch(stripped);
}

int _countMatches(String value, RegExp pattern) {
  return pattern.allMatches(value).length;
}

void _printTable(List<List<String>> rows) {
  final widths = <int>[];
  for (final row in rows) {
    for (var index = 0; index < row.length; index++) {
      if (widths.length <= index) widths.add(0);
      if (row[index].length > widths[index]) widths[index] = row[index].length;
    }
  }

  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    stdout.writeln(
      [
        for (var index = 0; index < row.length; index++)
          row[index].padRight(widths[index]),
      ].join('  '),
    );
    if (rowIndex == 0) {
      stdout.writeln(
        [for (final width in widths) ''.padRight(width, '-')].join('  '),
      );
    }
  }
}
