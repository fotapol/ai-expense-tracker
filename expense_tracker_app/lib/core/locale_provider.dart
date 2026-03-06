import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

class LocaleProvider extends ChangeNotifier {
  static const _prefsKey = 'app_locale';
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey)?.trim().toLowerCase();
    if (code == null || code.isEmpty) return;
    final supported = _normalizeSupported(code);
    if (supported == null) return;
    _locale = supported;
  }

  Future<void> setLocale(Locale locale) async {
    final next = _normalizeSupported(locale.languageCode);
    if (next == null) return;
    if (_locale.languageCode == next.languageCode) return;

    _locale = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _locale.languageCode);
    notifyListeners();
  }

  Locale? _normalizeSupported(String code) {
    final normalized = code.trim().toLowerCase();
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.languageCode.toLowerCase() == normalized) {
        return locale;
      }
    }
    return null;
  }
}
