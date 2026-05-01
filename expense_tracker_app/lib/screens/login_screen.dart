import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_env.dart';
import '../core/launch_error_copy.dart';
import '../core/redesign_system.dart';
import '../core/revenuecat_service.dart';
import '../core/session_invalidation.dart';
import '../l10n/app_localizations.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  String? _sessionNotice;

  @override
  void initState() {
    super.initState();
    _sessionNotice = consumePendingLoginNotice();
  }

  String _friendlyLoginError(Object error) {
    return friendlyLaunchErrorMessage(
      error,
      fallback: context.tr('login_error_fallback'),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _sessionNotice = null;
    });

    try {
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();
      final String? googleIdToken = googleUser.authentication.idToken;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleIdToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      await RevenueCatService.logInCurrentUser();

      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('Google Sign-In canceled by user.');
      } else if (mounted) {
        setState(() {
          _errorMessage = _friendlyLoginError(e.description ?? e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyLoginError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = AppEnv.uriFrom(rawUrl);
    var opened = false;
    try {
      opened =
          uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('could_not_open_that_link'))),
      );
    }
  }

  void _openTerms() {
    unawaited(_openExternalUrl(AppEnv.termsUrl));
  }

  void _openPrivacy() {
    unawaited(_openExternalUrl(AppEnv.privacyUrl));
  }

  @override
  Widget build(BuildContext context) {
    final compactHeight = MediaQuery.sizeOf(context).height < 690;
    final bottomSafePadding = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: ShellStyles.background(context),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      compactHeight ? 28 : 64,
                      20,
                      bottomSafePadding + 24,
                    ),
                    child: Column(
                      children: [
                        SizedBox(height: compactHeight ? 8 : 80),
                        const _BrandLockup(),
                        SizedBox(height: compactHeight ? 24 : 32),
                        _SignInCard(
                          isLoading: _isLoading,
                          onSignIn: _isLoading ? null : _signInWithGoogle,
                        ),
                        if (_sessionNotice != null) ...[
                          const SizedBox(height: 14),
                          _LoginMessageCard(
                            icon: Icons.info_outline,
                            message: _sessionNotice!,
                            tone: _LoginMessageTone.info,
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          _LoginMessageCard(
                            icon: Icons.error_outline,
                            message: _errorMessage!,
                            tone: _LoginMessageTone.error,
                          ),
                        ],
                        const Spacer(),
                        SizedBox(height: compactHeight ? 42 : 88),
                        _LegalFooter(
                          onOpenTerms: _openTerms,
                          onOpenPrivacy: _openPrivacy,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    final logoAsset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/brand/logo-login-white.png'
        : 'assets/brand/logo-login-black.png';

    return Column(
      children: [
        Image.asset(
          logoAsset,
          width: 176,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, _, _) => const _TextBrandLogo(),
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Text(
            context.tr('login_subtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ShellStyles.textSecondary(context),
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _TextBrandLogo extends StatelessWidget {
  const _TextBrandLogo();

  @override
  Widget build(BuildContext context) {
    final accentTone = ShellStyles.accentTone(context);
    final logoColor = ShellStyles.textPrimary(context);
    final dollarColor = Color.lerp(
      ShellStyles.warningPremium(context),
      accentTone.base,
      ShellStyles.isDark(context) ? 0.22 : 0.34,
    )!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'AI',
          style: TextStyle(
            color: logoColor,
            fontSize: 42,
            height: 0.95,
            letterSpacing: -2.7,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          r'$',
          style: TextStyle(
            color: dollarColor,
            fontSize: 45,
            height: 0.95,
            letterSpacing: -2.4,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          'expense\ntracker',
          style: TextStyle(
            color: logoColor,
            fontSize: 19,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/auth/google_g.png',
      width: 19,
      height: 19,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => Text(
        'G',
        style: TextStyle(
          color: const Color(0xFF4285F4),
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
      ),
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({required this.isLoading, required this.onSignIn});

  final bool isLoading;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 338),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: ShellStyles.cardDecoration(
          context,
          radius: 10,
          color: ShellStyles.sectionBackground(context),
        ),
        child: Column(
          children: [
            // Text(
            //   // 'Get started',
            //   style: TextStyle(
            //     color: ShellStyles.textPrimary(context),
            //     fontSize: 16,
            //     fontWeight: FontWeight.w800,
            //     letterSpacing: -0.1,
            //   ),
            // ),
            const SizedBox(height: 12),
            _GoogleSignInButton(isLoading: isLoading, onPressed: onSignIn),
            const SizedBox(height: 18),
            _LoginBenefit(text: context.tr('login_benefit_1')),
            _LoginBenefit(text: context.tr('login_benefit_2')),
            _LoginBenefit(text: context.tr('login_benefit_3')),
          ],
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = ShellStyles.textPrimary(context);

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: ShellStyles.standardSurface(context),
          foregroundColor: foreground,
          disabledBackgroundColor: ShellStyles.inputSurface(context),
          disabledForegroundColor: ShellStyles.textDisabled(context),
          side: BorderSide(color: ShellStyles.border(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isLoading
              ? SizedBox(
                  key: const ValueKey('login-spinner'),
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: ShellStyles.accent(context),
                  ),
                )
              : Row(
                  key: const ValueKey('login-google-label'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _GoogleLogo(),
                    const SizedBox(width: 12),
                    Text(context.tr('login_continue_google')),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LoginBenefit extends StatelessWidget {
  const _LoginBenefit({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: ShellStyles.textMuted(context),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: ShellStyles.textSecondary(context),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LoginMessageTone { info, error }

class _LoginMessageCard extends StatelessWidget {
  const _LoginMessageCard({
    required this.icon,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String message;
  final _LoginMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final toneColor = tone == _LoginMessageTone.error
        ? ShellStyles.error(context)
        : ShellStyles.info(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 338),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: toneColor.withAlpha(ShellStyles.isDark(context) ? 32 : 18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: toneColor.withAlpha(70)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: toneColor, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: ShellStyles.textPrimary(context),
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter({required this.onOpenTerms, required this.onOpenPrivacy});

  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final muted = ShellStyles.textSecondary(context);
    final linkColor = ShellStyles.textPrimary(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 338),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            context.tr('login_legal_prefix'),
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12.5, height: 1.35),
          ),
          _LegalLink(
            label: context.tr('settings_terms_of_service'),
            color: linkColor,
            onTap: onOpenTerms,
          ),
          Text(
            context.tr('login_legal_and'),
            style: TextStyle(color: muted, fontSize: 12.5, height: 1.35),
          ),
          _LegalLink(
            label: context.tr('settings_privacy_policy'),
            color: linkColor,
            onTap: onOpenPrivacy,
          ),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            height: 1.35,
            decoration: TextDecoration.underline,
            decorationColor: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
