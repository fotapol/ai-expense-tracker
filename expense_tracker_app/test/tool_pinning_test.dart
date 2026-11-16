import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_interface_test.dart' as fixture;

const prefsKey = 'tools_pinned_ids_v1';
Finder tool(String id) => find.byKey(ValueKey('tool-$id'));

Future<void> showTools(WidgetTester tester) async {
  fixture.phone(tester);
  await tester.pumpWidget(fixture.app(const Scaffold(body: ToolsScreen())));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    SharedPreferences.setMockInitialValues({});
    await themeProvider.load();
  });

  testWidgets('long press pins once, unpins, and remembers pin order', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({prefsKey: <String>[]});
    await showTools(tester);
    await tester.longPress(tool('duplicates'));
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsOneWidget);
    expect(tool('duplicates'), findsOneWidget);
    expect(
      tester.getTopLeft(tool('duplicates')).dy,
      lessThan(tester.getTopLeft(tool('scan')).dy),
    );
    await tester.ensureVisible(tool('receipts'));
    await tester.longPress(tool('receipts'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getStringList(prefsKey), [
      'duplicates',
      'receipts',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(fixture.app(const Scaffold(body: ToolsScreen())));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(tool('duplicates')).dy,
      lessThan(tester.getTopLeft(tool('receipts')).dy),
    );
    await tester.longPress(tool('duplicates'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getStringList(prefsKey), [
      'receipts',
    ]);
    expect(tool('duplicates'), findsOneWidget);
    expect(find.text('Duplicate finder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty saved list stays empty on restart', (tester) async {
    SharedPreferences.setMockInitialValues({prefsKey: <String>[]});
    await showTools(tester);
    expect(find.text('Pinned'), findsNothing);
    for (final id in ['scan', 'receipts', 'analytics']) {
      await tester.ensureVisible(tool(id));
      await tester.longPress(tool(id));
      await tester.pumpAndSettle();
      await tester.ensureVisible(tool(id));
      await tester.longPress(tool(id));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(fixture.app(const Scaffold(body: ToolsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Pinned'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getStringList(prefsKey),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
      '${locale.languageCode} pin guidance fits at accessibility size',
      (tester) async {
        fixture.phone(tester, width: 320);
        await tester.pumpWidget(
          fixture.app(
            const Scaffold(body: ToolsScreen()),
            locale: locale,
            factor: 1.2,
            systemText: 1.3,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
