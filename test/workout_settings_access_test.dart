import 'package:flutter/material.dart';
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
  for (final dark in [false, true]) {
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
}
