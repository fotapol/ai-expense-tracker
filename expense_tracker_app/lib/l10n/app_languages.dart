class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.nativeName,
    this.searchKeywords = const [],
  });

  final String code;
  final String nativeName;
  final List<String> searchKeywords;
}

const List<AppLanguage> appLanguages = [
  AppLanguage(code: 'en', nativeName: 'English', searchKeywords: ['english']),
  AppLanguage(code: 'de', nativeName: 'Deutsch', searchKeywords: ['german']),
  AppLanguage(code: 'fr', nativeName: 'Français', searchKeywords: ['french']),
  AppLanguage(
    code: 'uk',
    nativeName: 'Українська',
    searchKeywords: ['ukrainian'],
  ),
  AppLanguage(code: 'it', nativeName: 'Italiano', searchKeywords: ['italian']),
  AppLanguage(code: 'es', nativeName: 'Español', searchKeywords: ['spanish']),
  AppLanguage(code: 'pl', nativeName: 'Polski', searchKeywords: ['polish']),
  AppLanguage(code: 'sr', nativeName: 'Srpski', searchKeywords: ['serbian']),
  AppLanguage(code: 'ru', nativeName: 'Русский', searchKeywords: ['russian']),
  AppLanguage(
    code: 'pt',
    nativeName: 'Português',
    searchKeywords: ['portuguese'],
  ),
  AppLanguage(code: 'tr', nativeName: 'Türkçe', searchKeywords: ['turkish']),
  AppLanguage(code: 'nl', nativeName: 'Nederlands', searchKeywords: ['dutch']),
  AppLanguage(code: 'sv', nativeName: 'Svenska', searchKeywords: ['swedish']),
  AppLanguage(code: 'cs', nativeName: 'Čeština', searchKeywords: ['czech']),
  AppLanguage(code: 'ro', nativeName: 'Română', searchKeywords: ['romanian']),
  AppLanguage(code: 'hu', nativeName: 'Magyar', searchKeywords: ['hungarian']),
  AppLanguage(
    code: 'id',
    nativeName: 'Bahasa Indonesia',
    searchKeywords: ['indonesian'],
  ),
  AppLanguage(
    code: 'ms',
    nativeName: 'Bahasa Melayu',
    searchKeywords: ['malay'],
  ),
  AppLanguage(
    code: 'vi',
    nativeName: 'Tiếng Việt',
    searchKeywords: ['vietnamese'],
  ),
  AppLanguage(
    code: 'zh',
    nativeName: '中文',
    searchKeywords: ['chinese', 'mandarin'],
  ),
  AppLanguage(code: 'ja', nativeName: '日本語', searchKeywords: ['japanese']),
  AppLanguage(code: 'ko', nativeName: '한국어', searchKeywords: ['korean']),
  AppLanguage(code: 'hi', nativeName: 'हिन्दी', searchKeywords: ['hindi']),
  AppLanguage(code: 'ar', nativeName: 'العربية', searchKeywords: ['arabic']),
];
