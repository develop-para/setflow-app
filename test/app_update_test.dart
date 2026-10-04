import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/services/app_update_controller.dart';
import 'package:setflow/services/app_update_service.dart';
import 'package:setflow/services/app_version_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/app_update_tile.dart';

class FakeUpdates implements AppUpdateService {
  @override
  bool isAvailable = true;
  AppUpdateCheck result = const AppUpdateCheck(needsSignIn: true);
  AppUpdateException? failure;
  Completer<AppUpdateCheck>? pending;
  final requests = <bool>[];
  int installs = 0;
  @override
  Future<AppUpdateCheck> checkForUpdate({bool requestSignIn = false}) async {
    requests.add(requestSignIn);
    if (failure != null) throw failure!;
    return pending == null ? result : pending!.future;
  }

  @override
  Future<void> installUpdate() async {
    installs++;
    if (failure != null) throw failure!;
  }
}

const newRelease = AppRelease(
  version: '1.21.0',
  build: 1234,
  notes: '새 기능을 추가했어요.',
);

const installedVersion = InstalledAppVersion(
  version: '1.20.0',
  buildNumber: '1200',
);

class FakeVersions implements AppVersionService {
  InstalledAppVersion? result = installedVersion;
  Object? failure;
  Completer<InstalledAppVersion?>? pending;
  int reads = 0;

  @override
  Future<InstalledAppVersion?> readInstalledVersion() async {
    reads++;
    if (failure case final Object error) throw error;
    return pending == null ? result : pending!.future;
  }
}

void main() {
  late FakeUpdates service;
  late AppUpdateController updates;
  late FakeVersions versions;
  setUp(() {
    service = FakeUpdates();
    versions = FakeVersions();
    updates = AppUpdateController(service, versionService: versions);
    AppUpdates.instance = updates;
  });

  test('설치 버전은 업데이트 계정 연결 없이 한 번만 읽는다', () async {
    service.isAvailable = false;
    versions.pending = Completer<InstalledAppVersion?>();
    final first = updates.loadInstalledVersion();
    final second = updates.loadInstalledVersion();
    expect(updates.versionLoading, isTrue);
    expect(versions.reads, 1);
    expect(service.requests, isEmpty);
    versions.pending!.complete(installedVersion);
    await Future.wait([first, second]);
    await updates.loadInstalledVersion();
    expect(versions.reads, 1);
    expect(updates.installedVersion!.label, '1.20.0 (1200)');
    expect(updates.versionLoading, isFalse);
  });

  test('버전 조회 실패 후 다시 읽을 수 있고 업데이트 확인은 계속 동작한다', () async {
    versions.failure = StateError('metadata unavailable');
    await updates.loadInstalledVersion();
    expect(updates.installedVersion, isNull);
    expect(updates.versionChecked, isTrue);
    expect(updates.versionLoading, isFalse);
    service.result = const AppUpdateCheck(release: newRelease);
    await updates.check();
    expect(updates.release, newRelease);
    versions.failure = null;
    await updates.loadInstalledVersion(force: true);
    expect(updates.installedVersion, installedVersion);
    expect(versions.reads, 2);
  });

  test('설치 버전 조회가 끝나기 전에 컨트롤러를 닫아도 알림을 보내지 않는다', () async {
    final pending = Completer<InstalledAppVersion?>();
    final reader = FakeVersions()..pending = pending;
    final controller = AppUpdateController(service, versionService: reader);
    final operation = controller.loadInstalledVersion();
    controller.dispose();
    pending.complete(installedVersion);
    await operation;
    expect(controller.installedVersion, isNull);
  });
  tearDown(() {
    AppUpdates.instance = AppUpdateController(const DisabledAppUpdateService());
    updates.dispose();
  });

  test('자동 조회는 로그인 창을 열지 않고 재개 연속 호출을 제한한다', () async {
    await updates.check();
    await updates.check();
    expect(service.requests, [false]);
    expect(updates.needsSignIn, isTrue);
    expect(updates.checked, isFalse);
    await updates.check(interactive: true);
    expect(service.requests, [false, true]);
  });

  test('조회 중 중복 호출과 설치를 막는다', () async {
    service.pending = Completer<AppUpdateCheck>();
    final first = updates.check();
    await updates.check(interactive: true);
    await updates.install();
    expect(service.requests, [false]);
    expect(service.installs, 0);
    service.pending!.complete(const AppUpdateCheck(release: newRelease));
    await first;
    expect(updates.release, newRelease);
    expect(updates.busy, isFalse);
  });

  test('조회 실패를 최신 버전으로 표시하지 않고 수동으로 재시도할 수 있다', () async {
    service.result = const AppUpdateCheck();
    await updates.check();
    expect(updates.checked, isTrue);
    service.failure = const AppUpdateException('인터넷 연결을 확인해주세요.');
    await updates.check(interactive: true);
    expect(updates.checked, isFalse);
    expect(updates.error, '인터넷 연결을 확인해주세요.');
    service.failure = null;
    service.result = const AppUpdateCheck(release: newRelease);
    await updates.check(interactive: true);
    expect(updates.release, newRelease);
    expect(updates.error, isNull);
  });

  test('계정 연결과 설치 취소는 오류나 설치 완료로 표시하지 않는다', () async {
    service.failure = const AppUpdateException('취소', cancelled: true);
    await updates.check(interactive: true);
    expect(updates.error, isNull);
    expect(updates.checked, isFalse);
    service.failure = null;
    service.result = const AppUpdateCheck(release: newRelease);
    await updates.check(interactive: true);
    service.failure = const AppUpdateException('취소', cancelled: true);
    await updates.install();
    expect(updates.error, isNull);
    expect(updates.release, newRelease);
    expect(updates.busy, isFalse);
  });

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: screen),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('게스트와 사업자 설정에서 업데이트 화면으로 들어간다', (tester) async {
    for (final screen in [
      const SettingsScreen(),
      const BusinessSettingsListScreen(role: UserRole.trainer),
    ]) {
      await pumpScreen(tester, screen);
      expect(find.text('현재 버전 1.20.0 (1200)'), findsOneWidget);
      await tester.tap(find.text('앱 업데이트'));
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdateScreen), findsOneWidget);
      expect(find.text('계정 연결하고 확인'), findsOneWidget);
      expect(find.text('현재 설치 버전'), findsOneWidget);
      expect(find.text('1.20.0 (1200)'), findsOneWidget);
      expect(service.requests.every((interactive) => !interactive), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('홈은 새 버전만 안내하고 자동 팝업이나 설치를 하지 않는다', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: HomeScreen(onOpenRecord: () {}, onOpenCommunity: () {}),
      ),
    );
    expect(find.text('새 버전 1.21.0'), findsNothing);
    service.result = const AppUpdateCheck(release: newRelease);
    await updates.check();
    await tester.pump();
    expect(find.text('새 버전 1.21.0'), findsOneWidget);
    expect(find.byType(AppUpdateScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.installs, 0);
  });

  testWidgets('연결 후 새 버전과 변경 내용을 보여주고 누를 때만 설치한다', (tester) async {
    await pumpScreen(tester, const AppUpdateScreen());
    service.result = const AppUpdateCheck(release: newRelease);
    await tester.tap(find.text('계정 연결하고 확인'));
    await tester.pumpAndSettle();
    expect(service.requests, [false, true]);
    expect(find.text(newRelease.notes!), findsOneWidget);
    expect(service.installs, 0);
    await tester.tap(find.text('업데이트'));
    await tester.pumpAndSettle();
    expect(service.installs, 1);
    expect(find.text('새 버전 1.21.0 (1234)'), findsOneWidget);
    expect(find.text('1.20.0 (1200)'), findsOneWidget);
  });

  testWidgets('업데이트를 지원하지 않는 빌드에서도 설치 버전은 볼 수 있다', (tester) async {
    service.isAvailable = false;
    await pumpScreen(tester, const SettingsScreen());
    expect(find.text('앱 업데이트'), findsNothing);
    expect(find.text('앱 버전'), findsOneWidget);
    expect(find.text('현재 버전 1.20.0 (1200)'), findsOneWidget);
    await tester.tap(find.text('앱 버전'));
    await tester.pumpAndSettle();
    expect(find.text('1.20.0 (1200)'), findsOneWidget);
    expect(find.text('이 빌드는 앱 안에서 업데이트를 지원하지 않아요.'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await updates.check(interactive: true);
    expect(service.requests, isEmpty);
  });

  testWidgets('버전 정보를 읽지 못하면 가짜 버전을 쓰지 않고 다시 확인한다', (tester) async {
    versions.failure = StateError('metadata unavailable');
    await pumpScreen(tester, const AppUpdateScreen());
    expect(find.text('확인할 수 없어요'), findsOneWidget);
    expect(find.text('계정 연결하고 확인'), findsOneWidget);
    versions.failure = null;
    await tester.tap(find.text('버전 다시 확인'));
    await tester.pumpAndSettle();
    expect(find.text('1.20.0 (1200)'), findsOneWidget);
    expect(find.text('버전 다시 확인'), findsNothing);
    expect(service.requests, [false]);
  });

  testWidgets('작은 화면과 큰 글씨에서 오류와 재시도 버튼에 닿을 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
            padding: const EdgeInsets.only(bottom: 28),
          ),
          child: child!,
        ),
        home: const AppUpdateScreen(),
      ),
    );
    await tester.pumpAndSettle();
    service.failure = const AppUpdateException('인터넷 연결을 확인해주세요.');
    await tester.scrollUntilVisible(find.byType(FilledButton), 200);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('인터넷 연결을 확인해주세요.'), findsOneWidget);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomRight(find.byType(FilledButton)).dy,
      lessThanOrEqualTo(540),
    );
  });
}
