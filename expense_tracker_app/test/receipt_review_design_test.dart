import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:expense_tracker_app/core/receipt_filter_formatting.dart';
import 'package:expense_tracker_app/core/theme_provider.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/screens/duplicate_finder_screen.dart';
import 'package:expense_tracker_app/screens/receipts_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'duplicate_review_test.dart' as duplicates;
import 'receipt_history_screen_test.dart' as history;
import 'support/authenticated_api.dart';

const savePreviews = bool.fromEnvironment('SAVE_REVIEW_PREVIEWS');
// Override this path when generating previews on a system without DejaVu Sans.
const previewFontPath = String.fromEnvironment(
  'REVIEW_PREVIEW_FONT',
  defaultValue: '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
);
final previewKey = GlobalKey();

Widget reviewApp(
  Widget home, {
  Locale locale = const Locale('en'),
  double scale = 1,
  bool dark = false,
}) {
  final provider = ThemeProvider();
  var theme = dark ? provider.darkTheme : provider.lightTheme;
  if (savePreviews) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'ReviewPreview'),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: 'ReviewPreview',
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'ReviewPreview',
        ),
        toolbarTextStyle: theme.appBarTheme.toolbarTextStyle?.copyWith(
          fontFamily: 'ReviewPreview',
        ),
      ),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: theme.chipTheme.labelStyle?.copyWith(
          fontFamily: 'ReviewPreview',
        ),
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
          fontFamily: 'ReviewPreview',
        ),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        labelStyle: theme.inputDecorationTheme.labelStyle?.copyWith(
          fontFamily: 'ReviewPreview',
        ),
        floatingLabelStyle: theme.inputDecorationTheme.floatingLabelStyle
            ?.copyWith(fontFamily: 'ReviewPreview'),
        hintStyle: theme.inputDecorationTheme.hintStyle?.copyWith(
          fontFamily: 'ReviewPreview',
        ),
        helperStyle: theme.inputDecorationTheme.helperStyle?.copyWith(
          fontFamily: 'ReviewPreview',
        ),
      ),
    );
  }
  return RepaintBoundary(
    key: previewKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: theme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!savePreviews) return;
  await tester.pumpAndSettle();
  final boundary =
      previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      '${Directory.systemTemp.path}/receipt-review-previews',
    );
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

http.Response mockResponse(http.Request request) => switch (request.url.path) {
  '/v1/duplicates' => duplicates.page([duplicates.pair('one', 'two')]),
  '/v1/transactions/one' => http.Response(
    jsonEncode(duplicates.transaction('one')),
    200,
  ),
  '/v1/transactions/two' => http.Response(
    jsonEncode(duplicates.transaction('two')),
    200,
  ),
  '/v1/transactions' => http.Response(
    jsonEncode([
      history.receipt(1, merchant: 'Fresh Market'),
      history.receipt(2, merchant: 'Coffee & Co.'),
      history.receipt(3, merchant: 'City Bakery'),
    ]),
    200,
  ),
  _ => history.otherResponse(request),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (savePreviews) {
      final font = FontLoader('ReviewPreview');
      font.addFont(
        Future.value(
          ByteData.sublistView(File(previewFontPath).readAsBytesSync()),
        ),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });
  setUp(() {
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  test('Arabic decimal keyboards preserve exact API values', () {
    expect(normalizeReceiptFilterAmount('١٢٫٥٠'), '12.50');
    expect(normalizeReceiptFilterAmount('−۱۲,۲۵'), '-12.25');
    expect(normalizeReceiptFilterAmount(' 0,00 '), '0.00');
    expect(normalizeReceiptFilterAmount('   '), isNull);
    expect(normalizeReceiptFilterAmount('1,000'), '1.000');
  });

  for (final locale in [
    const Locale('en'),
    const Locale('de'),
    const Locale('ar'),
  ]) {
    testWidgets(
      '${locale.languageCode} filters keep Apply visible with large text',
      (tester) async {
        phone(tester, width: 360, height: 800);
        final l10n = AppLocalizations(locale);
        await http.runWithClient(() async {
          await tester.pumpWidget(
            reviewApp(
              const Scaffold(body: ReceiptsTab()),
              locale: locale,
              scale: 1.6,
              dark: locale.languageCode != 'en',
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip(l10n.tr('common_filter')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.text(l10n.tr('common_apply')).hitTestable(),
            findsOneWidget,
          );
          final field = find.byKey(const ValueKey('filter-min-amount'));
          await tester.ensureVisible(field);
          await tester.enterText(
            field,
            locale.languageCode == 'ar' ? '١٢٫٥٠' : '12,50',
          );
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.tr('common_apply')));
          await tester.pumpAndSettle();
          expect(find.text(l10n.tr('filters_choose_currency')), findsOneWidget);
          expect(find.text(l10n.tr('filters_invalid_amount')), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(l10n.tr('common_cancel')));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => MockClient((request) async => mockResponse(request)));
      },
    );
  }

  testWidgets('German range chips use localized decimal separators', (
    tester,
  ) async {
    await tester.pumpWidget(
      reviewApp(
        Builder(
          builder: (context) => Text(
            formatReceiptFilterRange(
              context,
              currency: 'EUR',
              minimum: '10.25',
              maximum: '50.50',
            ),
          ),
        ),
        locale: const Locale('de'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EUR 10,25 – 50,50'), findsOneWidget);
  });

  testWidgets('comparison actions remain visible in Arabic and larger text', (
    tester,
  ) async {
    phone(tester, width: 360, height: 800);
    final l10n = AppLocalizations(const Locale('ar'));
    await http.runWithClient(() async {
      await tester.pumpWidget(
        reviewApp(
          const DuplicateFinderScreen(),
          locale: const Locale('ar'),
          scale: 1.6,
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('duplicate-one-two')));
      await tester.pumpAndSettle();
      final choose = find.byKey(const ValueKey('select-two'));
      await tester.scrollUntilVisible(
        choose,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('duplicate-comparison-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.tr('duplicates_keep_selected')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text(l10n.tr('duplicates_keep_both')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async => mockResponse(request)));
  });

  testWidgets('receipt review previews', (tester) async {
    phone(tester);
    await http.runWithClient(() async {
      await tester.pumpWidget(reviewApp(const Scaffold(body: ReceiptsTab())));
      await tester.pumpAndSettle();
      await capture(tester, 'history-en');
      await tester.tap(find.byTooltip('Filter'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('filter-amount-section')),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'filters-en');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(reviewApp(const DuplicateFinderScreen()));
      await tester.pumpAndSettle();
      await capture(tester, 'duplicates-en');
      await tester.tap(find.byKey(const ValueKey('duplicate-one-two')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-one')));
      await tester.pumpAndSettle();
      await capture(tester, 'comparison-en');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        reviewApp(
          const Scaffold(body: ReceiptsTab()),
          locale: const Locale('de'),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(
          AppLocalizations(const Locale('de')).tr('common_filter'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('filter-amount-section')),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'filters-de-dark');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        reviewApp(
          const DuplicateFinderScreen(),
          locale: const Locale('ar'),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'duplicates-ar-dark');
      await tester.tap(find.byKey(const ValueKey('duplicate-one-two')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-one')));
      await tester.pumpAndSettle();
      await capture(tester, 'comparison-ar-dark');
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((request) async => mockResponse(request)));
    expect(tester.takeException(), isNull);
  }, skip: !savePreviews);
}
