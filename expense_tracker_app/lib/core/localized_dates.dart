import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

String localizedMonthName(
  AppLocalizations l10n,
  int month, {
  bool abbreviated = false,
}) {
  if (month < DateTime.january || month > DateTime.december) {
    throw RangeError.range(month, DateTime.january, DateTime.december, 'month');
  }
  final keys = abbreviated ? _shortMonthKeys : _fullMonthKeys;
  return l10n.tr(keys[month - 1]);
}

const _fullMonthKeys = <String>[
  'month_full_01',
  'month_full_02',
  'month_full_03',
  'month_full_04',
  'month_full_05',
  'month_full_06',
  'month_full_07',
  'month_full_08',
  'month_full_09',
  'month_full_10',
  'month_full_11',
  'month_full_12',
];

const _shortMonthKeys = <String>[
  'month_short_01',
  'month_short_02',
  'month_short_03',
  'month_short_04',
  'month_short_05',
  'month_short_06',
  'month_short_07',
  'month_short_08',
  'month_short_09',
  'month_short_10',
  'month_short_11',
  'month_short_12',
];

String formatLocalizedFullMonth(BuildContext context, DateTime date) {
  return localizedMonthName(AppLocalizations.of(context), date.month);
}

String formatLocalizedShortMonth(BuildContext context, DateTime date) {
  return localizedMonthName(
    AppLocalizations.of(context),
    date.month,
    abbreviated: true,
  );
}

String formatLocalizedMonthYear(BuildContext context, DateTime date) {
  final month = formatLocalizedFullMonth(context, date);
  switch (_languageCode(context)) {
    case 'zh':
    case 'ja':
      return '${date.year}年$month';
    case 'ko':
      return '${date.year}년 $month';
    default:
      return '$month ${date.year}';
  }
}

String formatLocalizedDayMonthYear(BuildContext context, DateTime date) {
  final month = formatLocalizedShortMonth(context, date);
  final day = date.day.toString();
  switch (_languageCode(context)) {
    case 'en':
      return '$month $day, ${date.year}';
    case 'zh':
    case 'ja':
      return '${date.year}年$month$day日';
    case 'ko':
      return '${date.year}년 $month $day일';
    default:
      return '$day $month ${date.year}';
  }
}

String formatLocalizedDayMonthTime(BuildContext context, DateTime date) {
  final month = formatLocalizedShortMonth(context, date);
  final day = date.day.toString();
  final time = _formatTime(date);
  switch (_languageCode(context)) {
    case 'en':
      return '$month $day, $time';
    case 'zh':
    case 'ja':
      return '$month$day日 $time';
    case 'ko':
      return '$month $day일 $time';
    default:
      return '$day $month, $time';
  }
}

String formatLocalizedDayMonthYearTime(BuildContext context, DateTime date) {
  return '${formatLocalizedDayMonthYear(context, date)} ${_formatTime(date)}';
}

String _languageCode(BuildContext context) {
  return Localizations.localeOf(context).languageCode.toLowerCase();
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
