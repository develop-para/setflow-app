import 'package:flutter/services.dart';

import '../domain/lock_screen_workout.dart';

abstract interface class LockScreenWorkoutPlatform {
  Future<LockScreenWorkoutStatus> status();
  Future<String?> getGuestOwnerKey();
  Future<bool> publish(Map<String, Object?> snapshot);
  Future<List<Map<String, Object?>>> readEvents();
  Future<void> acknowledge(List<String> eventIds);
  Future<void> clear();
  Future<bool> openSettings();
}

class MethodChannelLockScreenWorkoutPlatform
    implements LockScreenWorkoutPlatform {
  static const _channel = MethodChannel(
    'com.teampara.setflow/lock_screen_workout',
  );

  @override
  Future<LockScreenWorkoutStatus> status() async {
    try {
      final json = await _channel.invokeMapMethod<String, Object?>('status');
      return json == null
          ? LockScreenWorkoutStatus.unsupported
          : LockScreenWorkoutStatus.fromJson(json);
    } on MissingPluginException {
      return LockScreenWorkoutStatus.unsupported;
    }
  }

  @override
  Future<String?> getGuestOwnerKey() async {
    try {
      return await _channel.invokeMethod<String>('getGuestOwnerKey');
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> publish(Map<String, Object?> snapshot) async {
    try {
      return await _channel.invokeMethod<bool>('publish', snapshot) ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<Map<String, Object?>>> readEvents() async {
    try {
      final result = await _channel.invokeListMethod<Object?>('readEvents');
      return [
        for (final row in result ?? const [])
          if (row is Map) Map<String, Object?>.from(row),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> acknowledge(List<String> eventIds) async {
    await _channel.invokeMethod<void>('ack', {'eventIds': eventIds});
  }

  @override
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      // Hosts without the feature have no active native projection.
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
