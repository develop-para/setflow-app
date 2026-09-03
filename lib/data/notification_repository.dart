import '../services/push_service.dart';

/// 사용자에게 도착한 알림 하나. 알림창에서 지워졌어도 여기엔 남는다.
///
/// 서버가 보낸 것과 같은 어휘를 쓴다([kind]와 [data]) — 그래야 알림함에서
/// 누른 것이 시스템 알림을 누른 것과 **정확히 같은 곳**으로 간다. 목적지를
/// 두 벌로 관리하면 반드시 어긋난다.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.data = const {},
    this.readAt,
  });

  final String id;

  /// 설정 스위치 단위의 종류(`coaching_feedback` `together` `account` 등).
  final String kind;
  final String title;
  final String body;
  final Map<String, String> data;
  final DateTime createdAt;

  /// 읽은 시각. null이면 아직 안 읽었다.
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  /// 어떤 사건인지. 같은 [kind] 안에서 화면을 가르는 값이다.
  String? get event => data['event'];

  /// 탭했을 때 쓸 이동 정보. 푸시를 탭한 것과 같은 경로를 태우기 위한 것이다.
  PushOpen toPushOpen() => PushOpen(kind: kind, data: data);

  AppNotification copyWith({DateTime? readAt}) => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    data: data,
    readAt: readAt ?? this.readAt,
  );
}

/// 알림함 포트.
///
/// 앱 아이콘의 배지는 시스템 알림창에 남은 알림 수라서, 알림을 밀어 지우면
/// 배지만 남고 앱에는 흔적이 없었다. 이 포트가 그 흔적을 돌려준다.
abstract interface class NotificationRepository {
  /// 최신순. 계정이 없으면 빈 목록 — 알림은 계정에 붙는다.
  Future<List<AppNotification>> listNotifications({int limit = 100});

  /// 안 읽은 알림 수. 목록 전체를 받아 세는 것보다 싸다.
  Future<int> unreadCount();

  /// 하나를 읽음으로 표시한다. 이미 읽은 것은 시각을 덮어쓰지 않는다.
  Future<void> markRead(String id);

  /// 남은 것을 전부 읽음으로. 목록 화면의 "모두 읽음"이 부른다.
  Future<void> markAllRead();
}
