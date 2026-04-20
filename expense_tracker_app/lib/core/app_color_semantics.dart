import 'dart:math' as math;

import 'package:flutter/material.dart';

const String appAccentMix = 'mix';
const String appAccentNeutral = 'neutral';
const String appAccentPurple = 'purple';

enum AppLabelColorMode { raw, themed }

String appLabelColorModeId(AppLabelColorMode mode) {
  switch (mode) {
    case AppLabelColorMode.themed:
      return 'themed';
    case AppLabelColorMode.raw:
      return 'raw';
  }
}

AppLabelColorMode appLabelColorModeFromId(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'themed':
      return AppLabelColorMode.themed;
    case 'raw':
    default:
      return AppLabelColorMode.raw;
  }
}

@immutable
class SemanticColorTone {
  const SemanticColorTone({
    required this.base,
    required this.container,
    required this.containerStrong,
    required this.border,
    required this.foreground,
    required this.onSolid,
  });

  final Color base;
  final Color container;
  final Color containerStrong;
  final Color border;
  final Color foreground;
  final Color onSolid;
}

@immutable
class AppColorPickerOption {
  const AppColorPickerOption({
    required this.storedHex,
    required this.previewColor,
  });

  final String storedHex;
  final Color previewColor;
}

@immutable
class HeroAccentTone {
  const HeroAccentTone({
    required this.accent,
    required this.gradientColors,
    required this.border,
    required this.foreground,
    required this.secondaryForeground,
    required this.badgeFill,
    required this.badgeBorder,
    required this.badgeForeground,
  });

  final Color accent;
  final List<Color> gradientColors;
  final Color border;
  final Color foreground;
  final Color secondaryForeground;
  final Color badgeFill;
  final Color badgeBorder;
  final Color badgeForeground;
}

@immutable
class AppSemanticThemeExtension
    extends ThemeExtension<AppSemanticThemeExtension> {
  const AppSemanticThemeExtension({
    required this.accentId,
    required this.labelColorMode,
    required this.mixHomeAccentIndex,
    required this.brightness,
  });

  final String accentId;
  final AppLabelColorMode labelColorMode;
  final int mixHomeAccentIndex;
  final Brightness brightness;

  SemanticColorTone get accentTone => AppSemanticColors.primaryTone(
    accentId,
    brightness,
    mixHomeAccentIndex: mixHomeAccentIndex,
  );

  List<Color> get trendPalette {
    final palette = AppSemanticColors.trendPalette(accentId, brightness);
    final accent = accentTone.base;
    return [accent, ...palette.skip(1)];
  }

  List<Color> get chartRamp =>
      AppSemanticColors.chartRamp(accentId, brightness);

  Color get chartOtherColor =>
      AppSemanticColors.chartOtherColor(accentId, brightness);

  HeroAccentTone get homeHeroTone => AppSemanticColors.homeHeroTone(
    accentId,
    brightness,
    mixHomeAccentIndex: mixHomeAccentIndex,
  );

  SemanticColorTone categoryTone({
    String? code,
    String? parentCode,
    String? name,
    String? rawHex,
  }) {
    return AppSemanticColors.categoryTone(
      accentId: accentId,
      brightness: brightness,
      labelColorMode: labelColorMode,
      code: code,
      parentCode: parentCode,
      name: name,
      rawHex: rawHex,
    );
  }

  SemanticColorTone labelTone({String? labelId, String? name, String? rawHex}) {
    return AppSemanticColors.labelTone(
      accentId: accentId,
      brightness: brightness,
      labelColorMode: labelColorMode,
      labelId: labelId,
      name: name,
      rawHex: rawHex,
    );
  }

  @override
  AppSemanticThemeExtension copyWith({
    String? accentId,
    AppLabelColorMode? labelColorMode,
    int? mixHomeAccentIndex,
    Brightness? brightness,
  }) {
    return AppSemanticThemeExtension(
      accentId: accentId ?? this.accentId,
      labelColorMode: labelColorMode ?? this.labelColorMode,
      mixHomeAccentIndex: mixHomeAccentIndex ?? this.mixHomeAccentIndex,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  AppSemanticThemeExtension lerp(
    ThemeExtension<AppSemanticThemeExtension>? other,
    double t,
  ) {
    if (other is! AppSemanticThemeExtension) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

class AppSemanticColors {
  AppSemanticColors._();

  static const String defaultLabelColorHex = '#4D7BF3';
  static const String defaultCategoryColorHex = '#E27A3F';

  static const List<Color> _rawLabelPickerPalette = <Color>[
    Color(0xFF4D7BF3),
    Color(0xFFA347F5),
    Color(0xFFEC2D91),
    Color(0xFFFF3838),
    Color(0xFFFF6B00),
    Color(0xFFF2B900),
    Color(0xFF17C653),
    Color(0xFF19BFB4),
    Color(0xFF24B7D9),
    Color(0xFF6F5CF4),
  ];

  static const List<Color> _mixCategoryPaletteLight = <Color>[
    Color(0xFFE27A3F),
    Color(0xFF5979B6),
    Color(0xFF2D9A74),
    Color(0xFF2F8C8B),
    Color(0xFFC49734),
    Color(0xFF4C66C8),
    Color(0xFF2E8AAE),
    Color(0xFF8462D8),
    Color(0xFFC05F94),
    Color(0xFFD46575),
    Color(0xFFA96BBE),
    Color(0xFF748291),
  ];

  static const List<Color> _mixCategoryPaletteDark = <Color>[
    Color(0xFFFFB27E),
    Color(0xFF9EB7FF),
    Color(0xFF7BE0B7),
    Color(0xFF7ED6D3),
    Color(0xFFFFD77B),
    Color(0xFFAEB8FF),
    Color(0xFF82D7FF),
    Color(0xFFC8B3FF),
    Color(0xFFFFA8D2),
    Color(0xFFFFA9B6),
    Color(0xFFE0AEFF),
    Color(0xFFC5D0DB),
  ];

  static const List<Color> _purpleCategoryPaletteLight = <Color>[
    Color(0xFF8259D1),
    Color(0xFF6C58C6),
    Color(0xFF9B58D9),
    Color(0xFF6E69D2),
    Color(0xFFB16BE4),
    Color(0xFF5D47B6),
    Color(0xFFC17AF0),
    Color(0xFF8E61D8),
    Color(0xFFD281EC),
    Color(0xFFA44ED4),
    Color(0xFFB390FF),
    Color(0xFF7F729C),
  ];

  static const List<Color> _purpleCategoryPaletteDark = <Color>[
    Color(0xFFC4AEFF),
    Color(0xFFAB9FFF),
    Color(0xFFD8A8FF),
    Color(0xFFB4B1FF),
    Color(0xFFE2B6FF),
    Color(0xFF9E8AF4),
    Color(0xFFE6C5FF),
    Color(0xFFC7B1FF),
    Color(0xFFF0C6FF),
    Color(0xFFD09BFF),
    Color(0xFFD7C7FF),
    Color(0xFFBCB2D8),
  ];

  static const List<Color> _neutralCategoryPaletteLight = <Color>[
    Color(0xFF141414),
    Color(0xFF252525),
    Color(0xFF363636),
    Color(0xFF474747),
    Color(0xFF585858),
    Color(0xFF6A6A6A),
    Color(0xFF7C7C7C),
    Color(0xFF8F8F8F),
    Color(0xFFA3A3A3),
    Color(0xFFB8B8B8),
    Color(0xFFCECECE),
    Color(0xFF767676),
  ];

  static const List<Color> _neutralCategoryPaletteDark = <Color>[
    Color(0xFFF5F5F5),
    Color(0xFFE4E4E4),
    Color(0xFFD3D3D3),
    Color(0xFFC2C2C2),
    Color(0xFFB1B1B1),
    Color(0xFFA0A0A0),
    Color(0xFF8F8F8F),
    Color(0xFF7E7E7E),
    Color(0xFF6E6E6E),
    Color(0xFF5E5E5E),
    Color(0xFF4F4F4F),
    Color(0xFF989898),
  ];

  static const List<Color> _mixLabelPaletteLight = <Color>[
    Color(0xFF2F6BFF),
    Color(0xFF7E61D6),
    Color(0xFFD45C7B),
    Color(0xFFE5863E),
    Color(0xFF2F9A74),
    Color(0xFF248FA1),
    Color(0xFFB76A2F),
    Color(0xFF5368B7),
    Color(0xFF9F5DB6),
    Color(0xFF6F7D8C),
  ];

  static const List<Color> _mixLabelPaletteDark = <Color>[
    Color(0xFF9AB8FF),
    Color(0xFFC3B1FF),
    Color(0xFFFFB0C2),
    Color(0xFFFFBA82),
    Color(0xFF88E0BC),
    Color(0xFF82DAE6),
    Color(0xFFFFCB99),
    Color(0xFFAEC0FF),
    Color(0xFFDAB4F0),
    Color(0xFFC7D1DC),
  ];

  static const List<Color> _purpleLabelPaletteLight = <Color>[
    Color(0xFF7A4DCC),
    Color(0xFF9362DE),
    Color(0xFFB06BE6),
    Color(0xFF6A59C9),
    Color(0xFF9A58D7),
    Color(0xFFC37BEF),
    Color(0xFF8358BE),
    Color(0xFFA982F0),
    Color(0xFF6F53A9),
    Color(0xFF9182B6),
  ];

  static const List<Color> _purpleLabelPaletteDark = <Color>[
    Color(0xFFD7C2FF),
    Color(0xFFE3CEFF),
    Color(0xFFF0D4FF),
    Color(0xFFCAC4FF),
    Color(0xFFDDAEFA),
    Color(0xFFF2D2FF),
    Color(0xFFD7BCFF),
    Color(0xFFE7D0FF),
    Color(0xFFC6B8ED),
    Color(0xFFD5CEE6),
  ];

  static const List<Color> _neutralLabelPaletteLight = <Color>[
    Color(0xFF151515),
    Color(0xFF2A2A2A),
    Color(0xFF404040),
    Color(0xFF575757),
    Color(0xFF6E6E6E),
    Color(0xFF868686),
    Color(0xFF9E9E9E),
    Color(0xFFB7B7B7),
    Color(0xFFD0D0D0),
    Color(0xFF7B7B7B),
  ];

  static const List<Color> _neutralLabelPaletteDark = <Color>[
    Color(0xFFF5F5F5),
    Color(0xFFE3E3E3),
    Color(0xFFD2D2D2),
    Color(0xFFC1C1C1),
    Color(0xFFB0B0B0),
    Color(0xFF9F9F9F),
    Color(0xFF8F8F8F),
    Color(0xFF7F7F7F),
    Color(0xFF6F6F6F),
    Color(0xFF9A9A9A),
  ];

  static const List<Color> _mixHomeAccentPaletteLight = <Color>[
    Color(0xFF2F6BFF), // Vivid blue
    Color(0xFF1A8A6E), // Emerald
    Color(0xFF6D4AE8), // Indigo
    Color(0xFF0E7CC0), // Cobalt
    Color(0xFF9146D4), // Violet
    Color(0xFFD14D72), // Rose
    Color(0xFF1E88A8), // Teal
    Color(0xFFCF5528), // Burnt orange
  ];

  static const List<Color> _mixHomeAccentPaletteDark = <Color>[
    Color(0xFF9AB8FF), // Vivid blue
    Color(0xFF72DEB8), // Emerald
    Color(0xFFBDA8FF), // Indigo
    Color(0xFF6DC4F2), // Cobalt
    Color(0xFFD6AFFF), // Violet
    Color(0xFFFF9AB5), // Rose
    Color(0xFF6FD8E8), // Teal
    Color(0xFFFFAA82), // Burnt orange
  ];

  static const List<Color> _neutralTrendPaletteLight = <Color>[
    Color(0xFF171717),
    Color(0xFF4A4A4A),
    Color(0xFF7D7D7D),
    Color(0xFFB0B0B0),
  ];

  static const List<Color> _neutralTrendPaletteDark = <Color>[
    Color(0xFFF3F3F3),
    Color(0xFFD8D8D8),
    Color(0xFFAEAEAE),
    Color(0xFF7D7D7D),
  ];

  static const List<Color> _mixTrendPaletteLight = <Color>[
    Color(0xFF2F6BFF),
    Color(0xFF2F9A74),
    Color(0xFFD45C7B),
    Color(0xFF8462D8),
  ];

  static const List<Color> _mixTrendPaletteDark = <Color>[
    Color(0xFF9AB8FF),
    Color(0xFF8FE0C0),
    Color(0xFFFFAFBF),
    Color(0xFFD7C2FF),
  ];

  static const List<Color> _purpleTrendPaletteLight = <Color>[
    Color(0xFF7A4DCC),
    Color(0xFF9A58D7),
    Color(0xFF6A59C9),
    Color(0xFFC17AF0),
  ];

  static const List<Color> _purpleTrendPaletteDark = <Color>[
    Color(0xFFD7C2FF),
    Color(0xFFE7D0FF),
    Color(0xFFC5C1FF),
    Color(0xFFF0D5FF),
  ];

  static const Map<String, int> _categorySlots = <String, int>{
    'FOOD': 0,
    'TRANSPORT': 1,
    'HEALTH': 2,
    'UTILITIES': 3,
    'ENTERTAINMENT': 4,
    'HOME': 5,
    'ELECTRONICS': 6,
    'EDUCATION': 7,
    'CLOTHING': 8,
    'PERSONAL_CARE': 9,
    'FLOWERS': 10,
    'OTHER': 11,
    'UNCATEGORIZED': 11,
  };

  static Color primaryAccent(
    String accentId,
    Brightness brightness, {
    int mixHomeAccentIndex = 0,
  }) {
    switch (accentId) {
      case appAccentPurple:
        return brightness == Brightness.dark
            ? const Color(0xFFD7C2FF)
            : const Color(0xFF7A4DCC);
      case appAccentNeutral:
        return brightness == Brightness.dark
            ? const Color(0xFFE9E1D2)
            : const Color(0xFF1C1A19);
      case appAccentMix:
      default:
        return _pickIndexed(
          mixHomeAccentOptions(brightness),
          mixHomeAccentIndex,
        );
    }
  }

  static List<Color> mixHomeAccentOptions(Brightness brightness) {
    return brightness == Brightness.dark
        ? _mixHomeAccentPaletteDark
        : _mixHomeAccentPaletteLight;
  }

  static SemanticColorTone primaryTone(
    String accentId,
    Brightness brightness, {
    int mixHomeAccentIndex = 0,
  }) {
    return toneFromColor(
      primaryAccent(
        accentId,
        brightness,
        mixHomeAccentIndex: mixHomeAccentIndex,
      ),
      brightness,
    );
  }

  static List<Color> trendPalette(String accentId, Brightness brightness) {
    switch (accentId) {
      case appAccentPurple:
        return brightness == Brightness.dark
            ? _purpleTrendPaletteDark
            : _purpleTrendPaletteLight;
      case appAccentNeutral:
        return brightness == Brightness.dark
            ? _neutralTrendPaletteDark
            : _neutralTrendPaletteLight;
      case appAccentMix:
      default:
        return brightness == Brightness.dark
            ? _mixTrendPaletteDark
            : _mixTrendPaletteLight;
    }
  }

  static List<Color> chartRamp(String accentId, Brightness brightness) {
    switch (accentId) {
      case appAccentPurple:
        return brightness == Brightness.dark
            ? _purpleCategoryPaletteDark
            : _purpleCategoryPaletteLight;
      case appAccentNeutral:
        return brightness == Brightness.dark
            ? _neutralCategoryPaletteDark
            : _neutralCategoryPaletteLight;
      case appAccentMix:
      default:
        return brightness == Brightness.dark
            ? _mixCategoryPaletteDark
            : _mixCategoryPaletteLight;
    }
  }

  static Color chartOtherColor(String accentId, Brightness brightness) {
    switch (accentId) {
      case appAccentPurple:
        return brightness == Brightness.dark
            ? const Color(0xFFAA9BC6)
            : const Color(0xFF85749F);
      case appAccentNeutral:
        return brightness == Brightness.dark
            ? const Color(0xFF8E8E8E)
            : const Color(0xFF767676);
      case appAccentMix:
      default:
        return brightness == Brightness.dark
            ? const Color(0xFFA8B2BD)
            : const Color(0xFF75818E);
    }
  }

  static HeroAccentTone homeHeroTone(
    String accentId,
    Brightness brightness, {
    required int mixHomeAccentIndex,
  }) {
    final accent = primaryAccent(
      accentId,
      brightness,
      mixHomeAccentIndex: mixHomeAccentIndex,
    );
    final bool isDark = brightness == Brightness.dark;
    final Color foreground = isDark ? const Color(0xFFF2F5F7) : Colors.white;
    final double startBlend = accentId == appAccentNeutral
        ? (isDark ? 0.58 : 0.74)
        : (isDark ? 0.44 : 0.28);
    final double endBlend = accentId == appAccentNeutral
        ? (isDark ? 0.76 : 0.88)
        : (isDark ? 0.66 : 0.56);
    final Color start = Color.lerp(
      accent,
      isDark ? Colors.black : const Color(0xFF111215),
      startBlend,
    )!;
    final Color end = Color.lerp(
      accent,
      isDark ? const Color(0xFF111418) : const Color(0xFF231F1C),
      endBlend,
    )!;
    final Color badgeFill = isDark
        ? accent.withAlpha(38)
        : Colors.white.withAlpha(accentId == appAccentNeutral ? 16 : 22);
    final Color badgeBorder = isDark
        ? accent.withAlpha(88)
        : Colors.white.withAlpha(accentId == appAccentNeutral ? 24 : 34);

    return HeroAccentTone(
      accent: accent,
      gradientColors: <Color>[start, end],
      border: Color.lerp(accent, Colors.white, isDark ? 0.18 : 0.12)!,
      foreground: foreground,
      secondaryForeground: foreground.withAlpha(214),
      badgeFill: badgeFill,
      badgeBorder: badgeBorder,
      badgeForeground: foreground,
    );
  }

  static List<AppColorPickerOption> labelColorOptions({
    required String accentId,
    required Brightness brightness,
    required AppLabelColorMode labelColorMode,
  }) {
    final previewPalette = labelColorMode == AppLabelColorMode.raw
        ? _rawLabelPickerPalette
        : _labelPalette(accentId, brightness);
    return _colorOptionsFromPalettes(
      storedPalette: _rawLabelPickerPalette,
      previewPalette: previewPalette,
    );
  }

  static List<AppColorPickerOption> categoryColorOptions({
    required String accentId,
    required Brightness brightness,
    required AppLabelColorMode labelColorMode,
  }) {
    final storedPalette = _mixCategoryPaletteLight;
    final previewPalette = labelColorMode == AppLabelColorMode.raw
        ? storedPalette
        : _categoryPalette(accentId, brightness);
    return _colorOptionsFromPalettes(
      storedPalette: storedPalette,
      previewPalette: previewPalette,
    );
  }

  static SemanticColorTone categoryTone({
    required String accentId,
    required Brightness brightness,
    AppLabelColorMode labelColorMode = AppLabelColorMode.raw,
    String? code,
    String? parentCode,
    String? name,
    String? rawHex,
  }) {
    if (labelColorMode == AppLabelColorMode.raw) {
      final rawColor = parseHexColor(rawHex);
      if (rawColor != null) {
        return toneFromColor(rawColor, brightness);
      }

      final rawPalette = _categoryPalette(appAccentMix, brightness);
      final rawSlot = categorySlot(
        code: code,
        parentCode: parentCode,
        name: name,
      );
      return toneFromColor(rawPalette[rawSlot], brightness);
    }

    final palette = _categoryPalette(accentId, brightness);
    final rawSlot = _paletteSlotForRawHex(rawHex, _mixCategoryPaletteLight);
    final slot =
        rawSlot ?? categorySlot(code: code, parentCode: parentCode, name: name);
    return toneFromColor(palette[slot], brightness);
  }

  static SemanticColorTone labelTone({
    required String accentId,
    required Brightness brightness,
    required AppLabelColorMode labelColorMode,
    String? labelId,
    String? name,
    String? rawHex,
  }) {
    if (labelColorMode == AppLabelColorMode.raw) {
      final rawColor = parseHexColor(rawHex);
      if (rawColor != null) {
        return toneFromColor(rawColor, brightness);
      }
    }

    final palette = _labelPalette(accentId, brightness);
    final rawSlot = _paletteSlotForRawHex(rawHex, _rawLabelPickerPalette);
    if (rawSlot != null) {
      return toneFromColor(palette[rawSlot], brightness);
    }

    final seed = '${labelId ?? ''}|${name ?? ''}';
    final slot = stableIndex(seed, palette.length);
    return toneFromColor(palette[slot], brightness);
  }

  static int categorySlot({String? code, String? parentCode, String? name}) {
    final direct = _categorySlots[_normalizeToken(code)];
    if (direct != null) return direct;
    final inherited = _categorySlots[_normalizeToken(parentCode)];
    if (inherited != null) return inherited;

    final seed = '${code ?? ''}|${parentCode ?? ''}|${name ?? ''}';
    return stableIndex(seed, _mixCategoryPaletteLight.length);
  }

  static int stableIndex(String? seed, int length) {
    if (length <= 0) return 0;
    final normalized = (seed ?? '').trim().toUpperCase();
    if (normalized.isEmpty) return 0;

    var hash = 0;
    for (final unit in normalized.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash % length;
  }

  static Color? parseHexColor(String? raw) {
    final source = (raw ?? '').trim();
    if (source.isEmpty) return null;
    final hex = source.replaceFirst('#', '');
    final expanded = hex.length == 6 ? 'FF$hex' : hex;
    final value = int.tryParse(expanded, radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  static String colorToHex(Color color) {
    int channel(double value) => (value * 255.0).round().clamp(0, 255).toInt();
    final red = channel(color.r);
    final green = channel(color.g);
    final blue = channel(color.b);
    final hex =
        '${red.toRadixString(16).padLeft(2, '0')}'
        '${green.toRadixString(16).padLeft(2, '0')}'
        '${blue.toRadixString(16).padLeft(2, '0')}';
    return '#${hex.toUpperCase()}';
  }

  static SemanticColorTone toneFromColor(Color base, Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final foregroundBase = _shiftLightness(
      base,
      isDark ? 0.10 : -0.14,
      preserveSaturation: true,
    );
    final solidBrightness = ThemeData.estimateBrightnessForColor(base);
    return SemanticColorTone(
      base: base,
      container: Color.lerp(
        isDark ? const Color(0xFF1C2128) : Colors.white,
        base,
        isDark ? 0.20 : 0.12,
      )!,
      containerStrong: Color.lerp(
        isDark ? const Color(0xFF242A32) : Colors.white,
        base,
        isDark ? 0.34 : 0.20,
      )!,
      border: Color.lerp(
        isDark ? const Color(0xFF343B45) : const Color(0xFFE2E4E8),
        base,
        isDark ? 0.52 : 0.38,
      )!,
      foreground: foregroundBase,
      onSolid: solidBrightness == Brightness.dark
          ? Colors.white
          : Colors.black.withAlpha(215),
    );
  }

  static List<Color> _categoryPalette(String accentId, Brightness brightness) {
    switch (accentId) {
      case appAccentPurple:
        return brightness == Brightness.dark
            ? _purpleCategoryPaletteDark
            : _purpleCategoryPaletteLight;
      case appAccentNeutral:
        return brightness == Brightness.dark
            ? _neutralCategoryPaletteDark
            : _neutralCategoryPaletteLight;
      case appAccentMix:
      default:
        return brightness == Brightness.dark
            ? _mixCategoryPaletteDark
            : _mixCategoryPaletteLight;
    }
  }

  static List<Color> _labelPalette(String accentId, Brightness brightness) {
    switch (accentId) {
      case appAccentPurple:
        return brightness == Brightness.dark
            ? _purpleLabelPaletteDark
            : _purpleLabelPaletteLight;
      case appAccentNeutral:
        return brightness == Brightness.dark
            ? _neutralLabelPaletteDark
            : _neutralLabelPaletteLight;
      case appAccentMix:
      default:
        return brightness == Brightness.dark
            ? _mixLabelPaletteDark
            : _mixLabelPaletteLight;
    }
  }

  static List<AppColorPickerOption> _colorOptionsFromPalettes({
    required List<Color> storedPalette,
    required List<Color> previewPalette,
  }) {
    final length = math.min(storedPalette.length, previewPalette.length);
    return List<AppColorPickerOption>.generate(
      length,
      (index) => AppColorPickerOption(
        storedHex: colorToHex(storedPalette[index]),
        previewColor: previewPalette[index],
      ),
      growable: false,
    );
  }

  static int? _paletteSlotForRawHex(String? rawHex, List<Color> palette) {
    final rawColor = parseHexColor(rawHex);
    if (rawColor == null) return null;
    final normalized = colorToHex(rawColor);
    for (var index = 0; index < palette.length; index++) {
      if (colorToHex(palette[index]) == normalized) {
        return index;
      }
    }
    return null;
  }

  static T _pickIndexed<T>(List<T> items, int index) {
    if (items.isEmpty) {
      throw ArgumentError('items must not be empty');
    }
    final safeIndex = index.clamp(0, items.length - 1);
    return items[safeIndex];
  }

  static String _normalizeToken(String? raw) =>
      (raw ?? '').trim().toUpperCase();

  static Color _shiftLightness(
    Color color,
    double delta, {
    bool preserveSaturation = false,
  }) {
    final hsl = HSLColor.fromColor(color);
    final nextLightness = (hsl.lightness + delta).clamp(0.0, 1.0);
    final nextSaturation = preserveSaturation
        ? math.max(0.18, hsl.saturation)
        : hsl.saturation;
    return hsl
        .withLightness(nextLightness)
        .withSaturation(nextSaturation.clamp(0.0, 1.0))
        .toColor();
  }
}
