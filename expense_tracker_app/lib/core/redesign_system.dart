import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_color_semantics.dart';
import '../l10n/app_localizations.dart';

class ShellColors {
  static const Color lightBackground = Color(0xFFF6F7F8);
  static const Color lightSectionBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Colors.white;
  static const Color lightSurfaceAlt = Color(0xFFF1F2F4);
  static const Color lightInputSurface = Color(0xFFF6F7F9);
  static const Color lightHeroSurface = Color(0xFF1C1A19);
  static const Color lightBorder = Color(0xFFE2E4E8);
  static const Color lightDivider = Color(0xFFE0E3E8);
  static const Color lightText = Color(0xFF191716);
  static const Color lightTextSecondary = Color(0xFF555C67);
  static const Color lightMuted = Color(0xFF767A84);
  static const Color lightDisabled = Color(0xFFA5ACB8);
  static const Color lightAccent = Color(0xFF1C1A19);
  static const Color lightSelectedSurface = Color(0xFFF0F2F5);
  static const Color lightPressedOverlay = Color(0x14000000);
  static const Color lightFocusRing = Color(0xFFAFB8C5);
  static const Color lightScrim = Color(0xA6000000);
  static const Color lightTooltipSurface = Color(0xFF171717);
  static const Color lightTooltipText = Colors.white;

  static const Color darkBackground = Color(0xFF111418);
  static const Color darkSectionBackground = Color(0xFF161A20);
  static const Color darkSurface = Color(0xFF1C2128);
  static const Color darkSurfaceAlt = Color(0xFF242A32);
  static const Color darkInputSurface = Color(0xFF2B313A);
  static const Color darkHeroSurface = Color(0xFF323944);
  static const Color darkBorder = Color(0xFF343B45);
  static const Color darkDivider = Color(0xFF3A424D);
  static const Color darkText = Color(0xFFF2F5F7);
  static const Color darkTextSecondary = Color(0xFFC9D0D8);
  static const Color darkMuted = Color(0xFF929CAA);
  static const Color darkDisabled = Color(0xFF65707E);
  static const Color darkAccent = Color(0xFFE9E1D2);
  static const Color darkSelectedSurface = Color(0xFF242A32);
  static const Color darkPressedOverlay = Color(0x14F2F5F7);
  static const Color darkFocusRing = Color(0xFF697382);
  static const Color darkScrim = Color(0xB806080A);
  static const Color darkTooltipSurface = Color(0xFF2B313A);
  static const Color darkTooltipText = Color(0xFFF2F5F7);

  static const Color gold = Color(0xFFD3AF68);
  static const Color softGreen = Color(0xFF5E9B78);
  static const Color softRed = Color(0xFFC06A63);
  static const Color softBlue = Color(0xFF6D89C9);

  static const List<Color> chartRampLight = <Color>[
    Color(0xFF171717),
    Color(0xFF34312F),
    Color(0xFF4C4946),
    Color(0xFF64615D),
    Color(0xFF7C7873),
    Color(0xFF95918B),
  ];

  static const List<Color> chartRampDark = <Color>[
    Color(0xFFF3F6F8),
    Color(0xFFD7DDE4),
    Color(0xFFB7C0CA),
    Color(0xFF8F99A7),
    Color(0xFF697382),
    Color(0xFF4B5460),
  ];
}

@immutable
class ShellPalette extends ThemeExtension<ShellPalette> {
  const ShellPalette({
    required this.pageBackground,
    required this.sectionBackground,
    required this.standardSurface,
    required this.elevatedSurface,
    required this.inputSurface,
    required this.heroSurface,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.success,
    required this.error,
    required this.warningPremium,
    required this.info,
    required this.selectedSurface,
    required this.pressedOverlay,
    required this.focusRing,
    required this.scrim,
    required this.tooltipSurface,
    required this.tooltipText,
  });

  factory ShellPalette.light() {
    return const ShellPalette(
      pageBackground: ShellColors.lightBackground,
      sectionBackground: ShellColors.lightSectionBackground,
      standardSurface: ShellColors.lightSurface,
      elevatedSurface: ShellColors.lightSurfaceAlt,
      inputSurface: ShellColors.lightInputSurface,
      heroSurface: ShellColors.lightHeroSurface,
      border: ShellColors.lightBorder,
      divider: ShellColors.lightDivider,
      textPrimary: ShellColors.lightText,
      textSecondary: ShellColors.lightTextSecondary,
      textMuted: ShellColors.lightMuted,
      textDisabled: ShellColors.lightDisabled,
      success: ShellColors.softGreen,
      error: ShellColors.softRed,
      warningPremium: ShellColors.gold,
      info: ShellColors.softBlue,
      selectedSurface: ShellColors.lightSelectedSurface,
      pressedOverlay: ShellColors.lightPressedOverlay,
      focusRing: ShellColors.lightFocusRing,
      scrim: ShellColors.lightScrim,
      tooltipSurface: ShellColors.lightTooltipSurface,
      tooltipText: ShellColors.lightTooltipText,
    );
  }

  factory ShellPalette.dark() {
    return const ShellPalette(
      pageBackground: ShellColors.darkBackground,
      sectionBackground: ShellColors.darkSectionBackground,
      standardSurface: ShellColors.darkSurface,
      elevatedSurface: ShellColors.darkSurfaceAlt,
      inputSurface: ShellColors.darkInputSurface,
      heroSurface: ShellColors.darkHeroSurface,
      border: ShellColors.darkBorder,
      divider: ShellColors.darkDivider,
      textPrimary: ShellColors.darkText,
      textSecondary: ShellColors.darkTextSecondary,
      textMuted: ShellColors.darkMuted,
      textDisabled: ShellColors.darkDisabled,
      success: ShellColors.softGreen,
      error: ShellColors.softRed,
      warningPremium: ShellColors.gold,
      info: ShellColors.softBlue,
      selectedSurface: ShellColors.darkSelectedSurface,
      pressedOverlay: ShellColors.darkPressedOverlay,
      focusRing: ShellColors.darkFocusRing,
      scrim: ShellColors.darkScrim,
      tooltipSurface: ShellColors.darkTooltipSurface,
      tooltipText: ShellColors.darkTooltipText,
    );
  }

  final Color pageBackground;
  final Color sectionBackground;
  final Color standardSurface;
  final Color elevatedSurface;
  final Color inputSurface;
  final Color heroSurface;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color success;
  final Color error;
  final Color warningPremium;
  final Color info;
  final Color selectedSurface;
  final Color pressedOverlay;
  final Color focusRing;
  final Color scrim;
  final Color tooltipSurface;
  final Color tooltipText;

  @override
  ShellPalette copyWith({
    Color? pageBackground,
    Color? sectionBackground,
    Color? standardSurface,
    Color? elevatedSurface,
    Color? inputSurface,
    Color? heroSurface,
    Color? border,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? success,
    Color? error,
    Color? warningPremium,
    Color? info,
    Color? selectedSurface,
    Color? pressedOverlay,
    Color? focusRing,
    Color? scrim,
    Color? tooltipSurface,
    Color? tooltipText,
  }) {
    return ShellPalette(
      pageBackground: pageBackground ?? this.pageBackground,
      sectionBackground: sectionBackground ?? this.sectionBackground,
      standardSurface: standardSurface ?? this.standardSurface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      inputSurface: inputSurface ?? this.inputSurface,
      heroSurface: heroSurface ?? this.heroSurface,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      success: success ?? this.success,
      error: error ?? this.error,
      warningPremium: warningPremium ?? this.warningPremium,
      info: info ?? this.info,
      selectedSurface: selectedSurface ?? this.selectedSurface,
      pressedOverlay: pressedOverlay ?? this.pressedOverlay,
      focusRing: focusRing ?? this.focusRing,
      scrim: scrim ?? this.scrim,
      tooltipSurface: tooltipSurface ?? this.tooltipSurface,
      tooltipText: tooltipText ?? this.tooltipText,
    );
  }

  @override
  ShellPalette lerp(ThemeExtension<ShellPalette>? other, double t) {
    if (other is! ShellPalette) return this;
    return ShellPalette(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      sectionBackground: Color.lerp(
        sectionBackground,
        other.sectionBackground,
        t,
      )!,
      standardSurface: Color.lerp(standardSurface, other.standardSurface, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      inputSurface: Color.lerp(inputSurface, other.inputSurface, t)!,
      heroSurface: Color.lerp(heroSurface, other.heroSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warningPremium: Color.lerp(warningPremium, other.warningPremium, t)!,
      info: Color.lerp(info, other.info, t)!,
      selectedSurface: Color.lerp(selectedSurface, other.selectedSurface, t)!,
      pressedOverlay: Color.lerp(pressedOverlay, other.pressedOverlay, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      tooltipSurface: Color.lerp(tooltipSurface, other.tooltipSurface, t)!,
      tooltipText: Color.lerp(tooltipText, other.tooltipText, t)!,
    );
  }
}

class ShellStyles {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static ShellPalette palette(BuildContext context) =>
      Theme.of(context).extension<ShellPalette>() ??
      (isDark(context) ? ShellPalette.dark() : ShellPalette.light());

  static double textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1);

  static double densityScale(
    BuildContext context, {
    double min = 0.86,
    double max = 1.12,
  }) {
    final rawScale = textScale(context);
    final adjusted = 1 + ((rawScale - 1) * 0.65);
    return adjusted.clamp(min, max);
  }

  static double scaled(
    BuildContext context,
    double base, {
    double minFactor = 0.86,
    double maxFactor = 1.12,
    double? min,
    double? max,
  }) {
    var value = base * densityScale(context, min: minFactor, max: maxFactor);
    if (min != null) {
      value = math.max(value, min);
    }
    if (max != null) {
      value = math.min(value, max);
    }
    return value;
  }

  static EdgeInsets scaledInsets(
    BuildContext context, {
    double horizontal = 16,
    double vertical = 16,
    double minHorizontal = 12,
    double minVertical = 10,
  }) {
    return EdgeInsets.symmetric(
      horizontal: scaled(context, horizontal, min: minHorizontal),
      vertical: scaled(context, vertical, min: minVertical),
    );
  }

  static double minTapTarget(BuildContext context, {double base = 46}) =>
      scaled(context, base, min: 44, max: 56);

  static Widget clampOverlayScale(
    BuildContext context,
    Widget child, {
    double minTextScale = 0.9,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final currentScale = textScale(context);
    if (currentScale >= minTextScale) {
      return child;
    }
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(minTextScale)),
      child: child,
    );
  }

  static Color background(BuildContext context) =>
      palette(context).pageBackground;

  static Color pageBackground(BuildContext context) =>
      palette(context).pageBackground;

  static Color sectionBackground(BuildContext context) =>
      palette(context).sectionBackground;

  static Color surface(BuildContext context) =>
      palette(context).standardSurface;

  static Color standardSurface(BuildContext context) =>
      palette(context).standardSurface;

  static Color surfaceAlt(BuildContext context) =>
      palette(context).elevatedSurface;

  static Color elevatedSurface(BuildContext context) =>
      palette(context).elevatedSurface;

  static Color inputSurface(BuildContext context) =>
      palette(context).inputSurface;

  static Color heroSurface(BuildContext context) =>
      palette(context).heroSurface;

  static Color border(BuildContext context) => palette(context).border;

  static Color divider(BuildContext context) => palette(context).divider;

  static Color textPrimary(BuildContext context) =>
      palette(context).textPrimary;

  static Color textSecondary(BuildContext context) =>
      palette(context).textSecondary;

  static Color textMuted(BuildContext context) => palette(context).textMuted;

  static Color textDisabled(BuildContext context) =>
      palette(context).textDisabled;

  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static AppSemanticThemeExtension semanticTheme(BuildContext context) =>
      Theme.of(context).extension<AppSemanticThemeExtension>() ??
      AppSemanticThemeExtension(
        accentId: appAccentMix,
        labelColorMode: AppLabelColorMode.raw,
        mixHomeAccentIndex: 0,
        brightness: Theme.of(context).brightness,
      );

  static String accentId(BuildContext context) =>
      semanticTheme(context).accentId;

  static AppLabelColorMode labelColorMode(BuildContext context) =>
      semanticTheme(context).labelColorMode;

  static SemanticColorTone accentTone(BuildContext context) =>
      semanticTheme(context).accentTone;

  static SemanticColorTone categoryTone(
    BuildContext context, {
    String? code,
    String? parentCode,
    String? name,
  }) => semanticTheme(
    context,
  ).categoryTone(code: code, parentCode: parentCode, name: name);

  static SemanticColorTone labelTone(
    BuildContext context, {
    String? labelId,
    String? name,
    String? rawHex,
  }) => semanticTheme(
    context,
  ).labelTone(labelId: labelId, name: name, rawHex: rawHex);

  static HeroAccentTone homeHeroTone(BuildContext context) =>
      semanticTheme(context).homeHeroTone;

  static List<Color> trendPalette(BuildContext context) =>
      semanticTheme(context).trendPalette;

  static Color success(BuildContext context) => palette(context).success;

  static Color error(BuildContext context) => palette(context).error;

  static Color warningPremium(BuildContext context) =>
      palette(context).warningPremium;

  static Color info(BuildContext context) => palette(context).info;

  static Color selectedSurface(BuildContext context) =>
      palette(context).selectedSurface;

  static Color pressedOverlay(BuildContext context) =>
      palette(context).pressedOverlay;

  static Color focusRing(BuildContext context) => palette(context).focusRing;

  static Color scrim(BuildContext context) => palette(context).scrim;

  static Color tooltipSurface(BuildContext context) =>
      palette(context).tooltipSurface;

  static Color tooltipText(BuildContext context) =>
      palette(context).tooltipText;

  static List<Color> chartRamp(BuildContext context) =>
      semanticTheme(context).chartRamp;

  static Color chartOtherColor(BuildContext context) =>
      semanticTheme(context).chartOtherColor;

  static Color chartGrid(BuildContext context) =>
      divider(context).withAlpha(isDark(context) ? 170 : 120);

  static Color chartAxis(BuildContext context) => textMuted(context);

  static Color heroTextPrimary(BuildContext context) =>
      isDark(context) ? textPrimary(context) : Colors.white;

  static Color heroTextSecondary(BuildContext context) =>
      isDark(context) ? textSecondary(context) : Colors.white.withAlpha(210);

  static Color heroBadgeSurface(BuildContext context) =>
      isDark(context) ? elevatedSurface(context) : Colors.white.withAlpha(14);

  static Color heroBadgeBorder(BuildContext context) =>
      isDark(context) ? border(context) : Colors.white.withAlpha(24);

  static Color heroBadgeIcon(BuildContext context) =>
      isDark(context) ? textPrimary(context) : Colors.white;

  static Color homeHeroTextPrimary(BuildContext context) =>
      homeHeroTone(context).foreground;

  static Color homeHeroTextSecondary(BuildContext context) =>
      homeHeroTone(context).secondaryForeground;

  static Color homeHeroBadgeSurface(BuildContext context) =>
      homeHeroTone(context).badgeFill;

  static Color homeHeroBadgeBorder(BuildContext context) =>
      homeHeroTone(context).badgeBorder;

  static Color homeHeroBadgeIcon(BuildContext context) =>
      homeHeroTone(context).badgeForeground;

  static BoxDecoration cardDecoration(
    BuildContext context, {
    double radius = 22,
    Color? color,
    bool withShadow = true,
  }) {
    return BoxDecoration(
      color: color ?? standardSurface(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border(context)),
      boxShadow: withShadow
          ? [
              BoxShadow(
                color: Colors.black.withAlpha(isDark(context) ? 22 : 10),
                blurRadius: isDark(context) ? 10 : 14,
                offset: Offset(0, isDark(context) ? 2 : 4),
              ),
            ]
          : const [],
    );
  }

  static BoxDecoration heroCardDecoration(
    BuildContext context, {
    double radius = 22,
    Color? highlight,
    HeroAccentTone? tone,
  }) {
    if (tone != null) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tone.gradientColors,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: tone.border.withAlpha(184)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha(isDark(context) ? 24 : 18),
            blurRadius: isDark(context) ? 16 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      );
    }
    final base = heroSurface(context);
    final top = isDark(context)
        ? Color.lerp(base, elevatedSurface(context), 0.18)!
        : const Color(0xFF181716);
    final bottom = isDark(context)
        ? Color.lerp(base, standardSurface(context), 0.12)!
        : const Color(0xFF36312D);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[top, bottom],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: (highlight ?? border(context)).withAlpha(170)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withAlpha(isDark(context) ? 22 : 18),
          blurRadius: isDark(context) ? 16 : 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration iconBadgeDecoration(
    BuildContext context, {
    Color? color,
    double radius = 14,
  }) {
    final badgeColor = color ?? elevatedSurface(context);
    return BoxDecoration(
      color: badgeColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border(context)),
    );
  }

  static BoxDecoration semanticBadgeDecoration(
    BuildContext context, {
    required SemanticColorTone tone,
    double radius = 14,
    bool filled = false,
  }) {
    return BoxDecoration(
      color: filled ? tone.base : tone.container,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: filled ? tone.base : tone.border),
    );
  }

  static Widget sectionLabel(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: textMuted(context),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
      ),
    );
  }

  static void showComingSoon(BuildContext context, {String? message}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? context.tr('settings_feature_coming_soon')),
      ),
    );
  }
}

class AppIcons {
  static const IconData premium = CupertinoIcons.sparkles;
  static const IconData scan = CupertinoIcons.viewfinder;
  static const IconData scanFab = CupertinoIcons.viewfinder;
  static const IconData home = Icons.home_outlined;
  static const IconData homeFilled = Icons.home;
  static const IconData tools = Icons.build_outlined;
  static const IconData toolsFilled = Icons.build;
  static const IconData settings = Icons.settings_outlined;
  static const IconData settingsFilled = Icons.settings;
  static const IconData group = CupertinoIcons.group;
  static const IconData person = CupertinoIcons.person;
  static const IconData lock = CupertinoIcons.lock;
  static const IconData appearance = CupertinoIcons.paintbrush;
  static const IconData notifications = CupertinoIcons.bell;
  static const IconData language = CupertinoIcons.globe;
  static const IconData currency = CupertinoIcons.money_dollar;
  static const IconData translate = Icons.translate;
  static const IconData help = CupertinoIcons.question_circle;
  static const IconData feature = CupertinoIcons.wand_stars;
  static const IconData privacy = CupertinoIcons.shield;
  static const IconData document = CupertinoIcons.doc_text;
  static const IconData info = CupertinoIcons.info_circle;
  static const IconData logout = CupertinoIcons.square_arrow_right;
  static const IconData search = CupertinoIcons.search;
  static const IconData chevronRight = CupertinoIcons.chevron_right;
  static const IconData chevronDown = CupertinoIcons.chevron_down;
  static const IconData check = Icons.check;
  static const IconData checkCircle = CupertinoIcons.check_mark_circled_solid;
  static const IconData add = CupertinoIcons.add;
  static const IconData receipt = CupertinoIcons.doc_text;
  static const IconData analytics = CupertinoIcons.chart_bar;
  static const IconData analyticsAlt = CupertinoIcons.chart_pie;
  static const IconData category = CupertinoIcons.tag;
  static const IconData labels = Icons.label_outlined;
  static const IconData budget = CupertinoIcons.plusminus;
  static const IconData export = CupertinoIcons.tray_arrow_down;
  static const IconData importData = CupertinoIcons.tray_arrow_up;
  static const IconData photo = CupertinoIcons.photo_camera;
  static const IconData sun = CupertinoIcons.sun_max;
  static const IconData moon = CupertinoIcons.moon;
  static const IconData auto = CupertinoIcons.desktopcomputer;
  static const IconData refresh = CupertinoIcons.arrow_clockwise;
  static const IconData insight = CupertinoIcons.wand_stars;
}

class CurrencyDisplay {
  static String symbolForCode(String code) {
    switch (code.toUpperCase()) {
      case 'EUR':
        return '\u20AC';
      case 'USD':
        return '\$';
      case 'GBP':
        return '\u00A3';
      case 'AUD':
        return 'A\$';
      case 'CAD':
        return 'C\$';
      case 'CHF':
        return 'Fr';
      case 'JPY':
        return '\u00A5';
      case 'CNY':
        return '\u00A5';
      case 'KRW':
        return '\u20A9';
      case 'INR':
        return '\u20B9';
      case 'BRL':
        return 'R\$';
      case 'RSD':
        return 'RSD';
      case 'RUB':
        return '\u20BD'; // ₽
      case 'MXN':
        return 'Mex\$';
      case 'ZAR':
        return 'R';
      case 'SGD':
        return 'S\$';
      default:
        return code.toUpperCase();
    }
  }

  static String labelForCode(String code) {
    final symbol = symbolForCode(code);
    if (symbol == code.toUpperCase()) {
      return symbol;
    }
    return symbol;
  }
}

class CrownIcon extends StatelessWidget {
  const CrownIcon({
    super.key,
    required this.color,
    this.size = 20,
    this.strokeWidth = 1.8,
  });

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _CrownPainter(color, strokeWidth),
    );
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter(this.color, this.strokeWidth);

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.25)
      ..lineTo(size.width * 0.15, size.height * 0.8)
      ..lineTo(size.width * 0.85, size.height * 0.8)
      ..lineTo(size.width * 0.85, size.height * 0.25)
      ..lineTo(size.width * 0.65, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.15)
      ..lineTo(size.width * 0.35, size.height * 0.5)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
