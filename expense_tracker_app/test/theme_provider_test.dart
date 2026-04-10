import 'dart:math' as math;

import 'package:expense_tracker_app/core/app_color_semantics.dart';
import 'package:expense_tracker_app/core/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThemeProvider accent model', () {
    test(
      'migrates existing installs to Mix and defaults labels to raw',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'accent_color': appAccentNeutral,
        });

        final provider = ThemeProvider(random: math.Random(1));
        await provider.load();

        final prefs = await SharedPreferences.getInstance();
        expect(provider.accentId, appAccentMix);
        expect(provider.labelColorMode, AppLabelColorMode.raw);
        expect(prefs.getInt('accent_migration_version'), 1);
        expect(prefs.getString('accent_color'), appAccentMix);
        expect(prefs.getString('label_color_mode'), 'raw');
      },
    );

    test('persists explicit accent and label color mode choices', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'accent_migration_version': 1,
        'accent_color': appAccentNeutral,
        'label_color_mode': 'raw',
      });

      final provider = ThemeProvider(random: math.Random(2));
      await provider.load();
      await provider.setAccent(appAccentPurple);
      await provider.setLabelColorMode(AppLabelColorMode.themed);

      final reloaded = ThemeProvider(random: math.Random(9));
      await reloaded.load();

      expect(reloaded.accentId, appAccentPurple);
      expect(reloaded.labelColorMode, AppLabelColorMode.themed);
    });

    test('keeps one Mix home accent for the provider session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'accent_migration_version': 1,
        'accent_color': appAccentMix,
      });

      final provider = ThemeProvider(random: math.Random(4));
      await provider.load();

      final firstIndex = provider.mixHomeAccentIndex;
      final firstAccent = provider.lightTheme
          .extension<AppSemanticThemeExtension>()!
          .homeHeroTone
          .accent;

      await provider.setAccent(appAccentPurple);
      await provider.setAccent(appAccentMix);

      final secondAccent = provider.lightTheme
          .extension<AppSemanticThemeExtension>()!
          .homeHeroTone
          .accent;

      expect(provider.mixHomeAccentIndex, firstIndex);
      expect(secondAccent, firstAccent);
    });
  });
}
