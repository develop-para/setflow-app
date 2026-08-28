import '../models.dart';

/// 위치 포트.
///
/// 화면은 "지금 어디쯤인가"만 묻는다. 플러그인(geolocator)을 아는 파일은
/// 어댑터 하나뿐이다 — Supabase·Firebase와 같은 격리다. 위치는 **근처 공개방을
/// 찾는 데만** 쓰고, 서버에는 공개방을 열 때의 좌표만 남긴다.
abstract interface class LocationService {
  /// 이 빌드·플랫폼에서 위치를 읽을 수 있는가. 아니면 화면이 위치 관련
  /// 안내를 아예 내지 않는다.
  bool get isAvailable;

  /// 지금 위치. 권한이 없으면 묻고, 거절·꺼짐·실패는 [LocationResult]로
  /// 구분해 돌려준다 — 화면이 "허용해 주세요"와 "설정에서 켜 주세요"를 다르게
  /// 말해야 하기 때문이다.
  Future<LocationResult> current();

  /// 이미 허용돼 있는가 — **묻지 않고** 본다. 로비를 열 때마다 권한 창을
  /// 띄우면 안 되므로, 허용된 사람만 자동으로 근처 방을 불러온다.
  Future<bool> isGranted();

  /// 앱 설정 화면으로. "다시 묻지 않음"으로 거절한 사람이 되돌릴 유일한 길.
  Future<void> openSettings();
}

sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix(this.point);

  final GeoPoint point;
}

class LocationDenied extends LocationResult {
  const LocationDenied({required this.permanently});

  /// "다시 묻지 않음". 이때는 요청 대신 설정으로 보내야 한다.
  final bool permanently;
}

/// 위치 서비스가 꺼져 있거나 이 플랫폼이 지원하지 않는다.
class LocationUnavailable extends LocationResult {
  const LocationUnavailable();
}

/// 위치를 쓸 수 없는 자리에서 쓰는 빈 구현 — 테스트와 웹·데스크톱.
class DisabledLocationService implements LocationService {
  const DisabledLocationService();

  @override
  bool get isAvailable => false;

  @override
  Future<LocationResult> current() async => const LocationUnavailable();

  @override
  Future<bool> isGranted() async => false;

  @override
  Future<void> openSettings() async {}
}

/// 앱 어디서나 쓰는 단일 진입점. `Auth.instance` · `Push.instance`와 같은 모양.
abstract final class Location {
  static LocationService _instance = const DisabledLocationService();

  static LocationService get instance => _instance;

  /// 조립 지점(main.dart)과 테스트에서만 부른다.
  static void bind(LocationService service) => _instance = service;
}
