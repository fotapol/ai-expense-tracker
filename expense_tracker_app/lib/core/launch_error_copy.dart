import 'auth_session.dart';

String friendlyLaunchErrorMessage(Object error, {required String fallback}) {
  final raw = error.toString().trim();
  if (raw.isEmpty) return fallback;

  if (isExpiredSessionError(error)) {
    return 'Your session expired. Please sign in again.';
  }

  final normalized = raw.toLowerCase();

  if (normalized.contains('socketexception') ||
      normalized.contains('failed host lookup') ||
      normalized.contains('network is unreachable') ||
      normalized.contains(
        'connection closed before full header was received',
      ) ||
      normalized.contains('offline')) {
    return 'You appear to be offline. Please check your connection and try again.';
  }

  if (normalized.contains('timed out') || normalized.contains('timeout')) {
    return 'This is taking longer than expected. Please try again.';
  }

  if (normalized.contains(' 403') || normalized.contains(': 403')) {
    return 'This screen is unavailable right now. Please refresh and try again.';
  }

  if (normalized.contains(' 404') || normalized.contains(': 404')) {
    return 'We could not find the latest data anymore. Please refresh and try again.';
  }

  if (normalized.contains('unsupported receipt file type') ||
      normalized.contains('selected receipt file is empty') ||
      normalized.contains('receipt files larger than')) {
    return raw;
  }

  if (normalized.contains('one or more categories are invalid') ||
      normalized.contains('category') && normalized.contains('invalid')) {
    return 'Please choose valid categories before saving your changes.';
  }

  if (normalized.contains(
    'purchase completed, but premium access was not confirmed',
  )) {
    return 'Your purchase is still syncing. Please restore purchases or refresh in a moment.';
  }

  if (normalized.contains('purchase canceled')) {
    return 'Purchase canceled.';
  }

  if (normalized.contains('operationalreadyinprogresserror')) {
    return 'Another billing action is already in progress. Please wait a few seconds and try again.';
  }

  if (normalized.contains(
        'receipt processing finished, but no transaction was returned',
      ) ||
      normalized.contains('extraction failed') ||
      normalized.contains('receipt could not be found')) {
    return 'We could not finish reading this receipt. Please try another photo or review it again.';
  }

  return fallback;
}
