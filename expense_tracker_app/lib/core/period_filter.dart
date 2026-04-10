class PeriodDateRange {
  const PeriodDateRange({required this.start, required this.end});

  final DateTime? start;
  final DateTime? end;
}

class PeriodFilter {
  static const String last7Days = 'Last 7 Days';
  static const String thisMonth = 'This Month';
  static const String last30Days = 'Last 30 Days';
  static const String last3Months = 'Last 3 Months';
  static const String last6Months = 'Last 6 Months';
  static const String last12Months = 'Last 12 Months';
  static const String thisYear = 'This Year';
  static const String allTime = 'All Time';

  static const List<String> values = [
    last7Days,
    thisMonth,
    last30Days,
    last3Months,
    last6Months,
    last12Months,
    thisYear,
    allTime,
  ];

  static String localizationKey(String filter) {
    switch (filter) {
      case last7Days:
        return 'period_last_7_days';
      case thisMonth:
        return 'period_this_month';
      case last30Days:
        return 'period_last_30_days';
      case last3Months:
        return 'period_last_3_months';
      case last6Months:
        return 'period_last_6_months';
      case last12Months:
        return 'period_last_12_months';
      case thisYear:
        return 'period_this_year';
      case allTime:
        return 'period_all_time';
      default:
        return 'period_last_3_months';
    }
  }

  static DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static DateTime _endOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999, 999);
  }

  static DateTime _startOfMonth(DateTime value, int monthOffset) {
    return DateTime(value.year, value.month + monthOffset, 1);
  }

  static PeriodDateRange getRange(String filter) {
    final now = DateTime.now();
    final todayStart = _startOfDay(now);
    final todayEnd = _endOfDay(now);

    switch (filter) {
      case last7Days:
        return PeriodDateRange(
          start: todayStart.subtract(const Duration(days: 6)),
          end: todayEnd,
        );
      case thisMonth:
        return PeriodDateRange(
          start: DateTime(now.year, now.month, 1),
          end: todayEnd,
        );
      case last30Days:
        return PeriodDateRange(
          start: todayStart.subtract(const Duration(days: 29)),
          end: todayEnd,
        );
      case last3Months:
        return PeriodDateRange(start: _startOfMonth(now, -2), end: todayEnd);
      case last6Months:
        return PeriodDateRange(start: _startOfMonth(now, -5), end: todayEnd);
      case last12Months:
        return PeriodDateRange(start: _startOfMonth(now, -11), end: todayEnd);
      case thisYear:
        return PeriodDateRange(start: DateTime(now.year, 1, 1), end: todayEnd);
      case allTime:
        return PeriodDateRange(start: null, end: todayEnd);
      default:
        return PeriodDateRange(
          start: todayStart.subtract(const Duration(days: 89)),
          end: todayEnd,
        );
    }
  }

  /// Returns the start date for the given filter, or null for All Time.
  static DateTime? getStartDate(String filter) {
    return getRange(filter).start;
  }

  /// Returns the end date for the given filter.
  static DateTime? getEndDate(String filter) {
    return getRange(filter).end;
  }

  static PeriodDateRange? getPreviousMatchedRange(String filter) {
    final currentRange = getRange(filter);
    if (currentRange.start == null || currentRange.end == null) {
      return null;
    }

    final window = currentRange.end!.difference(currentRange.start!);
    final previousEnd = currentRange.start!.subtract(
      const Duration(microseconds: 1),
    );
    return PeriodDateRange(
      start: previousEnd.subtract(window),
      end: previousEnd,
    );
  }

  static String autoBucketUnit(String filter) {
    switch (filter) {
      case last7Days:
      case thisMonth:
      case last30Days:
        return 'day';
      case last3Months:
      case last6Months:
        return 'week';
      case last12Months:
      case thisYear:
      case allTime:
        return 'month';
      default:
        return 'week';
    }
  }

  /// Returns the number of days in the selected period for average calculations.
  static int getPeriodDays(String filter) {
    final range = getRange(filter);
    if (range.start == null || range.end == null) {
      return 365;
    }
    final inclusiveDays = range.end!.difference(range.start!).inDays + 1;
    switch (filter) {
      case last7Days:
        return 7;
      case thisMonth:
        return inclusiveDays;
      case last30Days:
        return 30;
      case last3Months:
        return inclusiveDays;
      case last6Months:
        return inclusiveDays;
      case last12Months:
        return inclusiveDays;
      case thisYear:
        return inclusiveDays.clamp(1, 366);
      case allTime:
        return 365; // Reasonable default for average
      default:
        return inclusiveDays.clamp(1, 3650);
    }
  }
}
