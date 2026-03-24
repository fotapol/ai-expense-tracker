import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'planning strings fall back to English for locales without overrides',
    () {
      final english = AppLocalizations(const Locale('en'));
      final german = AppLocalizations(const Locale('de'));

      expect(english.tr('budget_saved'), 'Budget updated.');
      expect(german.tr('budget_saved'), 'Budget updated.');
      expect(german.tr('bill_reminders_mark_paid'), 'Mark as Paid');
    },
  );
}
