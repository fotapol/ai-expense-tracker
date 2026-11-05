import 'dart:convert';

import 'package:expense_tracker_app/core/api_client.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/screens/duplicate_finder_screen.dart';
import 'package:expense_tracker_app/screens/transaction_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/authenticated_api.dart';

Map<String, dynamic> transaction(String id) => {
  'id': id,
  'merchant_name': 'Market $id',
  'amount_total': '12.00',
  'currency': 'EUR',
  'occurred_at': '2026-04-10T12:00:00Z',
  'created_at': '2026-04-10T12:00:00Z',
  'updated_at': '2026-04-10T12:00:00Z',
  'receipt_id': 'receipt-$id',
  'status': 'CONFIRMED',
  'source': 'RECEIPT',
  'items': [
    {
      'id': 'item-$id',
      'description': 'Milk',
      'amount': '12.00',
      'qty': '2',
      'unit': 'pc',
    },
  ],
};

Map<String, dynamic> pair(String first, String second) => {
  'first': transaction(first),
  'second': transaction(second),
  'confidence': 'high',
  'matching_item_count': 2,
  'reasons': ['same_total', 'same_date', 'similar_merchant', 'matching_items'],
};

http.Response page(List<Map<String, dynamic>> pairs, {bool more = false}) =>
    http.Response(
      jsonEncode({
        'items': pairs,
        'page': 1,
        'page_size': 20,
        'has_more': more,
      }),
      200,
    );

Widget app({Widget? home}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home ?? const DuplicateFinderScreen(),
);

Future<void> openComparison(WidgetTester tester) async {
  await tester.pumpWidget(app());
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('duplicate-one-two')));
  await tester.pumpAndSettle();
}

Future<void> reachActions(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.widgetWithText(OutlinedButton, 'Keep both'),
    150,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('duplicate-comparison-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  test('API sends a scoped page and preserves conflict responses', () async {
    await http.runWithClient(
      () async {
        await ApiClient.listDuplicates(page: 3, transactionId: 'one');
        await expectLater(
          ApiClient.resolveDuplicate(
            keepId: 'one',
            discardId: 'two',
            keepUpdatedAt: 'kept-version',
            discardUpdatedAt: 'discard-version',
          ),
          throwsA(isA<DuplicateConflictException>()),
        );
      },
      () => MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.method == 'GET') {
          expect(request.url.queryParameters['page'], '3');
          expect(request.url.queryParameters['transaction_id'], 'one');
          return page([]);
        }
        final body = jsonDecode(request.body);
        expect(body['keep_transaction_id'], 'one');
        expect(body['discard_transaction_id'], 'two');
        expect(body['keep_updated_at'], 'kept-version');
        expect(body['discard_updated_at'], 'discard-version');
        return http.Response('{}', 409);
      }),
    );
  });

  testWidgets(
    'keep both remembers the decision and refreshes from page one without deletion',
    (tester) async {
      var dismissed = false;
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await openComparison(tester);
          expect(
            find.text('2 matching items'),
            findsNothing,
          ); // Reasons are combined into one readable explanation.
          expect(find.textContaining('2 matching items'), findsOneWidget);
          expect(find.text('View original'), findsNWidgets(2));
          await reachActions(tester);
          await tester.tap(find.text('Keep both'));
          await tester.pumpAndSettle();
          expect(find.text('No possible duplicates found.'), findsOneWidget);
          expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
          expect(requests.last.url.queryParameters['page'], '1');
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/dismiss')) {
            final body = jsonDecode(request.body);
            expect(body['first_transaction_id'], 'one');
            expect(body['second_transaction_id'], 'two');
            dismissed = true;
            return http.Response('', 204);
          }
          if (request.url.path == '/v1/duplicates') {
            return page(dismissed ? [] : [pair('one', 'two')]);
          }
          return http.Response(
            jsonEncode(transaction(request.url.pathSegments.last)),
            200,
          );
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keep selected needs explicit selection and confirmation, and sends current versions',
    (tester) async {
      var resolved = false;
      var resolveCalls = 0;
      await http.runWithClient(
        () async {
          await openComparison(tester);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Keep selected'),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(const ValueKey('select-one')));
          await reachActions(tester);
          await tester.tap(find.text('Keep selected'));
          await tester.pumpAndSettle();
          expect(find.textContaining('permanently deleted'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(resolveCalls, 0);
          await tester.tap(find.text('Keep selected'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(resolved, isTrue);
          expect(find.text('No possible duplicates found.'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/resolve')) {
            resolveCalls++;
            final body = jsonDecode(request.body);
            expect(body['keep_transaction_id'], 'one');
            expect(body['discard_transaction_id'], 'two');
            expect(body['discard_updated_at'], '2026-04-10T12:00:00Z');
            resolved = true;
            return http.Response(
              '{"kept_transaction_id":"one","deleted_transaction_id":"two"}',
              200,
            );
          }
          if (request.url.path == '/v1/duplicates') {
            return page(resolved ? [] : [pair('one', 'two')]);
          }
          return http.Response(
            jsonEncode(transaction(request.url.pathSegments.last)),
            200,
          );
        }),
      );
      expect(resolveCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a changed receipt shows a reload message and prevents another removal attempt',
    (tester) async {
      await http.runWithClient(
        () async {
          await openComparison(tester);
          await tester.tap(find.byKey(const ValueKey('select-one')));
          await reachActions(tester);
          await tester.tap(find.text('Keep selected'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(
            find.text('These receipts changed. Reload before reviewing them.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Keep selected'),
                )
                .onPressed,
            isNull,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/resolve')) {
            return http.Response('{}', 409);
          }
          if (request.url.path == '/v1/duplicates') {
            return page([pair('one', 'two')]);
          }
          return http.Response(
            jsonEncode(transaction(request.url.pathSegments.last)),
            200,
          );
        }),
      );
    },
  );

  testWidgets('finder loads later result pages', (tester) async {
    final pages = <String>[];
    await http.runWithClient(
      () async {
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Load more'));
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('duplicate-three-four')),
          findsOneWidget,
        );
        expect(pages, ['1', '2']);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        final number = request.url.queryParameters['page']!;
        pages.add(number);
        return number == '1'
            ? page([pair('one', 'two')], more: true)
            : page([pair('three', 'four')]);
      }),
    );
  });
  testWidgets(
    'removing the originating expense exits its editor without refetching it',
    (tester) async {
      var removed = false;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            app(
              home: Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const TransactionEditScreen(transactionId: 'one'),
                      ),
                    ),
                    child: const Text('Open transaction'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open transaction'));
          await tester.pumpAndSettle();
          expect(
            find.text('This expense may already be recorded.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Review duplicates'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('duplicate-one-two')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('select-two')));
          await reachActions(tester);
          await tester.tap(find.text('Keep selected'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(removed, isTrue);
          expect(find.text('Open transaction'), findsOneWidget);
          expect(find.byType(TransactionEditScreen), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          final path = request.url.path;
          if (path == '/v1/me') {
            return http.Response(
              '{"id":"owner","default_currency":"EUR"}',
              200,
            );
          }
          if (path == '/v1/categories' || path == '/v1/labels') {
            return http.Response('[]', 200);
          }
          if (path == '/v1/duplicates') return page([pair('one', 'two')]);
          if (path.endsWith('/resolve')) {
            expect(jsonDecode(request.body)['discard_transaction_id'], 'one');
            removed = true;
            return http.Response(
              '{"kept_transaction_id":"two","deleted_transaction_id":"one"}',
              200,
            );
          }
          if (removed && path.endsWith('/one')) {
            fail('Deleted transaction must not be fetched');
          }
          return http.Response(
            jsonEncode({
              ...transaction(request.url.pathSegments.last),
              'user_id': 'owner',
              'source': 'MANUAL',
              'receipt_id': null,
              'items': [],
              'labels': [],
              'extraction_warnings': [],
              'display_currency': 'EUR',
              'display_amount_total': '12.00',
            }),
            200,
          );
        }),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
