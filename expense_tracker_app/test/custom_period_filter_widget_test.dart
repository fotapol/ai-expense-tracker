import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/widgets/filter_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openFilters(
  WidgetTester tester, {
  String period = PeriodFilter.allTime,
  PeriodDateRange? range,
  ValueChanged<Map<String, dynamic>?>? onResult,
  ThemeMode themeMode = ThemeMode.light,
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await FilterBottomSheet.show(
                context,
                selectedPeriod: period,
                selectedCustomRange: range,
                selectedCategoryIds: const ['category'],
                selectedLabelIds: const ['label'],
              );
              onResult?.call(result);
            },
            child: const Text('Open filters'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open filters'));
  await tester.pumpAndSettle();
}

Future<void> selectRange(WidgetTester tester, {bool singleDay = false}) async {
  await tester.tap(find.text('Custom period'));
  await tester.pumpAndSettle();
  expect(find.byType(DateRangePickerDialog), findsOneWidget);
  final dialog = tester.widget<DateRangePickerDialog>(
    find.byType(DateRangePickerDialog),
  );
  final now = DateTime.now();
  expect(dialog.firstDate, DateTime(2000));
  expect(dialog.lastDate, DateTime(now.year, now.month, now.day));
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), '01/10/2026');
  await tester.enterText(fields.at(1), singleDay ? '01/10/2026' : '01/12/2026');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('scoped clearing retains the selected custom period', (
    tester,
  ) async {
    final range = PeriodDateRange(
      start: DateTime(2026),
      end: DateTime(2026, 1, 3),
    );
    Map<String, dynamic>? result;
    await openFilters(
      tester,
      period: PeriodFilter.custom,
      range: range,
      onResult: (value) => result = value,
    );
    await tester.scrollUntilVisible(
      find.text('Clear scoped filters'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(FilterBottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Clear scoped filters'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result?['period'], PeriodFilter.custom);
    expect(result?['custom_range'], range);
    expect(result?['category_ids'], isEmpty);
    expect(result?['label_ids'], isEmpty);
  });

  testWidgets(
    'custom dates fit a narrow dark screen with large localized text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openFilters(
        tester,
        period: PeriodFilter.custom,
        range: PeriodDateRange(
          start: DateTime(2025, 12, 15),
          end: DateTime(2026, 2, 10),
        ),
        themeMode: ThemeMode.dark,
        locale: const Locale('de'),
        textScale: 2,
      );
      expect(find.text('Benutzerdefinierter Zeitraum'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byIcon(Icons.edit_calendar_outlined),
        200,
        scrollable: find
            .descendant(
              of: find.byType(FilterBottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byIcon(Icons.edit_calendar_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'calendar selection stays pending until Apply and preserves scope',
    (tester) async {
      Map<String, dynamic>? result;
      await openFilters(tester, onResult: (value) => result = value);
      await selectRange(tester);
      expect(result, isNull);
      expect(find.text('Jan 10, 2026 – Jan 12, 2026'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result?['period'], PeriodFilter.custom);
      expect(
        result?['custom_range'],
        PeriodDateRange(
          start: DateTime(2026, 1, 10),
          end: DateTime(2026, 1, 12),
        ),
      );
      expect(result?['category_ids'], ['category']);
      expect(result?['label_ids'], ['label']);
    },
  );

  testWidgets(
    'canceling the calendar preserves the previously applied period',
    (tester) async {
      Map<String, dynamic>? result;
      await openFilters(
        tester,
        period: PeriodFilter.thisMonth,
        onResult: (value) => result = value,
      );
      await tester.tap(find.text('Custom period'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result?['period'], PeriodFilter.thisMonth);
      expect(result?['custom_range'], isNull);
    },
  );

  testWidgets('canceling the sheet discards the calendar draft', (
    tester,
  ) async {
    var dismissed = false;
    Map<String, dynamic>? result;
    await openFilters(
      tester,
      onResult: (value) {
        dismissed = true;
        result = value;
      },
    );
    await selectRange(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(result, isNull);
  });

  testWidgets(
    'reopening a custom period preselects its dates and supports one day',
    (tester) async {
      final range = PeriodDateRange(
        start: DateTime(2026, 1, 10),
        end: DateTime(2026, 1, 12),
      );
      Map<String, dynamic>? result;
      await openFilters(
        tester,
        period: PeriodFilter.custom,
        range: range,
        onResult: (value) => result = value,
      );
      await tester.tap(find.text('Custom period'));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(
        dialog.initialDateRange,
        DateTimeRange(start: range.start!, end: range.end!),
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await selectRange(tester, singleDay: true);
      expect(find.text('Jan 10, 2026'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        (result?['custom_range'] as PeriodDateRange).start,
        DateTime(2026, 1, 10),
      );
      expect(
        (result?['custom_range'] as PeriodDateRange).end,
        DateTime(2026, 1, 10),
      );
    },
  );

  testWidgets('switching to a preset clears custom dates in dark mode', (
    tester,
  ) async {
    Map<String, dynamic>? result;
    await openFilters(
      tester,
      period: PeriodFilter.custom,
      range: PeriodDateRange(start: DateTime(2026), end: DateTime(2026, 1, 3)),
      themeMode: ThemeMode.dark,
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('Last 7 Days'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.edit_calendar_outlined), findsNothing);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(result?['period'], PeriodFilter.last7Days);
    expect(result?['custom_range'], isNull);
  });
}
