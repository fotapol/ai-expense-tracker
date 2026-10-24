import 'dart:convert';

import 'package:expense_tracker_app/core/analytics_filters.dart';
import 'package:expense_tracker_app/core/money_formatter.dart';
import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/screens/analytics_trends_tab.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/authenticated_api.dart';

void main() {
  for (final entry in <String, List<List<String>>>{
    'day': [
      ['2026-01-10', '2026-01-10'],
      ['2026-01-11', '2026-01-11'],
      ['2026-01-12', '2026-01-12'],
    ],
    'week': [
      ['2026-01-10', '2026-01-16'],
      ['2026-01-17', '2026-01-23'],
    ],
    'month': [
      ['2025-12-15', '2025-12-31'],
      ['2026-01-01', '2026-01-31'],
      ['2026-02-01', '2026-02-10'],
    ],
  }.entries) {
    testWidgets(
      'custom ${entry.key} trends retain backend bucket dates and accurate averages',
      (tester) async {
        installAuthenticatedApiUser();
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final selected = PeriodDateRange(
          start: DateTime.parse(entry.value.first.first),
          end: DateTime.parse(entry.value.last.last),
        );
        final filters = AnalyticsFilters(
          period: PeriodFilter.custom,
          customRange: selected,
        );
        final previous = PeriodFilter.getPreviousMatchedRange(
          PeriodFilter.custom,
          customRange: selected,
        )!;
        final requests = <http.Request>[];
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('en'),
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(body: AnalyticsTrendsTab(filters: filters)),
              ),
            );
            await tester.pumpAndSettle();
            final expectedDays = {
              'day': 3,
              'week': 14,
              'month': 58,
            }[entry.key]!;
            expect(
              find.text(formatMoney('EUR', 60 / expectedDays)),
              findsWidgets,
            );
            final chart = tester.widget<LineChart>(find.byType(LineChart));
            expect(
              chart.data.lineBarsData.single.spots,
              hasLength(entry.value.length),
            );
            expect(
              find.text(entry.key == 'month' ? 'Dec 2025' : 'Jan 10'),
              findsWidgets,
            );
            final previousRequest = requests.singleWhere(
              (request) =>
                  request.url.path.endsWith('/summary') &&
                  request.url.queryParameters['from_occurred_at'] ==
                      previous.start!.toUtc().toIso8601String(),
            );
            expect(
              previousRequest.url.queryParameters['to_occurred_at'],
              previous.end!.toUtc().toIso8601String(),
            );
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((request) async {
            requests.add(request);
            final isPrevious =
                request.url.queryParameters['from_occurred_at'] ==
                previous.start!.toUtc().toIso8601String();
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('/trends')
                    ? {
                        'currency': 'EUR',
                        'bucket_unit': entry.key,
                        'current_total_amount': 60,
                        'previous_total_amount': 30,
                        'buckets': [
                          for (final bucket in entry.value)
                            {
                              'start_date': bucket.first,
                              'end_date': bucket.last,
                              'label': 'server label should be localized',
                              'amount': 60 / entry.value.length,
                            },
                        ],
                      }
                    : {
                        'currency': 'EUR',
                        'total_amount': isPrevious ? 30 : 60,
                        'total_transactions': isPrevious ? 3 : 6,
                      },
              ),
              200,
            );
          }),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'long custom ranges preserve every bucket with readable chart spacing',
    (tester) async {
      installAuthenticatedApiUser();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final buckets = [
        for (var index = 0; index < 240; index++)
          {
            'start_date': DateTime(
              2000,
              index + 1,
              1,
            ).toIso8601String().split('T').first,
            'end_date': DateTime(
              2000,
              index + 2,
              0,
            ).toIso8601String().split('T').first,
            'amount': 1,
          },
      ];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: AnalyticsTrendsTab(
                  filters: AnalyticsFilters(
                    period: PeriodFilter.custom,
                    customRange: PeriodDateRange(
                      start: DateTime(2000),
                      end: DateTime(2019, 12, 31),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final line = tester.widget<LineChart>(find.byType(LineChart)).data;
          final bars = tester.widget<BarChart>(find.byType(BarChart)).data;
          expect(line.lineBarsData.single.spots, hasLength(240));
          expect(line.lineBarsData.single.dotData.show, isFalse);
          expect(
            line.titlesData.bottomTitles.sideTitles.interval,
            greaterThan(1),
          );
          expect(bars.barGroups, hasLength(240));
          expect(bars.barGroups.first.barRods.single.width, lessThan(4));
          expect(
            bars.titlesData.bottomTitles.sideTitles.interval,
            greaterThan(1),
          );
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/trends')
                  ? {
                      'currency': 'EUR',
                      'bucket_unit': 'month',
                      'current_total_amount': 240,
                      'previous_total_amount': 120,
                      'buckets': buckets,
                    }
                  : {
                      'currency': 'EUR',
                      'total_amount': 240,
                      'total_transactions': 240,
                    },
            ),
            200,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
