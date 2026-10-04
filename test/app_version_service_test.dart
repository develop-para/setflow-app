import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:setflow/services/package_info_app_version_service.dart';

void main() {
  void installedPackage({required String version, String build = ''}) {
    PackageInfo.setMockInitialValues(
      appName: 'Setflow',
      packageName: 'com.teampara.setflow',
      version: version,
      buildNumber: build,
      buildSignature: '',
    );
  }

  test('설치 패키지의 버전과 배포 빌드 번호를 읽는다', () async {
    installedPackage(version: '9.4.2', build: '777');
    final result = await const PackageInfoAppVersionService()
        .readInstalledVersion();
    expect(result!.version, '9.4.2');
    expect(result.buildNumber, '777');
    expect(result.label, '9.4.2 (777)');
  });

  test('빌드 번호가 없으면 버전만 표시하고 없는 버전을 만들지 않는다', () async {
    installedPackage(version: ' 9.4.2 ');
    final result = await const PackageInfoAppVersionService()
        .readInstalledVersion();
    expect(result!.label, '9.4.2');
    installedPackage(version: '');
    expect(
      await const PackageInfoAppVersionService().readInstalledVersion(),
      isNull,
    );
  });
}
