import 'dart:convert';

import 'package:expense_tracker_app/core/analytics_filters.dart';
import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/analytics_overview_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_interface_test.dart' as fixture;
import 'support/authenticated_api.dart';

http.Response analyticsResponse(http.Request request, {double? previous = 0}) {
  if (request.url.path.endsWith('/trends')) {
    return http.Response(
      jsonEncode({
        'previous_total_amount': previous,
        'change_percentage': null,
        'buckets': [],
      }),
      200,
    );
  }
  if (request.url.path.endsWith('/summary')) {
    return http.Response(
      jsonEncode({
        'currency': 'EUR',
        'total_amount': 132.5,
        'total_transactions': 3,
        'discounts': {'total_savings': 2.5},
        'breakdown': [],
      }),
      200,
    );
  }
  return fixture.response(request);
}

void main() {
  setUp(() async {
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
    await themeProvider.load();
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      '${locale.languageCode} overview metrics have equal sizes with large text',
      (tester) async {
        fixture.phone(tester, width: 320);
        await http.runWithClient(() async {
          await tester.pumpWidget(
            fixture.app(
              const Scaffold(
                body: AnalyticsOverviewTab(filters: AnalyticsFilters()),
              ),
              locale: locale,
              factor: 1.2,
              systemText: 1.3,
            ),
          );
          await tester.pumpAndSettle();
          final sizes = [
            for (var i = 0; i < 3; i++)
              tester.getSize(find.byKey(ValueKey('analytics-metric-$i'))),
          ];
          expect(sizes[0], sizes[1]);
          expect(sizes[1], sizes[2]);
          expect(
            find.text(
              AppLocalizations.lookup(
                'analytics_comparison_zero',
                languageCode: locale.languageCode,
              ),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }, () => MockClient((request) async => analyticsResponse(request)));
      },
    );
  }

  testWidgets(
    'compact overview does not break long metric words into fragments',
    (tester) async {
      fixture.phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(
          fixture.app(
            const Scaffold(
              body: AnalyticsOverviewTab(filters: AnalyticsFilters()),
            ),
            locale: const Locale('de'),
            factor: .8,
          ),
        );
        await tester.pumpAndSettle();
        final label = AppLocalizations.lookup(
          'analytics_total_transactions',
          languageCode: 'de',
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(
          paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length),
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      }, () => MockClient((request) async => analyticsResponse(request)));
    },
  );

  for (final factor in [.6, .8, 1.0, 1.2]) {
    testWidgets(
      '$factor overview keeps metrics equal and shows actual comparison dates',
      (tester) async {
        fixture.phone(tester);
        await http.runWithClient(() async {
          await tester.pumpWidget(
            fixture.app(
              Scaffold(
                body: AnalyticsOverviewTab(
                  filters: AnalyticsFilters(
                    period: PeriodFilter.custom,
                    customRange: PeriodDateRange(
                      start: DateTime(2026, 1, 10),
                      end: DateTime(2026, 1, 12),
                    ),
                  ),
                ),
              ),
              factor: factor,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Jan 10, 2026 – Jan 12, 2026'), findsOneWidget);
          expect(find.text('Jan 7, 2026 – Jan 9, 2026'), findsOneWidget);
          final sizes = [
            for (var i = 0; i < 3; i++)
              tester.getSize(find.byKey(ValueKey('analytics-metric-$i'))),
          ];
          expect(sizes[0], sizes[1]);
          expect(sizes[1], sizes[2]);
          expect(tester.takeException(), isNull);
        }, () => MockClient((request) async => analyticsResponse(request)));
      },
    );
  }

  testWidgets(
    'negative previous totals and all time do not invent a percentage',
    (tester) async {
      fixture.phone(tester);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            fixture.app(
              const Scaffold(
                body: AnalyticsOverviewTab(filters: AnalyticsFilters()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Comparison unavailable.'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            fixture.app(
              const Scaffold(
                body: AnalyticsOverviewTab(
                  filters: AnalyticsFilters(period: PeriodFilter.allTime),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Choose a date range to compare spending.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
        () => MockClient(
          (request) async => analyticsResponse(
            request,
            previous: request.url.queryParameters['from_occurred_at'] == null
                ? null
                : -10,
          ),
        ),
      );
    },
  );
}
