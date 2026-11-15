import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Keep API decimals canonical while accepting decimal keyboards in supported locales.
String? normalizeReceiptFilterAmount(String value) {
  final result = StringBuffer();
  for (final rune in value.trim().runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      result.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06f0 && rune <= 0x06f9) {
      result.writeCharCode(0x30 + rune - 0x06f0);
    } else if (rune == 0x2c || rune == 0x066b) {
      result.write('.');
    } else if (rune == 0x2212) {
      result.write('-');
    } else if (rune != 0x061c && rune != 0x200e && rune != 0x200f) {
      result.writeCharCode(rune);
    }
  }
  final text = result.toString();
  return text.isEmpty ? null : text;
}

String formatReceiptFilterBound(BuildContext context, String amount) {
  final value = num.tryParse(amount);
  if (value == null) return amount;
  final formatter = NumberFormat.decimalPattern(
    Localizations.localeOf(context).languageCode,
  );
  final fraction = amount.contains('.') ? amount.split('.').last.length : 0;
  formatter.minimumFractionDigits = fraction.clamp(0, 2);
  formatter.maximumFractionDigits = 2;
  return formatter.format(value);
}

String formatReceiptFilterRange(
  BuildContext context, {
  required String currency,
  String? minimum,
  String? maximum,
}) {
  final min = minimum == null
      ? null
      : formatReceiptFilterBound(context, minimum);
  final max = maximum == null
      ? null
      : formatReceiptFilterBound(context, maximum);
  final range = min != null && max != null
      ? '$min – $max'
      : min != null
      ? '≥ $min'
      : '≤ $max';
  return '$currency $range';
}
