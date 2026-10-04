import 'package:flutter/foundation.dart';

import 'app_update_service.dart';
import 'app_version_service.dart';

/// 조회는 조용히, 계정 연결과 설치는 사용자가 누른 뒤에만 시작한다.
class AppUpdateController extends ChangeNotifier {
  AppUpdateController(
    this.service, {
    this.versionService = const UnavailableAppVersionService(),
  });
  final AppUpdateService service;
  final AppVersionService versionService;
  InstalledAppVersion? installedVersion;
  bool versionLoading = false;
  bool versionChecked = false;
  Future<void>? _versionRead;
  bool _disposed = false;
  bool get isAvailable => service.isAvailable;
  bool busy = false;
  bool needsSignIn = false;
  bool checked = false;
  AppRelease? release;
  String? error;
  DateTime? _lastCheck;

  Future<void> loadInstalledVersion({bool force = false}) {
    if (_disposed || (versionChecked && !force)) return Future.value();
    final pending = _versionRead;
    if (pending != null) return pending;
    return _versionRead = _readInstalledVersion().whenComplete(() {
      _versionRead = null;
    });
  }

  Future<void> _readInstalledVersion() async {
    versionLoading = true;
    notifyListeners();
    try {
      final version = await versionService.readInstalledVersion();
      if (!_disposed) installedVersion = version;
    } catch (_) {
      // Missing metadata must not block checking for or installing updates.
    } finally {
      versionLoading = false;
      versionChecked = true;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> check({bool interactive = false}) async {
    if (!isAvailable || busy) return;
    if (!interactive &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 5)) {
      return;
    }
    busy = true;
    checked = false;
    error = null;
    notifyListeners();
    try {
      final result = await service.checkForUpdate(requestSignIn: interactive);
      needsSignIn = result.needsSignIn;
      release = result.release;
      checked = !needsSignIn;
      _lastCheck = DateTime.now();
    } on AppUpdateException catch (failure) {
      if (!failure.cancelled && interactive) error = failure.message;
    } catch (_) {
      if (interactive) error = '업데이트를 확인하지 못했어요. 다시 시도해주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> install() async {
    if (!isAvailable || busy || release == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await service.installUpdate();
      // 설치 화면을 열었다고 실제 설치가 끝난 것은 아니다. 새 실행에서 재확인.
    } on AppUpdateException catch (failure) {
      if (!failure.cancelled) error = failure.message;
    } catch (_) {
      error = '업데이트를 시작하지 못했어요. 다시 시도해주세요.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

abstract final class AppUpdates {
  static AppUpdateController instance = AppUpdateController(
    const DisabledAppUpdateService(),
  );
}
