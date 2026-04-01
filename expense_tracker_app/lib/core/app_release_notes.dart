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

const Map<String, AppReleaseNotes> _releaseNotesByVersion = {
  '1.0.0': AppReleaseNotes(
    version: '1.0.0',
    title: 'Settings and account polish',
    highlights: [
      'Subscription details are cleaner and match the current Premium offer more closely.',
      'Items translation now supports manual source-language selection when auto-detect is off.',
      'Currency display settings now change symbol position and decimal visibility across supported screens.',
      'About now reads the live app version/build and uses local release notes instead of placeholder copy.',
    ],
  ),
};

AppReleaseNotes releaseNotesForVersion(String version) {
  final normalized = version.trim();
  return _releaseNotesByVersion[normalized] ??
      AppReleaseNotes(
        version: normalized.isEmpty ? 'Current version' : normalized,
        title: 'Current release',
        highlights: const [
          'This build includes the latest account, settings, and display updates for AI Expense Tracker.',
        ],
      );
}

const String appAboutIdentityCopy =
    'AI Expense Tracker helps you scan receipts, review spending, manage categories and labels, and stay on top of budgets and bill reminders in one place.';
