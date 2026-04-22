import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planning strings are localized for supported non-English locales', () {
    final english = AppLocalizations(const Locale('en'));
    final german = AppLocalizations(const Locale('de'));

    expect(english.tr('budget_saved'), 'Budget updated.');
    expect(german.tr('budget_saved'), isNot(english.tr('budget_saved')));
    expect(
      german.tr('bill_reminders_mark_paid'),
      isNot(english.tr('bill_reminders_mark_paid')),
    );
  });
}
