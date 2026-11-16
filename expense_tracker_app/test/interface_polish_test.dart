import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/home_tab.dart';
import 'package:expense_tracker_app/screens/tools_screen.dart';
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
