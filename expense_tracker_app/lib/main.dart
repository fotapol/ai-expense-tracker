import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'core/invite_link_service.dart';
import 'core/locale_provider.dart';
import 'core/revenuecat_service.dart';
import 'core/theme_provider.dart';
import 'l10n/app_localizations.dart';
import 'screens/household_invite_accept_screen.dart';
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
  await InviteLinkService.instance.initialize();
  await localeProvider.load();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _inviteRouteOpen = false;
  StreamSubscription<User?>? _authSubscription;

  void _refreshApp() {
    if (mounted) setState(() {});
  }

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

  @override
  void initState() {
    super.initState();
    themeProvider.addListener(_refreshApp);
    localeProvider.addListener(_refreshApp);
    InviteLinkService.instance.addListener(_onInviteUpdated);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      _maybeOpenInviteAcceptance();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenInviteAcceptance();
    });
  }

  @override
  void dispose() {
    themeProvider.removeListener(_refreshApp);
    localeProvider.removeListener(_refreshApp);
    InviteLinkService.instance.removeListener(_onInviteUpdated);
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
      home: FirebaseAuth.instance.currentUser == null
          ? const LoginScreen()
          : const MainScreen(),
    );
  }
}
