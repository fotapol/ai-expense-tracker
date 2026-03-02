import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'me_screen.dart';

/// Login screen with a "Continue with Google" button.
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
      // Trigger interactive Google Sign-In (v7 API).
      // authenticate() throws GoogleSignInException on cancel/failure.
      final GoogleSignInAccount googleUser =
          await GoogleSignIn.instance.authenticate();

      // Obtain the Google ID token for Firebase credential exchange.
      final String? googleIdToken = googleUser.authentication.idToken;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleIdToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MeScreen()),
        );
      }
    } on GoogleSignInException catch (e) {
      // User canceled sign-in or other Google Sign-In specific error.
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // Silently ignore cancellation.
        debugPrint('Google Sign-In canceled by user.');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In error: ${e.description}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Continue with Google'),
                onPressed: _signInWithGoogle,
              ),
      ),
    );
  }
}
