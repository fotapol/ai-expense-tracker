import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_color_semantics.dart';
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
    id: appAccentMix,
    label: 'Mix',
    lightPrimary: Color(0xFF2F6BFF),
    darkPrimary: Color(0xFF9AB8FF),
    previewGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        Color(0xFF2F6BFF),
        Color(0xFFD45C7B),
        Color(0xFF2F9A74),
        Color(0xFFB87525),
      ],
    ),
  ),
  AppAccentTheme(
    id: appAccentNeutral,
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
    id: appAccentPurple,
    label: 'Purple',
    lightPrimary: Color(0xFF7A4DCC),
    darkPrimary: Color(0xFFD7C2FF),
    previewGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF6E3FD2), Color(0xFFC08BFF)],
    ),
  ),
];

class ThemeProvider extends ChangeNotifier {
  static const String _keyTheme = 'theme_mode';
  static const String _keyFontSize = 'font_size';
  static const String _keyAccent = 'accent_color';
  static const String _keyLabelColorMode = 'label_color_mode';
  static const String _keyAccentMigrationVersion = 'accent_migration_version';
  static const int _currentAccentMigrationVersion = 1;

  ThemeProvider({math.Random? random})
    : _random = random ?? math.Random(),
      _mixHomeAccentIndex = 0 {
    _mixHomeAccentIndex = _random.nextInt(
      AppSemanticColors.mixHomeAccentOptions(Brightness.light).length,
    );
  }

  final math.Random _random;

  ThemeMode _themeMode = ThemeMode.light;
  String _fontSizeId = '100';
  String _accentId = appAccentMix;
  AppLabelColorMode _labelColorMode = AppLabelColorMode.raw;
  int _mixHomeAccentIndex;

  ThemeMode get themeMode => _themeMode;
  String get fontSizeId => _fontSizeId;
  String get accentId => _accentId;
  AppLabelColorMode get labelColorMode => _labelColorMode;
  int get mixHomeAccentIndex => _mixHomeAccentIndex;
  List<AppAccentTheme> get availableAccents => appAccentThemes;

  AppAccentTheme get accentTheme => _accentFor(_accentId);
  String get accentLabel => accentTheme.label;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = _normalizeThemeMode(prefs.getInt(_keyTheme));
    _fontSizeId = _normalizeFontSizeId(prefs.getString(_keyFontSize));
    _accentId = _normalizeAccentId(prefs.getString(_keyAccent));
    _labelColorMode = appLabelColorModeFromId(
      prefs.getString(_keyLabelColorMode),
    );
    final accentMigrationVersion =
        prefs.getInt(_keyAccentMigrationVersion) ?? 0;
    if (accentMigrationVersion < _currentAccentMigrationVersion) {
      _accentId = appAccentMix;
      await prefs.setInt(
        _keyAccentMigrationVersion,
        _currentAccentMigrationVersion,
      );
    }
    await prefs.setInt(_keyTheme, _themeMode.index);
    await prefs.setString(_keyFontSize, _fontSizeId);
    await prefs.setString(_keyAccent, _accentId);
    await prefs.setString(
      _keyLabelColorMode,
      appLabelColorModeId(_labelColorMode),
    );
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

  Future<void> setLabelColorMode(AppLabelColorMode mode) async {
    if (_labelColorMode == mode) return;
    _labelColorMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLabelColorMode, appLabelColorModeId(mode));
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
    final semanticTheme = AppSemanticThemeExtension(
      accentId: _accentId,
      labelColorMode: _labelColorMode,
      mixHomeAccentIndex: _mixHomeAccentIndex,
      brightness: brightness,
    );
    final accentTone = semanticTheme.accentTone;
    final palette = isDark ? ShellPalette.dark() : ShellPalette.light();
    final focusColor = _accentId == appAccentNeutral
        ? palette.focusRing
        : Color.lerp(palette.focusRing, accent, isDark ? 0.55 : 0.35)!;
    final onPrimary = isDark ? palette.pageBackground : Colors.white;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onPrimary,
      secondary: palette.warningPremium,
      onSecondary: palette.pageBackground,
      error: palette.error,
      onError: palette.pageBackground,
      surface: palette.standardSurface,
      onSurface: palette.textPrimary,
    );

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: palette.pageBackground,
      colorScheme: colorScheme,
      canvasColor: palette.pageBackground,
      shadowColor: Colors.black.withAlpha(isDark ? 30 : 16),
      splashColor: palette.pressedOverlay,
      highlightColor: palette.pressedOverlay,
      dividerColor: palette.divider,
      dividerTheme: DividerThemeData(
        color: palette.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.sectionBackground,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        iconTheme: IconThemeData(color: palette.textPrimary),
        actionsIconTheme: IconThemeData(color: palette.textPrimary),
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.heroSurface,
        contentTextStyle: TextStyle(color: palette.textPrimary),
        actionTextColor: accent,
      ),
      cardColor: palette.standardSurface,
      cardTheme: CardThemeData(
        color: palette.standardSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: palette.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onPrimary,
          disabledBackgroundColor: palette.selectedSurface,
          disabledForegroundColor: palette.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          disabledForegroundColor: palette.textDisabled,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          disabledForegroundColor: palette.textDisabled,
          side: BorderSide(color: palette.border),
          backgroundColor: palette.standardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.elevatedSurface,
        selectedColor: accentTone.container,
        disabledColor: palette.standardSurface,
        secondarySelectedColor: accentTone.container,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelStyle: TextStyle(color: palette.textPrimary),
        secondaryLabelStyle: TextStyle(color: accentTone.foreground),
        brightness: brightness,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: palette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.inputSurface,
        labelStyle: TextStyle(color: palette.textMuted),
        floatingLabelStyle: TextStyle(color: focusColor),
        helperStyle: TextStyle(color: palette.textMuted),
        hintStyle: TextStyle(color: palette.textMuted),
        prefixIconColor: palette.textMuted,
        suffixIconColor: palette.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border.withAlpha(120)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: focusColor, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.error, width: 1.7),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: palette.inputSurface,
          hintStyle: TextStyle(color: palette.textMuted),
          labelStyle: TextStyle(color: palette.textMuted),
          floatingLabelStyle: TextStyle(color: focusColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: focusColor, width: 1.7),
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(
            palette.standardSurface,
          ),
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: palette.border),
            ),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.sectionBackground,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        modalBackgroundColor: palette.sectionBackground,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.sectionBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.sectionBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.border),
        ),
        textStyle: TextStyle(color: palette.textPrimary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onPrimary,
        elevation: isDark ? 2 : 4,
        highlightElevation: isDark ? 3 : 6,
        shape: const CircleBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        circularTrackColor: palette.elevatedSurface,
        linearTrackColor: palette.elevatedSurface,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.tooltipSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        textStyle: TextStyle(
          color: palette.tooltipText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        waitDuration: const Duration(milliseconds: 350),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.sectionBackground,
        indicatorColor: accentTone.container,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? accentTone.foreground : palette.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? accentTone.foreground : palette.textMuted,
          );
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return accentTone.container;
            }
            return palette.elevatedSurface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            return states.contains(WidgetState.selected)
                ? accentTone.foreground
                : palette.textMuted;
          }),
          side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
            return BorderSide(
              color: states.contains(WidgetState.selected)
                  ? accentTone.border
                  : palette.border,
            );
          }),
          overlayColor: WidgetStatePropertyAll<Color>(palette.pressedOverlay),
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: palette.sectionBackground,
        surfaceTintColor: Colors.transparent,
        dividerColor: palette.divider,
        headerForegroundColor: palette.textPrimary,
        dayForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return palette.textDisabled;
          }
          if (states.contains(WidgetState.selected)) {
            return onPrimary;
          }
          return palette.textPrimary;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return accent;
          }
          return null;
        }),
        todayForegroundColor: WidgetStatePropertyAll<Color>(
          palette.textPrimary,
        ),
        todayBorder: BorderSide(color: focusColor),
        yearForegroundColor: WidgetStatePropertyAll<Color>(palette.textPrimary),
        yearBackgroundColor: WidgetStatePropertyAll<Color>(
          palette.standardSurface,
        ),
        rangeSelectionBackgroundColor: palette.selectedSurface,
      ),
      extensions: <ThemeExtension<dynamic>>[
        palette,
        semanticTheme,
        AppDisplayThemeExtension(
          symbolPosition: moneyFormatSettings.symbolPosition,
          showDecimals: moneyFormatSettings.showDecimals,
        ),
      ],
      useMaterial3: true,
    );
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
