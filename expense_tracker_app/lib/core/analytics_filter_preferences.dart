import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_filters.dart';
import 'period_filter.dart';

class AnalyticsFilterPreferences {
  static const _customStart = 'analytics_custom_start_date';
  static const _customEnd = 'analytics_custom_end_date';

  static DateTime? _parseDate(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    return parsed != null && _dateString(parsed) == value ? parsed : null;
  }

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static AnalyticsFilters load(SharedPreferences preferences) {
    var period = preferences.getString('analytics_period');
    if (!PeriodFilter.values.contains(period)) {
      period = PeriodFilter.last3Months;
    }
    PeriodDateRange? range;
    if (period == PeriodFilter.custom) {
      range = PeriodDateRange(
        start: _parseDate(preferences.getString(_customStart)),
        end: _parseDate(preferences.getString(_customEnd)),
      );
      if (!PeriodFilter.isValidCustomRange(range)) {
        period = PeriodFilter.last3Months;
        range = null;
      }
    }
    return AnalyticsFilters(
      period: period!,
      customRange: range,
      categoryIds:
          preferences.getStringList('analytics_category_ids') ?? const [],
      subcategoryIds:
          preferences.getStringList('analytics_subcategory_ids') ?? const [],
      labelIds: preferences.getStringList('analytics_label_ids') ?? const [],
    );
  }

  static Future<void> save(
    SharedPreferences preferences,
    AnalyticsFilters filters,
  ) async {
    if (filters.period == PeriodFilter.custom &&
        PeriodFilter.isValidCustomRange(filters.customRange)) {
      await preferences.setString(
        _customStart,
        _dateString(filters.customRange!.start!),
      );
      await preferences.setString(
        _customEnd,
        _dateString(filters.customRange!.end!),
      );
    } else {
      await preferences.remove(_customStart);
      await preferences.remove(_customEnd);
    }
    await preferences.setString('analytics_period', filters.period);
    await preferences.setStringList(
      'analytics_category_ids',
      filters.categoryIds,
    );
    await preferences.setStringList(
      'analytics_subcategory_ids',
      filters.subcategoryIds,
    );
    await preferences.setStringList('analytics_label_ids', filters.labelIds);
  }
}
