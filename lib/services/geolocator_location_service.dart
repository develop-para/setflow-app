import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models.dart';
import 'location_service.dart';

/// [LocationService]의 geolocator 어댑터. 플러그인을 아는 유일한 파일이다.
///
/// 정확도는 **낮음**으로 잡는다 — 근처 공개방은 몇백 미터 단위면 충분하고,
/// 낮은 정확도가 배터리와 권한 부담을 줄인다(안드로이드 COARSE로도 된다).
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  bool get isAvailable => !kIsWeb;

  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationUnavailable();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.deniedForever:
          return const LocationDenied(permanently: true);
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return const LocationDenied(permanently: false);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LocationFix(GeoPoint(position.latitude, position.longitude));
    } catch (error) {
      // 시간 초과·플랫폼 미지원·플러그인 오류 전부 "지금은 못 읽는다"다. 앱은
      // 위치 없이도 방을 만들고 코드로 들어갈 수 있어야 한다.
      debugPrint('위치를 읽지 못했습니다: $error');
      return const LocationUnavailable();
    }
  }

  @override
  Future<bool> isGranted() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (error) {
      debugPrint('설정을 열지 못했습니다: $error');
    }
  }
}
