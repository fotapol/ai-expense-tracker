import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/revenuecat_service.dart';
import '../l10n/app_localizations.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('Google Sign-In canceled by user.');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'login_google_error',
                params: {'error': e.description ?? 'Unknown'},
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('login_failed', params: {'error': e.toString()}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12031F), Color(0xFF26103A), Color(0xFF06010C)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF7D74B), Color(0xFFF59E0B)],
                    ),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    size: 36,
                    color: Color(0xFF200532),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  context.tr('login_welcome_title'),
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.tr('login_welcome_description'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(12),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFFF7D74B)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('login_feature_highlight'),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(context.tr('login_continue_google')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: const Color(0xFFF7D74B),
                    foregroundColor: const Color(0xFF190527),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    context.tr('login_footer_note'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
