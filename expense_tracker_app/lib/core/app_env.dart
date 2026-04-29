import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  AppEnv._();

  static const String _websiteUrlDefine = String.fromEnvironment(
    'APP_WEBSITE_URL',
  );
  static const String _privacyUrlDefine = String.fromEnvironment(
    'APP_PRIVACY_URL',
  );
  static const String _termsUrlDefine = String.fromEnvironment('APP_TERMS_URL');
  static const String _supportEmailDefine = String.fromEnvironment(
    'APP_SUPPORT_EMAIL',
  );
  static const String _supportSubjectDefine = String.fromEnvironment(
    'APP_SUPPORT_SUBJECT',
  );

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env', isOptional: true);
    } catch (_) {
      // Keep launch-safe fallbacks if the asset is missing in local builds.
    }
  }

  static String get websiteUrl => _read(
    'APP_WEBSITE_URL',
    defineValue: _websiteUrlDefine,
    fallback: 'https://nexavend.store',
  );

  static String get privacyUrl => _read(
    'APP_PRIVACY_URL',
    defineValue: _privacyUrlDefine,
    fallback: 'https://nexavend.store/privacy',
  );

  static String get termsUrl => _read(
    'APP_TERMS_URL',
    defineValue: _termsUrlDefine,
    fallback: 'https://nexavend.store/terms',
  );

  static String get githubUrl => _read(
    'APP_GITHUB_URL',
    fallback: 'https://github.com/expense-tracker/ai-expense-tracker',
  );

  static String get supportEmail => _read(
    'APP_SUPPORT_EMAIL',
    defineValue: _supportEmailDefine,
    fallback: 'support@nexavend.store',
  );

  static String get supportSubject => _read(
    'APP_SUPPORT_SUBJECT',
    defineValue: _supportSubjectDefine,
    fallback: 'Expense Tracker Support',
  );

  static Uri? uriFrom(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return Uri.tryParse(trimmed);
  }

  static String _read(
    String key, {
    String defineValue = '',
    required String fallback,
  }) {
    final compiled = defineValue.trim();
    if (compiled.isNotEmpty) {
      return compiled;
    }
    if (!dotenv.isInitialized) {
      return fallback;
    }
    final value = dotenv.env[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }
}
