import 'package:expense_tracker_app/core/analytics_filter_preferences.dart';
import 'package:expense_tracker_app/core/analytics_filters.dart';
import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'saves and restores custom calendar dates with independent scope',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final filters = AnalyticsFilters(
        period: PeriodFilter.custom,
        customRange: PeriodDateRange(
          start: DateTime(2026, 1, 10),
          end: DateTime(2026, 1, 12),
        ),
        categoryIds: const ['category'],
        subcategoryIds: const ['subcategory'],
        labelIds: const ['label'],
      );
      await AnalyticsFilterPreferences.save(preferences, filters);
      expect(
        preferences.getString('analytics_custom_start_date'),
        '2026-01-10',
      );
      expect(preferences.getString('analytics_custom_end_date'), '2026-01-12');
      expect(AnalyticsFilterPreferences.load(preferences), filters);
      expect(
        preferences.getKeys().where((key) => key.startsWith('receipts')),
        isEmpty,
      );
    },
  );

  test('selecting a preset removes saved custom dates', () async {
    final preferences = await SharedPreferences.getInstance();
    await AnalyticsFilterPreferences.save(
      preferences,
      AnalyticsFilters(
        period: PeriodFilter.custom,
        customRange: PeriodDateRange(
          start: DateTime(2026),
          end: DateTime(2026),
        ),
      ),
    );
    await AnalyticsFilterPreferences.save(
      preferences,
      const AnalyticsFilters(period: PeriodFilter.thisMonth),
    );
    expect(preferences.containsKey('analytics_custom_start_date'), isFalse);
    expect(preferences.containsKey('analytics_custom_end_date'), isFalse);
    expect(
      AnalyticsFilterPreferences.load(preferences).period,
      PeriodFilter.thisMonth,
    );
  });

  test(
    'invalid saved ranges fall back without discarding category or label filters',
    () async {
      for (final dates in [
        <String?>[null, null],
        ['not-a-date', '2026-01-01'],
        ['2026-02-31', '2026-03-05'],
        ['2026-01-03', '2026-01-01'],
        ['1999-12-31', '2026-01-01'],
        ['2026-01-01', '2100-01-01'],
      ]) {
        SharedPreferences.setMockInitialValues({
          'analytics_period': PeriodFilter.custom,
          'analytics_category_ids': ['category'],
          'analytics_label_ids': ['label'],
          if (dates[0] != null) 'analytics_custom_start_date': dates[0]!,
          if (dates[1] != null) 'analytics_custom_end_date': dates[1]!,
        });
        final restored = AnalyticsFilterPreferences.load(
          await SharedPreferences.getInstance(),
        );
        expect(
          restored.period,
          PeriodFilter.last3Months,
          reason: dates.toString(),
        );
        expect(restored.customRange, isNull);
        expect(restored.categoryIds, ['category']);
        expect(restored.labelIds, ['label']);
      }
    },
  );

  test('existing saved presets remain compatible', () async {
    SharedPreferences.setMockInitialValues({
      'analytics_period': PeriodFilter.last6Months,
    });
    expect(
      AnalyticsFilterPreferences.load(
        await SharedPreferences.getInstance(),
      ).period,
      PeriodFilter.last6Months,
    );
  });
}
