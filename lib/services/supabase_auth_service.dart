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
