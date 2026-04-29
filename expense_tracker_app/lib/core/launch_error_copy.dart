import 'auth_session.dart';
import '../l10n/app_localizations.dart';

String friendlyLaunchErrorMessage(
  Object error, {
  required String fallback,
  String languageCode = 'en',
}) {
  final raw = error.toString().trim();
  if (raw.isEmpty) return fallback;

  if (isExpiredSessionError(error)) {
    return AppLocalizations.lookup(
      'error_session_expired',
      languageCode: languageCode,
    );
  }

  final normalized = raw.toLowerCase();

  if (normalized.contains('socketexception') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('network is unreachable') ||
      normalized.contains(
        'connection closed before full header was received',
      ) ||
      normalized.contains('offline')) {
    return AppLocalizations.lookup(
      'error_network_offline',
      languageCode: languageCode,
    );
  }

  if (normalized.contains('timed out') || normalized.contains('timeout')) {
    return AppLocalizations.lookup('error_timeout', languageCode: languageCode);
  }

  if (normalized.contains(' 403') || normalized.contains(': 403')) {
    return AppLocalizations.lookup(
      'error_forbidden',
      languageCode: languageCode,
    );
  }

  if (normalized.contains(' 404') || normalized.contains(': 404')) {
    return AppLocalizations.lookup(
      'error_not_found',
      languageCode: languageCode,
    );
  }

  if (normalized.contains('unsupported receipt file type') ||
      normalized.contains('selected receipt file is empty') ||
      normalized.contains('receipt files larger than')) {
    return raw;
  }

  if (normalized.contains('one or more categories are invalid') ||
      normalized.contains('category') && normalized.contains('invalid')) {
    return AppLocalizations.lookup(
      'error_invalid_categories',
      languageCode: languageCode,
    );
  }

  if (normalized.contains(
    'purchase completed, but premium access was not confirmed',
  )) {
    return AppLocalizations.lookup(
      'error_purchase_syncing',
      languageCode: languageCode,
    );
  }

  if (normalized.contains('purchase canceled')) {
    return AppLocalizations.lookup(
      'error_purchase_canceled',
      languageCode: languageCode,
    );
  }

  if (normalized.contains('operationalreadyinprogresserror')) {
    return AppLocalizations.lookup(
      'error_purchase_in_progress',
      languageCode: languageCode,
    );
  }

  if (normalized.contains(
        'receipt processing finished, but no transaction was returned',
      ) ||
      normalized.contains('extraction failed') ||
      normalized.contains('receipt could not be found')) {
    return AppLocalizations.lookup(
      'error_receipt_extraction_failed',
      languageCode: languageCode,
    );
  }

  return fallback;
}
