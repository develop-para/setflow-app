/// The app's auth contract, owned by the app rather than by a vendor.
///
/// Nothing in this file imports a backend SDK, and every type crossing it is
/// ours. That is the point: the plan is to move off Supabase onto our own
/// server, and the cost of that move is roughly "how much of the app names
/// Supabase types". Screens talk to [AuthService] through [Auth]; swapping the
/// backend then means writing one more implementation and rebinding it in
/// `main()`, not editing every screen.
///
/// The data layer already works this way — `AppRepository`,
/// `BusinessRepository`, `CommunityRepository` and `RoutineCatalogRepository`
/// are interfaces with Supabase implementations behind them. This closes the
/// last hole.
library;

import 'dart:async';

enum SocialLoginProvider { google, kakao, naver, apple }

/// The signed-in person, reduced to what the app actually uses.
class AuthUser {
  const AuthUser({required this.id, this.email, required this.displayName});

  final String id;
  final String? email;

  /// Already resolved — nickname, then name, then the email's local part.
  final String displayName;
}

enum AuthEvent {
  signedIn,
  signedOut,
  tokenRefreshed,

  /// The user opened a password-reset link. The backend has put them in a
  /// short-lived session whose only purpose is to set a new password, so the
  /// app must send them to that screen rather than silently treat it as a
  /// normal sign-in.
  passwordRecovery,
  other,
}

/// One place that decides what a usable password is.
///
/// Signup, reset and change all have to agree — when each screen carries its
/// own `length < 8` check they drift, and the backend rejecting a password the
/// form accepted is a dead end for the user.
abstract final class AuthPasswordPolicy {
  static const minLength = 8;

  /// Null when acceptable, otherwise the sentence to show under the field.
  static String? validate(String? value) {
    final password = value ?? '';
    if (password.length < minLength) return '비밀번호를 $minLength자 이상 입력해주세요.';
    if (password.trim().isEmpty) return '공백만으로는 비밀번호를 만들 수 없어요.';
    return null;
  }
}

class AuthChange {
  const AuthChange(this.event, this.user);

  final AuthEvent event;
  final AuthUser? user;
}

/// A signup either lands you in a session or waits on an emailed link. The
/// difference is the backend's policy, not a failure, so it is a result rather
/// than an exception.
class AuthSignUpResult {
  const AuthSignUpResult({required this.signedIn});

  final bool signedIn;

  bool get needsEmailConfirmation => !signedIn;
}

/// Auth failures the UI is expected to show as-is.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AuthService {
  AuthUser? get currentUser;
  bool get hasAuthenticatedUser;

  /// Falls back to a generic label rather than returning null, because every
  /// call site would otherwise repeat the same fallback.
  String get currentDisplayName;

  Stream<AuthChange> get authChanges;

  /// False when the provider is not wired up on this build or backend, so the
  /// UI can show it disabled instead of failing on tap.
  bool isConfigured(SocialLoginProvider provider);

  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required String nickname,
  });

  Future<void> signIn({required String email, required String password});

  /// True when the provider's screen was actually launched.
  Future<bool> signInWithSocial(SocialLoginProvider provider);

  /// Mails a reset link.
  ///
  /// Deliberately returns normally for addresses that have no account —
  /// reporting "no such user" turns this form into a way to test whether
  /// someone is a member. The UI says "if an account exists we sent a mail".
  Future<void> sendPasswordReset({required String email});

  /// Sends the signup confirmation mail again.
  ///
  /// Without this, a confirmation mail that lands in spam or never arrives
  /// leaves the account permanently unreachable: it exists, so signing up
  /// again fails, and it is unconfirmed, so signing in fails too.
  Future<void> resendConfirmationEmail({required String email});

  /// Sets a new password for the *current* session.
  ///
  /// Valid both after a [AuthEvent.passwordRecovery] link and for a signed-in
  /// user changing their password.
  Future<void> updatePassword({required String newPassword});

  /// True when [password] is the signed-in user's current password.
  ///
  /// Changing a password from inside a live session must not rely on the
  /// session alone — an unlocked phone would otherwise be enough to lock the
  /// owner out of their own account.
  Future<bool> verifyPassword(String password);

  Future<void> signOut();

  Future<bool> isVerifiedAdmin();

  /// Turns any thrown object into a sentence worth showing a user.
  String messageFor(Object error);
}

/// The single seam the app resolves auth through.
///
/// `main()` binds the real implementation. Anything that runs without that
/// binding — widget tests, previews — gets [_UnboundAuthService], which behaves
/// like a signed-out session instead of throwing on a null client.
abstract final class Auth {
  static AuthService _instance = const _UnboundAuthService();

  static AuthService get instance => _instance;

  static void use(AuthService service) => _instance = service;

  /// Restores the signed-out stand-in. For tests that rebind.
  static void reset() => _instance = const _UnboundAuthService();
}

class _UnboundAuthService implements AuthService {
  const _UnboundAuthService();

  @override
  AuthUser? get currentUser => null;

  @override
  bool get hasAuthenticatedUser => false;

  @override
  String get currentDisplayName => '회원';

  @override
  Stream<AuthChange> get authChanges => const Stream<AuthChange>.empty();

  @override
  bool isConfigured(SocialLoginProvider provider) => false;

  @override
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async => throw const AuthFailure('로그인 서버에 연결되어 있지 않아요.');

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async => throw const AuthFailure('로그인 서버에 연결되어 있지 않아요.');

  @override
  Future<bool> signInWithSocial(SocialLoginProvider provider) async =>
      throw const AuthFailure('로그인 서버에 연결되어 있지 않아요.');

  @override
  Future<void> sendPasswordReset({required String email}) async =>
      throw const AuthFailure('로그인 서버에 연결되어 있지 않아요.');

  @override
  Future<void> resendConfirmationEmail({required String email}) async =>
      throw const AuthFailure('로그인 서버에 연결되어 있지 않아요.');

  @override
  Future<void> updatePassword({required String newPassword}) async =>
      throw const AuthFailure('로그인 서버에 연결되어 있지 않아요.');

  @override
  Future<bool> verifyPassword(String password) async => false;

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  String messageFor(Object error) =>
      error is AuthFailure ? error.message : '문제가 발생했어요. 잠시 후 다시 시도해주세요.';
}
