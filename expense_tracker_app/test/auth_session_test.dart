import 'dart:async';
import 'dart:io';

import 'package:expense_tracker_app/core/auth_session.dart';
import 'package:expense_tracker_app/core/session_invalidation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Auth session unit tests.
///
/// These tests exercise the pure-Dart logic in auth_session.dart and
/// session_invalidation.dart without requiring Firebase or Google Sign-In.
///
/// Tests that require a live FirebaseAuth instance (e.g. actual token refresh)
/// are exercised in the manual QA checklist in docs/auth_firebase_results.md.
void main() {
  // ---------------------------------------------------------------------------
  // isExpiredSessionMessage — precision checks after tightening the patterns
  // ---------------------------------------------------------------------------
  group('isExpiredSessionMessage precision', () {
    test('matches internal sentinel "session expired"', () {
      expect(isExpiredSessionMessage('Your session expired.'), isTrue);
      expect(isExpiredSessionMessage('SESSION EXPIRED'), isTrue);
    });

    test('matches "no authenticated user"', () {
      expect(isExpiredSessionMessage('StateError: No authenticated user'), isTrue);
    });

    test('matches exact backend 401 detail strings', () {
      // These are the exact strings returned by backend/app/auth/deps.py.
      expect(isExpiredSessionMessage('Token has expired. Please re-authenticate.'), isTrue);
      expect(isExpiredSessionMessage('Token has been revoked. Please re-authenticate.'), isTrue);
      expect(isExpiredSessionMessage('Invalid authentication token.'), isTrue);
      expect(isExpiredSessionMessage('Authentication failed.'), isTrue);
      expect(isExpiredSessionMessage('Token does not contain a valid uid.'), isTrue);
    });

    test('matches ": 401" suffix pattern', () {
      expect(isExpiredSessionMessage('HTTP error: 401'), isTrue);
    });

    test('matches " 401 " embedded pattern', () {
      expect(isExpiredSessionMessage('failed with status 401 unauthorized'), isTrue);
    });

    test('matches " 401" at end of string', () {
      expect(isExpiredSessionMessage('status code 401'), isTrue);
    });

    // --- Previous false positives that should now NOT match ---

    test('does NOT false-positive on a 4010-item response body', () {
      expect(
        isExpiredSessionMessage('returned 4010 items'),
        isFalse,
        reason: 'Contains "4010" which embeds "401" but is not an auth error',
      );
    });

    test('does NOT false-positive on an unrelated 500 body mentioning 401', () {
      // A pathological case: a 500 response body whose text contains "401"
      // in a non-auth context.  With the old " 401" broad match this
      // incorrectly triggered a sign-out.
      expect(
        isExpiredSessionMessage('Internal error: expected 2401 records'),
        isFalse,
      );
    });

    test('does NOT false-positive on network / timeout errors', () {
      expect(isExpiredSessionMessage('SocketException: Failed host lookup'), isFalse);
      expect(isExpiredSessionMessage('TimeoutException: Connection timed out'), isFalse);
      expect(isExpiredSessionMessage('500 Internal Server Error'), isFalse);
      expect(isExpiredSessionMessage('503 Service Unavailable'), isFalse);
    });

    test('returns false for null and blank', () {
      expect(isExpiredSessionMessage(null), isFalse);
      expect(isExpiredSessionMessage(''), isFalse);
      expect(isExpiredSessionMessage('   '), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // isExpiredSessionError — wraps isExpiredSessionMessage
  // ---------------------------------------------------------------------------
  group('isExpiredSessionError', () {
    test('detects StateError with expiry message', () {
      expect(
        isExpiredSessionError(StateError('No authenticated user')),
        isTrue,
      );
    });

    test('does not detect a plain network exception', () {
      expect(
        isExpiredSessionError(const SocketException('Connection refused')),
        isFalse,
      );
    });

    test('does not detect a generic timeout', () {
      expect(
        isExpiredSessionError(TimeoutException('Timed out')),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // shouldForceSessionTokenRefresh
  // ---------------------------------------------------------------------------
  group('shouldForceSessionTokenRefresh', () {
    final now = DateTime.utc(2026, 4, 2, 10, 0);

    test('forces refresh when token expires in less than 5 minutes', () {
      expect(
        shouldForceSessionTokenRefresh(
          DateTime.utc(2026, 4, 2, 10, 4),
          nowProvider: () => now,
        ),
        isTrue,
      );
    });

    test('skips refresh when token expires in more than 5 minutes', () {
      expect(
        shouldForceSessionTokenRefresh(
          DateTime.utc(2026, 4, 2, 10, 10),
          nowProvider: () => now,
        ),
        isFalse,
      );
    });

    test('forces refresh at exactly the 5-minute boundary', () {
      // expirationTime - now == exactly 5 min  →  <= window  →  refresh
      expect(
        shouldForceSessionTokenRefresh(
          DateTime.utc(2026, 4, 2, 10, 5),
          nowProvider: () => now,
        ),
        isTrue,
      );
    });

    test('forces refresh when expirationTime is null', () {
      expect(
        shouldForceSessionTokenRefresh(null, nowProvider: () => now),
        isTrue,
      );
    });

    test('forces refresh when token is already expired', () {
      expect(
        shouldForceSessionTokenRefresh(
          DateTime.utc(2026, 4, 2, 9, 59),
          nowProvider: () => now,
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // requireAuthenticatedSessionToken
  // ---------------------------------------------------------------------------
  group('requireAuthenticatedSessionToken', () {
    test('returns a non-blank token unchanged', () {
      expect(requireAuthenticatedSessionToken('tok-abc-123'), 'tok-abc-123');
    });

    test('throws StateError for null token', () {
      expect(
        () => requireAuthenticatedSessionToken(null),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError for blank token', () {
      expect(
        () => requireAuthenticatedSessionToken('   '),
        throwsA(isA<StateError>()),
      );
    });

    test('throws StateError for empty string', () {
      expect(
        () => requireAuthenticatedSessionToken(''),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Pending login notice (session_invalidation helpers)
  // ---------------------------------------------------------------------------
  group('pendingLoginNotice', () {
    setUp(() {
      // Ensure the notice is clear before each test.
      consumePendingLoginNotice();
    });

    test('stores and consumes a notice once', () {
      primePendingLoginNotice(expiredSessionMessage);
      expect(consumePendingLoginNotice(), expiredSessionMessage);
      expect(consumePendingLoginNotice(), isNull);
    });

    test('uses expiredSessionMessage when primed with a blank string', () {
      primePendingLoginNotice('   ');
      expect(consumePendingLoginNotice(), expiredSessionMessage);
    });

    test('preserves a custom notice message', () {
      const custom = 'Custom session notice for tests.';
      primePendingLoginNotice(custom);
      expect(consumePendingLoginNotice(), custom);
    });

    test('second prime overwrites the first', () {
      primePendingLoginNotice('first');
      primePendingLoginNotice('second');
      expect(consumePendingLoginNotice(), 'second');
    });
  });

  // ---------------------------------------------------------------------------
  // Network-failure non-logout contract
  //
  // These are integration-style contracts expressed as unit tests over the
  // pure helpers.  The actual _getToken / _handleUnauthorizedResponse methods
  // cannot be tested without a Firebase instance, but the pure helper
  // functions they rely on are fully testable.
  // ---------------------------------------------------------------------------
  group('network failure must not trigger logout (contract tests)', () {
    test('SocketException is NOT an expired-session error', () {
      // This is the contract relied on by ApiClient._getToken to decide
      // whether to fall back to the cached token or invalidate the session.
      final err = const SocketException('Failed host lookup');
      expect(isExpiredSessionError(err), isFalse);
    });

    test('TimeoutException is NOT an expired-session error', () {
      final err = TimeoutException('timed out');
      expect(isExpiredSessionError(err), isFalse);
    });

    test('generic Exception with 503 body is NOT an expired-session error', () {
      final err = Exception('Server error: 503 unavailable');
      expect(isExpiredSessionError(err), isFalse);
    });

    test('a real 401 sentinel IS an expired-session error', () {
      // This should still be caught and ultimately lead to invalidation
      // (after the retry path in ApiClient._handleUnauthorizedResponse).
      final err = StateError('Token has expired. Please re-authenticate.');
      expect(isExpiredSessionError(err), isTrue);
    });
  });
}
