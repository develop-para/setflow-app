import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/services/push_service.dart';
import 'package:setflow/theme.dart';

/// 푸시 등록의 규칙들.
///
/// 이 두 스위치는 오래도록 값만 저장하고 보낼 곳이 없었다. 이제 서버가 보내므로
/// **누구에게 붙느냐**가 중요해졌다 — 토큰이 잘못된 계정에 남으면 다음 사람이
/// 남의 알림을 받는다.
void main() {
  setUp(() => Push.bind(const DisabledPushService()));
  tearDown(() => Push.bind(const DisabledPushService()));

  group('PushService 포트', () {
    test('꺼진 구현은 아무것도 약속하지 않는다', () async {
      const service = DisabledPushService();
      expect(service.isAvailable, isFalse);
      expect(await service.requestPermission(), isFalse);
      expect(await service.currentToken(), isNull);
      expect(await service.tokenChanges.toList(), isEmpty);
    });

    test('bind 하기 전 기본값은 꺼진 구현이다 — 초기화 실패가 앱을 죽이지 않는다', () {
      expect(Push.instance.isAvailable, isFalse);
    });
  });

  group('알림 설정', () {
    Future<void> pumpNotifications(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const SettingDetailScreen(
              section: SettingSection.notifications,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('푸시를 못 쓰는 기기에는 켤 수 있다고 말하지 않는다', (tester) async {
      await pumpNotifications(tester);
      // 켜 놓고 안 오는 것이 가장 나쁘다.
      expect(
        find.byKey(const ValueKey('setting-push-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('setting-push-coaching')), findsNothing);
      expect(
        find.byKey(const ValueKey('setting-push-community')),
        findsNothing,
      );
    });

    testWidgets('푸시를 쓸 수 있으면 두 스위치가 돌아온다', (tester) async {
      Push.bind(_FakePush(token: 'token-1'));
      await pumpNotifications(tester);
      expect(
        find.byKey(const ValueKey('setting-push-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('setting-push-coaching')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('setting-push-community')),
        findsOneWidget,
      );
    });
  });

  group('토큰 등록', () {
    test('푸시를 못 쓰면 서버를 부르지 않는다', () async {
      final repository = _RecordingRepository();
      final state = AppState(repository: repository);
      await state.initialize();
      addTearDown(state.dispose);

      await state.syncPushRegistration();
      expect(repository.registered, isEmpty);
    });

    test('권한을 거절하면 등록하지 않는다', () async {
      // 거절한 사람의 토큰을 서버에 남기면 보낼 수 없는 곳으로 계속 쏜다.
      Push.bind(_FakePush(token: 'token-1', granted: false));
      final repository = _RecordingRepository();
      final state = AppState(repository: repository);
      await state.initialize();
      addTearDown(state.dispose);

      await state.syncPushRegistration();
      expect(repository.registered, isEmpty);
    });

    test('로그아웃은 화면을 먼저 비운다 — 토큰 해제가 그것을 밀어내면 안 된다', () async {
      // 토큰 해제를 logout() 첫 줄에 두면 역할 초기화가 await 뒤로 밀려,
      // 로그아웃을 누른 뒤에도 한 틱 동안 이전 역할의 셸이 남는다.
      final signOut = Completer<void>();
      Push.bind(_FakePush(token: 'token-1'));
      final state = AppState(
        repository: _RecordingRepository(),
        authSignOut: () => signOut.future,
      );
      addTearDown(state.dispose);
      await state.initialize();
      state.chooseRole(UserRole.trainer);
      expect(state.role, UserRole.trainer);

      final logout = state.logout();
      // await 없이 곧바로 — 초기화는 동기여야 한다.
      expect(state.role, UserRole.guest);
      signOut.complete();
      await logout;
    });

    test('로그인하지 않았으면 등록하지 않는다 — 붙일 계정이 없다', () async {
      Push.bind(_FakePush(token: 'token-1'));
      final repository = _RecordingRepository();
      final state = AppState(repository: repository);
      await state.initialize();
      addTearDown(state.dispose);

      // 테스트 환경에는 인증된 사용자가 없다.
      await state.syncPushRegistration();
      expect(repository.registered, isEmpty);
    });
  });
}

class _FakePush implements PushService {
  _FakePush({required this.token, this.granted = true});

  final String? token;
  final bool granted;
  final _refresh = StreamController<String>.broadcast();
  bool deleted = false;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get tokenChanges => _refresh.stream;

  @override
  Future<void> deleteToken() async => deleted = true;

  @override
  Stream<PushOpen> get opens => const Stream<PushOpen>.empty();

  @override
  Future<PushOpen?> initialOpen() async => null;
}

class _RecordingRepository implements AppRepository, PushTokenRegistry {
  final registered = <({String token, String platform})>[];
  final unregistered = <String>[];

  @override
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async => registered.add((token: token, platform: platform));

  @override
  Future<void> unregisterPushToken(String token) async =>
      unregistered.add(token);

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async =>
      null;

  @override
  Future<void> save(AppSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}
}
