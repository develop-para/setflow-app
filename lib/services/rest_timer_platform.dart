import 'package:flutter/services.dart';

class RestTimerStatus {
  const RestTimerStatus({required this.remainingSeconds, this.endsAtMillis});

  final int remainingSeconds;
  final int? endsAtMillis;
}

/// Bridges the in-app timer to Android's foreground timer and home widget.
/// Calls are best-effort so non-Android platforms keep using the Dart timer.
abstract final class RestTimerPlatform {
  static const _channel = MethodChannel('com.setflow.setflow/rest_timer');

  static Future<void> start({
    required int seconds,
    required bool showCompletionNotification,
    required bool vibrate,
  }) async {
    try {
      await _channel.invokeMethod<void>('start', {
        'seconds': seconds,
        'showCompletionNotification': showCompletionNotification,
        'vibrate': vibrate,
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
