import 'package:expense_tracker_app/main.dart' show themeProvider;
import 'package:expense_tracker_app/screens/analytics_screen.dart';
import 'package:expense_tracker_app/widgets/sliding_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adaptive_interface_test.dart' as fixture;
import 'custom_period_screens_test.dart' as analytics;
import 'support/authenticated_api.dart';

void main() {
  setUp(() async {
    installAuthenticatedApiUser();
    SharedPreferences.setMockInitialValues({});
    await themeProvider.load();
  });

  for (final reduced in [false, true]) {
    testWidgets(
      'root tabs preserve drafts and support reduced motion=$reduced',
      (tester) async {
        fixture.phone(tester);
        var index = 0;
        late StateSetter update;
        await tester.pumpWidget(
          fixture.app(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduced),
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return Scaffold(
                      body: SlidingTabView(
                        index: index,
                        children: const [
                          Align(
                            alignment: Alignment.topLeft,
                            child: TextField(key: ValueKey('draft')),
                          ),
                          Center(child: Text('Second page')),
                          Center(child: Text('Third page')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('draft')),
          'Unsaved draft',
        );
        update(() => index = 1);
        await tester.pump();
        if (reduced) {
          expect(
            tester.getCenter(find.text('Second page')).dx,
            closeTo(195, .1),
          );
        } else {
          await tester.pump(const Duration(milliseconds: 80));
          final x = tester.getCenter(find.text('Second page')).dx;
          expect(x, greaterThan(195));
          expect(x, lessThan(585));
        }
        // Rapid taps retarget the current position rather than resetting state.
        update(() => index = 2);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        update(() => index = 0);
        await tester.pumpAndSettle();
        expect(find.text('Unsaved draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'analytics indicator moves with the page and saves the final section',
    (tester) async {
      fixture.phone(tester);
      final requests = <http.Request>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(fixture.app(const AnalyticsScreen()));
        await tester.pumpAndSettle();
        final indicator = find.byKey(const ValueKey('analytics-tab-indicator'));
        final initial = tester.getRect(indicator);
        final categories = find.byKey(
          const ValueKey('analytics-section-categories'),
        );
        await tester.tap(categories);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final moving = tester.getRect(indicator);
        expect(moving.left, greaterThan(initial.left));
        expect(moving.left, lessThan(tester.getRect(categories).left));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(indicator).left,
          closeTo(tester.getRect(categories).left, 1),
        );
        expect(
          tester.getRect(indicator).width,
          closeTo(tester.getRect(categories).width, 1),
        );
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('analytics_section'), 'categories');
        final beforeReturn = requests.length;
        await tester.tap(
          find.byKey(const ValueKey('analytics-section-overview')),
        );
        await tester.pumpAndSettle();
        expect(
          requests.length,
          beforeReturn,
          reason: 'A visited overview retains its loaded data',
        );
        await tester.tap(
          find.byKey(const ValueKey('analytics-section-categories')),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(320, 0));
        await tester.pumpAndSettle();
        expect(preferences.getString('analytics_section'), 'trends');
        expect(tester.takeException(), isNull);
      }, () => MockClient((request) async => analytics.response(request)));
    },
  );
}
