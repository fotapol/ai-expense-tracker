import 'dart:async';
import 'dart:convert';

import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/core/money_formatter.dart';
import 'package:expense_tracker_app/screens/receipts_tab.dart';
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
}
