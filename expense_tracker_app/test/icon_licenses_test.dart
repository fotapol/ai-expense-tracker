import 'package:expense_tracker_app/core/category_icon_registry.dart';
import 'package:expense_tracker_app/core/third_party_licenses.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/screens/about_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'adaptive_interface_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'existing saved category keys keep resolving after the icon migration',
    () {
      const savedKeys = [
        'restaurant',
        'car',
        'bag',
        'movie',
        'health',
        'bolt',
        'school',
        'shirt',
        'devices',
        'home',
        'flight',
        'gift',
        'shield',
        'sparkle',
        'pets',
        'work',
        'cafe',
        'fitness',
        'beauty',
        'tag',
      ];
      expect(
        CategoryIconRegistry.options.map((option) => option.key),
        savedKeys,
      );
      for (final key in savedKeys) {
        final glyph = CategoryIconRegistry.resolve(key);
        expect(glyph.fontFamily, 'Lucide');
        expect(glyph.fontPackage, 'lucide_icons_flutter');
      }
    },
  );

  test(
    'the in-app license registry includes both upstream notices once',
    () async {
      registerThirdPartyLicenses();
      registerThirdPartyLicenses();
      final entries = await LicenseRegistry.licenses
          .where((entry) => entry.packages.contains('Lucide / Feather icons'))
          .toList();
      expect(entries, hasLength(1));
      final notice = entries.single.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      expect(notice, contains('ISC License'));
      expect(notice, contains('2026 Lucide Icons and Contributors'));
      expect(notice, contains('The MIT License (MIT)'));
      expect(notice, contains('2013-present Cole Bemis'));
    },
  );

  testWidgets(
    'About shows localized release notes and a short license overview',
    (tester) async {
      const locale = Locale('de');
      final strings = AppLocalizations(locale);
      PackageInfo.setMockInitialValues(
        appName: 'AI Expense Tracker',
        packageName: 'com.nexavend.expense_tracker_app',
        version: '1.1.0',
        buildNumber: '2',
        buildSignature: '',
      );
      fixture.phone(tester, width: 320);
      await tester.pumpWidget(
        fixture.app(const AboutScreen(), locale: locale, systemText: 1.35),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1.1.0'), findsNWidgets(2));
      expect(
        find.text(strings.tr('about_release_receipt_filters')),
        findsOneWidget,
      );
      final licenses = find.text(strings.tr('about_licenses_subtitle'));
      await tester.ensureVisible(licenses);
      await tester.tap(licenses);
      await tester.pumpAndSettle();

      expect(find.text('Lucide / Feather'), findsOneWidget);
      expect(find.byType(LicensePage), findsNothing);
      await tester.tap(find.text(strings.tr('about_licenses_full')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(LicensePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
