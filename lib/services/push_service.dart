/// 푸시 알림 포트.
///
/// 화면도 AppState도 Firebase를 모른다. 지금 배달부는 FCM이지만 EC2로 옮기면
/// 다른 것이 될 수 있고, 그때 바뀌어야 하는 파일은 어댑터 하나여야 한다.
/// 그래서 여기에는 벤더 타입이 하나도 없다 — 토큰은 그냥 문자열이다.
abstract interface class PushService {
  /// 이 기기에서 푸시가 가능한가. iOS에 설정 파일이 없거나 초기화가 실패하면
  /// false — 그때는 앱이 조용히 푸시 없이 동작해야 한다.
  bool get isAvailable;

  /// 알림 권한을 요청하고 허용 여부를 돌려준다. 안드로이드 13+와 iOS 모두
  /// 사용자가 거절할 수 있다.
  Future<bool> requestPermission();

  /// 이 기기의 발송 토큰. 권한이 없거나 초기화 전이면 null.
  Future<String?> currentToken();

  /// 토큰이 갱신될 때마다 흘려보낸다. FCM은 앱 재설치·복원·주기적 회전으로
  /// 토큰을 바꾸므로, 한 번 등록하고 끝내면 언젠가 조용히 배달이 멈춘다.
  Stream<String> get tokenChanges;

  /// 이 기기의 토큰을 지운다. 로그아웃할 때 부른다 — 안 지우면 다음 사람에게
  /// 남의 알림이 간다.
  Future<void> deleteToken();
}

/// 푸시를 쓸 수 없는 자리에서 쓰는 빈 구현.
///
/// 테스트와, Firebase 설정이 없는 플랫폼(지금은 iOS)이 여기로 떨어진다.
/// null을 다루는 분기를 호출부마다 만들지 않기 위한 것이다.
class DisabledPushService implements PushService {
  const DisabledPushService();

  @override
  bool get isAvailable => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> currentToken() async => null;

  @override
  Stream<String> get tokenChanges => const Stream<String>.empty();

  @override
  Future<void> deleteToken() async {}
}

/// 앱 어디서나 쓰는 단일 진입점. [AuthService]의 `Auth.instance`와 같은 모양이다.
abstract final class Push {
  static PushService _instance = const DisabledPushService();

  static PushService get instance => _instance;

  /// 조립 지점(main.dart)에서만 부른다.
  static void bind(PushService service) => _instance = service;
}
