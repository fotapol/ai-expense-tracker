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
}
