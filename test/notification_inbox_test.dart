import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/notification_repository.dart';
import 'package:setflow/screens/notification_screen.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

/// 알림함. 런처 배지는 시스템 알림창이 세는 것이라, 알림을 밀어 지우면 배지만
/// 남고 앱에는 흔적이 없었다("알림 표기가 있는 것 같은데 들어가면 무슨 알림인지
/// 모르겠네"). 이 화면이 그 흔적이므로, 여기서 지켜야 할 것들을 잡는다.
void main() {
  setUp(() => Auth.use(_SignedInAuth()));
  tearDown(Auth.reset);

  AppNotification sample({
    String id = '1',
    String kind = 'coaching_feedback',
    String title = '트레이너 답변이 도착했어요',
    Map<String, String> data = const {'event': 'consultation_reply'},
    bool read = false,
    Duration age = const Duration(minutes: 5),
  }) {
    return AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: '상담 내용을 확인해주세요.',
      data: data,
      createdAt: DateTime.now().subtract(age),
      readAt: read ? DateTime.now() : null,
    );
  }

  Future<AppState> pumpInbox(
    WidgetTester tester,
    _FakeNotifications repository,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(notificationRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const NotificationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // AppState의 저장 디바운스(250ms)가 아직 걸려 있으면 위젯 트리가 사라진
    // 뒤 "pending timer"로 깨진다.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    return state;
  }

  test('알림함이 없으면 목록은 비고 조작은 조용히 넘어간다', () async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    await state.refreshNotifications();

    expect(state.notifications, isEmpty);
    expect(state.unreadNotificationCount, 0);
    await state.markNotificationRead('1');
    await state.markAllNotificationsRead();
  });

  test('읽음 표시는 화면이 먼저 바뀌고 서버가 뒤따른다', () async {
    final repository = _FakeNotifications([
      sample(id: '1'),
      sample(id: '2', read: true),
    ]);
    final state = AppState(notificationRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    await state.refreshNotifications();
    expect(state.unreadNotificationCount, 1);

    await state.markNotificationRead('1');

    expect(state.notifications.first.isUnread, isFalse);
    expect(state.unreadNotificationCount, 0);
    expect(repository.readIds, ['1']);

    // 이미 읽은 것을 다시 눌러도 서버를 부르지 않는다 — 처음 읽은 시각이 남아야 한다.
    await state.markNotificationRead('2');
    expect(repository.readIds, ['1']);
  });

  test('모두 읽음은 안 읽은 것이 있을 때만 서버를 부른다', () async {
    final repository = _FakeNotifications([sample(id: '1', read: true)]);
    final state = AppState(notificationRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    await state.refreshNotifications();

    await state.markAllNotificationsRead();
    expect(repository.markedAll, 0);

    repository.items = [sample(id: '2')];
    await state.refreshNotifications();
    await state.markAllNotificationsRead();
    expect(repository.markedAll, 1);
    expect(state.unreadNotificationCount, 0);
  });

  test('로그아웃하면 알림함이 비워진다', () async {
    final repository = _FakeNotifications([sample()]);
    final state = AppState(notificationRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    await state.refreshNotifications();
    expect(state.notifications, isNotEmpty);

    Auth.use(_SignedOutAuth());
    await state.logout();

    expect(state.notifications, isEmpty, reason: '남의 알림이 다음 사람에게 보인다');
    expect(state.unreadNotificationCount, 0);
  });

  test('서버가 실패해도 앱의 다른 부분은 건드리지 않는다', () async {
    final repository = _FakeNotifications([], failing: true);
    final state = AppState(notificationRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);

    await state.refreshNotifications();

    expect(state.notificationsError, isNotNull);
    expect(state.notificationsLoading, isFalse);
    expect(state.cloudSyncError, isNull, reason: '알림 실패가 홈을 오류로 덮었다');
  });

  test('알림은 푸시와 같은 이동 정보를 낸다', () {
    final notification = sample(
      kind: 'community_reaction',
      data: const {'event': 'post_like', 'postId': 'p1'},
    );

    final open = notification.toPushOpen();

    expect(open.kind, 'community_reaction');
    expect(open.event, 'post_like');
    expect(open.data['postId'], 'p1');
  });

  test('언제 왔는지는 사람 말로 적는다', () {
    final now = DateTime(2026, 9, 3, 12);
    String at(Duration ago) =>
        relativeNotificationTime(now.subtract(ago), now: now);

    expect(at(const Duration(seconds: 30)), '방금');
    expect(at(const Duration(minutes: 5)), '5분 전');
    expect(at(const Duration(hours: 3)), '3시간 전');
    expect(at(const Duration(days: 2)), '2일 전');
    expect(at(const Duration(days: 30)), '8월 4일');
  });

  testWidgets('목록은 안 읽은 것을 표시하고 모두 읽음이 그것을 지운다', (tester) async {
    final repository = _FakeNotifications([
      sample(id: '1', title: '트레이너 답변이 도착했어요'),
      sample(id: '2', title: '함께 운동 방이 시작됐어요', kind: 'together', read: true),
    ]);
    final state = await pumpInbox(tester, repository);

    expect(find.text('트레이너 답변이 도착했어요'), findsOneWidget);
    expect(find.text('함께 운동 방이 시작됐어요'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notifications-mark-all')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('notifications-mark-all')));
    await tester.pumpAndSettle();

    expect(state.unreadNotificationCount, 0);
    expect(
      find.byKey(const ValueKey('notifications-mark-all')),
      findsNothing,
      reason: '읽을 것이 없는데 "모두 읽음"이 남아 있다',
    );
  });

  testWidgets('누르면 읽음이 되고 알림함을 닫으면서 같은 곳으로 보낸다', (tester) async {
    final repository = _FakeNotifications([sample(id: '7')]);
    final state = await pumpInbox(tester, repository);

    await tester.tap(find.text('트레이너 답변이 도착했어요'));
    await tester.pumpAndSettle();

    expect(repository.readIds, ['7']);
    expect(
      state.pendingPushOpen?.event,
      'consultation_reply',
      reason: '알림함에서 누른 것이 푸시와 다른 곳으로 갔다',
    );
  });

  testWidgets('게스트에게는 빈 목록이 아니라 로그인 안내가 보인다', (tester) async {
    Auth.use(_SignedOutAuth());
    final repository = _FakeNotifications([]);
    await pumpInbox(tester, repository);

    expect(find.text('로그인하면 알림이 쌓여요'), findsOneWidget);
    expect(repository.listCalls, 0, reason: '계정이 없는데 서버에 알림을 물었다');
  });

  testWidgets('받은 알림이 없으면 그렇게 말한다', (tester) async {
    await pumpInbox(tester, _FakeNotifications([]));
    expect(find.text('받은 알림이 없어요'), findsOneWidget);
  });
}

class _FakeNotifications implements NotificationRepository {
  _FakeNotifications(this.items, {this.failing = false});

  List<AppNotification> items;
  final bool failing;
  final List<String> readIds = [];
  int markedAll = 0;
  int listCalls = 0;

  @override
  Future<List<AppNotification>> listNotifications({int limit = 100}) async {
    listCalls++;
    if (failing) throw StateError('offline');
    return List.of(items);
  }

  @override
  Future<int> unreadCount() async {
    if (failing) throw StateError('offline');
    return items.where((item) => item.isUnread).length;
  }

  @override
  Future<void> markRead(String id) async => readIds.add(id);

  @override
  Future<void> markAllRead() async => markedAll++;
}

class _SignedInAuth implements AuthService {
  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => '테스터';

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedOutAuth implements AuthService {
  @override
  bool get hasAuthenticatedUser => false;

  @override
  String get currentDisplayName => '게스트';

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
