import 'package:expense_tracker_app/core/item_translation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('item translation freshness', () {
    test('retranslates when the stored source language changed', () {
      expect(
        ItemTranslationService.shouldRetranslate(
          translatedText: 'Milk',
          expectedSourceLanguage: 'sr',
          expectedTargetLanguage: 'en',
          translatedSourceLanguage: 'en',
          translatedTargetLanguage: 'en',
        ),
        isTrue,
      );
    });

    test(
      'reuses an existing translation when source and target still match',
      () {
        expect(
          ItemTranslationService.shouldRetranslate(
            translatedText: 'Milk',
            expectedSourceLanguage: 'sr',
            expectedTargetLanguage: 'en',
            translatedSourceLanguage: 'sr',
            translatedTargetLanguage: 'en',
          ),
          isFalse,
        );
      },
    );

    test('retranslates when the stored target language changed', () {
      expect(
        ItemTranslationService.shouldRetranslate(
          translatedText: 'Milk',
          expectedSourceLanguage: 'sr',
          expectedTargetLanguage: 'de',
          translatedSourceLanguage: 'sr',
          translatedTargetLanguage: 'en',
        ),
        isTrue,
      );
    });
  });

  group('item translation visibility', () {
    test('shows only enabled, non-empty, different translated text', () {
      expect(
        ItemTranslationService.shouldShowTranslatedText(
          translationEnabled: true,
          originalText: 'Milk',
          translatedText: 'Молоко',
        ),
        isTrue,
      );
      expect(
        ItemTranslationService.shouldShowTranslatedText(
          translationEnabled: false,
          originalText: 'Milk',
          translatedText: 'Молоко',
        ),
        isFalse,
      );
      expect(
        ItemTranslationService.shouldShowTranslatedText(
          translationEnabled: true,
          originalText: 'Milk',
          translatedText: '   ',
        ),
        isFalse,
      );
      expect(
        ItemTranslationService.shouldShowTranslatedText(
          translationEnabled: true,
          originalText: 'Milk',
          translatedText: '  Milk  ',
        ),
        isFalse,
      );
    });
  });

  group('item translation language support', () {
    test('maps RU language code to ML Kit Russian', () {
      expect(
        ItemTranslationService.instance.supportsMlKitLanguageForTesting('RU'),
        isTrue,
      );
    });
  });
}
