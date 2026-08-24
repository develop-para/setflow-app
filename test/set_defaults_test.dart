import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// The ⋮ menu's 세트 기본값: what a newly added exercise starts with.
///
/// Precedence is the point. A default the user typed in must beat the goal
/// prescription (explicit beats inferred), but must lose to what they actually
/// lifted last time — history is more accurate than any preset.
void main() {
  Future<AppState> freshState() async {
    final state = AppState();
    await state.initialize();
    // 목표가 있으면 처방이 우선순위 비교 대상이 된다 — 테스트가 그 비교를
    // 하려면 목표부터 있어야 한다.
    state.setMemberProfile(goals: const ['근육 증가']);
    return state;
  }

  test(
    'a chosen default beats the prescription for a fresh exercise',
    () async {
      final state = await freshState();
      addTearDown(state.dispose);
      state.setDefaultSetPlan(sets: 5, reps: 12);

      final date = DateTime(2026, 11, 3);
      final template = state.exercises.firstWhere((e) => !e.isCardio);
      state.addExercise(date, template);

      final exercise = state.sessions[state.dateOnly(date)]!.exercises.single;
      expect(exercise.sets, hasLength(5), reason: '기본 세트 수가 처방에 밀렸다');
      expect(exercise.sets.first.reps, 12, reason: '기본 횟수가 처방에 밀렸다');
    },
  );

  test(
    'history still beats the default — last time is more accurate',
    () async {
      final state = await freshState();
      addTearDown(state.dispose);
      final template = state.exercises.firstWhere((e) => !e.isCardio);

      // 지난 세션: 실제로 3세트 8회를 들었다.
      final before = DateTime(2026, 11, 1);
      state.addExercise(before, template);
      final past = state.sessions[state.dateOnly(before)]!.exercises.single;
      for (final set in past.sets) {
        state.updateSet(set, weight: 60, reps: 8);
        state.toggleSet(set, startRest: false);
      }

      state.setDefaultSetPlan(sets: 5, reps: 12);
      final date = DateTime(2026, 11, 3);
      state.addExercise(date, template);

      final exercise = state.sessions[state.dateOnly(date)]!.exercises.single;
      // 추천 엔진은 지난 기록을 복사하지 않고 다음 단계를 처방한다(8회를
      // 들었으면 더 무겁게 6회, 같은 식). 여기서 고정할 것은 정확한 숫자가
      // 아니라 우선순위다: 기록 기반 추천이 있으면 기본값(12회)은 물러난다.
      expect(
        exercise.sets.first.reps,
        isNot(12),
        reason: '이전 기록이 있으면 추천이 기본값보다 앞서야 한다',
      );
      expect(
        exercise.sets.first.weight,
        greaterThan(0),
        reason: '추천이 지난 무게에서 출발하지 않았다',
      );
    },
  );

  test('the defaults survive a snapshot round trip', () {
    AppSnapshot roundTrip({int? sets, int? reps}) {
      final snapshot = AppSnapshot(
        role: UserRole.member,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        defaultSetCount: sets,
        defaultRepCount: reps,
        sessions: const {},
        routines: const [],
      );
      return AppSnapshotCodec.decode(
        AppSnapshotCodec.encode(snapshot),
        const [],
      )!;
    }

    final decoded = roundTrip(sets: 4, reps: 15);
    expect(decoded.defaultSetCount, 4);
    expect(decoded.defaultRepCount, 15);

    // 정한 적 없음(null)도 그대로 남아야 한다 — null이 3으로 굳으면
    // "정하지 않았다"가 사라진다.
    final cleared = roundTrip();
    expect(cleared.defaultSetCount, isNull);
    expect(cleared.defaultRepCount, isNull);
  });

  testWidgets('the sheet edits the values the next exercise is born with', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = await freshState();
    addTearDown(state.dispose);
    final date = DateTime(2026, 11, 5);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: date),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('기록 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('세트 기본값'));
    await tester.pumpAndSettle();

    // 3세트 → 4세트, 10회 → 12회.
    await tester.tap(find.byTooltip('세트 수 늘리기'));
    await tester.pump();
    await tester.tap(find.byTooltip('횟수 늘리기'));
    await tester.pump();
    await tester.tap(find.byTooltip('횟수 늘리기'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('set-defaults-apply')));
    await tester.pumpAndSettle();

    expect(state.defaultSetCount, 4);
    expect(state.defaultRepCount, 12);

    final template = state.exercises.firstWhere((e) => !e.isCardio);
    state.addExercise(date, template);
    final exercise = state.sessions[state.dateOnly(date)]!.exercises.single;
    expect(exercise.sets, hasLength(4));
    expect(exercise.sets.first.reps, 12);

    // 저장 디바운스를 흘려보낸다.
    await tester.pump(const Duration(milliseconds: 400));
  });
}
