class InstalledAppVersion {
  const InstalledAppVersion({required this.version, this.buildNumber = ''});

  final String version;
  final String buildNumber;

  String get label => buildNumber.isEmpty ? version : '$version ($buildNumber)';
}

/// Installed package metadata is independent of the update provider/account.
abstract interface class AppVersionService {
  Future<InstalledAppVersion?> readInstalledVersion();
}

class UnavailableAppVersionService implements AppVersionService {
  const UnavailableAppVersionService();

  @override
  Future<InstalledAppVersion?> readInstalledVersion() async => null;
}
