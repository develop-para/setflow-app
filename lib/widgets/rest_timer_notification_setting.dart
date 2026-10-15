import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/rest_timer_platform.dart';
import 'common.dart';

/// 알림 권한은 운동을 기록할 때가 아니라 사용자가 설정을 켤 때 확인한다.
class RestTimerNotificationSetting extends StatefulWidget {
  const RestTimerNotificationSetting({super.key});

  @override
  State<RestTimerNotificationSetting> createState() =>
      _RestTimerNotificationSettingState();
}

class _RestTimerNotificationSettingState
    extends State<RestTimerNotificationSetting>
    with WidgetsBindingObserver {
  bool? _allowed;
  bool _loaded = false;
  bool _openingSettings = false;
  bool _waitingForSettings = false;
  int _statusRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
  }

  @override
  void dispose() {
    ++_statusRequest;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  Future<void> _reload() async {
    final request = ++_statusRequest;
    final allowed = await RestTimerPlatform.notificationsAllowed();
    if (!mounted || request != _statusRequest) return;
    setState(() {
      _allowed = allowed;
      _loaded = true;
      _waitingForSettings = false;
    });
  }

  Future<void> _change(bool enabled) async {
    if (!mounted || !_loaded || _openingSettings || _waitingForSettings) return;
    // 이전 조회가 사용자의 변경이나 설정 복귀 후 새 권한을 덮지 못하게 한다.
    ++_statusRequest;
    AppScope.of(context).setRestTimerNotifications(enabled);
    if (!enabled || _allowed != false) return;
    setState(() {
      _openingSettings = true;
      _waitingForSettings = true;
    });
    final opened = await RestTimerPlatform.openNotificationSettings();
    if (!mounted) return;
    setState(() {
      _openingSettings = false;
      if (!opened) _waitingForSettings = false;
    });
    if (!opened) {
      AppSnackbar.error(context, '알림 설정을 열지 못했어요. 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = AppScope.of(context).restTimerNotifications;
    final needsPermission = enabled && _allowed == false;
    return SwitchListTile(
      key: const ValueKey('setting-rest-timer-notifications'),
      title: const Text('휴식 타이머 종료 알림'),
      subtitle: needsPermission
          ? const Text('기기에서 알림을 허용해야 해요. 다시 켜서 알림 설정을 열어주세요.')
          : null,
      value: enabled && _allowed != false,
      onChanged: !_loaded || _openingSettings || _waitingForSettings
          ? null
          : _change,
    );
  }
}
