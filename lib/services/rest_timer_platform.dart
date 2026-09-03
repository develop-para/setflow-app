import 'package:flutter/services.dart';

class RestTimerStatus {
  const RestTimerStatus({required this.remainingSeconds, this.endsAtMillis});

  final int remainingSeconds;
  final int? endsAtMillis;
}

/// Bridges the in-app timer to Android's foreground timer and home widget.
/// Calls are best-effort so non-Android platforms keep using the Dart timer.
abstract final class RestTimerPlatform {
  static const _channel = MethodChannel('com.teampara.setflow/rest_timer');

  static Future<void> start({
    required int seconds,
    required bool showCompletionNotification,
    required bool vibrate,
    bool sound = true,
    int countdownSeconds = 30,
    String? detail,
  }) async {
    try {
      await _channel.invokeMethod<void>('start', {
        'seconds': seconds,
        'showCompletionNotification': showCompletionNotification,
        'vibrate': vibrate,
        'sound': sound,
        'countdownSeconds': countdownSeconds,
        // 알림 창의 둘째 줄 — "다음: 스쿼트" 같은 지금 위치. 없으면 네이티브가
        // 기본 문구를 쓴다.
        'detail': ?detail,
      });
    } on MissingPluginException {
      // Supported only by the Android host.
    } on PlatformException {
      // The foreground service is an enhancement; the in-app timer continues.
    } catch (_) {
      // Pure Dart/unit-test contexts have no ServicesBinding.
    }
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Supported only by the Android host.
    } on PlatformException {
      // The local timer is still cancelled even if the host is unavailable.
    } catch (_) {
      // Pure Dart/unit-test contexts have no ServicesBinding.
    }
  }

  /// 알림창에 남은 "휴식이 끝났어요"를 걷어낸다.
  ///
  /// 그 알림은 탭해야만 사라지는데, 앱을 보면서 쉰 사람은 탭할 일이 없다.
  /// 그러면 알림창에 그것만 남고 런처 아이콘의 배지가 계속 붙어 있는데,
  /// 앱에 들어와도 무슨 알림이었는지 알 길이 없다. 앱이 앞으로 나온 순간
  /// 그 알림은 이미 할 일을 마친 것이다.
  static Future<void> clearCompletionNotification() async {
    try {
      await _channel.invokeMethod<void>('clearCompletionNotification');
    } on MissingPluginException {
      // Supported only by the Android host.
    } on PlatformException {
      // 배지가 남는 것은 불편이지 고장이 아니다 — 조용히 넘어간다.
    } catch (_) {
      // Pure Dart/unit-test contexts have no ServicesBinding.
    }
  }

  static Future<RestTimerStatus?> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('status');
      if (raw == null) return null;
      return RestTimerStatus(
        remainingSeconds: (raw['remainingSeconds'] as num?)?.toInt() ?? 0,
        endsAtMillis: (raw['endsAtMillis'] as num?)?.toInt(),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
