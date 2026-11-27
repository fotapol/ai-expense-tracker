import 'dart:convert';

import 'package:expense_tracker_app/core/analytics_filters.dart';
import 'package:expense_tracker_app/core/money_formatter.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/analytics_trends_tab.dart';
import 'package:expense_tracker_app/widgets/filter_bottom_sheet.dart';
import 'package:expense_tracker_app/widgets/receipt_history_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_interface_test.dart' as fixture;
import 'support/authenticated_api.dart';

http.Response response(http.Request request) {
  if (request.url.path.endsWith('/summary')) {
    return http.Response(
      jsonEncode({
        'currency': 'EUR',
        'total_amount': 98765.43,
        'total_transactions': 42,
        'breakdown': [],
      }),
      200,
    );
  }
  if (request.url.path.endsWith('/trends')) {
    return http.Response(
      jsonEncode({
        'currency': 'EUR',
        'total_amount': 98765.43,
        'previous_total_amount': 100,
        'change_percentage': 30,
        'bucket_unit': 'month',
        'buckets': [],
      }),
      200,
    );
  }
  return fixture.response(request);
}

void main() {
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
    await themeProvider.load();
  });

  Future<void> checkTrends(
    WidgetTester tester,
    Locale locale,
    double factor, {
    double text = 1.3,
  }) async {
    fixture.phone(tester, width: 320);
    await http.runWithClient(() async {
      await tester.pumpWidget(
        fixture.app(
          const Scaffold(body: AnalyticsTrendsTab(filters: AnalyticsFilters())),
          locale: locale,
          factor: factor,
          systemText: text,
        ),
      );
      await tester.pumpAndSettle();
      final amount = find.text(formatMoney('EUR', 98765.43));
      expect(amount, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(amount).didExceedMaxLines,
        isFalse,
      );
      final label = find.text(
        AppLocalizations.lookup(
          'analytics_trends_transactions',
          languageCode: locale.languageCode,
        ),
      );
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      final sizes = [
        for (var i = 0; i < 3; i++)
          tester.getSize(find.byKey(ValueKey('analytics-metric-$i'))),
      ];
      expect(sizes[0], sizes[1]);
      expect(sizes[1], sizes[2]);
      expect(
        tester.getSize(find.byKey(const ValueKey('trends-range-0'))),
        tester.getSize(find.byKey(const ValueKey('trends-range-1'))),
      );
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async => response(request)));
  }

  testWidgets('zero change has no negative sign', (tester) async {
    await checkTrends(tester, const Locale('en'), 1, text: 1);
    expect(find.text('0%'), findsNWidgets(3));
    expect(find.text('−0%'), findsNothing);
    expect(find.text('-0%'), findsNothing);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      '${locale.languageCode} Trends shows complete labels and amounts',
      (tester) => checkTrends(tester, locale, 1.2),
    );
  }
  for (final factor in [.6, .8, 1.0, 1.2]) {
    testWidgets(
      '$factor Trends metrics remain complete',
      (tester) => checkTrends(tester, const Locale('de'), factor, text: 1),
    );
  }

  testWidgets('short subcategories share rows and can be unselected', (
    tester,
  ) async {
    fixture.phone(tester);
    Map<String, dynamic>? result;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          fixture.app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => result = await FilterBottomSheet.show(
                    context,
                    selectedPeriod: 'All Time',
                    selectedCategoryIds: ['food'],
                    selectedSubcategoryIds: ['sub-0', 'sub-1', 'sub-2'],
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final first = find.byKey(const ValueKey('selected-subcategory-sub-0'));
        final second = find.byKey(const ValueKey('selected-subcategory-sub-1'));
        await tester.ensureVisible(first);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(first).dy,
          closeTo(tester.getTopLeft(second).dy, .1),
        );
        await tester.tap(first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(result?['subcategory_ids'], ['sub-1', 'sub-2']);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        if (request.url.path == '/v1/categories') {
          return http.Response(
            jsonEncode([
              {
                'id': 'food',
                'name': 'Food',
                'code': 'FOOD',
                'scope': 'TRANSACTION',
              },
              for (var i = 0; i < 3; i++)
                {
                  'id': 'sub-$i',
                  'parent_id': 'food',
                  'name': ['Tea', 'Oil', 'Egg'][i],
                  'code': 'CUSTOM_$i',
                  'scope': 'ITEM',
                },
            ]),
            200,
          );
        }
        return response(request);
      }),
    );
  });

  testWidgets('sorting changes both the selected option and its icon', (
    tester,
  ) async {
    fixture.phone(tester);
    var sort = 'newest';
    const options = {
      'newest': 'receipts_sort_newest',
      'oldest': 'receipts_sort_oldest',
      'amount_asc': 'receipts_sort_amount_asc',
      'amount_desc': 'receipts_sort_amount_desc',
      'merchant_asc': 'receipts_sort_merchant_asc',
    };
    await tester.pumpWidget(
      fixture.app(
        StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ReceiptHistoryControls(
              sort: sort,
              labels: options,
              reviewOnly: false,
              onSort: (value) => setState(() => sort = value),
              onReview: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final seen = <IconData?>{};
    for (final option in options.entries) {
      await tester.tap(find.byKey(const ValueKey('receipt-sort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<String>,
          AppLocalizations.lookup(option.value, languageCode: 'en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(sort, option.key);
      final icon = tester.widget<Icon>(
        find
            .descendant(
              of: find.byKey(const ValueKey('receipt-sort')),
              matching: find.byType(Icon),
            )
            .first,
      );
      seen.add(icon.icon);
    }
    expect(seen, hasLength(options.length));
    expect(tester.takeException(), isNull);
  });
}
