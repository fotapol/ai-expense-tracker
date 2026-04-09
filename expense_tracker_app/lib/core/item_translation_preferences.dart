import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_languages.dart';

class ItemTranslationPreferences extends ChangeNotifier {
  static const String _keyAutoDetect = 'items_translation_auto_detect_source';
  static const String _keyManualSource = 'items_translation_manual_source';

  bool _autoDetectSourceLanguage = true;
  String _manualSourceLanguage = 'en';

  bool get autoDetectSourceLanguage => _autoDetectSourceLanguage;
  String get manualSourceLanguage => _manualSourceLanguage;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _autoDetectSourceLanguage =
        prefs.getBool(_keyAutoDetect) ?? _autoDetectSourceLanguage;
    _manualSourceLanguage =
        _normalizeLanguageCode(prefs.getString(_keyManualSource)) ??
        _manualSourceLanguage;
    notifyListeners();
  }

  Future<void> setAutoDetectSourceLanguage(
    bool value, {
    String? fallbackLanguageCode,
  }) async {
    if (_autoDetectSourceLanguage == value) return;
    _autoDetectSourceLanguage = value;
    if (!value) {
      _manualSourceLanguage =
          _normalizeLanguageCode(_manualSourceLanguage) ??
          _normalizeLanguageCode(fallbackLanguageCode) ??
          _manualSourceLanguage;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoDetect, _autoDetectSourceLanguage);
    await prefs.setString(_keyManualSource, _manualSourceLanguage);
    notifyListeners();
  }

  Future<void> setManualSourceLanguage(String code) async {
    final normalized = _normalizeLanguageCode(code) ?? _manualSourceLanguage;
    if (_manualSourceLanguage == normalized) return;
    _manualSourceLanguage = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyManualSource, _manualSourceLanguage);
    notifyListeners();
  }

  String? resolveSourceLanguage(
    String? detectedOrStoredLanguage, {
    String? fallbackLanguageCode,
  }) {
    if (_autoDetectSourceLanguage) {
      return _normalizeLanguageCode(detectedOrStoredLanguage) ??
          _normalizeLanguageCode(fallbackLanguageCode);
    }
    return _normalizeLanguageCode(_manualSourceLanguage) ??
        _normalizeLanguageCode(fallbackLanguageCode);
  }

  String? _normalizeLanguageCode(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final language in appLanguages) {
      if (language.code == normalized) {
        return normalized;
      }
    }
    return null;
  }
}

final itemTranslationPreferences = ItemTranslationPreferences();
