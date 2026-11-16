import 'dart:convert';

import 'package:expense_tracker_app/core/duplicate_comparison.dart';
import 'package:expense_tracker_app/core/money_format_preferences.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/duplicate_finder_screen.dart';
import 'package:expense_tracker_app/widgets/duplicate_details_comparison.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_interface_test.dart' as fixture;
import 'support/authenticated_api.dart';

Map<String, dynamic> item({
  Object qty = 2,
  String unit = 'pc',
  Object? price = '5.0000',
  Object total = 10,
}) => {
  'description': 'Milk',
  'qty': qty,
  'unit': unit,
  'unit_price': price,
  'amount': total,
};

void main() {
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
    await themeProvider.load();
  });

  test('comparison uses visible precision and canonical units', () {
    expect(
      ComparedItem(
        item(),
        item(qty: '2.000', unit: 'pieces', total: '10.00', price: 5.00000001),
      ).identical,
      isTrue,
    );
    expect(ComparedItem(item(), item(price: null)).identical, isTrue);
    expect(ComparedItem(item(), item(price: 5.0001)).identical, isFalse);
    expect(ComparedItem(item(), item(qty: 2.001)).identical, isFalse);
    expect(ComparedItem(item(unit: 'kg'), item(unit: 'g')).identical, isFalse);
    expect(ComparedItem(item(), item(total: 10.01)).identical, isFalse);
    expect(
      comparisonUnitPrice({...item(price: null), 'discount_amount': 2}),
      6,
    );
    expect(
      comparisonUnitPrice({...item(price: null), 'amount_before_discount': 14}),
      7,
    );
    expect(comparisonUnitPrice(item(qty: 0, price: null)), isNull);
  });

  test('equivalent ISO dates compare by the displayed purchase minute', () {
    expect(
      samePurchaseMinute(
        '2026-02-27T14:36:00.000Z',
        '2026-02-27T15:36:45+01:00',
      ),
      isTrue,
    );
    expect(
      samePurchaseMinute('2026-02-27T14:36:00Z', '2026-02-27T14:37:00Z'),
      isFalse,
    );
    expect(samePurchaseMinute(null, null), isTrue);
    expect(samePurchaseMinute(null, '2026-02-27T14:36:00Z'), isFalse);
  });

  Future<void> showComparison(
    WidgetTester tester, {
    bool changedPrice = false,
    bool discounted = false,
  }) async {
    fixture.phone(tester);
    final a = {
      ...fixture.tx('one'),
      'items': [item()],
    };
    final b = {
      ...fixture.tx('two'),
      'amount_total': a['amount_total'],
      'occurred_at': '2026-01-10T13:30:45+01:00',
      'items': [
        {
          ...item(
            unit: 'pieces',
            price: changedPrice
                ? 5.0001
                : discounted
                ? 5
                : null,
            total: discounted ? 8 : 10,
          ),
          if (discounted) 'discount_amount': 2,
        },
      ],
    };
    await tester.pumpWidget(
      fixture.app(
        Scaffold(
          body: SingleChildScrollView(
            child: DuplicateDetailsComparison(
              transactions: [a, b],
              selectedId: null,
              onSelect: (_) {},
              onPhoto: (_) {},
              busy: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'equal visible values are neutral and differences-only removes all equal items',
    (tester) async {
      await showComparison(tester);
      expect(find.byKey(const ValueKey('comparison-difference')), findsNothing);
      expect(find.byKey(const ValueKey('compared-item-0')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('duplicate-differences-only')),
      );
      await tester.tap(
        find.byKey(const ValueKey('duplicate-differences-only')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compared-item-0')), findsNothing);
      expect(find.text('No item differences found.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unit-price precision stays visible even when rounded totals are enabled',
    (tester) async {
      await moneyFormatSettings.setShowDecimals(false);
      addTearDown(() => moneyFormatSettings.setShowDecimals(true));
      await showComparison(tester, changedPrice: true);
      await tester.ensureVisible(
        find.byKey(const ValueKey('duplicate-differences-only')),
      );
      await tester.tap(
        find.byKey(const ValueKey('duplicate-differences-only')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compared-item-0')), findsOneWidget);
      expect(find.text('RSD 5.0001'), findsOneWidget);
      expect(find.text('Unit price'), findsOneWidget);
      expect(find.text('Line total'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('comparison-difference')),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recorded discounts have their own labeled comparison row', (
    tester,
  ) async {
    await showComparison(tester, discounted: true);
    await tester.ensureVisible(
      find.byKey(const ValueKey('duplicate-differences-only')),
    );
    await tester.tap(find.byKey(const ValueKey('duplicate-differences-only')));
    await tester.pumpAndSettle();
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('RSD 2.00'), findsOneWidget);
    expect(find.text('RSD 8.00'), findsOneWidget);
    expect(find.text('Unit price'), findsOneWidget);
    expect(find.text('Line total'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('comparison-difference')),
      findsNWidgets(4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'three receipts open direct comparisons and resolve only a real selected pair',
    (tester) async {
      fixture.phone(tester);
      final requested = <String>[];
      final mutations = <Map<String, dynamic>>[];
      var resolved = false;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(fixture.app(const DuplicateFinderScreen()));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('duplicate-one-two')));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.text('Comparison 1 of 2'), findsOneWidget);
          expect(find.byKey(const ValueKey('select-one')), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('duplicate-next-comparison')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Comparison 2 of 2'), findsOneWidget);
          expect(find.byKey(const ValueKey('select-three')), findsOneWidget);
          expect(find.byKey(const ValueKey('select-one')), findsNothing);
          await tester.tap(find.byKey(const ValueKey('select-three')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Keep selected'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete'));
          await tester.pumpAndSettle();
          expect(mutations, hasLength(1));
          expect(mutations.single['keep_transaction_id'], 'three');
          expect(mutations.single['discard_transaction_id'], 'two');
          expect(
            mutations.single['keep_updated_at'],
            fixture.tx('three')['updated_at'],
          );
          expect(
            requested,
            containsAll([
              '/v1/transactions/one',
              '/v1/transactions/two',
              '/v1/transactions/three',
            ]),
          );
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          requested.add(request.url.path);
          if (request.url.path == '/v1/duplicates') {
            return http.Response(
              jsonEncode({
                'items': resolved
                    ? []
                    : [
                        fixture.pair('one', 'two'),
                        {
                          ...fixture.pair('three', 'two'),
                          'confidence': 'possible',
                        },
                      ],
                'has_more': false,
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/resolve')) {
            mutations.add(jsonDecode(request.body));
            resolved = true;
            return http.Response('{"deleted_transaction_id":"two"}', 200);
          }
          return fixture.response(request);
        }),
      );
    },
  );
}
