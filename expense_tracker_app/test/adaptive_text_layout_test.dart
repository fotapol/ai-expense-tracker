import 'dart:convert';

import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/analytics_screen.dart';
import 'package:expense_tracker_app/screens/login_screen.dart';
import 'package:expense_tracker_app/screens/receipts_tab.dart';
import 'package:expense_tracker_app/widgets/filter_bottom_sheet.dart';
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
    SharedPreferences.setMockInitialValues({});
    await themeProvider.load();
  });

  testWidgets('sign-in card stays centered with unequal side insets', (
    tester,
  ) async {
    fixture.phone(tester, width: 370);
    const insets = FakeViewPadding(top: 24, bottom: 24, left: 8, right: 32);
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    await tester.pumpWidget(fixture.app(const LoginScreen()));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byType(OutlinedButton));
    expect(button.center.dx, closeTo(185, .01));
    expect(button.right, lessThan(370 - insets.right));
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('de'),
    const Locale('ar'),
  ]) {
    testWidgets(
      '${locale.languageCode} sign-in label fits at large bold text size',
      (tester) async {
        fixture.phone(tester, width: 320);
        await tester.pumpWidget(
          fixture.app(
            const LoginScreen(),
            locale: locale,
            factor: 1.2,
            systemText: 1.6,
            boldText: true,
          ),
        );
        await tester.pumpAndSettle();

        final label = AppLocalizations(locale).tr('login_continue_google');
        final text = find.text(label);
        final button = find.widgetWithText(OutlinedButton, label);
        expect(button, findsOneWidget);
        expect(
          tester
              .getRect(button)
              .inflate(1)
              .contains(tester.getRect(text).bottomRight),
          isTrue,
        );
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'analytics scrolls complete bold tab titles into view as pages change',
    (tester) async {
      fixture.phone(tester, width: 320);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            fixture.app(
              const AnalyticsScreen(),
              factor: 1.2,
              systemText: 1.55,
              boldText: true,
            ),
          );
          await tester.pumpAndSettle();
          final strip = find.byKey(const ValueKey('analytics-section-strip'));
          final categories = find.byKey(
            const ValueKey('analytics-section-categories'),
          );
          final title = find.descendant(
            of: categories,
            matching: find.text('Categories'),
          );
          expect(
            tester.getRect(categories).right,
            greaterThan(tester.getRect(strip).right),
          );

          for (var i = 0; i < 2; i++) {
            await tester.fling(
              find.byType(PageView),
              const Offset(-225, 0),
              1000,
            );
            await tester.pumpAndSettle();
          }

          expect(
            tester
                .getRect(strip)
                .inflate(1)
                .contains(tester.getRect(title).bottomRight),
            isTrue,
          );
          final lines = tester
              .renderObject<RenderParagraph>(title)
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 10),
              )
              .map((box) => box.top)
              .toSet();
          expect(lines, hasLength(1));
          final indicator = tester.getRect(
            find.byKey(const ValueKey('analytics-tab-indicator')),
          );
          expect(indicator.left, closeTo(tester.getRect(categories).left, 1));
          expect(indicator.width, closeTo(tester.getRect(categories).width, 1));
          expect(tester.takeException(), isNull);
        },
        () => MockClient(
          (request) async => fixture.homeSpendingResponse(request),
        ),
      );
    },
  );

  testWidgets('long receipt amount leaves space for the merchant name', (
    tester,
  ) async {
    fixture.phone(tester, width: 320);
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          fixture.app(
            const Scaffold(body: ReceiptsTab()),
            factor: 1.2,
            systemText: 1.45,
            boldText: true,
          ),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('one'));
        final merchant = find.descendant(
          of: card,
          matching: find.text('Entertainment Market'),
        );
        final amount = find.descendant(
          of: card,
          matching: find.text('RSD 1234567890.12'),
        );
        expect(tester.getSize(merchant).width, greaterThan(130));
        expect(
          tester.getRect(amount).top,
          greaterThan(tester.getRect(merchant).bottom),
        );
        expect(
          tester.getRect(card).contains(tester.getRect(amount).bottomRight),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        if (request.url.path == '/v1/transactions') {
          return http.Response(
            jsonEncode([
              {
                ...fixture.tx('one'),
                'merchant_name': 'Entertainment Market',
                'currency': 'RSD',
                'amount_total': 1234567890.12,
                'display_currency': 'RSD',
                'display_amount_total': 1234567890.12,
              },
            ]),
            200,
          );
        }
        return fixture.response(request);
      }),
    );
  });

  testWidgets('amount filters stack when the bold labels need more room', (
    tester,
  ) async {
    fixture.phone(tester, width: 320);
    await http.runWithClient(() async {
      await tester.pumpWidget(
        fixture.app(
          const Scaffold(
            body: FilterBottomSheet(
              selectedPeriod: 'All Time',
              enableReceiptFilters: true,
              displayCurrency: 'RSD',
            ),
          ),
          locale: const Locale('de'),
          factor: 1.2,
          systemText: 1.45,
          boldText: true,
        ),
      );
      await tester.pumpAndSettle();
      final minimum = find.byKey(const ValueKey('filter-min-amount'));
      final maximum = find.byKey(const ValueKey('filter-max-amount'));
      expect(
        tester.getRect(maximum).top,
        greaterThan(tester.getRect(minimum).bottom),
      );
      expect(tester.getRect(maximum).width, tester.getRect(minimum).width);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async => fixture.response(request)));
  });
}
