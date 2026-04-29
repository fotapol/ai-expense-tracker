import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localization coverage', () {
    test('every supported locale resolves core runtime keys', () {
      const keys = <String>[
        'app_title',
        'common_cancel',
        'common_delete',
        'common_retry',
        'common_error',
        'common_yes',
        'common_no',
        'common_filter',
        'common_clear_filters',
        'nav_home',
        'nav_receipts',
        'nav_tools',
        'nav_settings',
        'settings_title',
        'settings_language',
        'home_greeting_morning',
        'home_start_subtitle',
        'receipts_filter_needs_review',
        'receipts_history_total',
        'transaction_review_receipt',
        'transaction_receipt_photo_title',
      ];

      for (final locale in AppLocalizations.supportedLocales) {
        final localizations = AppLocalizations(locale);
        for (final key in keys) {
          expect(
            localizations.tr(key),
            isNot(key),
            reason:
                '${locale.languageCode} should provide a visible translation '
                'for $key.',
          );
        }
      }
    });

    test(
      'supported non-English locales do not fall back to English for critical screens',
      () {
        const keys = <String>[
          'home_start_subtitle',
          'home_review_count_plural',
          'home_smart_insights',
          'receipts_empty_body',
          'receipts_no_filter_matches',
          'receipts_history_load_error',
          'transaction_unsaved_changes_title',
          'transaction_unsaved_changes_body',
          'transaction_receipt_photo_title',
          'transaction_receipt_photo_subtitle',
          'transaction_warning_accepts_edits',
          'transaction_open_receipt_error',
        ];

        final english = AppLocalizations(const Locale('en'));
        final localizedLocales = AppLocalizations.supportedLocales.where(
          (locale) => locale.languageCode != 'en',
        );
        for (final locale in localizedLocales) {
          final localizations = AppLocalizations(locale);
          for (final key in keys) {
            expect(
              localizations.tr(key),
              isNot(english.tr(key)),
              reason:
                  '${locale.languageCode} should not fall back to English '
                  'for $key.',
            );
          }
        }
      },
    );

    test('lookup resolves service keys for every supported locale', () {
      const keys = <String>[
        'bill_due_soon',
        'bill_due_today',
        'error_session_expired',
        'error_network_offline',
        'error_timeout',
        'error_forbidden',
        'error_not_found',
        'error_invalid_categories',
        'error_purchase_syncing',
        'error_purchase_canceled',
        'error_purchase_in_progress',
        'error_receipt_extraction_failed',
      ];

      for (final locale in AppLocalizations.supportedLocales) {
        for (final key in keys) {
          expect(
            AppLocalizations.lookup(key, languageCode: locale.languageCode),
            isNot(key),
            reason:
                '${locale.languageCode} should provide a service translation '
                'for $key.',
          );
        }
      }
    });
  });
}
