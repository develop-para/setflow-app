import 'dart:async';

import 'package:flutter/material.dart';

import '../services/rest_timer_platform.dart';
import 'common.dart';

/// 기기의 표시 권한과 함께 저장되는 설정이라 계정 스냅샷에 넣지 않는다.
class RestTimerOverlaySetting extends StatefulWidget {
  const RestTimerOverlaySetting({super.key});

  @override
  State<RestTimerOverlaySetting> createState() =>
      _RestTimerOverlaySettingState();
}

class _RestTimerOverlaySettingState extends State<RestTimerOverlaySetting>
    with WidgetsBindingObserver {
  RestTimerOverlayStatus? _status;
  bool _busy = false;
  bool _pendingEnable = false;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_reload());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reload());
  }

  Future<void> _reload() async {
    final status = await RestTimerPlatform.overlayStatus();
    if (!mounted) return;
    if (status == null) {
      if (_status != null || _pendingEnable) {
        _pendingEnable = false;
        AppSnackbar.error(context, '타이머 표시 설정을 확인하지 못했어요.');
      }
      return;
    }
    setState(() => _status = status);
    if (!_pendingEnable) return;
    _pendingEnable = false;
    if (status.permissionGranted) {
      await _saveEnabled(true, status);
    } else {
      setState(() => _permissionDenied = true);
      AppSnackbar.info(context, '다른 앱 위에 표시 권한을 허용해주세요.');
    }
  }

  Future<void> _saveEnabled(bool enabled, RestTimerOverlayStatus status) async {
    setState(() => _busy = true);
    final saved = await RestTimerPlatform.setOverlayEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved) {
        _status = RestTimerOverlayStatus(
          enabled: enabled,
          permissionGranted: status.permissionGranted,
        );
        _permissionDenied = false;
      }
    });
    if (!saved) {
      AppSnackbar.error(context, '타이머 표시 설정을 변경하지 못했어요.');
    }
  }

  Future<void> _change(bool enabled) async {
    final status = _status;
    if (_busy || status == null) return;
    if (!enabled || status.permissionGranted) {
      await _saveEnabled(enabled, status);
      return;
    }
    setState(() => _busy = true);
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('타이머 표시 권한'),
        content: const Text(
          '다른 앱을 보면서 휴식 타이머를 확인하려면 Android 설정에서 '
          '셋플로우의 «다른 앱 위에 표시»를 허용해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('권한 설정'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (openSettings != true) return;
    _pendingEnable = true;
    final opened = await RestTimerPlatform.openOverlaySettings();
    if (!mounted || opened) return;
    _pendingEnable = false;
    AppSnackbar.error(context, '권한 설정을 열지 못했어요. 다시 시도해주세요.');
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final needsPermission =
        !status.permissionGranted && (status.enabled || _permissionDenied);
    return SwitchListTile(
      key: const ValueKey('setting-rest-timer-overlay'),
      title: const Text('다른 앱 위에 타이머'),
      subtitle: Text(
        needsPermission
            ? '다른 앱 위에 표시 권한이 필요해요. 다시 켜서 권한 설정을 열어주세요.'
            : '앱을 나가도 남은 휴식과 운동 복귀 버튼을 보여줘요.',
      ),
      value: status.enabled && status.permissionGranted,
      onChanged: _busy ? null : _change,
    );
  }
}
