import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'redesign_system.dart';

class MoneyFormatSettings extends ChangeNotifier {
  static const String _keySymbolPosition = 'currency_symbol_position';
  static const String _keyShowDecimals = 'currency_show_decimals';

  String _symbolPosition = 'before';
  bool _showDecimals = true;

  String get symbolPosition => _symbolPosition;
  bool get showDecimals => _showDecimals;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _symbolPosition = _normalizePosition(
      prefs.getString(_keySymbolPosition) ?? _symbolPosition,
    );
    _showDecimals = prefs.getBool(_keyShowDecimals) ?? _showDecimals;
    notifyListeners();
  }

  Future<void> setSymbolPosition(String value) async {
    final normalized = _normalizePosition(value);
    if (_symbolPosition == normalized) return;
    _symbolPosition = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySymbolPosition, _symbolPosition);
    notifyListeners();
  }

  Future<void> setShowDecimals(bool value) async {
    if (_showDecimals == value) return;
    _showDecimals = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowDecimals, _showDecimals);
    notifyListeners();
  }

  int resolveDecimals(int defaultDecimals) {
    if (!_showDecimals) return 0;
    return defaultDecimals < 0 ? 0 : defaultDecimals;
  }

  String format(
    String currency,
    num amount, {
    int defaultDecimals = 2,
    String? symbolPosition,
    bool? showDecimals,
  }) {
    final normalizedCurrency = currency.trim().toUpperCase();
    final symbol = CurrencyDisplay.symbolForCode(normalizedCurrency);
    final effectivePosition = _normalizePosition(
      symbolPosition ?? _symbolPosition,
    );
    final decimals = (showDecimals ?? _showDecimals)
        ? (defaultDecimals < 0 ? 0 : defaultDecimals)
        : 0;
    final absoluteAmount = amount.abs().toStringAsFixed(decimals);
    final sign = amount < 0 ? '-' : '';
    final usesCurrencyCode = symbol == normalizedCurrency;

    if (effectivePosition == 'after') {
      final suffix = usesCurrencyCode ? normalizedCurrency : symbol;
      return '$sign$absoluteAmount $suffix';
    }

    if (usesCurrencyCode) {
      return '$sign$normalizedCurrency $absoluteAmount';
    }
    return '$sign$symbol$absoluteAmount';
  }

  String preview(String currency, {num amount = 1234.56}) {
    return format(currency, amount);
  }

  String _normalizePosition(String raw) {
    return raw.trim().toLowerCase() == 'after' ? 'after' : 'before';
  }
}

final moneyFormatSettings = MoneyFormatSettings();
