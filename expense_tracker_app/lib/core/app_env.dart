import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  AppEnv._();

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Keep launch-safe fallbacks if the asset is missing in local builds.
    }
  }

  static String get websiteUrl =>
      _read('APP_WEBSITE_URL', fallback: 'https://expense-tracker.app');

  static String get privacyUrl =>
      _read('APP_PRIVACY_URL', fallback: 'https://expense-tracker.app/privacy');

  static String get termsUrl =>
      _read('APP_TERMS_URL', fallback: 'https://expense-tracker.app/terms');

  static String get githubUrl => _read(
    'APP_GITHUB_URL',
    fallback: 'https://github.com/expense-tracker/ai-expense-tracker',
  );

  static String get supportEmail =>
      _read('APP_SUPPORT_EMAIL', fallback: 'support@expense-tracker.app');

  static String get supportSubject =>
      _read('APP_SUPPORT_SUBJECT', fallback: 'Expense Tracker Support');

  static Uri? uriFrom(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return Uri.tryParse(trimmed);
  }

  static String _read(String key, {required String fallback}) {
    final value = dotenv.env[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }
}
