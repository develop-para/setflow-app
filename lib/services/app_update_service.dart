/// 앱 업데이트 포트. 배포 제공자의 계정과 SDK 타입은 어댑터 안에 둔다.
abstract interface class AppUpdateService {
  bool get isAvailable;
  Future<AppUpdateCheck> checkForUpdate({bool requestSignIn = false});
  Future<void> installUpdate();
}

class AppRelease {
  const AppRelease({required this.version, required this.build, this.notes});
  final String version;
  final int build;
  final String? notes;
}

class AppUpdateCheck {
  const AppUpdateCheck({this.needsSignIn = false, this.release});
  final bool needsSignIn;
  final AppRelease? release;
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
}

class DisabledAppUpdateService implements AppUpdateService {
  const DisabledAppUpdateService();
  @override
  bool get isAvailable => false;
  @override
  Future<AppUpdateCheck> checkForUpdate({bool requestSignIn = false}) async =>
      const AppUpdateCheck();
  @override
  Future<void> installUpdate() async {}
}
