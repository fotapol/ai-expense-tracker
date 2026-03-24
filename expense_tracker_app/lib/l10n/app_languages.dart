class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.englishName,
    required this.nativeName,
    this.searchKeywords = const [],
  });

  final String code;
  final String englishName;
  final String nativeName;
  final List<String> searchKeywords;
}

const List<AppLanguage> appLanguages = [
  AppLanguage(
    code: 'en',
    englishName: 'English',
    nativeName: 'English',
    searchKeywords: ['english'],
  ),
  AppLanguage(
    code: 'de',
    englishName: 'German',
    nativeName: 'Deutsch',
    searchKeywords: ['german'],
  ),
  AppLanguage(
    code: 'fr',
    englishName: 'French',
    nativeName: 'Français',
    searchKeywords: ['french'],
  ),
  AppLanguage(
    code: 'uk',
    englishName: 'Ukrainian',
    nativeName: 'Українська',
    searchKeywords: ['ukrainian'],
  ),
  AppLanguage(
    code: 'it',
    englishName: 'Italian',
    nativeName: 'Italiano',
    searchKeywords: ['italian'],
  ),
  AppLanguage(
    code: 'es',
    englishName: 'Spanish',
    nativeName: 'Español',
    searchKeywords: ['spanish'],
  ),
  AppLanguage(
    code: 'pl',
    englishName: 'Polish',
    nativeName: 'Polski',
    searchKeywords: ['polish'],
  ),
  AppLanguage(
    code: 'sr',
    englishName: 'Serbian',
    nativeName: 'Srpski',
    searchKeywords: ['serbian'],
  ),
  AppLanguage(
    code: 'ru',
    englishName: 'Russian',
    nativeName: 'Русский',
    searchKeywords: ['russian'],
  ),
  AppLanguage(
    code: 'pt',
    englishName: 'Portuguese',
    nativeName: 'Português',
    searchKeywords: ['portuguese'],
  ),
  AppLanguage(
    code: 'tr',
    englishName: 'Turkish',
    nativeName: 'Türkçe',
    searchKeywords: ['turkish'],
  ),
  AppLanguage(
    code: 'nl',
    englishName: 'Dutch',
    nativeName: 'Nederlands',
    searchKeywords: ['dutch'],
  ),
  AppLanguage(
    code: 'sv',
    englishName: 'Swedish',
    nativeName: 'Svenska',
    searchKeywords: ['swedish'],
  ),
  AppLanguage(
    code: 'cs',
    englishName: 'Czech',
    nativeName: 'Čeština',
    searchKeywords: ['czech'],
  ),
  AppLanguage(
    code: 'ro',
    englishName: 'Romanian',
    nativeName: 'Română',
    searchKeywords: ['romanian'],
  ),
  AppLanguage(
    code: 'hu',
    englishName: 'Hungarian',
    nativeName: 'Magyar',
    searchKeywords: ['hungarian'],
  ),
  AppLanguage(
    code: 'id',
    englishName: 'Indonesian',
    nativeName: 'Bahasa Indonesia',
    searchKeywords: ['indonesian'],
  ),
  AppLanguage(
    code: 'ms',
    englishName: 'Malay',
    nativeName: 'Bahasa Melayu',
    searchKeywords: ['malay'],
  ),
  AppLanguage(
    code: 'vi',
    englishName: 'Vietnamese',
    nativeName: 'Tiếng Việt',
    searchKeywords: ['vietnamese'],
  ),
  AppLanguage(
    code: 'zh',
    englishName: 'Chinese',
    nativeName: '中文',
    searchKeywords: ['chinese', 'mandarin'],
  ),
  AppLanguage(
    code: 'ja',
    englishName: 'Japanese',
    nativeName: '日本語',
    searchKeywords: ['japanese'],
  ),
  AppLanguage(
    code: 'ko',
    englishName: 'Korean',
    nativeName: '한국어',
    searchKeywords: ['korean'],
  ),
  AppLanguage(
    code: 'hi',
    englishName: 'Hindi',
    nativeName: 'हिन्दी',
    searchKeywords: ['hindi'],
  ),
  AppLanguage(
    code: 'ar',
    englishName: 'Arabic',
    nativeName: 'العربية',
    searchKeywords: ['arabic'],
  ),
];
