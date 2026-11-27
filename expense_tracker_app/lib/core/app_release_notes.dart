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

AppReleaseNotes? releaseNotesForVersion(BuildContext context, String version) {
  if (version.trim() != '1.1.0') return null;
  return AppReleaseNotes(
    version: '1.1.0',
    title: context.tr('about_release_receipts_and_tools'),
    highlights: [
      context.tr('about_release_receipt_filters'),
      context.tr('about_release_duplicate_review'),
      context.tr('about_release_tools_and_text'),
    ],
  );
}

String appAboutIdentityCopy(BuildContext context) {
  return context.tr('app_about_identity_copy');
}
