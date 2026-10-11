import 'package:flutter/services.dart';

class RestTimerStatus {
  const RestTimerStatus({required this.remainingSeconds, this.endsAtMillis});

  final int remainingSeconds;
  final int? endsAtMillis;
}

/// Device-local preference and Android's current overlay permission.
class RestTimerOverlayStatus {
  const RestTimerOverlayStatus({
    required this.enabled,
    required this.permissionGranted,
  });

  final bool enabled;
  final bool permissionGranted;
}

/// The recording screen requested by the background timer's return button.
class RestWorkoutOpen {
  const RestWorkoutOpen({this.workoutDate, this.coachingWorkoutId});

  final DateTime? workoutDate;
  final String? coachingWorkoutId;
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
    DateTime? workoutDate,
    String? coachingWorkoutId,
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
        'workoutDate': ?workoutDate?.toIso8601String().split('T').first,
        'sessionId': ?coachingWorkoutId,
      });
    } on MissingPluginException {
      // Supported only by the Android host.
    } on PlatformException {
      // The foreground service is an enhancement; the in-app timer continues.
    } catch (_) {
      // Pure Dart/unit-test contexts have no ServicesBinding.
    }
  }

  /// Null means that this host does not support a floating background timer.
  static Future<RestTimerOverlayStatus?> overlayStatus() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'overlayStatus',
      );
      if (raw == null) return null;
      return RestTimerOverlayStatus(
        enabled: raw['enabled'] == true,
        permissionGranted: raw['permissionGranted'] == true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// A device preference; changing it never requests a permission or stops rest.
  static Future<bool> setOverlayEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setOverlayEnabled', {
        'enabled': enabled,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Called only after the user chooses the permission action in settings.
  static Future<bool> openOverlaySettings() async {
    try {
      return await _channel.invokeMethod<bool>('openOverlaySettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// The native host retains a return request across Activity/process restarts.
  static Future<RestWorkoutOpen?> consumePendingWorkoutOpen() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'consumePendingWorkoutOpen',
      );
      if (raw == null) return null;
      DateTime? date;
      final encodedDate = raw['workoutDate'];
      if (encodedDate is String &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(encodedDate)) {
        final parsed = DateTime.tryParse(encodedDate);
        if (parsed != null &&
            parsed.toIso8601String().split('T').first == encodedDate) {
          date = parsed;
        }
      }
      final encodedId = raw['sessionId'];
      return RestWorkoutOpen(
        workoutDate: date,
        coachingWorkoutId: encodedId is String && encodedId.trim().isNotEmpty
            ? encodedId.trim()
            : null,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
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
