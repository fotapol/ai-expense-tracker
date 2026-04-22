import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

class AppReleaseNotes {
  const AppReleaseNotes({
    required this.version,
    required this.title,
    required this.highlights,
  });

  final String version;
  final String title;
  final List<String> highlights;
}

Map<String, AppReleaseNotes> _releaseNotesByVersion(BuildContext context) => {
  '1.0.0': AppReleaseNotes(
    version: '1.0.0',
    title: context.tr('settings_and_account_polish'),
    highlights: const [
      'Subscription details are cleaner and match the current Premium offer more closely.',
      'Items translation now supports manual source-language selection when auto-detect is off.',
      'Currency display settings now change symbol position and decimal visibility across supported screens.',
      'About now shows clearer app information and local release notes instead of placeholder copy.',
    ],
  ),
};

AppReleaseNotes releaseNotesForVersion(BuildContext context, String version) {
  final normalized = version.trim();
  return _releaseNotesByVersion(context)[normalized] ??
      AppReleaseNotes(
        version: normalized.isEmpty ? 'Current version' : normalized,
        title: context.tr('current_release'),
        highlights: const [
          'This build includes the latest account, settings, and display updates for AI Expense Tracker.',
        ],
      );
}

const String appAboutIdentityCopy =
    context.tr('app_about_identity_copy');
