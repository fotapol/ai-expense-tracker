class PeriodFilter {
  static const String last30Days = 'Last 30 days';
  static const String last3Months = 'Last 3 months';
  static const String thisYear = 'This year';
  
  static const List<String> values = [
    last30Days,
    last3Months,
    thisYear,
  ];

  static DateTime getStartDate(String filter) {
    final now = DateTime.now();
    switch (filter) {
      case last30Days:
        return now.subtract(const Duration(days: 30));
      case last3Months:
        return DateTime(now.year, now.month - 3, now.day);
      case thisYear:
        return DateTime(now.year, 1, 1);
      default:
        return now.subtract(const Duration(days: 30));
    }
  }
}
