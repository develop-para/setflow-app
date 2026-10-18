import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

final _day = DateTime(2026, 10, 14);

Future<AppState> _pump(WidgetTester tester, {required bool dark}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  state.sessions.clear();
  state.setMemberProfile(goals: []);
  state.setAutoRecommendNextExercise(false);
  state.setDefaultSetPlan(sets: 2, reps: 8);
  state.setRestDefaultSeconds(90);
  state.addExercise(
    _day,
    state.exercises.firstWhere((exercise) => exercise.id == 'bench'),
  );
  final set = state.sessionFor(_day).exercises.single.sets.first;
  state.updateSet(set, weight: 60, reps: 8, rir: 2);
  set.completed = true;
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: dark ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 24, bottom: 28),
          ),
          child: child!,
        ),
        home: DailyWorkoutScreen(date: _day),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openMenuItem(WidgetTester tester, String key) async {
  await _tap(tester, find.byTooltip('기록 메뉴'));
  await _tap(tester, find.byKey(ValueKey(key)));
}

void main() {
  const timerChannel = MethodChannel('com.teampara.setflow/rest_timer');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final timerCalls = <MethodCall>[];
  var overlaySupported = true;
  var overlayEnabled = false;
  var overlayPermissionGranted = false;

  setUp(() {
    overlaySupported = true;
    overlayEnabled = true;
    overlayPermissionGranted = false;
    timerCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(timerChannel, (
      call,
    ) async {
      timerCalls.add(call);
      return switch (call.method) {
        'overlayStatus' =>
          overlaySupported
              ? {
                  'enabled': overlayEnabled,
                  'permissionGranted': overlayPermissionGranted,
                }
              : null,
        'notificationStatus' => true,
        'openOverlaySettings' => true,
        'setOverlayEnabled' =>
          overlayEnabled = (call.arguments as Map)['enabled'] as bool,
        _ => null,
      };
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(timerChannel, null);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'rest timer settings are reachable without interrupting recording at 2x ($dark)',
      (tester) async {
        final state = await _pump(tester, dark: dark);
        final set = state.sessionFor(_day).exercises.single.sets.last;
        await state.toggleSet(set);
        await tester.pumpAndSettle();
        final before = AppSnapshotCodec.sessionToJson(state.sessionFor(_day));
        final timerSession = state.restSessionId;
        expect(state.restRemaining, greaterThan(0));
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          timerCalls.where((call) => call.method == 'openOverlaySettings'),
          isEmpty,
        );
        timerCalls.clear();

        await _openMenuItem(tester, 'daily-rest-timer-settings');
        final overlay = find.byKey(
          const ValueKey('setting-rest-timer-overlay'),
        );
        final close = find.byKey(const ValueKey('rest-timer-settings-close'));
        expect(find.text('휴식 타이머'), findsOneWidget);
        expect(tester.widget<SwitchListTile>(overlay).value, isFalse);
        expect(
          find.byKey(const ValueKey('setting-rest-timer-notifications')),
          findsOneWidget,
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          timerCalls.map((call) => call.method),
          unorderedEquals(['overlayStatus', 'notificationStatus']),
        );

        await _tap(tester, overlay);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          timerCalls.where((call) => call.method == 'openOverlaySettings'),
          isEmpty,
        );
        await _tap(tester, find.text('권한 설정'));
        expect(
          timerCalls.where((call) => call.method == 'openOverlaySettings'),
          hasLength(1),
        );
        expect(overlayEnabled, isTrue);
        expect(tester.widget<SwitchListTile>(overlay).value, isFalse);
        overlayPermissionGranted = true;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(overlay).value, isTrue);
        expect(overlayEnabled, isTrue);

        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(close.hitTestable(), findsOneWidget);
        expect(tester.getRect(close).bottom, lessThanOrEqualTo(700 - 28));
        expect(tester.takeException(), isNull);
        await _tap(tester, close);
        expect(overlay, findsNothing);
        expect(AppSnapshotCodec.sessionToJson(state.sessionFor(_day)), before);
        expect(state.defaultSetCount, 2);
        expect(state.defaultRepCount, 8);
        expect(state.restDefaultSeconds, 90);
        expect(state.restSessionId, timerSession);
        expect(
          timerCalls.where(
            (call) => call.method == 'start' || call.method == 'cancel',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        state.cancelRestTimer();
        await tester.pump();
      },
    );

    testWidgets(
      'record settings remain reachable with recommendation off at 2x ($dark)',
      (tester) async {
        final state = await _pump(tester, dark: dark);
        final recorded = state.sessionFor(_day).exercises.single;
        final before = AppSnapshotCodec.sessionToJson(state.sessionFor(_day));
        await _openMenuItem(tester, 'daily-recommendation-settings');

        final toggle = find.byKey(const ValueKey('recommendation-auto-toggle'));
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(find.text('다음 운동 추천'), findsNothing);
        expect(find.text('오늘의 첫 운동 추천'), findsNothing);
        expect(state.autoRecommendNextExercise, isFalse);
        await _tap(
          tester,
          find.byKey(const ValueKey('recommendation-time-30')),
        );
        expect(state.sessionFor(_day).timeBudgetMinutes, 30);
        expect(state.autoRecommendNextExercise, isFalse);
        expect(state.sessionFor(_day).exercises.single, same(recorded));
        final changed = AppSnapshotCodec.sessionToJson(state.sessionFor(_day));
        expect(changed['exercises'], before['exercises']);

        await _tap(tester, toggle);
        expect(state.autoRecommendNextExercise, isTrue);
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        expect(find.text('다음 운동 추천'), findsNothing);
        await _tap(tester, toggle);
        expect(state.autoRecommendNextExercise, isFalse);
        await _tap(tester, find.text('닫기'));
        expect(find.text('추천 OFF'), findsOneWidget);

        await _tap(tester, find.byTooltip('기록 메뉴'));
        expect(find.text('오늘 30분 · 추천 설정'), findsOneWidget);
        await _tap(
          tester,
          find.byKey(const ValueKey('daily-recommendation-settings')),
        );
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('recommendation-time-30')),
              )
              .selected,
          isTrue,
        );
        await _tap(tester, find.text('닫기'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'set defaults scroll to apply and cancel leaves recorded values intact at 2x ($dark)',
      (tester) async {
        final state = await _pump(tester, dark: dark);
        final before = AppSnapshotCodec.sessionToJson(state.sessionFor(_day));
        await _openMenuItem(tester, 'daily-set-defaults');
        await _tap(tester, find.byTooltip('세트 수 늘리기'));
        await _tap(tester, find.byTooltip('횟수 늘리기'));
        await _tap(tester, find.byTooltip('휴식 늘리기'));
        expect(state.defaultSetCount, 2);
        expect(state.defaultRepCount, 8);
        expect(state.restDefaultSeconds, 90);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(state.defaultSetCount, 2);
        expect(state.defaultRepCount, 8);
        expect(state.restDefaultSeconds, 90);

        await _openMenuItem(tester, 'daily-set-defaults');
        await _tap(tester, find.byTooltip('세트 수 늘리기'));
        await _tap(tester, find.byTooltip('횟수 늘리기'));
        await _tap(tester, find.byTooltip('휴식 늘리기'));
        final apply = find.byKey(const ValueKey('set-defaults-apply'));
        await tester.ensureVisible(apply);
        await tester.pumpAndSettle();
        expect(apply.hitTestable(), findsOneWidget);
        expect(tester.getRect(apply).bottom, lessThanOrEqualTo(700 - 28));
        expect(tester.takeException(), isNull);
        await _tap(tester, apply);
        expect(state.defaultSetCount, 3);
        expect(state.defaultRepCount, 9);
        expect(state.restDefaultSeconds, 105);
        expect(AppSnapshotCodec.sessionToJson(state.sessionFor(_day)), before);

        state.setMemberProfile(goals: ['근력 향상']);
        state.addExercise(
          _day,
          state.exercises.firstWhere((exercise) => exercise.id == 'curl'),
        );
        final newSets = state.sessionFor(_day).exercises.last.sets;
        expect(newSets, hasLength(3));
        expect(newSets.map((set) => set.reps), everyElement(9));
        expect(
          newSets.map((set) => set.restSeconds),
          everyElement(105),
          reason: '운동 목표가 있어도 직접 추가한 새 운동은 사용자가 고른 휴식을 따른다',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unsupported hosts hide the optional floating timer control', (
    tester,
  ) async {
    overlaySupported = false;
    final state = await _pump(tester, dark: false);
    final before = AppSnapshotCodec.sessionToJson(state.sessionFor(_day));

    await _openMenuItem(tester, 'daily-rest-timer-settings');

    expect(find.text('휴식 타이머'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('setting-rest-timer-overlay')),
      findsNothing,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      timerCalls.where((call) => call.method == 'openOverlaySettings'),
      isEmpty,
    );
    await _tap(tester, find.byKey(const ValueKey('rest-timer-settings-close')));
    expect(AppSnapshotCodec.sessionToJson(state.sessionFor(_day)), before);
    expect(tester.takeException(), isNull);
  });
}
