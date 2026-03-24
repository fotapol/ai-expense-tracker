import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'redesign_system.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _keyTheme = 'theme_mode';
  static const String _keyFontSize = 'font_size';
  
  ThemeMode _themeMode = ThemeMode.system;
  String _fontSizeId = 'medium';

  ThemeMode get themeMode => _themeMode;
  String get fontSizeId => _fontSizeId;

  ThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_keyTheme);
    if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    } else {
      final isDark = prefs.getBool('is_dark_mode');
      if (isDark == true) {
        _themeMode = ThemeMode.dark;
      } else if (isDark == false) {
        _themeMode = ThemeMode.light;
      }
    }
    _fontSizeId = prefs.getString(_keyFontSize) ?? 'medium';
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, _themeMode.index);
    notifyListeners();
  }

  Future<void> setFontSize(String sizeId) async {
    if (_fontSizeId == sizeId) return;
    _fontSizeId = sizeId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFontSize, _fontSizeId);
    notifyListeners();
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> setDarkMode(bool value) => setThemeMode(value ? ThemeMode.dark : ThemeMode.light);

  Future<void> toggle() => setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);

  double get fontSizeFactor {
    switch (_fontSizeId) {
      case 'small': return 0.9;
      case 'large': return 1.15;
      case 'medium':
      default: return 1.0;
    }
  }

  ThemeData get lightTheme {
    final base = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: ShellColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: ShellColors.lightAccent,
        secondary: ShellColors.gold,
        surface: ShellColors.lightSurface,
        onSurface: ShellColors.lightText,
      ),
      dividerColor: ShellColors.lightBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ShellColors.lightText,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ShellColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShellColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShellColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShellColors.lightAccent),
        ),
      ),
      useMaterial3: true,
    );
    return base;
  }

  ThemeData get darkTheme {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: ShellColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: ShellColors.gold,
        secondary: ShellColors.softBlue,
        surface: ShellColors.darkSurface,
        onSurface: ShellColors.darkText,
      ),
      dividerColor: ShellColors.darkBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: ShellColors.darkText,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ShellColors.darkSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShellColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShellColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ShellColors.gold),
        ),
      ),
      useMaterial3: true,
    );
    return base;
  }

  // Backwards compatibility
  ThemeData get themeData => isDarkMode ? darkTheme : lightTheme;
}
