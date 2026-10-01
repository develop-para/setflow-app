import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_update_service.dart';

/// 공식 Android SDK와 연결하는 어댑터. 일반/스토어 빌드에서는 꺼진다.
class FirebaseAppUpdateService implements AppUpdateService {
  const FirebaseAppUpdateService();
  static const _channel = MethodChannel('com.teampara.setflow/app_updates');

  @override
  bool get isAvailable =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      const bool.fromEnvironment('APP_DISTRIBUTION_UPDATES');

  @override
  Future<AppUpdateCheck> checkForUpdate({bool requestSignIn = false}) async {
    if (!isAvailable) return const AppUpdateCheck();
    final data = await _invoke('check', {'requestSignIn': requestSignIn});
    if (data == null) {
      throw const AppUpdateException('업데이트 정보를 받지 못했어요. 다시 시도해주세요.');
    }
    final version = data['version'] as String?;
    return AppUpdateCheck(
      needsSignIn: data['needsSignIn'] == true,
      release: version == null
          ? null
          : AppRelease(
              version: version,
              build: (data['build'] as num).toInt(),
              notes: data['notes'] as String?,
            ),
    );
  }

  @override
  Future<void> installUpdate() async {
    if (!isAvailable) return;
    await _invoke('install');
  }

  Future<Map<Object?, Object?>?> _invoke(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
    } on PlatformException catch (error) {
      final cancelled = const {
        'AUTHENTICATION_CANCELED',
        'INSTALLATION_CANCELED',
        'HOST_ACTIVITY_INTERRUPTED',
      }.contains(error.code);
      throw AppUpdateException(switch (error.code) {
        'API_DISABLED' => '업데이트 연결이 아직 준비되지 않았어요. 배포 담당자에게 알려주세요.',
        'AUTHENTICATION_FAILURE' => '초대받은 Google 계정으로 연결했는지 확인해주세요.',
        'NETWORK_FAILURE' => '인터넷 연결을 확인하고 다시 시도해주세요.',
        'UPDATE_NOT_AVAILABLE' => '설치할 새 버전이 없어요. 다시 확인해주세요.',
        _ => '업데이트를 완료하지 못했어요. 잠시 후 다시 시도해주세요.',
      }, cancelled: cancelled);
    } on MissingPluginException {
      throw const AppUpdateException('이 빌드에서는 앱 업데이트를 사용할 수 없어요.');
    }
  }
}
