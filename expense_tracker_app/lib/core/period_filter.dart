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

  /// Returns the start date for the given filter, or null for All Time.
  static DateTime? getStartDate(String filter) {
    final now = DateTime.now();
    switch (filter) {
      case last7Days:
        return now.subtract(const Duration(days: 7));
      case thisMonth:
        return DateTime(now.year, now.month, 1);
      case last30Days:
        return now.subtract(const Duration(days: 30));
      case last3Months:
        return now.subtract(const Duration(days: 90));
      case last6Months:
        return now.subtract(const Duration(days: 180));
      case last12Months:
        return now.subtract(const Duration(days: 365));
      case thisYear:
        return DateTime(now.year, 1, 1);
      case allTime:
        return null;
      default:
        return now.subtract(const Duration(days: 90));
    }
  }

  /// Returns the number of days in the selected period for average calculations.
  static int getPeriodDays(String filter) {
    final now = DateTime.now();
    switch (filter) {
      case last7Days:
        return 7;
      case thisMonth:
        return now.day;
      case last30Days:
        return 30;
      case last3Months:
        return 90;
      case last6Months:
        return 180;
      case last12Months:
        return 365;
      case thisYear:
        return now.difference(DateTime(now.year, 1, 1)).inDays.clamp(1, 366);
      case allTime:
        return 365; // Reasonable default for average
      default:
        return 90;
    }
  }
}
