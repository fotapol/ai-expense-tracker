import 'package:expense_tracker_app/core/category_icon_registry.dart';
import 'package:expense_tracker_app/core/third_party_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
