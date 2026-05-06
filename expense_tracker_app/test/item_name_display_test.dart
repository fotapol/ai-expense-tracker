import 'package:expense_tracker_app/core/item_name_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('item name display priority', () {
    test('user edit wins only when raw name exists', () {
      final item = <String, dynamic>{
        'raw_name': 'RAW MILK 1L',
        'translatable_name': 'UHT milk',
        'normalized_display_name': 'UHT milk',
        'translated_description': 'Translated milk',
        'translation_source_text': 'UHT milk',
        'normalization_base_language': 'en',
      };

      final display = ItemNameDisplayResolver.resolve(
        item: item,
        currentDescription: 'My custom milk',
        translationEnabled: true,
      );

      expect(display.primaryText, 'My custom milk');
      expect(display.isUserEdited, isTrue);
    });

    test('does not infer a user edit when raw name is missing', () {
      final item = <String, dynamic>{
        'translatable_name': 'clean product',
        'normalized_display_name': 'clean product',
        'translated_description': 'translated product',
        'translation_source_text': 'clean product',
        'normalization_base_language': 'en',
      };

      final display = ItemNameDisplayResolver.resolve(
        item: item,
        currentDescription: 'Different current text',
        translationEnabled: true,
      );

      expect(display.isUserEdited, isFalse);
      expect(display.primaryText, 'translated product');
    });

    test('uses normalized display name when translation is missing', () {
      final item = <String, dynamic>{
        'raw_name': 'NOISY ITEM 500G',
        'translatable_name': 'clean item',
        'normalized_display_name': 'clean item',
        'expanded_name': 'expanded clean item',
        'normalization_base_language': 'en',
      };

      final display = ItemNameDisplayResolver.resolve(
        item: item,
        currentDescription: 'NOISY ITEM 500G',
        translationEnabled: true,
      );

      expect(display.primaryText, 'clean item');
    });

    test('falls back to raw/current name without blank translation space', () {
      final item = <String, dynamic>{
        'description_lang': 'de',
        'translated_description': '   ',
      };

      final display = ItemNameDisplayResolver.resolve(
        item: item,
        currentDescription: 'Original item',
        translationEnabled: true,
      );

      expect(display.primaryText, 'Original item');
    });
  });

  group('item translation source selection', () {
    test('ML Kit uses translatable name when available', () {
      final source = ItemNameDisplayResolver.preferredTranslationSource(
        item: <String, dynamic>{
          'raw_name': 'RAW ITEM',
          'translatable_name': 'clean item',
          'normalization_base_language': 'en',
          'description_lang': 'sr',
        },
        currentDescription: 'RAW ITEM',
      );

      expect(source?.text, 'clean item');
      expect(source?.language, 'en');
      expect(source?.usesNormalizedName, isTrue);
    });

    test(
      'ML Kit falls back to current name when normalized name is absent',
      () {
        final source = ItemNameDisplayResolver.preferredTranslationSource(
          item: <String, dynamic>{'description_lang': 'de'},
          currentDescription: 'Current item',
        );

        expect(source?.text, 'Current item');
        expect(source?.language, 'de');
        expect(source?.usesNormalizedName, isFalse);
      },
    );
  });
}
