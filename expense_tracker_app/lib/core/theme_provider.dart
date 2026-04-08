import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'money_format_preferences.dart';
import 'redesign_system.dart';

@immutable
class AppAccentTheme {
  const AppAccentTheme({
    required this.id,
    required this.label,
    required this.lightPrimary,
    required this.darkPrimary,
    required this.previewGradient,
  });

  final String id;
  final String label;
  final Color lightPrimary;
  final Color darkPrimary;
  final Gradient previewGradient;

  Color primaryFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkPrimary : lightPrimary;
}

@immutable
class AppDisplayThemeExtension
    extends ThemeExtension<AppDisplayThemeExtension> {
  const AppDisplayThemeExtension({
    required this.symbolPosition,
    required this.showDecimals,
  });

  final String symbolPosition;
  final bool showDecimals;

  @override
  AppDisplayThemeExtension copyWith({
    String? symbolPosition,
    bool? showDecimals,
  }) {
    return AppDisplayThemeExtension(
      symbolPosition: symbolPosition ?? this.symbolPosition,
      showDecimals: showDecimals ?? this.showDecimals,
    );
  }

  @override
  AppDisplayThemeExtension lerp(
    ThemeExtension<AppDisplayThemeExtension>? other,
    double t,
  ) {
    if (other is! AppDisplayThemeExtension) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

const List<AppAccentTheme> appAccentThemes = <AppAccentTheme>[
  AppAccentTheme(
    id: 'neutral',
    label: 'Neutral',
    lightPrimary: Color(0xFF1C1A19),
    darkPrimary: Color(0xFFE9E1D2),
    previewGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF111111), Color(0xFF4A4A4A)],
    ),
  ),
  AppAccentTheme(
    id: 'purple',
    label: 'Purple',
    lightPrimary: Color(0xFF7A4DCC),
    darkPrimary: Color(0xFFD2BCFF),
    previewGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF6E3FD2), Color(0xFFC08BFF)],
    ),
  ),
  AppAccentTheme(
    id: 'mix',
    label: 'Mix',
    lightPrimary: Color(0xFFE64F8F),
    darkPrimary: Color(0xFFFFC1E1),
    previewGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color(0xFFFF5F6D),
        Color(0xFFFFC371),
        Color(0xFF57CC99),
        Color(0xFF4D96FF),
      ],
    ),
  ),
];

class ThemeProvider extends ChangeNotifier {
  static const String _keyTheme = 'theme_mode';
  static const String _keyFontSize = 'font_size';
  static const String _keyAccent = 'accent_color';

  ThemeMode _themeMode = ThemeMode.light;
  String _fontSizeId = '100';
  String _accentId = 'neutral';

  ThemeMode get themeMode => _themeMode;
  String get fontSizeId => _fontSizeId;
  String get accentId => _accentId;
  List<AppAccentTheme> get availableAccents => appAccentThemes;

  AppAccentTheme get accentTheme => _accentFor(_accentId);
  String get accentLabel => accentTheme.label;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = _normalizeThemeMode(prefs.getInt(_keyTheme));
    _fontSizeId = _normalizeFontSizeId(prefs.getString(_keyFontSize));
    _accentId = _normalizeAccentId(prefs.getString(_keyAccent));
    await prefs.setInt(_keyTheme, _themeMode.index);
    await prefs.setString(_keyFontSize, _fontSizeId);
    await prefs.setString(_keyAccent, _accentId);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final normalized = _normalizeThemeMode(mode.index);
    if (_themeMode == normalized) return;
    _themeMode = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, _themeMode.index);
    notifyListeners();
  }

  Future<void> setFontSize(String sizeId) async {
    final normalized = _normalizeFontSizeId(sizeId);
    if (_fontSizeId == normalized) return;
    _fontSizeId = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFontSize, _fontSizeId);
    notifyListeners();
  }

  Future<void> setAccent(String accentId) async {
    final normalized = _normalizeAccentId(accentId);
    if (_accentId == normalized) return;
    _accentId = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccent, _accentId);
    notifyListeners();
  }

  String get scalePercentLabel => _fontSizeId;

  String get themeModeLabel {
    switch (_themeMode) {
      case ThemeMode.system:
        return 'Auto';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.light:
        return 'Light';
    }
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> setDarkMode(bool value) =>
      setThemeMode(value ? ThemeMode.dark : ThemeMode.light);

  Future<void> toggle() =>
      setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);

  double get fontSizeFactor {
    switch (_fontSizeId) {
      case '60':
        return 0.7;
      case '80':
        return 0.82;
      case '120':
        return 1.02;
      case '100':
      default:
        return 0.9;
    }
  }

  ThemeData get lightTheme => _buildTheme(Brightness.light);

  ThemeData get darkTheme => _buildTheme(Brightness.dark);

  ThemeData get themeData => lightTheme;

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final accent = accentTheme.primaryFor(brightness);
    final background = isDark
        ? ShellColors.darkBackground
        : ShellColors.lightBackground;
    final surface = isDark ? ShellColors.darkSurface : ShellColors.lightSurface;
    final surfaceAlt = isDark
        ? ShellColors.darkSurfaceAlt
        : ShellColors.lightSurfaceAlt;
    final border = isDark ? ShellColors.darkBorder : ShellColors.lightBorder;
    final text = isDark ? ShellColors.darkText : ShellColors.lightText;
    final muted = isDark ? ShellColors.darkMuted : ShellColors.lightMuted;
    final onPrimary = isDark ? ShellColors.darkBackground : Colors.white;

    final base = ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: onPrimary,
        secondary: ShellColors.gold,
        onSecondary: Colors.black,
        error: ShellColors.softRed,
        onError: Colors.white,
        surface: surface,
        onSurface: text,
      ),
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onPrimary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: accent.withAlpha(isDark ? 52 : 34),
        disabledColor: surfaceAlt,
        secondarySelectedColor: accent.withAlpha(isDark ? 52 : 34),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: TextStyle(color: text),
        secondaryLabelStyle: TextStyle(color: text),
        brightness: brightness,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.3),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          hintStyle: TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: accent, width: 1.3),
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(surface),
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        AppDisplayThemeExtension(
          symbolPosition: moneyFormatSettings.symbolPosition,
          showDecimals: moneyFormatSettings.showDecimals,
        ),
      ],
      useMaterial3: true,
    );

    return base;
  }

  ThemeMode _normalizeThemeMode(int? rawIndex) {
    switch (rawIndex) {
      case 0:
        return ThemeMode.system;
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.dark;
      default:
        return ThemeMode.light;
    }
  }

  String _normalizeFontSizeId(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'tiny':
      case '60':
        return '60';
      case 'small':
      case '90':
      case '80':
        return '80';
      case 'large':
      case '110':
      case '120':
        return '120';
      case 'medium':
      case '100':
      default:
        return '100';
    }
  }

  String _normalizeAccentId(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized == 'rainbow') return 'mix';
    for (final accent in appAccentThemes) {
      if (accent.id == normalized) return accent.id;
    }
    return appAccentThemes.first.id;
  }

  AppAccentTheme _accentFor(String id) {
    for (final accent in appAccentThemes) {
      if (accent.id == id) return accent;
    }
    return appAccentThemes.first;
  }
}
