import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class CustomAuthException implements Exception {
  const CustomAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class CustomAuthUser {
  const CustomAuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.nickname,
    this.avatarUrl,
    this.isFirstRun = true,
  });

  factory CustomAuthUser.fromJson(Map<String, dynamic> json) {
    return CustomAuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String? ?? 'general',
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isFirstRun: json['is_first_run'] as bool? ?? true,
    );
  }

  final String id;
  final String email;
  final String role;
  final String? nickname;
  final String? avatarUrl;
  final bool isFirstRun;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'role': role,
    'nickname': nickname,
    'avatar_url': avatarUrl,
    'is_first_run': isFirstRun,
  };
}

class CustomAuthSession {
  const CustomAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final CustomAuthUser user;
}

class CustomAuthService {
  CustomAuthService._();

  static final CustomAuthService instance = CustomAuthService._();

  static const endpoint = String.fromEnvironment(
    'CUSTOM_AUTH_URL',
    defaultValue:
        'https://fblrtxnpgftrtplqmsqe.supabase.co/functions/v1/custom-auth',
  );
  static const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static const _accessTokenKey = 'setflow_access_token';
  static const _refreshTokenKey = 'setflow_refresh_token';
  static const _expiresAtKey = 'setflow_access_expires_at';
  static const _userKey = 'setflow_auth_user';

  static const _storage = FlutterSecureStorage(
    webOptions: WebOptions(
      dbName: 'setflow_auth',
      publicKey: 'setflow_auth_key',
    ),
  );

  final GoogleSignIn _google = GoogleSignIn.instance;
  final StreamController<GoogleSignInAccount> _googleAccounts =
      StreamController<GoogleSignInAccount>.broadcast();
  Future<void>? _googleInitialization;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleSubscription;

  bool get googleConfigured => googleClientId.trim().isNotEmpty;
  Stream<GoogleSignInAccount> get googleAccounts => _googleAccounts.stream;

  Future<void> initializeGoogle() {
    if (!googleConfigured) {
      return Future<void>.value();
    }
    return _googleInitialization ??= _initializeGoogle();
  }

  Future<void> _initializeGoogle() async {
    await _google.initialize(
      clientId: kIsWeb ? googleClientId : null,
      serverClientId: kIsWeb
          ? null
          : (googleServerClientId.trim().isEmpty
                ? googleClientId
                : googleServerClientId),
    );
    _googleSubscription = _google.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _googleAccounts.add(event.user);
      }
    }, onError: _googleAccounts.addError);
  }

  Future<void> beginGoogleSignIn() async {
    if (!googleConfigured) {
      throw const CustomAuthException(
        'google_not_configured',
        'Google 로그인 설정이 필요해요.',
      );
    }
    await initializeGoogle();
    if (!_google.supportsAuthenticate()) {
      throw const CustomAuthException(
        'google_button_required',
        'Google 버튼에서 로그인을 진행해주세요.',
      );
    }
    await _google.authenticate();
  }

  Future<CustomAuthSession> signInWithGoogle(
    GoogleSignInAccount account,
  ) async {
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const CustomAuthException(
        'missing_google_token',
        'Google 인증 정보를 받지 못했어요. 다시 시도해주세요.',
      );
    }

    final payload = await _request(
      method: 'POST',
      path: 'google',
      body: {'id_token': idToken},
    );
    final userJson = payload['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const CustomAuthException(
        'invalid_server_response',
        '로그인 응답을 확인하지 못했어요.',
      );
    }
    final session = CustomAuthSession(
      accessToken: payload['access_token'] as String,
      refreshToken: payload['refresh_token'] as String,
      expiresIn: payload['expires_in'] as int,
      user: CustomAuthUser.fromJson(userJson),
    );
    await _saveSession(session);
    return session;
  }

  Future<void> signOut() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    try {
      if (accessToken != null && accessToken.isNotEmpty) {
        await _request(
          method: 'POST',
          path: 'logout',
          accessToken: accessToken,
        );
      }
    } catch (_) {
      // A local sign-out must still succeed when the session is expired or the
      // network is unavailable.
    } finally {
      await _clearSession();
      if (_googleInitialization != null) {
        try {
          await _google.signOut();
        } catch (_) {
          // The Setflow session has already been removed locally.
        }
      }
    }
  }

  Future<String?> validAccessToken() async {
    final accessToken = await _storage.read(key: _accessTokenKey);
    final expiresAtText = await _storage.read(key: _expiresAtKey);
    final expiresAt = expiresAtText == null
        ? null
        : DateTime.tryParse(expiresAtText);
    if (accessToken != null &&
        expiresAt != null &&
        expiresAt.isAfter(
          DateTime.now().toUtc().add(const Duration(seconds: 30)),
        )) {
      return accessToken;
    }

    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      final payload = await _request(
        method: 'POST',
        path: 'refresh',
        body: {'refresh_token': refreshToken},
      );
      final refreshedAccessToken = payload['access_token'] as String;
      final refreshedRefreshToken = payload['refresh_token'] as String;
      final expiresIn = payload['expires_in'] as int;
      await _saveTokens(
        accessToken: refreshedAccessToken,
        refreshToken: refreshedRefreshToken,
        expiresIn: expiresIn,
      );
      return refreshedAccessToken;
    } on CustomAuthException catch (error) {
      if (error.code != 'network_error') await _clearSession();
      rethrow;
    }
  }

  Future<void> _saveSession(CustomAuthSession session) async {
    await _saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      expiresIn: session.expiresIn,
    );
    await _storage.write(
      key: _userKey,
      value: jsonEncode(session.user.toJson()),
    );
  }

  Future<void> _saveTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) async {
    final expiresAt = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toUtc()
        .toIso8601String();
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _expiresAtKey, value: expiresAt),
    ]);
  }

  Future<void> _clearSession() {
    return Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _expiresAtKey),
      _storage.delete(key: _userKey),
    ]);
  }

  Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final uri = Uri.parse('$endpoint/$path');
    try {
      final headers = {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };
      final response = switch (method) {
        'POST' => await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const <String, dynamic>{}),
        ),
        'GET' => await http.get(uri, headers: headers),
        _ => throw ArgumentError.value(method, 'method'),
      };
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const CustomAuthException(
          'invalid_server_response',
          '서버 응답을 확인하지 못했어요.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CustomAuthException(
          decoded['code'] as String? ?? 'auth_failed',
          decoded['message'] as String? ?? '로그인하지 못했어요.',
        );
      }
      return decoded;
    } on CustomAuthException {
      rethrow;
    } catch (_) {
      throw const CustomAuthException(
        'network_error',
        '서버에 연결하지 못했어요. 잠시 후 다시 시도해주세요.',
      );
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    await _googleSubscription?.cancel();
    await _googleAccounts.close();
  }
}
