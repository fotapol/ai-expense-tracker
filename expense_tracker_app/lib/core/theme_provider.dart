import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'is_dark_mode';
  bool _isDarkMode = true;

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_key) ?? true; // Dark by default
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDarkMode);
    notifyListeners();
  }

  ThemeData get themeData {
    if (_isDarkMode) {
      return ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF120A1F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB388FF),
          secondary: Color(0xFFE1BEE7),
          surface: Color(0xFF1A1230),
        ),
        useMaterial3: true,
      );
    } else {
      return ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5EFFF),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF7E57C2),
          secondary: Color(0xFFA855F7),
          surface: Colors.white,
          onSurface: Colors.black87,
        ),
        useMaterial3: true,
      );
    }
  }
}
