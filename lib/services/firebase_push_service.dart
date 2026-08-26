import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_service.dart';

/// [PushService]의 FCM 어댑터. Firebase 타입을 아는 유일한 파일이다.
///
/// 초기화가 실패해도 **앱은 계속 떠야 한다.** iOS에는 아직
/// GoogleService-Info.plist가 없고(APNs 키가 있어야 만들 수 있다), 설정이
/// 반쯤 된 상태에서 initializeApp이 던지면 스플래시에서 앱이 죽는다. 알림이
/// 안 오는 것과 앱이 안 켜지는 것은 등급이 다른 실패다.
class FirebasePushService implements PushService {
  FirebasePushService._();

  static bool _initialized = false;

  /// 초기화를 시도하고, 되면 살아 있는 서비스를 돌려준다. 실패하면
  /// [DisabledPushService]로 떨어진다 — 호출부는 차이를 몰라도 된다.
  static Future<PushService> create() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _initialized = true;
      return FirebasePushService._();
    } catch (error, stack) {
      // 설정 파일이 없는 플랫폼에서 흔한 경로다. 조용히 넘기되 흔적은 남긴다.
      debugPrint('푸시를 초기화하지 못했습니다: $error');
      assert(() {
        debugPrintStack(stackTrace: stack, label: 'FirebasePushService');
        return true;
      }());
      return const DisabledPushService();
    }
  }

  @override
  bool get isAvailable => _initialized;

  @override
  Future<bool> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (error) {
      debugPrint('알림 권한을 요청하지 못했습니다: $error');
      return false;
    }
  }

  @override
  Future<String?> currentToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      // iOS에서 APNs 토큰이 아직 없으면 여기서 던진다. 다음 실행에 다시
      // 시도하면 되는 일이라 실패로 취급하지 않는다.
      debugPrint('푸시 토큰을 가져오지 못했습니다: $error');
      return null;
    }
  }

  @override
  Stream<String> get tokenChanges => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Future<void> deleteToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('푸시 토큰을 지우지 못했습니다: $error');
    }
  }
}
