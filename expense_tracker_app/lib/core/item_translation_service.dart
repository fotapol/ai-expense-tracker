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

  static const Map<String, String> _mlKitLanguageFallbacks = {
    // ML Kit does not provide a Serbian model. Croatian gives the closest result.
    'sr': 'hr',
    'bs': 'hr',
    'me': 'hr',
    'sh': 'hr',
  };

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
        final translated = await translator.translateText(preparedSourceText);
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
    final resolved = _mlKitLanguageFallbacks[normalized] ?? normalized;
    for (final lang in TranslateLanguage.values) {
      if (lang.bcpCode == resolved) {
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

    final uppercaseLetters = lettersOnly.replaceAll(
      RegExp(r'[^A-Z\u0400-\u042F]'),
      '',
    );
    final uppercaseRatio = uppercaseLetters.length / lettersOnly.length;
    if (uppercaseRatio >= 0.65) {
      return normalized.toLowerCase();
    }
    return normalized;
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
