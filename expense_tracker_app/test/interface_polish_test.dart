import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/home_tab.dart';
import 'package:expense_tracker_app/screens/tools_screen.dart';
import 'package:expense_tracker_app/screens/duplicate_finder_screen.dart';
import 'package:expense_tracker_app/widgets/anchored_choice_field.dart';
import 'package:expense_tracker_app/widgets/receipt_history_controls.dart';
import 'package:expense_tracker_app/core/period_filter.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_interface_test.dart' as fixture;
import 'support/authenticated_api.dart';

void main() {
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({'accent_migration_version': 1});
    await themeProvider.load();
  });

  testWidgets(
    'empty duplicate finder is designed, scrollable and can refresh',
    (tester) async {
      fixture.phone(tester, width: 320);
      var requests = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            fixture.app(
              const DuplicateFinderScreen(),
              factor: 1.2,
              systemText: 1.3,
              locale: const Locale('de'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('duplicate-finder-status')),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byIcon(Icons.refresh));
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.refresh));
          await tester.pumpAndSettle();
          expect(requests, 2);
          expect(
            find.byKey(const ValueKey('duplicate-finder-status')),
            findsNothing,
          );
          expect(find.text('Sample Market'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncode({
              'items': requests == 1 ? [] : [fixture.pair('one', 'two')],
              'has_more': false,
            }),
            200,
          );
        }),
      );
    },
  );

  for (final factor in [.6, .8, 1.0, 1.2]) {
    testWidgets(
      '$factor menu opens below its anchor and review stays beside sorting',
      (tester) async {
        fixture.phone(tester);
        var selected = '';
        await tester.pumpWidget(
          fixture.app(
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
                child: Column(
                  children: [
                    ReceiptHistoryControls(
                      sort: 'newest',
                      labels: const {'newest': 'receipts_sort_newest'},
                      reviewOnly: false,
                      onSort: (_) {},
                      onReview: (_) => selected = 'review',
                    ),
                    const SizedBox(height: 20),
                    AnchoredChoiceField(
                      key: const ValueKey('period-choice'),
                      value: PeriodFilter.allTime,
                      options: {
                        for (final period in PeriodFilter.values)
                          period: period,
                      },
                      onChanged: (value) => selected = value,
                    ),
                  ],
                ),
              ),
            ),
            factor: factor,
            systemText: 1.3,
            locale: const Locale('de'),
          ),
        );
        await tester.pumpAndSettle();
        final sort = tester.getRect(find.byKey(const ValueKey('receipt-sort')));
        final review = tester.getRect(
          find.byKey(const ValueKey('receipt-review-filter')),
        );
        expect(sort.center.dy, closeTo(review.center.dy, 1));
        expect(review.left, greaterThan(sort.right));
        await tester.tap(find.byKey(const ValueKey('receipt-review-filter')));
        expect(selected, 'review');
        final anchor = tester.getRect(
          find.byKey(const ValueKey('period-choice')),
        );
        await tester.tap(find.byKey(const ValueKey('period-choice')));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byType(MenuItemButton).first).top,
          greaterThanOrEqualTo(anchor.bottom),
        );
        await tester.ensureVisible(find.text(PeriodFilter.custom));
        await tester.pumpAndSettle();
        await tester.tap(find.text(PeriodFilter.custom));
        await tester.pumpAndSettle();
        expect(selected, PeriodFilter.custom);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      '${locale.languageCode} home actions and unique tools fit large text',
      (tester) async {
        fixture.phone(tester, width: 320);
        String tr(String key) =>
            AppLocalizations.lookup(key, languageCode: locale.languageCode);
        await http.runWithClient(() async {
          await tester.pumpWidget(
            fixture.app(
              const Scaffold(body: HomeTab()),
              factor: 1.2,
              systemText: 1.3,
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          for (final key in ['home_start_subtitle', 'home_add_expense']) {
            final text = find.text(tr(key));
            if (text.evaluate().isEmpty) {
              await tester.scrollUntilVisible(text, 160);
              await tester.pumpAndSettle();
            }
            expect(text, findsOneWidget);
            expect(
              (tester.renderObject(text) as RenderParagraph).didExceedMaxLines,
              isFalse,
            );
          }
          await tester.pumpWidget(
            fixture.app(
              const Scaffold(body: ToolsScreen()),
              factor: 1.2,
              systemText: 1.3,
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          for (final key in [
            'tools_scan_receipt',
            'tools_receipt_manager',
            'tools_analytics',
          ]) {
            expect(find.text(tr(key)), findsOneWidget);
          }
        }, () => MockClient((request) async => fixture.response(request)));
      },
    );
  }
}
