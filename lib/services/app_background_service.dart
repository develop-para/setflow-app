import 'package:flutter/services.dart';

/// Sends the Android task to the background without finishing its activity.
///
/// This preserves the current screen while Android keeps the process alive.
/// Ongoing rest timers continue through their separate foreground service.
abstract final class AppBackgroundService {
  static const _channel = MethodChannel('com.teampara.setflow/app_background');

  /// Returns false when the host cannot move the task or lacks this capability.
  static Future<bool> moveToBackground() async {
    try {
      return await _channel.invokeMethod<bool>('moveToBackground') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
