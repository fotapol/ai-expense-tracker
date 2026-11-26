import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:expense_tracker_app/core/duplicate_comparison.dart';
import 'package:expense_tracker_app/core/interface_scale.dart';
import 'package:expense_tracker_app/core/money_formatter.dart';
import 'package:expense_tracker_app/core/theme_provider.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/appearance_settings_screen.dart';
import 'package:expense_tracker_app/screens/categories_screen.dart';
import 'package:expense_tracker_app/screens/subcategories_screen.dart';
import 'package:expense_tracker_app/screens/labels_screen.dart';
import 'package:expense_tracker_app/screens/duplicate_finder_screen.dart';
import 'package:expense_tracker_app/screens/receipts_tab.dart';
import 'package:expense_tracker_app/screens/home_tab.dart';
import 'package:expense_tracker_app/screens/tools_screen.dart';
import 'package:expense_tracker_app/screens/analytics_screen.dart';
import 'package:expense_tracker_app/screens/analytics_trends_tab.dart';
import 'package:expense_tracker_app/core/analytics_filters.dart';
import 'package:expense_tracker_app/widgets/app_tab_footer.dart';
import 'package:expense_tracker_app/widgets/filter_bottom_sheet.dart';
import 'package:expense_tracker_app/widgets/duplicate_details_comparison.dart';
import 'package:expense_tracker_app/widgets/receipt_history_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/authenticated_api.dart';

const _sorts = {
  'newest': 'receipts_sort_newest',
  'oldest': 'receipts_sort_oldest',
  'amount_asc': 'receipts_sort_amount_asc',
  'amount_desc': 'receipts_sort_amount_desc',
  'merchant_asc': 'receipts_sort_merchant_asc',
};
final _previewKey = GlobalKey();

Widget app(
  Widget home, {
  double factor = 1,
  Locale locale = const Locale('en'),
  double systemText = 1,
  bool boldText = false,
  bool dark = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: _theme(dark),
  locale: locale,
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
    ).copyWith(textScaler: TextScaler.linear(systemText), boldText: boldText),
    child: InterfaceScale(factor: factor, child: child!),
  ),
  home: home,
);

ThemeData _theme(bool dark) {
  final theme = dark ? themeProvider.darkTheme : themeProvider.lightTheme;
  return const bool.fromEnvironment('SAVE_ADAPTIVE_PREVIEWS')
      ? theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'DejaVuSans'),
          chipTheme: theme.chipTheme.copyWith(
            labelStyle: theme.chipTheme.labelStyle?.copyWith(
              fontFamily: 'DejaVuSans',
            ),
            secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
              fontFamily: 'DejaVuSans',
            ),
          ),
          popupMenuTheme: theme.popupMenuTheme.copyWith(
            textStyle: theme.popupMenuTheme.textStyle?.copyWith(
              fontFamily: 'DejaVuSans',
            ),
          ),
          appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
              fontFamily: 'DejaVuSans',
            ),
          ),
        )
      : theme;
}

void phone(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

Map<String, dynamic> tx(String id) => {
  'id': id,
  'merchant_name': 'Sample Market',
  'occurred_at': '2026-01-10T12:30:00Z',
  'created_at': '2026-01-10T12:30:00Z',
  'updated_at': '2026-01-10T12:30:00Z',
  'amount_total': id == 'two' ? 1685.0 : 1680.0,
  'currency': 'RSD',
  'display_amount_total': id == 'two' ? 14.04 : 14.0,
  'display_currency': 'EUR',
  'source': 'RECEIPT',
  'status': 'CONFIRMED',
  'receipt_id': 'photo-$id',
  'labels': [],
  'category_code': 'FOOD',
  'category_name': 'Food',
  'items': [
    for (var i = 0; i < 14; i++)
      {
        'id': '$id-$i',
        'description': ['Milk 2.8%', 'Tomatoes', 'Bread'][i % 3],
        'amount': i == 2 && id == 'two' ? 125 : 120,
        'qty': i == 1 && id == 'two' ? 0.75 : 0.5,
        'unit': 'kg',
        'unit_price': 240,
        'line_no': i + 1,
      },
  ],
};
Map<String, dynamic> pair(String a, String b) => {
  'first': tx(a),
  'second': tx(b),
  'confidence': 'exact',
  'reasons': ['same_image'],
  'matching_item_count': 12,
};

http.Response response(http.Request request) {
  final path = request.url.path;
  if (path.endsWith('/summary')) {
    return http.Response(
      '{"currency":"EUR","total_amount":860.50,"total_transactions":3,"breakdown":[]}',
      200,
    );
  }
  if (path == '/v1/me') return http.Response('{"default_currency":"EUR"}', 200);
  if (path.contains('subscription')) {
    return http.Response(
      '{"category_usage":{"categories_limit":3,"categories_used":0,"subcategories_limit":10,"subcategories_used":0}}',
      200,
    );
  }
  if (path == '/v1/categories') {
    return http.Response(
      jsonEncode([
        {
          'id': 'food',
          'code': 'FOOD',
          'name': 'Food',
          'scope': 'TRANSACTION',
          'is_default': true,
          'is_active': true,
        },
        for (var i = 0; i < 12; i++)
          {
            'id': 'sub-$i',
            'parent_id': 'food',
            'code': 'CUSTOM_$i',
            'name': [
              'Baby food',
              'Bakery',
              'Meat and seafood',
              'Dairy products',
            ][i % 4],
            'scope': 'ITEM',
            'is_default': true,
            'is_active': true,
          },
      ]),
      200,
    );
  }
  if (path == '/v1/labels') {
    return http.Response(
      '[{"id":"work","name":"Work expenses","color":"#AB7CFF"},{"id":"travel","name":"Travel","color":"#51A590"}]',
      200,
    );
  }
  if (path == '/v1/transactions') {
    return http.Response(jsonEncode([tx('one'), tx('two'), tx('three')]), 200);
  }
  if (path.startsWith('/v1/transactions/')) {
    return http.Response(jsonEncode(tx(path.split('/').last)), 200);
  }
  if (path == '/v1/duplicates') {
    return http.Response(
      jsonEncode({
        'items': [
          pair('one', 'two'),
          pair('one', 'three'),
          pair('two', 'three'),
        ],
        'has_more': false,
      }),
      200,
    );
  }
  return http.Response('[]', 200);
}

http.Response homeSpendingResponse(http.Request request) {
  if (request.url.path == '/v1/me') {
    return http.Response(
      '{"default_currency":"RSD","profile":{"display_name":"Sample Shopper"}}',
      200,
    );
  }
  if (request.url.path.endsWith('/summary')) {
    return http.Response(
      jsonEncode({
        'currency': 'RSD',
        'total_amount': 6856,
        'breakdown': [
          {'code': 'FOOD', 'amount': 6241, 'percentage': 91},
          {'code': 'ENTERTAINMENT', 'amount': 400, 'percentage': 6},
          {'code': 'PERSONAL_CARE', 'amount': 215, 'percentage': 3},
        ],
      }),
      200,
    );
  }
  return response(request);
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final boundary =
      _previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(
      '/tmp/expense-adaptive-previews',
    ).create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({'accent_migration_version': 1});
    await themeProvider.load();
  });

  test('scale labels are exact percentages and survive reload', () async {
    final provider = ThemeProvider();
    await provider.load();
    for (final id in ['60', '80', '100', '120']) {
      await provider.setFontSize(id);
      expect(provider.interfaceScaleFactor, double.parse(id) / 100);
      final restored = ThemeProvider();
      await restored.load();
      expect(restored.interfaceScaleFactor, double.parse(id) / 100);
    }
  });

  test(
    'three duplicate receipts form one group without implying a new match',
    () {
      final groups = duplicateGroups([
        pair('one', 'two'),
        pair('two', 'three'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single, hasLength(2));
      expect(
        duplicateGroups([pair('one', 'two'), pair('two', 'one')]).single,
        hasLength(1),
      );
    },
  );

  test(
    'item alignment preserves repeated lines and exposes weight and price differences',
    () {
      final rows = compareItems(
        [
          {'description': 'Milk', 'amount': 10, 'qty': 1, 'unit': 'l'},
          {'description': 'Milk', 'amount': 20, 'qty': 2, 'unit': 'l'},
          {'description': 'Apples', 'amount': 30, 'qty': 0.5, 'unit': 'kg'},
        ],
        [
          {'description': 'Milk', 'amount': 20, 'qty': 2, 'unit': 'l'},
          {'description': 'Apples', 'amount': 30, 'qty': 0.75, 'unit': 'kg'},
        ],
      );
      expect(rows, hasLength(3));
      expect(rows[0].second, isNull);
      expect(rows[1].identical, isTrue);
      expect(rows[2].same('amount'), isTrue);
      expect(rows[2].same('qty'), isFalse);
    },
  );

  for (final factor in [.6, .8, 1.0, 1.2]) {
    testWidgets(
      '$factor scales layout and keeps system text and navigation insets',
      (tester) async {
        phone(tester);
        late MediaQueryData media;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: SafeArea(
                child: Builder(
                  builder: (context) {
                    media = MediaQuery.of(context);
                    return Column(
                      children: [
                        const SizedBox(
                          key: ValueKey('measured'),
                          width: 100,
                          height: 40,
                        ),
                        const Spacer(),
                        FilledButton(
                          key: const ValueKey('touch'),
                          onPressed: () {},
                          child: const Text('Apply'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            factor: factor,
            systemText: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(const ValueKey('measured')));
        expect(rect.width, closeTo(100 * factor, .1));
        expect(rect.height, closeTo(40 * factor, .1));
        expect(media.size.width, closeTo(390 / factor, .1));
        expect(media.textScaler.scale(10), 15);
        final button = tester.getRect(find.byKey(const ValueKey('touch')));
        expect(button.bottom, lessThanOrEqualTo(820.1));
        expect(button.height, greaterThanOrEqualTo(47.9 * factor));
        expect(button.height, lessThanOrEqualTo(60 * factor));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'comparison totals stay aligned with missing unit prices and wrapped quantities',
    (tester) async {
      phone(tester, width: 320);
      final first = tx('one');
      final second = tx('two');
      first['items'] = [
        {
          'description': 'Produce',
          'qty': 1,
          'unit': 'kilograms of produce',
          'unit_price': 10,
          'amount': 10,
        },
      ];
      second['items'] = [
        {
          'description': 'Produce',
          'qty': 1000,
          'unit': 'kilograms of produce',
          'amount': 20,
        },
      ];
      await tester.pumpWidget(
        app(
          Scaffold(
            body: SingleChildScrollView(
              child: DuplicateDetailsComparison(
                transactions: [first, second],
                selectedId: null,
                onSelect: (_) {},
                onPhoto: (_) {},
                busy: false,
              ),
            ),
          ),
          factor: 1.2,
          systemText: 1.4,
        ),
      );
      await tester.pumpAndSettle();
      final left = find.text(formatMoney('RSD', 10)).last;
      final right = find.text(formatMoney('RSD', 20));
      expect(
        tester.getTopLeft(left).dy,
        closeTo(tester.getTopLeft(right).dy, .1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'controls share a row at compact scale and equal height at 100 percent',
    (tester) async {
      phone(tester);
      Widget controls() => Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ReceiptHistoryControls(
            sort: 'newest',
            labels: _sorts,
            reviewOnly: false,
            onSort: (_) {},
            onReview: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(
        app(controls(), factor: .6, locale: const Locale('de')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('receipt-controls-inline')),
        findsOneWidget,
      );
      await tester.pumpWidget(app(controls()));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('receipt-sort'))).height,
        closeTo(
          tester
              .getSize(find.byKey(const ValueKey('receipt-review-filter')))
              .height,
          .5,
        ),
      );
    },
  );

  testWidgets(
    'three matching receipts are shown once each above the navigation inset',
    (tester) async {
      phone(tester);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const DuplicateFinderScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Sample Market'), findsNWidgets(3));
        expect(find.text('Receipts in this group: 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => MockClient((r) async => response(r)));
    },
  );

  testWidgets(
    'display amount needs no original currency and advanced filters are collapsed',
    (tester) async {
      phone(tester);
      await http.runWithClient(() async {
        Map<String, dynamic>? result;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await FilterBottomSheet.show(
                      context,
                      selectedPeriod: 'All Time',
                      enableReceiptFilters: true,
                      displayCurrency: 'EUR',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Amount (EUR)'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('filter-min-amount')),
          '5,25',
        );
        await tester.enterText(
          find.byKey(const ValueKey('filter-max-amount')),
          '20',
        );
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(result?['min_amount'], '5.25');
        expect(result?['currency'], isNull);
        expect(result?['display_currency'], 'EUR');
      }, () => MockClient((r) async => response(r)));
    },
  );

  testWidgets(
    'compact interface popup menus and dialogs keep correct tap coordinates',
    (tester) async {
      phone(tester);
      String? chosen;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ReceiptHistoryControls(
                    sort: 'newest',
                    labels: _sorts,
                    reviewOnly: false,
                    onSort: (value) => chosen = value,
                    onReview: (_) {},
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Dialog'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Open dialog'),
                  ),
                ],
              ),
            ),
          ),
          factor: .6,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-sort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Oldest first'),
      );
      await tester.pumpAndSettle();
      expect(chosen, 'oldest');
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final factor in [.6, 1.2]) {
    testWidgets(
      '$factor converts keyboard insets without covering body actions',
      (tester) async {
        phone(tester);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          app(
            Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    const TextField(key: ValueKey('keyboard-input')),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('keyboard-action'),
                      onPressed: () {},
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ),
            factor: factor,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('keyboard-input')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('keyboard-action'))).bottom,
          lessThanOrEqualTo(544.1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'main and management pages reflow at 120 percent with larger system text',
    (tester) async {
      phone(tester, width: 320);
      await http.runWithClient(() async {
        for (final home in [
          const HomeTab(),
          const ToolsScreen(),
          const CategoriesScreen(),
          const SubcategoriesScreen(
            parentId: 'food',
            parentName: 'A long category title',
            parentIsDefault: true,
          ),
          const LabelsScreen(),
          const AppearanceSettingsScreen(),
        ]) {
          await tester.pumpWidget(
            app(
              Scaffold(body: home),
              factor: 1.2,
              systemText: 1.4,
              locale: const Locale('ru'),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }, () => MockClient((r) async => response(r)));
    },
  );

  testWidgets(
    'adaptive previews',
    (tester) async {
      phone(tester);
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await tester.runAsync(() async {
          for (final font in {
            'DejaVuSans': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
            'Roboto': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
            'packages/lucide_icons_flutter/Lucide':
                '/home/kirill/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.3/assets/lucide.ttf',
            'MaterialIcons':
                '/home/kirill/.local/flutter-sdks/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          }.entries) {
            if (await File(font.value).exists()) {
              await (FontLoader(font.key)..addFont(
                    File(
                      font.value,
                    ).readAsBytes().then((b) => b.buffer.asByteData()),
                  ))
                  .load();
            }
          }
        });
        await http.runWithClient(() async {
          Future<void> show(
            Widget home,
            String name, {
            double factor = 1,
            Locale locale = const Locale('en'),
            bool dark = true,
            double systemText = 1,
            bool boldText = false,
            String? reveal,
          }) async {
            await themeProvider.setFontSize((factor * 100).round().toString());
            await tester.pumpWidget(
              RepaintBoundary(
                key: _previewKey,
                child: app(
                  home,
                  factor: factor,
                  locale: locale,
                  dark: dark,
                  systemText: systemText,
                  boldText: boldText,
                ),
              ),
            );
            if (reveal != null) {
              await tester.pumpAndSettle();
              final target = find.text(reveal);
              if (target.evaluate().isEmpty) {
                await tester.scrollUntilVisible(target, 140);
              } else {
                await tester.ensureVisible(target);
              }
              await tester.pumpAndSettle();
            }
            await capture(tester, name);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }

          tester.view.physicalSize = const Size(320, 844);
          await http.runWithClient(
            () async {
              const home = Scaffold(body: HomeTab());
              await show(
                home,
                'home-bold-narrow',
                dark: false,
                systemText: 1.35,
                boldText: true,
              );
              await show(
                home,
                'home-bold-spending',
                dark: false,
                systemText: 1.35,
                boldText: true,
                reveal: 'Spending Overview',
              );
            },
            () => MockClient((request) async => homeSpendingResponse(request)),
          );
          tester.view.physicalSize = const Size(390, 844);

          await show(const Scaffold(body: ReceiptsTab()), 'history-100');
          await show(
            const Scaffold(body: ReceiptsTab()),
            'history-de-60',
            factor: .6,
            locale: const Locale('de'),
            dark: false,
          );
          await show(const DuplicateFinderScreen(), 'duplicate-group');
          await http.runWithClient(
            () async {
              for (final locale in [const Locale('en'), const Locale('de')]) {
                await show(
                  const Scaffold(
                    body: AnalyticsTrendsTab(filters: AnalyticsFilters()),
                  ),
                  'final-trends-${locale.languageCode}-100',
                  locale: locale,
                  dark: false,
                );
              }
            },
            () => MockClient((request) async {
              if (request.url.path.endsWith('/trends')) {
                return http.Response(
                  jsonEncode({
                    'currency': 'EUR',
                    'total_amount': 1004,
                    'previous_total_amount': 0,
                    'change_percentage': null,
                    'bucket_unit': 'month',
                    'buckets': [
                      {
                        'label': 'Sep',
                        'start_date': '2026-09-01',
                        'end_date': '2026-09-30',
                        'amount': 1004,
                        'transaction_count': 1,
                      },
                      {
                        'label': 'Oct',
                        'start_date': '2026-10-01',
                        'end_date': '2026-10-31',
                        'amount': 0,
                        'transaction_count': 0,
                      },
                      {
                        'label': 'Nov',
                        'start_date': '2026-11-01',
                        'end_date': '2026-11-30',
                        'amount': 0,
                        'transaction_count': 0,
                      },
                    ],
                  }),
                  200,
                );
              }
              if (request.url.path.endsWith('/summary')) {
                return http.Response(
                  '{"currency":"EUR","total_amount":1004,"total_transactions":1,"breakdown":[]}',
                  200,
                );
              }
              return response(request);
            }),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: _previewKey,
              child: app(
                const DuplicateFinderScreen(),
                dark: true,
                locale: const Locale('ru'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('duplicate-one-two')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('select-one')));
          await capture(tester, 'comparison-top');
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.drag(
            find.byKey(const ValueKey('duplicate-comparison-list')),
            const Offset(0, -240),
          );
          await capture(tester, 'comparison-items');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await show(
            const AppearanceSettingsScreen(),
            'appearance-60',
            factor: .6,
            locale: const Locale('de'),
            dark: false,
          );
          await show(
            const Scaffold(body: HomeTab()),
            'home-ru-120',
            factor: 1.2,
            locale: const Locale('ru'),
            systemText: 1.4,
          );
          await http.runWithClient(
            () async {
              await show(
                Scaffold(
                  body: const HomeTab(),
                  bottomNavigationBar: AppTabFooter(
                    selectedIndex: 0,
                    onSelected: (_) {},
                  ),
                ),
                'polish-home-de-100',
                locale: const Locale('de'),
                dark: false,
              );
            },
            () => MockClient((request) async {
              if (request.url.path == '/v1/transactions') {
                return http.Response('[]', 200);
              }
              if (request.url.path.endsWith('/summary')) {
                return http.Response(
                  '{"currency":"EUR","total_amount":0,"total_transactions":0,"breakdown":[]}',
                  200,
                );
              }
              return response(request);
            }),
          );
          await show(
            Scaffold(
              body: const ToolsScreen(),
              bottomNavigationBar: AppTabFooter(
                selectedIndex: 1,
                onSelected: (_) {},
              ),
            ),
            'polish-tools-de-100',
            locale: const Locale('de'),
            dark: false,
          );
          await http.runWithClient(
            () async {
              await show(
                const DuplicateFinderScreen(),
                'polish-empty-duplicates',
                locale: const Locale('de'),
                dark: false,
              );
            },
            () => MockClient(
              (request) async =>
                  http.Response('{"items":[],"has_more":false}', 200),
            ),
          );
          await http.runWithClient(
            () async {
              for (final factor in [.8, 1.0, 1.2]) {
                await show(
                  const AnalyticsScreen(),
                  'polish-analytics-de-${(factor * 100).round()}',
                  factor: factor,
                  locale: const Locale('de'),
                  dark: false,
                );
              }
            },
            () => MockClient((request) async {
              if (request.url.path.endsWith('/trends')) {
                return http.Response(
                  '{"currency":"EUR","total_amount":42.04,"previous_total_amount":0,"change_percentage":null,"buckets":[]}',
                  200,
                );
              }
              if (request.url.path.endsWith('/summary')) {
                return http.Response(
                  '{"currency":"EUR","total_amount":42.04,"total_transactions":3,"breakdown":[]}',
                  200,
                );
              }
              return response(request);
            }),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: _previewKey,
              child: app(
                const Scaffold(
                  body: FilterBottomSheet(
                    selectedPeriod: 'All Time',
                    enableReceiptFilters: true,
                    displayCurrency: 'EUR',
                  ),
                ),
                locale: const Locale('de'),
                dark: false,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('Weitere Filter')),
          );
          await tester.pump(const Duration(milliseconds: 200));
          await capture(tester, 'polish-filter-pressed');
          await gesture.up();
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('receipt-period-All Time')),
          );
          await capture(tester, 'polish-period-menu');
          await tester.tapAt(const Offset(1, 1));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await show(
            const Scaffold(
              body: FilterBottomSheet(
                selectedPeriod: 'All Time',
                enableReceiptFilters: true,
                displayCurrency: 'EUR',
                selectedCategoryIds: ['food'],
                selectedSubcategoryIds: ['sub-0', 'sub-1', 'sub-3'],
              ),
            ),
            'polish-selected-categories',
            reveal: 'Baby food',
            locale: const Locale('de'),
            dark: false,
          );
          await show(const CategoriesScreen(), 'categories-100');
          await show(
            const SubcategoriesScreen(
              parentId: 'food',
              parentName: 'Food',
              parentIsDefault: true,
            ),
            'subcategories-100',
          );
          await show(const LabelsScreen(), 'labels-100');
          await show(
            const Scaffold(
              body: FilterBottomSheet(
                selectedPeriod: 'All Time',
                enableReceiptFilters: true,
                displayCurrency: 'EUR',
              ),
            ),
            'filters-100',
          );
        }, () => MockClient((r) async => response(r)));
      } finally {
        debugDisableShadows = oldShadows;
      }
    },
    skip: !const bool.fromEnvironment('SAVE_ADAPTIVE_PREVIEWS'),
  );
}
