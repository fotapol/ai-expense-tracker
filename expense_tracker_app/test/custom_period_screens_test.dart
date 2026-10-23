import 'dart:async';
import 'dart:convert';

import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/screens/analytics_category_detail_screen.dart';
import 'package:expense_tracker_app/screens/analytics_screen.dart';
import 'package:expense_tracker_app/screens/analytics_subcategory_items_screen.dart';
import 'package:expense_tracker_app/screens/receipt_manager_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/authenticated_api.dart';

Widget app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

http.Response response(http.Request request) {
  final path = request.url.path;
  final Object body;
  if (path == '/v1/transactions' ||
      path == '/v1/categories' ||
      path == '/v1/labels') {
    body = [];
  } else if (path == '/v1/me') {
    body = {'default_currency': 'EUR'};
  } else if (path == '/v1/me/entitlements') {
    body = {
      'feature_codes': ['premium.analytics.advanced'],
    };
  } else {
    body = {
      'currency': 'EUR',
      'total_amount': 0,
      'total_transactions': 0,
      'breakdown': [],
      'bucket_unit': 'day',
      'buckets': [],
      'items': [],
    };
  }
  return http.Response(jsonEncode(body), 200);
}

Future<void> pickCustomRange(WidgetTester tester) async {
  await tester.tap(find.text('Custom period'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(DateRangePickerDialog),
    matching: find.byType(TextField),
  );
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), '01/10/2026');
  await tester.enterText(fields.at(1), '01/12/2026');
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
}

void expectRange(http.Request request, PeriodDateRange range) {
  expect(
    request.url.queryParameters['from_occurred_at'],
    range.start!.toUtc().toIso8601String(),
  );
  expect(
    request.url.queryParameters['to_occurred_at'],
    range.end!.toUtc().toIso8601String(),
  );
}

void main() {
  setUp(() {
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Receipt Manager applies and removes both custom date bounds', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(app(const ReceiptManagerScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Filter'));
        await tester.pumpAndSettle();
        await pickCustomRange(tester);
        final selected = PeriodFilter.getRange(
          PeriodFilter.custom,
          customRange: PeriodDateRange(
            start: DateTime(2026, 1, 10),
            end: DateTime(2026, 1, 12),
          ),
        );
        final filtered = requests.where(
          (r) =>
              r.url.path == '/v1/transactions' &&
              r.url.queryParameters.containsKey('from_occurred_at'),
        );
        expect(filtered, isNotEmpty);
        expectRange(filtered.last, selected);
        final chip = find.widgetWithText(
          InputChip,
          'Jan 10, 2026 – Jan 12, 2026',
        );
        expect(chip, findsOneWidget);
        tester.widget<InputChip>(chip).onDeleted!();
        await tester.pumpAndSettle();
        expect(chip, findsNothing);
        final latest = requests.lastWhere(
          (r) => r.url.path == '/v1/transactions',
        );
        expect(
          latest.url.queryParameters.containsKey('from_occurred_at'),
          isFalse,
        );
        expect(
          latest.url.queryParameters.containsKey('to_occurred_at'),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        requests.add(request);
        return response(request);
      }),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Analytics restores custom dates across overview, trends and categories',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'analytics_period': PeriodFilter.custom,
        'analytics_custom_start_date': '2026-01-10',
        'analytics_custom_end_date': '2026-01-12',
      });
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(app(const AnalyticsScreen()));
          await tester.pumpAndSettle();
          expect(find.text('Jan 10, 2026 – Jan 12, 2026'), findsOneWidget);
          for (final title in ['Trends', 'Categories']) {
            await tester.tap(find.text(title).first);
            await tester.pumpAndSettle();
          }
          final selected = PeriodFilter.getRange(
            PeriodFilter.custom,
            customRange: PeriodDateRange(
              start: DateTime(2026, 1, 10),
              end: DateTime(2026, 1, 12),
            ),
          );
          final dated = requests.where(
            (r) => r.url.path.startsWith('/v1/transactions'),
          );
          expect(
            dated.map((r) => r.url.path).toSet(),
            containsAll([
              '/v1/transactions',
              '/v1/transactions/summary',
              '/v1/transactions/summary/trends',
            ]),
          );
          for (final request in dated) {
            if (DateTime.parse(
                  request.url.queryParameters['from_occurred_at']!,
                ) ==
                selected.start!.toUtc()) {
              expectRange(request, selected);
            }
          }
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          requests.add(request);
          return response(request);
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category-to-item navigation retains the custom period and label scope',
    (tester) async {
      final range = PeriodFilter.getRange(
        PeriodFilter.custom,
        customRange: PeriodDateRange(
          start: DateTime(2026, 1, 10),
          end: DateTime(2026, 1, 12),
        ),
      );
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            app(
              AnalyticsCategoryDetailScreen(
                categoryId: 'category',
                categoryName: 'Custom category',
                categoryCode: 'custom',
                fromDate: range.start,
                toDate: range.end,
                selectedCategoryIds: const ['category'],
                selectedSubcategoryIds: const [],
                selectedLabelIds: const ['label'],
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Custom child'));
          await tester.pumpAndSettle();
          expect(find.byType(AnalyticsSubcategoryItemsScreen), findsOneWidget);
          final dated = requests.where(
            (r) => r.url.path.startsWith('/v1/transactions/summary/'),
          );
          expect(dated, hasLength(2));
          for (final request in dated) {
            expectRange(request, range);
            expect(request.url.queryParameters['label_ids'], 'label');
          }
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/subcategories')) {
            return http.Response(
              jsonEncode({
                'currency': 'EUR',
                'total_amount': 12,
                'subcategories': [
                  {
                    'subcategory_id': 'child',
                    'name': 'Custom child',
                    'code': 'custom_child',
                    'amount': 12,
                    'percentage': 100,
                    'item_count': 1,
                  },
                ],
              }),
              200,
            );
          }
          return response(request);
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a custom range applied during a receipt refresh is fetched next',
    (tester) async {
      final pending = Completer<http.Response>();
      final requests = <http.Request>[];
      var first = true;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(app(const ReceiptManagerScreen()));
          await tester.pump();
          await tester.tap(find.byTooltip('Filter'));
          await tester.pumpAndSettle();
          await pickCustomRange(tester);
          pending.complete(http.Response('[]', 200));
          await tester.pumpAndSettle();
          expect(
            requests.any(
              (r) =>
                  r.url.path == '/v1/transactions' &&
                  r.url.queryParameters.containsKey('from_occurred_at'),
            ),
            isTrue,
          );
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/v1/transactions' && first) {
            first = false;
            return pending.future;
          }
          return response(request);
        }),
      );
    },
  );
}
