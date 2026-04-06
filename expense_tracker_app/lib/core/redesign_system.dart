import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class ShellColors {
  static const Color lightBackground = Color(0xFFF6F7F8);
  static const Color lightSurface = Colors.white;
  static const Color lightSurfaceAlt = Color(0xFFF1F2F4);
  static const Color lightBorder = Color(0xFFE2E4E8);
  static const Color lightText = Color(0xFF191716);
  static const Color lightMuted = Color(0xFF767A84);
  static const Color lightAccent = Color(0xFF1C1A19);

  static const Color darkBackground = Color(0xFF101114);
  static const Color darkSurface = Color(0xFF171A1F);
  static const Color darkSurfaceAlt = Color(0xFF1D2128);
  static const Color darkBorder = Color(0xFF2A2F37);
  static const Color darkText = Color(0xFFF5F1EA);
  static const Color darkMuted = Color(0xFF9A958B);
  static const Color darkAccent = Color(0xFFE9E1D2);

  static const Color gold = Color(0xFFD6A94D);
  static const Color softGreen = Color(0xFF4F9B68);
  static const Color softRed = Color(0xFFB2584E);
  static const Color softBlue = Color(0xFF5F7FD5);
}

class ShellStyles {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static double textScale(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1);

  static double densityScale(
    BuildContext context, {
    double min = 0.86,
    double max = 1.12,
  }) {
    final rawScale = textScale(context);
    final adjusted = 1 + ((rawScale - 1) * 0.45);
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

  static Color background(BuildContext context) => isDark(context)
      ? ShellColors.darkBackground
      : ShellColors.lightBackground;

  static Color surface(BuildContext context) =>
      isDark(context) ? ShellColors.darkSurface : ShellColors.lightSurface;

  static Color surfaceAlt(BuildContext context) => isDark(context)
      ? ShellColors.darkSurfaceAlt
      : ShellColors.lightSurfaceAlt;

  static Color border(BuildContext context) =>
      isDark(context) ? ShellColors.darkBorder : ShellColors.lightBorder;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? ShellColors.darkText : ShellColors.lightText;

  static Color textMuted(BuildContext context) =>
      isDark(context) ? ShellColors.darkMuted : ShellColors.lightMuted;

  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static BoxDecoration cardDecoration(
    BuildContext context, {
    double radius = 22,
    Color? color,
    bool withShadow = true,
  }) {
    return BoxDecoration(
      color: color ?? surface(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border(context)),
      boxShadow: withShadow
          ? [
              BoxShadow(
                color: Colors.black.withAlpha(isDark(context) ? 20 : 10),
                blurRadius: isDark(context) ? 12 : 14,
                offset: const Offset(0, 4),
              ),
            ]
          : const [],
    );
  }

  static BoxDecoration iconBadgeDecoration(
    BuildContext context, {
    Color? color,
    double radius = 14,
  }) {
    final badgeColor = color ?? surfaceAlt(context);
    return BoxDecoration(
      color: badgeColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border(context)),
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
