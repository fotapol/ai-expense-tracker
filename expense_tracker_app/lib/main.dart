import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'core/api_client.dart';
import 'core/auth_session.dart';
import 'core/bill_reminder_notification_service.dart';
// TODO(household): re-import invite_link_service when household feature ships
// import 'core/invite_link_service.dart';
import 'core/locale_provider.dart';
import 'core/premium_refresh.dart';
import 'core/revenuecat_service.dart';
import 'core/theme_provider.dart';
import 'l10n/app_localizations.dart';
// TODO(household): re-import household_invite_accept_screen when household feature ships
// import 'screens/household_invite_accept_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

final themeProvider = ThemeProvider();
final localeProvider = LocaleProvider();
final appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleSignIn.instance.initialize();
  await RevenueCatService.logInCurrentUser();
  // TODO(household): restore invite link initialization when household feature ships
  // await InviteLinkService.instance.initialize();
  await BillReminderNotificationService.instance.initialize();
  await localeProvider.load();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // TODO(household): restore _inviteRouteOpen when household feature ships
  // bool _inviteRouteOpen = false;
  StreamSubscription<User?>? _authSubscription;
  final PremiumRefreshController _premiumRefreshController =
      PremiumRefreshController();

  void _refreshApp() {
    if (mounted) setState(() {});
  }

  // TODO(household): restore _onInviteUpdated and _maybeOpenInviteAcceptance 
  // when household feature ships
  /*
  void _onInviteUpdated() {
    if (mounted) setState(() {});
    _maybeOpenInviteAcceptance();
  }

  void _maybeOpenInviteAcceptance() {
    final token = InviteLinkService.instance.pendingInviteToken;
    final user = FirebaseAuth.instance.currentUser;
    if (token == null || token.isEmpty || user == null || _inviteRouteOpen) {
      return;
    }

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    _inviteRouteOpen = true;
    navigator
        .push(
          MaterialPageRoute(
            builder: (_) => HouseholdInviteAcceptScreen(
              inviteToken: token,
              launchedFromLink: true,
            ),
          ),
        )
        .whenComplete(() {
          _inviteRouteOpen = false;
          Future<void>.microtask(() async => _maybeOpenInviteAcceptance());
        });
  }
  */

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeProvider.addListener(_refreshApp);
    localeProvider.addListener(_refreshApp);
    
    // TODO(household): restore invite listener when household feature ships
    // InviteLinkService.instance.addListener(_onInviteUpdated);
    
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      BillReminderNotificationService.instance.handleAuthStateChanged(
        FirebaseAuth.instance.currentUser,
      );
      // TODO(household): restore _maybeOpenInviteAcceptance() when household feature ships
      // _maybeOpenInviteAcceptance();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      BillReminderNotificationService.instance.handleAuthStateChanged(
        FirebaseAuth.instance.currentUser,
      );
      // TODO(household): restore _maybeOpenInviteAcceptance() when household feature ships
      // _maybeOpenInviteAcceptance();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    BillReminderNotificationService.instance.syncScheduledNotifications();
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
    
    // TODO(household): restore _maybeOpenInviteAcceptance() when household feature ships
    // _maybeOpenInviteAcceptance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeProvider.removeListener(_refreshApp);
    localeProvider.removeListener(_refreshApp);
    
    // TODO(household): restore invite listener when household feature ships
    // InviteLinkService.instance.removeListener(_onInviteUpdated);
    
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
        stream: FirebaseAuth.instance.authStateChanges(),
        initialValue: FirebaseAuth.instance.currentUser,
        isAuthenticated: (user) => user != null,
        unauthenticatedBuilder: (_) => const LoginScreen(),
        authenticatedBuilder: (_) => const MainScreen(),
      ),
    );
  }
}
