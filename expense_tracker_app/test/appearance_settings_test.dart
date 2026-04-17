import 'dart:math' as math;

import 'package:expense_tracker_app/core/app_color_semantics.dart';
import 'package:expense_tracker_app/core/redesign_system.dart';
import 'package:expense_tracker_app/core/theme_provider.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/appearance_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpLocalizedApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeProvider.lightTheme,
        darkTheme: themeProvider.darkTheme,
        themeMode: themeProvider.themeMode,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'accent_migration_version': 1,
      'accent_color': appAccentMix,
      'label_color_mode': 'raw',
      'theme_mode': ThemeMode.light.index,
    });
    await themeProvider.load();
    await themeProvider.setThemeMode(ThemeMode.light);
    await themeProvider.setAccent(appAccentMix);
    await themeProvider.setLabelColorMode(AppLabelColorMode.raw);
  });

  testWidgets('Appearance settings shows only Mix, Neutral, and Purple', (
    tester,
  ) async {
    await pumpLocalizedApp(tester, const AppearanceSettingsScreen());

    expect(find.text('Mix'), findsOneWidget);
    expect(find.text('Neutral'), findsOneWidget);
    expect(find.text('Purple'), findsOneWidget);
    expect(find.text('Blue'), findsNothing);
    expect(find.text('Raw colors'), findsOneWidget);
    expect(find.text('Accent-aware colors'), findsOneWidget);
  });

  testWidgets('Appearance settings toggles taxonomy color mode', (
    tester,
  ) async {
    await pumpLocalizedApp(tester, const AppearanceSettingsScreen());

    expect(find.text('Category and label colors'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Accent-aware colors'),
      220,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Accent-aware colors'));
    await tester.pumpAndSettle();

    expect(themeProvider.labelColorMode, AppLabelColorMode.themed);
  });

  testWidgets('Mix home hero accent stays stable during a session', (
    tester,
  ) async {
    final provider = ThemeProvider(random: math.Random(5));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'accent_migration_version': 1,
      'accent_color': appAccentMix,
    });
    await provider.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: provider.lightTheme,
        home: const Scaffold(body: _HomeHeroProbe()),
      ),
    );
    await tester.pump();

    final firstDecoration =
        tester
                .widget<Container>(find.byKey(const Key('home_scan_hero')))
                .decoration!
            as BoxDecoration;
    final firstColors = (firstDecoration.gradient! as LinearGradient).colors
        .toList();

    await tester.pumpWidget(
      MaterialApp(
        theme: provider.lightTheme,
        home: const Scaffold(body: _HomeHeroProbe()),
      ),
    );
    await tester.pump();

    final secondDecoration =
        tester
                .widget<Container>(find.byKey(const Key('home_scan_hero')))
                .decoration!
            as BoxDecoration;
    final secondColors = (secondDecoration.gradient! as LinearGradient).colors
        .toList();

    expect(secondColors, firstColors);
  });
}

class _HomeHeroProbe extends StatelessWidget {
  const _HomeHeroProbe();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const Key('home_scan_hero'),
        width: 240,
        height: 120,
        decoration: ShellStyles.heroCardDecoration(
          context,
          tone: ShellStyles.homeHeroTone(context),
        ),
      ),
    );
  }
}
