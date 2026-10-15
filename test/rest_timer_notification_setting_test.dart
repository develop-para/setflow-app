import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';
import 'package:setflow/widgets/rest_timer_notification_setting.dart';

void main() {
  const channel = MethodChannel('com.teampara.setflow/rest_timer');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final tile = find.byKey(const ValueKey('setting-rest-timer-notifications'));
  final calls = <MethodCall>[];
  bool? allowed;
  var settingsOpened = true;
  Completer<bool?>? nextStatus;
  Completer<bool>? nextSettings;

  setUp(() {
    allowed = false;
    settingsOpened = true;
    nextStatus = null;
    nextSettings = null;
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'notificationStatus':
          final delayed = nextStatus;
          nextStatus = null;
          return delayed == null ? allowed : delayed.future;
        case 'openNotificationSettings':
          final delayed = nextSettings;
          nextSettings = null;
          return delayed == null ? settingsOpened : delayed.future;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<AppState> launch(
    WidgetTester tester, {
    bool enabled = true,
    bool settingsScreen = false,
  }) async {
    await binding.setSurfaceSize(const Size(432, 900));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final state = AppState();
    await state.initialize();
    state.setRestTimerNotifications(enabled);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: settingsScreen
              ? const SettingDetailScreen(section: SettingSection.notifications)
              : const Scaffold(body: RestTimerNotificationSetting()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    addTearDown(() async {
      AppSnackbar.dismiss();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      state.dispose();
      await binding.setSurfaceSize(null);
    });
    return state;
  }

  Future<void> returnFromSettings(WidgetTester tester) async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  int settingsLaunches() =>
      calls.where((call) => call.method == 'openNotificationSettings').length;

  testWidgets('진입은 권한 상태만 읽고 팝업 없이 실제 표시 상태를 보여준다', (tester) async {
    final state = await launch(tester);

    expect(state.restTimerNotifications, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.textContaining('기기에서 알림을 허용해야 해요.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls.map((call) => call.method), ['notificationStatus']);
  });

  testWidgets('이미 허용된 기기에서는 설정을 열지 않고 켜고 끈다', (tester) async {
    allowed = true;
    final state = await launch(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(state.restTimerNotifications, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(state.restTimerNotifications, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(settingsLaunches(), 0);
    expect(calls.where((call) => call.method == 'cancel'), isEmpty);
  });

  testWidgets('직접 켤 때만 알림 설정을 한 번 열고 허용 후 켜짐을 표시한다', (tester) async {
    final state = await launch(tester, enabled: false);
    await tester.tap(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(settingsLaunches(), 1);
    expect(state.restTimerNotifications, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);
    allowed = true;
    await returnFromSettings(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
    expect(settingsLaunches(), 1);
  });

  testWidgets('허용하지 않고 돌아오면 꺼짐과 권한 안내를 유지한다', (tester) async {
    final state = await launch(tester, enabled: false);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await returnFromSettings(tester);

    expect(state.restTimerNotifications, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
    expect(find.textContaining('기기에서 알림을 허용해야 해요.'), findsOneWidget);
    expect(settingsLaunches(), 1);
  });

  testWidgets('지원하지 않는 기기는 기존 앱 설정만 켜고 끈다', (tester) async {
    allowed = null;
    final state = await launch(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(state.restTimerNotifications, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(state.restTimerNotifications, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(settingsLaunches(), 0);
  });

  testWidgets('설정 열기 실패는 안내하고 재시도할 수 있다', (tester) async {
    settingsOpened = false;
    await launch(tester, enabled: false);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('알림 설정을 열지 못했어요. 다시 시도해주세요.'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
    settingsOpened = true;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(settingsLaunches(), 2);
  });

  testWidgets('늦은 권한 조회가 복귀 후 허용된 상태를 덮지 않는다', (tester) async {
    await launch(tester, enabled: false);
    final stale = Completer<bool?>();
    nextStatus = stale;
    await returnFromSettings(tester);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    allowed = true;
    await returnFromSettings(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    stale.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(settingsLaunches(), 1);
  });

  testWidgets('닫힌 화면의 권한 조회 응답은 상태를 바꾸지 않는다', (tester) async {
    final pending = Completer<bool?>();
    nextStatus = pending;
    await launch(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('설정 열기 대기 중 화면이 닫혀도 뒤늦은 오류 안내를 띄우지 않는다', (tester) async {
    await launch(tester, enabled: false);
    final pending = Completer<bool>();
    nextSettings = pending;
    await tester.tap(tile);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('게스트 알림 설정에 종료 알림 스위치를 연결한다', (tester) async {
    await launch(tester, settingsScreen: true);
    expect(tile, findsOneWidget);
    expect(find.text('로그인'), findsNothing);
    expect(settingsLaunches(), 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
