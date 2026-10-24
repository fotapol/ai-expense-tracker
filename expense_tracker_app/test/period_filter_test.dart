import 'package:expense_tracker_app/core/analytics_filters.dart';
import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('custom periods', () {
    test('includes the full first and last day', () {
      final range = PeriodFilter.getRange(
        PeriodFilter.custom,
        customRange: PeriodDateRange(
          start: DateTime(2026, 1, 10, 14),
          end: DateTime(2026, 1, 12, 8),
        ),
      );
      expect(range.start, DateTime(2026, 1, 10));
      expect(range.end, DateTime(2026, 1, 12, 23, 59, 59, 999, 999));
      expect(range.start!.toUtc().isUtc, isTrue);
      expect(range.end!.toUtc().toLocal(), range.end);
    });

    test('supports a single day and the earliest supported date', () {
      final selected = PeriodDateRange(
        start: DateTime(2000),
        end: DateTime(2000),
      );
      expect(PeriodFilter.isValidCustomRange(selected), isTrue);
      expect(
        PeriodFilter.getPeriodDays(PeriodFilter.custom, customRange: selected),
        1,
      );
    });

    test(
      'counts calendar days across leap, month, year and DST boundaries',
      () {
        for (final dates in [
          [DateTime(2024, 2, 28), DateTime(2024, 3, 1)],
          [DateTime(2025, 12, 30), DateTime(2026, 1, 1)],
          [DateTime(2026, 3, 28), DateTime(2026, 3, 30)],
          [DateTime(2025, 10, 25), DateTime(2025, 10, 27)],
        ]) {
          final selected = PeriodDateRange(start: dates[0], end: dates[1]);
          expect(
            PeriodFilter.getPeriodDays(
              PeriodFilter.custom,
              customRange: selected,
            ),
            3,
            reason: dates.toString(),
          );
          final range = PeriodFilter.getRange(
            PeriodFilter.custom,
            customRange: selected,
          );
          expect(
            range.end!.add(const Duration(microseconds: 1)),
            DateTime(dates[1].year, dates[1].month, dates[1].day + 1),
          );
        }
      },
    );

    test(
      'accepts today and rejects missing, reversed or out-of-bounds dates',
      () {
        final today = DateTime(2026, 10, 23);
        expect(
          PeriodFilter.isValidCustomRange(
            PeriodDateRange(start: today, end: today),
            now: today,
          ),
          isTrue,
        );
        for (final range in <PeriodDateRange?>[
          null,
          PeriodDateRange(start: null, end: today),
          PeriodDateRange(start: today, end: null),
          PeriodDateRange(start: today, end: DateTime(2026, 10, 22)),
          PeriodDateRange(start: DateTime(1999), end: today),
          PeriodDateRange(start: today, end: DateTime(2026, 10, 24)),
        ]) {
          expect(PeriodFilter.isValidCustomRange(range, now: today), isFalse);
          expect(
            () => PeriodFilter.getRange(
              PeriodFilter.custom,
              customRange: range,
              now: today,
            ),
            throwsArgumentError,
          );
        }
      },
    );

    test('compares with the preceding interval of identical duration', () {
      final selected = PeriodDateRange(
        start: DateTime(2026, 3, 28),
        end: DateTime(2026, 3, 30),
      );
      final range = PeriodFilter.getRange(
        PeriodFilter.custom,
        customRange: selected,
      );
      final previous = PeriodFilter.getPreviousMatchedRange(
        PeriodFilter.custom,
        customRange: selected,
      )!;
      expect(
        previous.end,
        range.start!.subtract(const Duration(microseconds: 1)),
      );
      expect(
        previous.end!.difference(previous.start!),
        range.end!.difference(range.start!),
      );
    });

    test('preserves all existing preset choices and defaults', () {
      expect(
        PeriodFilter.values,
        containsAll([
          PeriodFilter.last7Days,
          PeriodFilter.thisMonth,
          PeriodFilter.last30Days,
          PeriodFilter.last3Months,
          PeriodFilter.last6Months,
          PeriodFilter.last12Months,
          PeriodFilter.thisYear,
          PeriodFilter.allTime,
          PeriodFilter.custom,
        ]),
      );
      expect(PeriodFilter.getRange(PeriodFilter.allTime).start, isNull);
      expect(const AnalyticsFilters().period, PeriodFilter.last3Months);
    });
  });

  test(
    'analytics range changes trigger filter inequality and preserve scope',
    () {
      final first = AnalyticsFilters(
        period: PeriodFilter.custom,
        customRange: PeriodDateRange(
          start: DateTime(2026),
          end: DateTime(2026, 1, 3),
        ),
        categoryIds: const ['category'],
        labelIds: const ['label'],
      );
      final second = first.copyWith(
        customRange: PeriodDateRange(
          start: DateTime(2026),
          end: DateTime(2026, 1, 4),
        ),
      );
      expect(first, isNot(second));
      expect(first, first.copyWith());
      expect(first.hashCode, first.copyWith().hashCode);
      expect(second.periodDays, 4);
      expect(second.categoryIds, ['category']);
      expect(second.labelIds, ['label']);
      expect(
        second.copyWith(period: PeriodFilter.thisMonth).customRange,
        isNull,
      );
      expect(
        second.copyWith(categoryIds: const []).customRange,
        second.customRange,
      );
    },
  );
}
