import 'package:package_info_plus/package_info_plus.dart';

import 'app_version_service.dart';

class PackageInfoAppVersionService implements AppVersionService {
  const PackageInfoAppVersionService();

  @override
  Future<InstalledAppVersion?> readInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    if (version.isEmpty) return null;
    return InstalledAppVersion(
      version: version,
      buildNumber: info.buildNumber.trim(),
    );
  }
}
