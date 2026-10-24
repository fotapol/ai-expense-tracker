import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

/// Supplies a local authenticated user without calling Firebase services.
void installAuthenticatedApiUser() {
  FirebasePlatform.instance = _Firebase();
  FirebaseAuthPlatform.instance = _Auth();
}

class _Firebase extends FirebasePlatform {
  final _app = FirebaseAppPlatform(
    '[DEFAULT]',
    const FirebaseOptions(
      apiKey: 'test-key',
      appId: 'test-app',
      messagingSenderId: 'test-sender',
      projectId: 'test-project',
    ),
  );

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = '[DEFAULT]']) => _app;
}

class _Auth extends FirebaseAuthPlatform {
  late final _user = _User(this);

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    InternalUserDetails? currentUser,
    String? languageCode,
  }) => this;

  @override
  UserPlatform get currentUser => _user;
}

class _MultiFactor extends MultiFactorPlatform {
  _MultiFactor(super.auth);
}

class _User extends UserPlatform {
  _User(FirebaseAuthPlatform auth)
    : super(
        auth,
        _MultiFactor(auth),
        InternalUserDetails(
          userInfo: InternalUserInfo(
            uid: 'test-user',
            isAnonymous: false,
            isEmailVerified: true,
          ),
          providerData: [],
        ),
      );

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      _Token();
}

class _Token extends IdTokenResult {
  _Token()
    : super(
        InternalIdTokenResult(
          token: 'test-token',
          expirationTimestamp: DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
      );
}
