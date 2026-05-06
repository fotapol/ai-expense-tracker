class ItemTranslationSource {
  const ItemTranslationSource({
    required this.text,
    required this.language,
    required this.usesNormalizedName,
  });

  final String text;
  final String language;
  final bool usesNormalizedName;
}

class ItemNameDisplay {
  const ItemNameDisplay({
    required this.primaryText,
    required this.translationSource,
    required this.isUserEdited,
  });

  final String primaryText;
  final ItemTranslationSource? translationSource;
  final bool isUserEdited;
}

class ItemNameDisplayResolver {
  const ItemNameDisplayResolver._();

  static String normalizeText(String? raw) {
    return (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String normalizeLanguageCode(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (normalized.isEmpty) return '';
    return normalized.contains('-') ? normalized.split('-').first : normalized;
  }

  static bool hasUserEditedName({
    required Map<String, dynamic> item,
    required String currentDescription,
  }) {
    final rawName = item['raw_name']?.toString();
    if (rawName == null) return false;
    final raw = normalizeText(rawName).toLowerCase();
    final current = normalizeText(currentDescription).toLowerCase();
    if (raw.isEmpty || current.isEmpty) return false;
    return raw != current;
  }

  static ItemTranslationSource? preferredTranslationSource({
    required Map<String, dynamic> item,
    required String currentDescription,
  }) {
    final current = normalizeText(currentDescription);
    if (current.isEmpty) return null;

    if (!hasUserEditedName(item: item, currentDescription: current)) {
      final translatableName = normalizeText(
        item['translatable_name']?.toString(),
      );
      if (translatableName.isNotEmpty) {
        final baseLanguage = normalizeLanguageCode(
          item['normalization_base_language']?.toString(),
        );
        return ItemTranslationSource(
          text: translatableName,
          language: baseLanguage.isEmpty ? 'en' : baseLanguage,
          usesNormalizedName: true,
        );
      }
    }

    var language = normalizeLanguageCode(item['description_lang']?.toString());
    if (language.isEmpty) {
      language = normalizeLanguageCode(
        item['translation_source_language']?.toString(),
      );
    }
    return ItemTranslationSource(
      text: current,
      language: language,
      usesNormalizedName: false,
    );
  }

  static ItemNameDisplay resolve({
    required Map<String, dynamic> item,
    required String currentDescription,
    required bool translationEnabled,
  }) {
    final current = normalizeText(currentDescription);
    final source = preferredTranslationSource(
      item: item,
      currentDescription: current,
    );
    final isUserEdited = hasUserEditedName(
      item: item,
      currentDescription: current,
    );
    if (isUserEdited) {
      return ItemNameDisplay(
        primaryText: current,
        translationSource: source,
        isUserEdited: true,
      );
    }

    final translated = normalizeText(
      item['translated_description']?.toString(),
    );
    final translatedSourceText = normalizeText(
      item['translation_source_text']?.toString(),
    );
    final translationMatchesSource =
        source != null &&
        translatedSourceText.isNotEmpty &&
        translatedSourceText.toLowerCase() == source.text.toLowerCase();
    final showTranslated =
        translationEnabled &&
        translated.isNotEmpty &&
        source != null &&
        translationMatchesSource &&
        translated.toLowerCase() != source.text.toLowerCase();
    if (showTranslated) {
      return ItemNameDisplay(
        primaryText: translated,
        translationSource: source,
        isUserEdited: false,
      );
    }

    final normalizedDisplay = normalizeText(
      item['normalized_display_name']?.toString(),
    );
    if (normalizedDisplay.isNotEmpty) {
      return ItemNameDisplay(
        primaryText: normalizedDisplay,
        translationSource: source,
        isUserEdited: false,
      );
    }

    final expandedName = normalizeText(item['expanded_name']?.toString());
    if (expandedName.isNotEmpty) {
      return ItemNameDisplay(
        primaryText: expandedName,
        translationSource: source,
        isUserEdited: false,
      );
    }

    final showRawTranslation =
        translationEnabled &&
        translated.isNotEmpty &&
        source != null &&
        !source.usesNormalizedName &&
        translated.toLowerCase() != current.toLowerCase();
    if (showRawTranslation) {
      return ItemNameDisplay(
        primaryText: translated,
        translationSource: source,
        isUserEdited: false,
      );
    }

    return ItemNameDisplay(
      primaryText: current,
      translationSource: source,
      isUserEdited: false,
    );
  }
}
