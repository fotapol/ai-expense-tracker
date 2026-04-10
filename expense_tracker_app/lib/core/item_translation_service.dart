import 'dart:async';

import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'api_client.dart';

class ItemTranslationResult {
  const ItemTranslationResult({
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
}

class ItemTranslationService {
  ItemTranslationService._();

  static final ItemTranslationService instance = ItemTranslationService._();

  final LanguageIdentifier _languageIdentifier = LanguageIdentifier(
    confidenceThreshold: 0.5,
  );
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();

  final Map<String, ItemTranslationResult?> _memoryCache = {};
  final Map<String, Future<ItemTranslationResult?>> _inFlight = {};
  final Map<String, Map<String, String>> _pendingBatchByKey = {};
  Timer? _flushTimer;
  bool _isFlushing = false;

  String normalizeLanguageCode(String? raw) {
    if (raw == null) return '';
    final normalized = raw.trim().toLowerCase().replaceAll('_', '-');
    if (normalized.isEmpty) return '';
    if (normalized.contains('-')) {
      return normalized.split('-').first;
    }
    return normalized;
  }

  String normalizeSourceText(String raw) {
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool shouldRetranslate({
    required String translatedText,
    required String expectedSourceLanguage,
    required String expectedTargetLanguage,
    String? translatedSourceLanguage,
    String? translatedTargetLanguage,
  }) {
    final normalizedTranslation = translatedText.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (normalizedTranslation.isEmpty) {
      return true;
    }

    String normalizeCode(String? raw) {
      if (raw == null) return '';
      final normalized = raw.trim().toLowerCase().replaceAll('_', '-');
      if (normalized.isEmpty) return '';
      if (normalized.contains('-')) {
        return normalized.split('-').first;
      }
      return normalized;
    }

    final normalizedExpectedSource = normalizeCode(expectedSourceLanguage);
    final normalizedExpectedTarget = normalizeCode(expectedTargetLanguage);
    final normalizedStoredSource = normalizeCode(translatedSourceLanguage);
    final normalizedStoredTarget = normalizeCode(translatedTargetLanguage);

    if (normalizedStoredTarget.isEmpty ||
        normalizedStoredTarget != normalizedExpectedTarget) {
      return true;
    }

    if (normalizedExpectedSource.isEmpty) {
      return normalizedStoredSource.isEmpty;
    }

    return normalizedStoredSource != normalizedExpectedSource;
  }

  Future<ItemTranslationResult?> translate({
    required String sourceText,
    required String targetLanguage,
    String? sourceLanguage,
    bool forceRefresh = false,
  }) async {
    final normalizedSourceText = normalizeSourceText(sourceText);
    if (normalizedSourceText.isEmpty) return null;

    final normalizedTarget = normalizeLanguageCode(targetLanguage);
    if (normalizedTarget.isEmpty) return null;

    var normalizedSource = normalizeLanguageCode(sourceLanguage);
    if (normalizedSource.isEmpty) {
      normalizedSource = await _detectLanguage(normalizedSourceText);
      if (normalizedSource.isEmpty) return null;
    }

    if (normalizedSource == normalizedTarget) {
      return null;
    }

    final key = '$normalizedSourceText|$normalizedSource|$normalizedTarget';
    if (forceRefresh) {
      _memoryCache.remove(key);
    }
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }
    final existingInFlight = _inFlight[key];
    if (existingInFlight != null) {
      return existingInFlight;
    }

    final task = _translateInternal(
      sourceText: normalizedSourceText,
      sourceLanguage: normalizedSource,
      targetLanguage: normalizedTarget,
    );
    _inFlight[key] = task;
    final result = await task;
    _inFlight.remove(key);
    _memoryCache[key] = result;
    if (result != null) {
      _enqueueBatch(
        sourceText: normalizedSourceText,
        sourceLanguage: result.sourceLanguage,
        targetLanguage: result.targetLanguage,
        translatedText: result.translatedText,
      );
    }
    return result;
  }

  Future<void> flushPending() async {
    if (_isFlushing || _pendingBatchByKey.isEmpty) return;
    _isFlushing = true;
    final snapshot = _pendingBatchByKey.values.toList(growable: false);
    _pendingBatchByKey.clear();
    try {
      await ApiClient.postItemTranslationsBatch(snapshot);
    } catch (_) {
      for (final row in snapshot) {
        final sourceText = row['source_text'];
        final sourceLanguage = row['source_language'];
        final targetLanguage = row['target_language'];
        final translatedText = row['translated_text'];
        if (sourceText == null ||
            sourceLanguage == null ||
            targetLanguage == null ||
            translatedText == null) {
          continue;
        }
        final key =
            '${sourceText.toLowerCase()}|$sourceLanguage|$targetLanguage';
        _pendingBatchByKey[key] = row;
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<String> _detectLanguage(String text) async {
    try {
      final detected = await _languageIdentifier.identifyLanguage(text);
      if (detected == 'und') return '';
      return normalizeLanguageCode(detected);
    } catch (_) {
      return '';
    }
  }

  Future<ItemTranslationResult?> _translateInternal({
    required String sourceText,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final extractedUnitMatch = RegExp(
      r'\b\d+(?:[.,]\d+)?\s*(kg|g|gr|ml|l|kom|pcs|pc)\b',
      caseSensitive: false,
    ).firstMatch(sourceText);
    final extractedUnit = extractedUnitMatch?.group(0);

    final preparedSourceText = _prepareSourceText(sourceText);
    final sourceMl = _toMlKitLanguage(sourceLanguage);
    final targetMl = _toMlKitLanguage(targetLanguage);
    if (sourceMl == null || targetMl == null) return null;
    if (sourceMl.bcpCode == targetMl.bcpCode) return null;

    try {
      await _modelManager.downloadModel(
        sourceMl.bcpCode,
        isWifiRequired: false,
      );
      await _modelManager.downloadModel(
        targetMl.bcpCode,
        isWifiRequired: false,
      );

      final translator = OnDeviceTranslator(
        sourceLanguage: sourceMl,
        targetLanguage: targetMl,
      );
      try {
        String translated = await translator.translateText(preparedSourceText);
        if (extractedUnit != null) {
          translated = '$translated $extractedUnit';
        }
        final normalizedTranslated = normalizeSourceText(translated);
        if (normalizedTranslated.isEmpty) return null;
        return ItemTranslationResult(
          translatedText: normalizedTranslated,
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        );
      } finally {
        translator.close();
      }
    } catch (_) {
      return null;
    }
  }

  TranslateLanguage? _toMlKitLanguage(String code) {
    final normalized = normalizeLanguageCode(code);
    // TODO(translation): route unsupported Serbian translation requests
    // through a backend/cloud provider instead of coercing them to another
    // language on-device. For now we keep the requested language as-is and
    // fail closed when ML Kit has no matching model.
    for (final lang in TranslateLanguage.values) {
      if (lang.bcpCode == normalized) {
        return lang;
      }
    }
    return null;
  }

  String _prepareSourceText(String sourceText) {
    final normalized = normalizeSourceText(sourceText.replaceAll('/', ' / '));
    if (normalized.isEmpty) return normalized;

    final lettersOnly = normalized.replaceAll(
      RegExp(r'[^A-Za-z\u00C0-\u024F\u0400-\u04FF]'),
      '',
    );
    if (lettersOnly.length < 6) {
      return normalized;
    }

    var prepared = normalized;
    final uppercaseLetters = lettersOnly.replaceAll(
      RegExp(r'[^A-Z\u0400-\u042F]'),
      '',
    );
    final uppercaseRatio = uppercaseLetters.length / lettersOnly.length;
    if (uppercaseRatio >= 0.65) {
      // Convert to title case rather than all-lowercase. All-lowercase causes
      // ML Kit to mis-translate loanwords that are grammatically ambiguous in
      // the target language (e.g. "desert" → geographic desert instead of the
      // Serbian/Croatian food loanword "desert/dessert"). Title case preserves
      // the capital-first-letter convention that helps ML Kit pick the correct
      // word sense while still removing the ALL-CAPS formatting noise.
      prepared = prepared
          .split(' ')
          .map(
            (word) => word.isEmpty
                ? word
                : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
          )
          .join(' ');
    }

    // Remove noisy receipt fragments that degrade translation quality.
    prepared = prepared.replaceAll(RegExp(r'\b\d+\s*/\s*\d+\b'), ' ');
    prepared = prepared.replaceAll(
      RegExp(
        r'\b\d+(?:[.,]\d+)?\s*(kg|g|gr|ml|l|kom|pcs|pc)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    prepared = prepared.replaceFirst(
      RegExp(r'^(?:[a-z]{1,3}\s+){1,2}(?=[a-z]{3,})'),
      '',
    );
    prepared = normalizeSourceText(prepared);
    return prepared.isEmpty ? normalized : prepared;
  }

  void _enqueueBatch({
    required String sourceText,
    required String sourceLanguage,
    required String targetLanguage,
    required String translatedText,
  }) {
    final source = normalizeSourceText(sourceText);
    final translated = normalizeSourceText(translatedText);
    if (source.isEmpty || translated.isEmpty) return;

    final key = '${source.toLowerCase()}|$sourceLanguage|$targetLanguage';
    _pendingBatchByKey[key] = {
      'source_text': source,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'translated_text': translated,
      'provider': 'mlkit',
    };

    _flushTimer?.cancel();
    if (_pendingBatchByKey.length >= 20) {
      unawaited(flushPending());
      return;
    }
    _flushTimer = Timer(const Duration(seconds: 2), () {
      unawaited(flushPending());
    });
  }
}
