import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthChangeEvent, AuthUser;
import 'package:supabase_flutter/supabase_flutter.dart'
    as supabase
    show AuthChangeEvent;

import 'auth_service.dart';
import 'supabase_config.dart';

/// The Supabase adapter for [AuthService]. Everything Supabase-shaped stops
/// here: the rest of the app only sees the app's own auth types, so replacing
/// this class is the whole cost of moving auth to another backend.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService._();

  static final instance = SupabaseAuthService._();

  SupabaseClient? _client;

  void configure(SupabaseClient client) => _client = client;

  SupabaseClient get _requiredClient {
    final client = _client;
    if (client == null) {
      throw const AuthFailure('로그인 서버에 연결되어 있지 않아요.');
    }
    return client;
  }

  @override
  AuthUser? get currentUser {
    final user = _client?.auth.currentUser;
    if (user == null) return null;
    return AuthUser(
      id: user.id,
      email: user.email,
      displayName: _displayNameOf(user),
    );
  }

  @override
  bool get hasAuthenticatedUser => _client?.auth.currentUser != null;

  @override
  String get currentDisplayName {
    final user = _client?.auth.currentUser;
    if (user == null) return '회원';
    return _displayNameOf(user);
  }

  String _displayNameOf(User user) {
    final metadata = user.userMetadata;
    for (final value in [
      metadata?['nickname'],
      metadata?['name'],
      metadata?['full_name'],
    ]) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    final emailName = user.email?.split('@').first.trim();
    return emailName == null || emailName.isEmpty ? '회원' : emailName;
  }

  @override
  Future<bool> isVerifiedAdmin() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return false;
    final result = await client.rpc<Object?>('is_admin');
    return result == true;
  }

  @override
  Stream<AuthChange> get authChanges {
    final stream = _client?.auth.onAuthStateChange;
    if (stream == null) return const Stream<AuthChange>.empty();
    return stream.map((state) {
      final event = switch (state.event) {
        supabase.AuthChangeEvent.signedIn => AuthEvent.signedIn,
        supabase.AuthChangeEvent.initialSession => AuthEvent.signedIn,
        supabase.AuthChangeEvent.signedOut => AuthEvent.signedOut,
        supabase.AuthChangeEvent.tokenRefreshed => AuthEvent.tokenRefreshed,
        // Must not fall through to signedIn: the recovery session exists only
        // so the user can set a new password, and treating it as a normal
        // sign-in would drop them on the home screen still locked out.
        supabase.AuthChangeEvent.passwordRecovery => AuthEvent.passwordRecovery,
        _ => AuthEvent.other,
      };
      final user = state.session?.user;
      return AuthChange(
        event,
        user == null
            ? null
            : AuthUser(
                id: user.id,
                email: user.email,
                displayName: _displayNameOf(user),
              ),
      );
    });
  }

  @override
  bool isConfigured(SocialLoginProvider provider) {
    return switch (provider) {
      SocialLoginProvider.google => SupabaseConfig.googleOauthEnabled,
      SocialLoginProvider.kakao => SupabaseConfig.kakaoOauthEnabled,
      SocialLoginProvider.naver => SupabaseConfig.naverProviderName.isNotEmpty,
      SocialLoginProvider.apple => SupabaseConfig.appleOauthEnabled,
    };
  }

  /// Signs up straight against GoTrue, the way a Supabase client app normally
  /// does.
  ///
  /// This used to POST to an `email-signup` Edge Function that created the user
  /// with the service-role key and `email_confirm: true`. That put a
  /// privileged server hop on the critical path of the most common action in
  /// the app, and when its key stopped resolving every signup began failing
  /// with an opaque 500 — which is exactly the instability this replaces.
  ///
  /// The trade is that email confirmation is now the project's setting to make,
  /// not ours: when confirmations are on, [AuthResponse.session] comes back
  /// null and the caller must send the user to their inbox rather than pretend
  /// they are signed in.
  @override
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final response = await _requiredClient.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'nickname': nickname.trim()},
      emailRedirectTo: kIsWeb ? null : SupabaseConfig.mobileAuthRedirect,
    );
    // No session means the project requires email confirmation.
    return AuthSignUpResult(signedIn: response.session != null);
  }

  @override
  Future<void> signIn({required String email, required String password}) {
    return _requiredClient.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<bool> signInWithSocial(SocialLoginProvider provider) {
    if (!isConfigured(provider)) {
      final label = switch (provider) {
        SocialLoginProvider.google => 'Google',
        SocialLoginProvider.kakao => '카카오',
        SocialLoginProvider.naver => '네이버',
        SocialLoginProvider.apple => 'Apple',
      };
      throw SupabaseAuthUiException(
        '$label 로그인은 Supabase OAuth 등록 후 활성화할 수 있어요.',
      );
    }
    final oauthProvider = switch (provider) {
      SocialLoginProvider.google => OAuthProvider.google,
      SocialLoginProvider.kakao => OAuthProvider.kakao,
      SocialLoginProvider.apple => OAuthProvider.apple,
      SocialLoginProvider.naver
          when SupabaseConfig.naverProviderName.isNotEmpty =>
        OAuthProvider(SupabaseConfig.naverProviderName),
      SocialLoginProvider.naver => throw const SupabaseAuthUiException(
        '네이버 로그인 설정을 확인해주세요.',
      ),
    };
    return _requiredClient.auth.signInWithOAuth(
      oauthProvider,
      redirectTo: kIsWeb ? null : SupabaseConfig.mobileAuthRedirect,
    );
  }

  @override
  Future<void> sendPasswordReset({required String email}) async {
    try {
      await _requiredClient.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: kIsWeb ? null : SupabaseConfig.mobileAuthRedirect,
      );
    } on AuthException catch (error) {
      // "User not found" is not an error the user should see -- it would make
      // this form an account-existence oracle. Rate limiting is a real answer
      // and still surfaces.
      if (_isUnknownUser(error)) return;
      rethrow;
    }
  }

  @override
  Future<void> resendConfirmationEmail({required String email}) async {
    try {
      await _requiredClient.auth.resend(
        type: OtpType.signup,
        email: email.trim().toLowerCase(),
        emailRedirectTo: kIsWeb ? null : SupabaseConfig.mobileAuthRedirect,
      );
    } on AuthException catch (error) {
      if (_isUnknownUser(error)) return;
      rethrow;
    }
  }

  bool _isUnknownUser(AuthException error) {
    final message = error.message.toLowerCase();
    return message.contains('user not found') ||
        message.contains('unable to validate email');
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
    await _requiredClient.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  @override
  Future<bool> verifyPassword(String password) async {
    final email = _client?.auth.currentUser?.email;
    // Social-only accounts have no password to verify; the caller must not
    // offer a password change for them.
    if (email == null || email.isEmpty) return false;
    try {
      // Re-signing in issues a fresh session for the same user. A wrong
      // password throws and leaves the existing session untouched.
      await _requiredClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return true;
    } on AuthException {
      return false;
    }
  }

  @override
  Future<void> signOut() => _client?.auth.signOut() ?? Future<void>.value();

  @override
  String messageFor(Object error) {
    if (error is AuthFailure) return error.message;
    if (error is SupabaseAuthUiException) return error.message;
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        return '이메일 또는 비밀번호를 확인해주세요.';
      }
      if (message.contains('already registered') ||
          message.contains('already been registered')) {
        return '이미 가입된 이메일이에요. 로그인해주세요.';
      }
      if (message.contains('password should be')) {
        return '비밀번호는 8자 이상으로 입력해주세요.';
      }
      if (message.contains('email not confirmed')) {
        return '이메일 인증을 완료한 뒤 로그인해주세요.';
      }
      if (message.contains('rate limit') ||
          message.contains('too many requests') ||
          message.contains('for security purposes')) {
        return '요청이 많아요. 잠시 후 다시 시도해주세요.';
      }
      if (message.contains('signups not allowed') ||
          message.contains('signup is disabled')) {
        return '지금은 회원가입을 받고 있지 않아요.';
      }
      if (message.contains('should be different from the old password')) {
        return '지금 쓰고 있는 비밀번호와 다른 비밀번호를 입력해주세요.';
      }
      // Covers the leaked-password check (HaveIBeenPwned) as well as the plain
      // strength rules. "이 비밀번호가 유출됐다"고 말해야 사용자가 다른 서비스의 같은
      // 비밀번호도 바꾼다 — "약한 비밀번호"로 뭉뚱그리면 그 신호가 사라진다.
      if (message.contains('easy to guess') ||
          message.contains('pwned') ||
          message.contains('compromised') ||
          message.contains('data breach')) {
        return '다른 사이트 유출 목록에 있는 비밀번호예요. 다른 비밀번호를 써주세요.';
      }
      if (message.contains('weak password') ||
          message.contains('password is too')) {
        return '더 안전한 비밀번호를 입력해주세요. 길게 쓰는 것이 가장 효과적이에요.';
      }
      // A recovery link is single-use and short-lived, and "otp expired" reads
      // as gibberish to someone who just clicked a mail link.
      if (message.contains('expired') || message.contains('invalid token')) {
        return '재설정 링크가 만료됐어요. 다시 요청해주세요.';
      }
      if (message.contains('session') && message.contains('missing')) {
        return '로그인이 만료됐어요. 다시 로그인해주세요.';
      }
      return error.message;
    }
    return '인증 요청을 처리하지 못했어요. 잠시 후 다시 시도해주세요.';
  }
}

class SupabaseAuthUiException implements Exception {
  const SupabaseAuthUiException(this.message);
  final String message;

  @override
  String toString() => message;
}
