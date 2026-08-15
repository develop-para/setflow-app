import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

enum SocialLoginProvider { google, kakao, naver, apple }

class SupabaseAuthService {
  SupabaseAuthService._();

  static final instance = SupabaseAuthService._();

  SupabaseClient? _client;

  void configure(SupabaseClient client) => _client = client;

  SupabaseClient get _requiredClient {
    final client = _client;
    if (client == null) {
      throw const SupabaseAuthUiException('Supabase 인증이 아직 초기화되지 않았어요.');
    }
    return client;
  }

  User? get currentUser => _client?.auth.currentUser;
  bool get hasAuthenticatedUser => currentUser != null;

  String get currentDisplayName {
    final user = currentUser;
    if (user == null) return '회원';
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

  Future<bool> isVerifiedAdmin() async {
    final client = _client;
    if (client == null || client.auth.currentUser == null) return false;
    final result = await client.rpc<Object?>('is_admin');
    return result == true;
  }

  Stream<AuthState> get authChanges =>
      _client?.auth.onAuthStateChange ?? const Stream<AuthState>.empty();

  bool isConfigured(SocialLoginProvider provider) {
    if (provider == SocialLoginProvider.naver) {
      return SupabaseConfig.naverProviderName.isNotEmpty;
    }
    return true;
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _requiredClient.functions.invoke(
      'email-signup',
      body: {
        'email': normalizedEmail,
        'password': password,
        'nickname': nickname.trim(),
      },
    );
    return _requiredClient.auth.signInWithPassword(
      email: normalizedEmail,
      password: password,
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _requiredClient.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<bool> signInWithSocial(SocialLoginProvider provider) {
    final oauthProvider = switch (provider) {
      SocialLoginProvider.google => OAuthProvider.google,
      SocialLoginProvider.kakao => OAuthProvider.kakao,
      SocialLoginProvider.apple => OAuthProvider.apple,
      SocialLoginProvider.naver
          when SupabaseConfig.naverProviderName.isNotEmpty =>
        OAuthProvider(SupabaseConfig.naverProviderName),
      SocialLoginProvider.naver => throw const SupabaseAuthUiException(
        '네이버 로그인은 Supabase Custom OAuth/OIDC 등록 후 활성화할 수 있어요.',
      ),
    };
    return _requiredClient.auth.signInWithOAuth(
      oauthProvider,
      redirectTo: kIsWeb ? null : SupabaseConfig.mobileAuthRedirect,
    );
  }

  Future<void> signOut() => _client?.auth.signOut() ?? Future<void>.value();

  String messageFor(Object error) {
    if (error is SupabaseAuthUiException) return error.message;
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map) {
        final message = details['message'];
        if (message is String && message.trim().isNotEmpty) return message;
      }
      if (error.status == 429) {
        return '가입 요청이 많아요. 1시간 뒤 다시 시도해주세요.';
      }
      return '회원가입을 처리하지 못했어요. 잠시 후 다시 시도해주세요.';
    }
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
      if (message.contains('rate limit')) {
        return '요청이 많아요. 잠시 후 다시 시도해주세요.';
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
