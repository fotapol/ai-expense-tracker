import 'dart:io';
import 'dart:async';

import 'package:expense_tracker_app/core/auth_session.dart';
import 'package:expense_tracker_app/core/core_request_timeout.dart';
import 'package:expense_tracker_app/core/premium_refresh.dart';
import 'package:expense_tracker_app/core/receipt_upload_flow.dart';
import 'package:expense_tracker_app/core/session_invalidation.dart';
import 'package:expense_tracker_app/core/single_user_launch.dart';
import 'package:expense_tracker_app/core/subscription_confirmation.dart';
import 'package:expense_tracker_app/l10n/app_localizations.dart';
import 'package:expense_tracker_app/screens/tools_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('auth session launch guards', () {
    test(
      'rejects missing or blank bearer tokens with a clean auth failure',
      () {
        expect(
          () => requireAuthenticatedSessionToken('   '),
          throwsA(isA<StateError>()),
        );
        expect(requireAuthenticatedSessionToken('token-123'), 'token-123');
      },
    );

    test('refreshes tokens before they are effectively expired', () {
      final now = DateTime.utc(2026, 3, 31, 10, 0);

      expect(
        shouldForceSessionTokenRefresh(
          DateTime.utc(2026, 3, 31, 10, 4),
          nowProvider: () => now,
        ),
        isTrue,
      );
      expect(
        shouldForceSessionTokenRefresh(
          DateTime.utc(2026, 3, 31, 10, 20),
          nowProvider: () => now,
        ),
        isFalse,
      );
    });

    test('detects expired-session style errors', () {
      expect(isExpiredSessionError(Exception('request failed: 401')), isTrue);
      expect(isExpiredSessionError(Exception('network timeout')), isFalse);
    });

    test('stores a one-time login notice for expired sessions', () {
      primePendingLoginNotice(expiredSessionMessage);

      expect(consumePendingLoginNotice(), expiredSessionMessage);
      expect(consumePendingLoginNotice(), isNull);
    });

    testWidgets('session restore gate reacts to auth changes', (tester) async {
      final streamController = StreamController<String?>(sync: true);
      addTearDown(streamController.close);

      await tester.pumpWidget(
        MaterialApp(
          home: SessionRestoreGate<String>(
            stream: streamController.stream,
            initialValue: null,
            isAuthenticated: (user) => user != null,
            loadingBuilder: (_) => const Text('loading'),
            unauthenticatedBuilder: (_) => const Text('login'),
            authenticatedBuilder: (_) => const Text('main'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('loading'), findsOneWidget);

      streamController.add(null);
      await tester.pump();
      expect(find.text('login'), findsOneWidget);

      streamController.add('user-1');
      await tester.pump();
      expect(find.text('main'), findsOneWidget);

      streamController.add(null);
      await tester.pump();
      expect(find.text('login'), findsOneWidget);
    });

    testWidgets('session restore gate honors a restored initial user', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionRestoreGate<String>(
            stream: const Stream<String?>.empty(),
            initialValue: 'restored-user',
            isAuthenticated: (user) => user != null,
            unauthenticatedBuilder: (_) => const Text('login'),
            authenticatedBuilder: (_) => const Text('main'),
          ),
        ),
      );

      expect(find.text('main'), findsOneWidget);
    });

  });

  group('core request timeout', () {
    test('returns the completed result', () async {
      final result = await runWithCoreRequestTimeout(
        Future<String>.value('ok'),
        operationName: 'Save transaction',
      );

      expect(result, 'ok');
    });

    test('throws a timeout for slow launch-critical requests', () async {
      await expectLater(
        runWithCoreRequestTimeout(
          Future<String>.delayed(
            const Duration(milliseconds: 50),
            () => 'late',
          ),
          operationName: 'Upload receipt',
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('receipt polling launch guards', () {
    test('fails completed receipts that are missing a transaction id', () {
      final decision = interpretReceiptPollingPayload(
        const {'status': 'COMPLETED'},
        missingTransactionMessage: 'Missing transaction',
        extractionFailedFallback: 'Extraction failed',
      );

      expect(decision.action, ReceiptPollingAction.failed);
      expect(decision.errorMessage, 'Missing transaction');
    });

    test('surfaces explicit extraction failures', () {
      final decision = interpretReceiptPollingPayload(
        const {
          'status': 'FAILED',
          'failure_reason': 'OCR could not parse this receipt.',
        },
        missingTransactionMessage: 'Missing transaction',
        extractionFailedFallback: 'Extraction failed',
      );

      expect(decision.action, ReceiptPollingAction.failed);
      expect(decision.errorMessage, 'OCR could not parse this receipt.');
    });

    test('treats non-terminal states as pending', () {
      final decision = interpretReceiptPollingPayload(
        const {'status': 'PROCESSING'},
        missingTransactionMessage: 'Missing transaction',
        extractionFailedFallback: 'Extraction failed',
      );

      expect(decision.action, ReceiptPollingAction.pending);
      expect(decision.transactionId, isNull);
      expect(decision.errorMessage, isNull);
    });

    test('maps permanent receipt polling errors to user-facing messages', () {
      expect(
        permanentReceiptPollingErrorMessage(Exception('HTTP 404 not found')),
        'This receipt could not be found anymore. Please upload it again.',
      );
      expect(
        permanentReceiptPollingErrorMessage(
          StateError('No authenticated user'),
        ),
        'Your session expired. Please sign in again.',
      );
      expect(
        permanentReceiptPollingErrorMessage(Exception('HTTP 500 timeout')),
        isNull,
      );
    });
  });

  group('receipt upload hardening', () {
    test('rejects unsupported and oversized receipt files before upload', () {
      final prepared = prepareReceiptUpload(
        filename: 'receipt.png',
        fileSizeBytes: 1024,
      );

      expect(prepared.mimeType, 'image/png');
      expect(
        () => prepareReceiptUpload(filename: 'receipt.txt', fileSizeBytes: 10),
        throwsA(isA<ReceiptUploadValidationException>()),
      );
      expect(
        () => prepareReceiptUpload(
          filename: 'receipt.jpg',
          fileSizeBytes: maxReceiptUploadBytes + 1,
        ),
        throwsA(isA<ReceiptUploadValidationException>()),
      );
    });

    test(
      'maps timeout and offline upload failures to retry-friendly messages',
      () {
        expect(
          formatReceiptUploadError(TimeoutException('too slow')),
          contains('timed out'),
        );
        expect(
          formatReceiptUploadError(const SocketException('offline')),
          contains('offline'),
        );
      },
    );

    test(
      'prevents duplicate upload starts while a launch upload is in flight',
      () {
        expect(
          canStartReceiptUpload(hasPickedFile: true, status: 'idle'),
          isTrue,
        );
        expect(
          canStartReceiptUpload(hasPickedFile: true, status: 'uploading'),
          isFalse,
        );
        expect(
          canStartReceiptUpload(hasPickedFile: true, status: 'processing'),
          isFalse,
        );
      },
    );
  });

  group('single-user launch package filtering', () {
    test('removes family offerings from subscription choices', () {
      final filtered = filterSingleUserLaunchPackages([
        'personal_monthly',
        'family_monthly',
        'personal_yearly',
      ], isFamilyPackage: (package) => package.contains('family'));

      expect(filtered, ['personal_monthly', 'personal_yearly']);
    });
  });

  group('subscription confirmation guards', () {
    test('accepts premium feature codes from backend sync as confirmation', () {
      expect(
        syncPayloadConfirmsPremiumAccess(const {
          'has_active_subscription': false,
          'feature_codes': ['premium.receipt_scans.unlimited'],
        }, expectsFamilyPlan: false),
        isTrue,
      );
    });

    test('accepts active subscription ids from RevenueCat customer info', () {
      expect(
        customerInfoConfirmsPremiumAccess(
          hasPremiumEntitlement: false,
          activeSubscriptions: const ['individual_plan_monthly'],
          acceptedProductIds: const ['individual_plan_monthly', '\$rc_monthly'],
        ),
        isTrue,
      );
    });

    test('prefers active entitlement expiration over latest expiration', () {
      expect(
        resolvePremiumAccessExpiration(
          latestExpirationDate: '2099-05-01T00:00:00Z',
          activeEntitlementExpirationDates: const [
            null,
            '2099-04-01T00:00:00Z',
          ],
        ),
        '2099-04-01T00:00:00Z',
      );
    });
  });

  group('premium freshness on resume', () {
    test('refreshes once on resume and throttles repeated refreshes', () async {
      var now = DateTime.utc(2026, 3, 27, 9);
      final controller = PremiumRefreshController(
        minimumRefreshInterval: const Duration(minutes: 5),
        nowProvider: () => now,
      );
      var calls = 0;

      await controller.refreshOnResume(
        isSignedIn: true,
        isBillingAvailable: true,
        refreshAction: () async {
          calls += 1;
        },
      );
      await controller.refreshOnResume(
        isSignedIn: true,
        isBillingAvailable: true,
        refreshAction: () async {
          calls += 1;
        },
      );

      now = now.add(const Duration(minutes: 6));
      await controller.refreshOnResume(
        isSignedIn: true,
        isBillingAvailable: true,
        refreshAction: () async {
          calls += 1;
        },
      );

      expect(calls, 2);
    });

    test('skips resume refresh when the user is signed out', () async {
      final controller = PremiumRefreshController();
      var calls = 0;

      await controller.refreshOnResume(
        isSignedIn: false,
        isBillingAvailable: true,
        refreshAction: () async {
          calls += 1;
        },
      );

      expect(calls, 0);
    });
  });

  testWidgets('tools screen hides import and export tools for launch', (
    tester,
  ) async {
    final l10n = AppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ToolsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.tr('tools_data')), findsNothing);
    expect(find.text(l10n.tr('tools_export_data')), findsNothing);
    expect(find.text(l10n.tr('tools_import_data')), findsNothing);
  });
}
