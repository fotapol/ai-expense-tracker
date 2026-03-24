import 'package:flutter/foundation.dart';

import 'period_filter.dart';

@immutable
class AnalyticsFilters {
  const AnalyticsFilters({
    this.period = PeriodFilter.last3Months,
    this.categoryIds = const <String>[],
    this.subcategoryIds = const <String>[],
    this.labelIds = const <String>[],
  });

  final String period;
  final List<String> categoryIds;
  final List<String> subcategoryIds;
  final List<String> labelIds;

  bool get hasScopedFilters =>
      categoryIds.isNotEmpty ||
      subcategoryIds.isNotEmpty ||
      labelIds.isNotEmpty;

  int get activeFilterCount {
    var count = 0;
    if (period != PeriodFilter.last3Months) count++;
    if (categoryIds.isNotEmpty) count++;
    if (subcategoryIds.isNotEmpty) count++;
    if (labelIds.isNotEmpty) count++;
    return count;
  }

  AnalyticsFilters copyWith({
    String? period,
    List<String>? categoryIds,
    List<String>? subcategoryIds,
    List<String>? labelIds,
  }) {
    return AnalyticsFilters(
      period: period ?? this.period,
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
        listEquals(other.categoryIds, categoryIds) &&
        listEquals(other.subcategoryIds, subcategoryIds) &&
        listEquals(other.labelIds, labelIds);
  }

  @override
  int get hashCode => Object.hash(
    period,
    Object.hashAll(categoryIds),
    Object.hashAll(subcategoryIds),
    Object.hashAll(labelIds),
  );
}
