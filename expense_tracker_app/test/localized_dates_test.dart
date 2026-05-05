import 'package:expense_tracker_app/core/localized_dates.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('localized month helper returns Russian full month names', () {
    final l10n = AppLocalizations(const Locale('ru'));

    expect(localizedMonthName(l10n, DateTime.april), 'Апрель');
  });

  test('localized month helper returns English short month names', () {
    final l10n = AppLocalizations(const Locale('en'));

    expect(localizedMonthName(l10n, DateTime.april, abbreviated: true), 'Apr');
  });
}
