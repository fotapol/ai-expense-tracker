import 'package:flutter/material.dart';

/// Measures a Text widget using the same inherited font and accessibility data.
({double width, double height, double minWidth}) measureTextLayout(
  BuildContext context,
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
}) {
  var effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    effectiveStyle = effectiveStyle.copyWith(fontWeight: FontWeight.bold);
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: effectiveStyle),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
  )..layout(maxWidth: maxWidth);
  final result = (
    width: painter.width,
    height: painter.height,
    minWidth: painter.minIntrinsicWidth,
  );
  painter.dispose();
  return result;
}
