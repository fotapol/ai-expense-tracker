import 'dart:async';
import 'dart:convert';

import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/core/money_formatter.dart';
import 'package:expense_tracker_app/screens/receipts_tab.dart';
import 'package:expense_tracker_app/widgets/filter_bottom_sheet.dart';
import 'package:expense_tracker_app/core/period_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/authenticated_api.dart';

Widget historyApp() => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: const Scaffold(body: ReceiptsTab()),
);

Map<String, dynamic> receipt(int id, {String? merchant}) => {
  'id': 'tx-$id',
  'merchant_name': merchant ?? 'Store $id',
  'occurred_at': '2026-01-10T12:00:00Z',
  'created_at': '2026-01-10T12:00:00Z',
  'currency': 'EUR',
  'amount_total': 10,
  'status': 'CONFIRMED',
  'items': [],
};

http.Response otherResponse(http.Request request) => http.Response(
  request.url.path == '/v1/me' ? '{"default_currency":"EUR"}' : '[]',
  200,
);

Future<void> reachLoadMore(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('receipt-load-more')),
    500,
    scrollable: find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    ),
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    WidgetController.hitTestWarningShouldBeFatal = true;
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('background refresh preserves the current scroll position', (
    tester,
  ) async {
    var requests = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(historyApp());
        await tester.pumpAndSettle();
        await reachLoadMore(tester);
        final scrollable = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        final before = tester
            .state<ScrollableState>(scrollable)
            .position
            .pixels;
        expect(before, greaterThan(0));
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(requests, 2);
        expect(
          tester.state<ScrollableState>(scrollable).position.pixels,
          closeTo(before, 0.1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.url.path != '/v1/transactions') {
          return otherResponse(request);
        }
        requests++;
        return http.Response(jsonEncode(List.generate(50, receipt)), 200);
      }),
    );
  });

  testWidgets(
    'totals keep currencies separate when a conversion is unavailable',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(historyApp());
          await tester.pumpAndSettle();
          expect(
            find.text('${formatMoney('EUR', 20)} · ${formatMoney('USD', 100)}'),
            findsWidgets,
          );
          expect(find.text(formatMoney('USD', 120)), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path != '/v1/transactions') {
            return otherResponse(request);
          }
          return http.Response(
            jsonEncode([
              {...receipt(1), 'amount_total': 20},
              {...receipt(2), 'amount_total': 100, 'currency': 'USD'},
            ]),
            200,
          );
        }),
      );
    },
  );

  testWidgets(
    'load more keeps the history on failure and retries the same page',
    (tester) async {
      final pages = <String>[];
      var failNextPage = true;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(historyApp());
          await tester.pumpAndSettle();
          expect(find.text('50 receipts loaded'), findsOneWidget);
          expect(find.text('Total of loaded receipts'), findsOneWidget);
          await reachLoadMore(tester);
          await tester.tap(find.byKey(const ValueKey('receipt-load-more')));
          await tester.pumpAndSettle();
          expect(find.text('50 receipts loaded'), findsOneWidget);
          expect(find.text('Retry'), findsOneWidget);
          await tester.tap(find.text('Retry'));
          await tester.pumpAndSettle();
          expect(find.text('51 receipts'), findsOneWidget);
          expect(find.text('Store 50'), findsOneWidget);
          expect(find.text('Total of loaded receipts'), findsNothing);
          expect(find.byKey(const ValueKey('receipt-load-more')), findsNothing);
          expect(pages, ['1', '2', '2']);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path != '/v1/transactions') {
            return otherResponse(request);
          }
          final page = request.url.queryParameters['page']!;
          pages.add(page);
          if (page == '2' && failNextPage) {
            failNextPage = false;
            return http.Response('unavailable', 503);
          }
          return http.Response(
            jsonEncode(
              page == '1' ? List.generate(50, receipt) : [receipt(50)],
            ),
            200,
          );
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing sort ignores a stale load-more response and resets pagination',
    (tester) async {
      final delayedPage = Completer<http.Response>();
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(historyApp());
          await tester.pumpAndSettle();
          await reachLoadMore(tester);
          await tester.tap(find.byKey(const ValueKey('receipt-load-more')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('receipt-sort')));
          // A load-more spinner is active, so don't pumpAndSettle until sort finishes.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(
            find.widgetWithText(CheckedPopupMenuItem<String>, 'Highest amount'),
          );
          await tester.pumpAndSettle();
          delayedPage.complete(
            http.Response(
              jsonEncode([receipt(999, merchant: 'Stale receipt')]),
              200,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Sorted receipt'), findsOneWidget);
          expect(find.text('Stale receipt'), findsNothing);
          expect(find.text('1 receipts'), findsOneWidget);
          final sorted = requests.last.url.queryParameters;
          expect(sorted['sort_by'], 'amount_desc');
          expect(sorted['page'], '1');
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path != '/v1/transactions') {
            return otherResponse(request);
          }
          requests.add(request);
          if (request.url.queryParameters['sort_by'] == 'amount_desc') {
            return http.Response(
              jsonEncode([receipt(500, merchant: 'Sorted receipt')]),
              200,
            );
          }
          if (request.url.queryParameters['page'] == '2') {
            return delayedPage.future;
          }
          return http.Response(jsonEncode(List.generate(50, receipt)), 200);
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review toggle requests server filtering', (tester) async {
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(historyApp());
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilterChip, 'Needs review'));
        await tester.pumpAndSettle();
        expect(find.text('Old draft'), findsOneWidget);
        expect(requests.last.url.queryParameters['needs_review'], 'true');
        expect(requests.last.url.queryParameters['page'], '1');
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.url.path != '/v1/transactions') {
          return otherResponse(request);
        }
        requests.add(request);
        return http.Response(
          jsonEncode([
            receipt(
              1,
              merchant: request.url.queryParameters['needs_review'] == 'true'
                  ? 'Old draft'
                  : 'Recent receipt',
            ),
          ]),
          200,
        );
      }),
    );
  });

  testWidgets(
    'search and advanced filters persist through paging and clear together',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(historyApp());
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'coffee & milk');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Filter'));
          await tester.pumpAndSettle();

          Future<void> choose(String key, String label) async {
            final field = find.byKey(ValueKey(key));
            await tester.ensureVisible(field);
            await tester.pumpAndSettle();
            await tester.tap(field);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text(label),
              200,
              scrollable: find.byType(Scrollable).last,
              maxScrolls: 50,
            );
            await tester.tap(find.text(label).last);
            await tester.pumpAndSettle();
          }

          await choose('filter-currency', 'EUR');
          for (final entry in {
            'filter-min-amount': '10,25',
            'filter-max-amount': '50.50',
          }.entries) {
            final input = find.byKey(ValueKey(entry.key));
            await tester.ensureVisible(input);
            await tester.enterText(input, entry.value);
            tester.testTextInput.hide();
            await tester.pumpAndSettle();
          }
          await choose('filter-source', 'Manual entry');
          await choose('filter-status', 'Saved');
          await tester.tap(find.text('Apply'));
          await tester.pumpAndSettle();
          expect(find.text('EUR 10.25 – 50.50'), findsOneWidget);
          await reachLoadMore(tester);
          await tester.tap(find.byKey(const ValueKey('receipt-load-more')));
          await tester.pumpAndSettle();
          final filtered = requests
              .where((r) => r.url.queryParameters['currency'] == 'EUR')
              .toList();
          expect(filtered.map((r) => r.url.queryParameters['page']), [
            '1',
            '2',
          ]);
          for (final request in filtered) {
            expect(request.url.queryParameters['search'], 'coffee & milk');
            expect(request.url.queryParameters['min_amount'], '10.25');
            expect(request.url.queryParameters['max_amount'], '50.50');
            expect(request.url.queryParameters['source'], 'MANUAL');
            expect(request.url.queryParameters['status'], 'CONFIRMED');
          }
          await tester.tap(find.byTooltip('Filter'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const ValueKey('filter-min-amount')),
                )
                .controller!
                .text,
            '10.25',
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          tester
              .widget<InputChip>(find.widgetWithText(InputChip, 'EUR'))
              .onDeleted!();
          await tester.pumpAndSettle();
          expect(requests.last.url.queryParameters['currency'], isNull);
          expect(requests.last.url.queryParameters['min_amount'], isNull);
          expect(requests.last.url.queryParameters['max_amount'], isNull);
          expect(requests.last.url.queryParameters['search'], 'coffee & milk');
          final clear = find.text('Clear all filters');
          await tester.tap(clear);
          await tester.pumpAndSettle();
          expect(
            requests.last.url.queryParameters.keys,
            isNot(
              contains(
                anyOf(
                  'search',
                  'currency',
                  'min_amount',
                  'max_amount',
                  'source',
                  'status',
                ),
              ),
            ),
          );
          expect(requests.last.url.queryParameters['page'], '1');
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path != '/v1/transactions') {
            return otherResponse(request);
          }
          requests.add(request);
          return http.Response(
            jsonEncode(
              request.url.queryParameters['page'] == '2'
                  ? [receipt(50)]
                  : List.generate(50, receipt),
            ),
            200,
          );
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('amount filters require currency and reject invalid ranges', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(historyApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Filter'));
        await tester.pumpAndSettle();
        final minimum = find.byKey(const ValueKey('filter-min-amount'));
        await tester.ensureVisible(minimum);
        await tester.enterText(minimum, '10.001');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter an amount with up to 2 decimal places.'),
          findsOneWidget,
        );
        expect(
          find.text('Choose a currency for the amount range.'),
          findsOneWidget,
        );
        expect(requests, hasLength(1));
        await tester.ensureVisible(minimum);
        await tester.enterText(minimum, '20');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        final maximum = find.byKey(const ValueKey('filter-max-amount'));
        await tester.ensureVisible(maximum);
        await tester.enterText(maximum, '10');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(find.text('Minimum must not exceed maximum.'), findsOneWidget);
        expect(requests, hasLength(1));
        final clear = find.text('Clear filters');
        await tester.scrollUntilVisible(
          clear,
          250,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(clear);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(requests, hasLength(2));
        expect(requests.last.url.queryParameters['min_amount'], isNull);
        expect(requests.last.url.queryParameters['max_amount'], isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.url.path != '/v1/transactions') {
          return otherResponse(request);
        }
        if (request.url.queryParameters['page_size'] == '50') {
          requests.add(request);
        }
        return http.Response('[]', 200);
      }),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing a reopened sheet removes its initial amount bounds', (
    tester,
  ) async {
    Map<String, dynamic>? result;
    await http.runWithClient(() async {
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
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await FilterBottomSheet.show(
                    context,
                    selectedPeriod: PeriodFilter.allTime,
                    enableReceiptFilters: true,
                    selectedCurrency: 'EUR',
                    selectedMinAmount: '10.25',
                    selectedMaxAmount: '50.50',
                    selectedSource: 'MANUAL',
                    selectedStatus: 'CONFIRMED',
                  );
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
      final clear = find.text('Clear filters');
      await tester.scrollUntilVisible(
        clear,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      for (final key in [
        'min_amount',
        'max_amount',
        'currency',
        'source',
        'status',
      ]) {
        expect(
          result![key],
          isNull,
          reason: '$key must clear its saved selection',
        );
      }
    }, () => MockClient((request) async => otherResponse(request)));
  });
}
