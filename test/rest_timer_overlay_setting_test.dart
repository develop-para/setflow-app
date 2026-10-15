import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';
import 'package:setflow/widgets/rest_timer_overlay_setting.dart';

void main() {
  const channel = MethodChannel('com.teampara.setflow/rest_timer');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var supported = true;
  var enabled = false;
  var permissionGranted = false;
  var failSave = false;
  var failSettings = false;
  Completer<Map<String, Object?>?>? nextStatus;

  setUp(() {
    supported = true;
    enabled = false;
    permissionGranted = false;
    failSave = false;
    failSettings = false;
    nextStatus = null;
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'overlayStatus':
          final delayed = nextStatus;
          nextStatus = null;
          if (delayed != null) return delayed.future;
          return supported
              ? {'enabled': enabled, 'permissionGranted': permissionGranted}
              : null;
        case 'setOverlayEnabled':
          if (failSave) throw PlatformException(code: 'save_failed');
          enabled = (call.arguments as Map)['enabled'] as bool;
          return null;
        case 'openOverlaySettings':
          return !failSettings;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  final tile = find.byKey(const ValueKey('setting-rest-timer-overlay'));

  Future<void> launch(
    WidgetTester tester, {
    Widget content = const RestTimerOverlaySetting(),
    double textScale = 1,
  }) async {
    await binding.setSurfaceSize(const Size(432, 900));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: content)),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      AppSnackbar.dismiss();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await binding.setSurfaceSize(null);
    });
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

  Future<void> requestPermission(WidgetTester tester) async {
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(calls.where((call) => call.method == 'setOverlayEnabled'), isEmpty);
    expect(
      calls.where((call) => call.method == 'openOverlaySettings'),
      isEmpty,
    );
    await tester.tap(find.text('권한 설정'));
    await tester.pumpAndSettle();
  }

  testWidgets('supported host starts off and only reads status on entry', (
    tester,
  ) async {
    await launch(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('다른 앱 위에 타이머'), findsOneWidget);
    expect(find.text('앱을 나가도 남은 휴식과 운동 복귀 버튼을 보여줘요.'), findsOneWidget);
    expect(calls.map((call) => call.method), ['overlayStatus']);
  });

  testWidgets('unsupported hosts hide the setting', (tester) async {
    supported = false;
    await launch(tester);
    expect(tile, findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('granted permission enables directly and disabling keeps timer', (
    tester,
  ) async {
    permissionGranted = true;
    await launch(tester);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      calls.where((call) => call.method == 'openOverlaySettings'),
      isEmpty,
    );

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(calls.where((call) => call.method == 'cancel'), isEmpty);
    expect(
      calls
          .where((call) => call.method == 'setOverlayEnabled')
          .map((call) => (call.arguments as Map)['enabled']),
      [true, false],
    );
  });

  testWidgets('only returning with granted permission enables the overlay', (
    tester,
  ) async {
    await launch(tester);
    await requestPermission(tester);
    expect(enabled, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(
      calls.where((call) => call.method == 'openOverlaySettings').length,
      1,
    );
    permissionGranted = true;
    await returnFromSettings(tester);
    expect(enabled, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets(
    'returning after Android enabled the overlay avoids another save',
    (tester) async {
      await launch(tester);
      await requestPermission(tester);
      permissionGranted = true;
      enabled = true;

      await returnFromSettings(tester);

      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      expect(
        calls.where((call) => call.method == 'setOverlayEnabled'),
        isEmpty,
      );
    },
  );

  testWidgets('denied permission stays off with guidance', (tester) async {
    await launch(tester);
    await requestPermission(tester);
    await returnFromSettings(tester);
    expect(enabled, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(calls.where((call) => call.method == 'setOverlayEnabled'), isEmpty);
    expect(
      find.text('다른 앱 위에 표시 권한이 필요해요. 다시 켜서 권한 설정을 열어주세요.'),
      findsOneWidget,
    );
    // 거절한 의도는 끝난다. 나중의 앱 복귀가 몰래 설정을 켜면 안 된다.
    permissionGranted = true;
    await returnFromSettings(tester);
    expect(enabled, isFalse);
  });

  testWidgets('cancelling explanation never opens Android settings', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(
      calls.where((call) => call.method == 'openOverlaySettings'),
      isEmpty,
    );
    expect(calls.where((call) => call.method == 'setOverlayEnabled'), isEmpty);
  });

  testWidgets('failed native save reports failure without changing switch', (
    tester,
  ) async {
    permissionGranted = true;
    failSave = true;
    await launch(tester);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(enabled, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('타이머 표시 설정을 변경하지 못했어요.'), findsOneWidget);
  });

  testWidgets('failed permission settings launch remains off with feedback', (
    tester,
  ) async {
    failSettings = true;
    await launch(tester);
    await requestPermission(tester);
    expect(enabled, isFalse);
    expect(find.text('권한 설정을 열지 못했어요. 다시 시도해주세요.'), findsOneWidget);
    permissionGranted = true;
    await returnFromSettings(tester);
    expect(enabled, isFalse);
  });

  testWidgets('revoked permission looks off and offers recovery', (
    tester,
  ) async {
    enabled = true;
    await launch(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(
      find.text('다른 앱 위에 표시 권한이 필요해요. 다시 켜서 권한 설정을 열어주세요.'),
      findsOneWidget,
    );
    await requestPermission(tester);
    permissionGranted = true;
    await returnFromSettings(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('failed resume status reload reports feedback', (tester) async {
    await launch(tester);
    supported = false;
    await returnFromSettings(tester);
    expect(find.text('타이머 표시 설정을 확인하지 못했어요.'), findsOneWidget);
  });

  testWidgets('a late status response cannot undo a saved switch change', (
    tester,
  ) async {
    permissionGranted = true;
    await launch(tester);
    final delayed = Completer<Map<String, Object?>?>();
    nextStatus = delayed;
    await returnFromSettings(tester);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(enabled, isTrue);

    delayed.complete({'enabled': false, 'permissionGranted': true});
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(enabled, isTrue);
  });

  testWidgets('a newer resume response wins over an older response', (
    tester,
  ) async {
    permissionGranted = true;
    await launch(tester);
    final delayed = Completer<Map<String, Object?>?>();
    nextStatus = delayed;
    await returnFromSettings(tester);
    enabled = true;
    await returnFromSettings(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    delayed.complete({'enabled': false, 'permissionGranted': true});
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  });

  testWidgets('permission settings disable duplicate enable requests', (
    tester,
  ) async {
    await launch(tester);
    await requestPermission(tester);

    expect(tester.widget<SwitchListTile>(tile).onChanged, isNull);

    await returnFromSettings(tester);
    expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
    permissionGranted = true;
    await returnFromSettings(tester);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(enabled, isTrue);
  });

  testWidgets('notification settings expose the control to guests', (
    tester,
  ) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await binding.setSurfaceSize(const Size(432, 1400));
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
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tile, findsOneWidget);
    expect(find.text('로그인'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await binding.setSurfaceSize(null);
  });

  testWidgets('large text grows the setting without overflow', (tester) async {
    await launch(tester, textScale: 2);
    expect(tile, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
