import 'package:flutter/foundation.dart';

import 'period_filter.dart';

@immutable
class AnalyticsFilters {
  const AnalyticsFilters({
    this.period = PeriodFilter.last3Months,
    this.customRange,
    this.categoryIds = const <String>[],
    this.subcategoryIds = const <String>[],
    this.labelIds = const <String>[],
  });

  final String period;
  final PeriodDateRange? customRange;
  final List<String> categoryIds;
  final List<String> subcategoryIds;
  final List<String> labelIds;

  PeriodDateRange get dateRange =>
      PeriodFilter.getRange(period, customRange: customRange);

  int get periodDays =>
      PeriodFilter.getPeriodDays(period, customRange: customRange);

  bool get hasScopedFilters =>
      categoryIds.isNotEmpty ||
      subcategoryIds.isNotEmpty ||
      labelIds.isNotEmpty;

  int get activeFilterCount {
    var count = 0;
    if (categoryIds.isNotEmpty) count++;
    if (subcategoryIds.isNotEmpty) count++;
    if (labelIds.isNotEmpty) count++;
    return count;
  }

  AnalyticsFilters copyWith({
    String? period,
    PeriodDateRange? customRange,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
  }) {
    return AnalyticsFilters(
      period: period ?? this.period,
      customRange: period != null && period != PeriodFilter.custom
          ? null
          : customRange ?? this.customRange,
      categoryIds: categoryIds ?? this.categoryIds,
      subcategoryIds: subcategoryIds ?? this.subcategoryIds,
      labelIds: labelIds ?? this.labelIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnalyticsFilters &&
        other.period == period &&
        other.customRange == customRange &&
        listEquals(other.categoryIds, categoryIds) &&
        listEquals(other.subcategoryIds, subcategoryIds) &&
        listEquals(other.labelIds, labelIds);
  }

  @override
  int get hashCode => Object.hash(
    period,
    customRange,
    Object.hashAll(categoryIds),
    Object.hashAll(subcategoryIds),
    Object.hashAll(labelIds),
  );
}
