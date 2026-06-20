import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'core/app_env.dart';
import 'core/app_navigation.dart';
import 'core/api_client.dart';
import 'core/auth_session.dart';
import 'core/bill_reminder_notification_service.dart';
import 'core/item_translation_preferences.dart';
import 'core/money_format_preferences.dart';
import 'core/locale_provider.dart';
import 'core/premium_refresh.dart';
import 'core/revenuecat_service.dart';
import 'core/theme_provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

final themeProvider = ThemeProvider();
final localeProvider = LocaleProvider();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppEnv.load();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleSignIn.instance.initialize();
  await RevenueCatService.logInCurrentUser();
  await BillReminderNotificationService.instance.initialize();
  await themeProvider.load();
  await moneyFormatSettings.load();
  await itemTranslationPreferences.load();
  await localeProvider.load();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSubscription;
  final PremiumRefreshController _premiumRefreshController =
      PremiumRefreshController();

  void _refreshApp() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeProvider.addListener(_refreshApp);
    moneyFormatSettings.addListener(_refreshApp);
    itemTranslationPreferences.addListener(_refreshApp);
    localeProvider.addListener(_refreshApp);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      BillReminderNotificationService.instance.handleAuthStateChanged(
        FirebaseAuth.instance.currentUser,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BillReminderNotificationService.instance.handleAuthStateChanged(
        FirebaseAuth.instance.currentUser,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    BillReminderNotificationService.instance.syncScheduledNotifications();

    // Pre-warm the Firebase ID token when the app comes back to the
    // foreground.  If the token is within the expiry refresh window (5 min)
    // this forces a silent refresh so the first API call after resume does
    // not bear the refresh latency.  Errors are intentionally swallowed
    // because this is best-effort; the regular _getToken path will retry.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Best-effort token pre-warm. Any error is intentionally swallowed.
      unawaited(() async {
        try {
          final result = await user.getIdTokenResult();
          if (shouldForceSessionTokenRefresh(result.expirationTime)) {
            await user.getIdToken(true);
          }
        } catch (_) {}
      }());
    }

    unawaited(
      _premiumRefreshController.refreshOnResume(
        isSignedIn: FirebaseAuth.instance.currentUser != null,
        isBillingAvailable: RevenueCatService.isAvailable,
        refreshAction: () async {
          await RevenueCatService.logInCurrentUser();
          await ApiClient.syncRevenueCatSubscription();
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeProvider.removeListener(_refreshApp);
    moneyFormatSettings.removeListener(_refreshApp);
    itemTranslationPreferences.removeListener(_refreshApp);
    localeProvider.removeListener(_refreshApp);

    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      onGenerateTitle: (context) => context.tr('app_title'),
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.themeMode,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(themeProvider.fontSizeFactor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      locale: localeProvider.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SessionRestoreGate<User>(
        // idTokenChanges() is a superset of authStateChanges():
        // it also fires when the token is silently refreshed or revoked,
        // giving the gate a chance to react to real session changes in
        // real time without waiting for an explicit sign-out event.
        stream: FirebaseAuth.instance.idTokenChanges(),
        initialValue: FirebaseAuth.instance.currentUser,
        isAuthenticated: (user) => user != null,
        loadingBuilder: (_) => const SessionRestoreLoadingScreen(),
        unauthenticatedBuilder: (_) => const LoginScreen(),
        authenticatedBuilder: (_) => const MainScreen(),
      ),
    );
  }
}
