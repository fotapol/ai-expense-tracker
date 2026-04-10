import 'package:expense_tracker_app/core/app_color_semantics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSemanticColors', () {
    test('keeps category mapping stable for the same category code', () {
      final first = AppSemanticColors.categoryTone(
        accentId: appAccentMix,
        brightness: Brightness.light,
        code: 'FOOD',
      );
      final second = AppSemanticColors.categoryTone(
        accentId: appAccentMix,
        brightness: Brightness.light,
        code: 'FOOD',
      );

      expect(first.base, second.base);
    });

    test('keeps themed label mapping stable for the same label seed', () {
      final first = AppSemanticColors.labelTone(
        accentId: appAccentMix,
        brightness: Brightness.light,
        labelColorMode: AppLabelColorMode.themed,
        labelId: 'label-1',
        name: 'Business',
      );
      final second = AppSemanticColors.labelTone(
        accentId: appAccentMix,
        brightness: Brightness.light,
        labelColorMode: AppLabelColorMode.themed,
        labelId: 'label-1',
        name: 'Business',
      );

      expect(first.base, second.base);
    });

    test('uses raw label color when available', () {
      final tone = AppSemanticColors.labelTone(
        accentId: appAccentPurple,
        brightness: Brightness.light,
        labelColorMode: AppLabelColorMode.raw,
        labelId: 'label-2',
        name: 'Travel',
        rawHex: '#24B7D9',
      );

      expect(tone.base, const Color(0xFF24B7D9));
    });

    test('falls back to themed mapping when raw label color is invalid', () {
      final rawFallback = AppSemanticColors.labelTone(
        accentId: appAccentMix,
        brightness: Brightness.light,
        labelColorMode: AppLabelColorMode.raw,
        labelId: 'label-3',
        name: 'Office',
        rawHex: 'not-a-color',
      );
      final themed = AppSemanticColors.labelTone(
        accentId: appAccentMix,
        brightness: Brightness.light,
        labelColorMode: AppLabelColorMode.themed,
        labelId: 'label-3',
        name: 'Office',
      );

      expect(rawFallback.base, themed.base);
    });

    test('Neutral remaps category colors to grayscale values', () {
      final tone = AppSemanticColors.categoryTone(
        accentId: appAccentNeutral,
        brightness: Brightness.light,
        code: 'HEALTH',
      );

      expect(tone.base.red, tone.base.green);
      expect(tone.base.green, tone.base.blue);
    });

    test('Purple remaps category colors into a purple-led family', () {
      final tone = AppSemanticColors.categoryTone(
        accentId: appAccentPurple,
        brightness: Brightness.light,
        code: 'HEALTH',
      );

      expect(tone.base.blue, greaterThan(tone.base.green));
      expect(tone.base.red, greaterThan(tone.base.green - 10));
    });

    test('returns distinct trend palettes for Mix, Neutral, and Purple', () {
      final mix = AppSemanticColors.trendPalette(
        appAccentMix,
        Brightness.light,
      );
      final neutral = AppSemanticColors.trendPalette(
        appAccentNeutral,
        Brightness.light,
      );
      final purple = AppSemanticColors.trendPalette(
        appAccentPurple,
        Brightness.light,
      );

      expect(mix.first, isNot(neutral.first));
      expect(purple.first, isNot(neutral.first));
      expect(neutral.first.red, neutral.first.green);
      expect(neutral.first.green, neutral.first.blue);
    });
  });
}
