import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// 맨몸운동은 무게가 없다. 푸시업에 무게 다이얼을 주면 남는 일은 0을
/// 타이핑하는 것뿐이고, 플랭크는 횟수조차 없다 — 버틴 시간이 기록이다.
/// 종목이 자기 측정 방식을 선언하고, 세트 행이 그 방식대로만 그려지는지 본다.
void main() {
  final date = DateTime(2026, 11, 5);

  ExerciseTemplate byId(String id) =>
      exerciseCatalog.firstWhere((exercise) => exercise.id == id);

  Future<AppState> pumpDay(
    WidgetTester tester,
    ExerciseTemplate template,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, template);

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
    return state;
  }

  WorkoutExercise exerciseOf(AppState state) =>
      state.sessions[state.dateOnly(date)]!.exercises.single;

  group('catalog declares measurements', () {
    test('plank holds, pushup counts, bench weighs', () {
      expect(byId('plank').measurement, ExerciseMeasurement.duration);
      expect(byId('pushup').measurement, ExerciseMeasurement.repsOnly);
      expect(byId('bench').measurement, ExerciseMeasurement.weightReps);
      // 새로 들어온 맨몸 종목들.
      expect(byId('wall_sit').measurement, ExerciseMeasurement.duration);
      expect(byId('burpee').measurement, ExerciseMeasurement.repsOnly);
    });

    test('bodyweight sets are seeded without a fake barbell', () async {
      final state = AppState();
      await state.initialize();
      state.addExercise(date, byId('pushup'));
      final pushup = state.sessions[state.dateOnly(date)]!.exercises.single;
      expect(pushup.sets.first.weight, 0);
      expect(pushup.sets.first.reps, greaterThan(0));

      state.addExercise(date, byId('plank'));
      final plank = state.sessions[state.dateOnly(date)]!.exercises.last;
      expect(plank.sets.first.durationSeconds, greaterThan(0));
      expect(plank.sets.first.reps, 0);
      state.dispose();
    });
  });

  group('reps-only row', () {
    testWidgets('has no weight dial, folds to reps alone', (tester) async {
      final state = await pumpDay(tester, byId('pushup'));
      expect(find.byKey(const ValueKey('inline-set-weight-1')), findsNothing);
      expect(find.byKey(const ValueKey('inline-set-reps-1')), findsOneWidget);

      final set = exerciseOf(state).sets.first;
      state.updateSet(set, reps: 15);
      await state.toggleSet(set, startRest: false);
      await tester.pumpAndSettle();
      // 완료 줄에는 "0kg × 15회"가 아니라 횟수만 남는다. (요약 바의 볼륨
      // "0kg"은 세트 줄이 아니므로 × 패턴으로만 잡는다.)
      expect(find.text('15회'), findsOneWidget);
      expect(find.textContaining('kg ×'), findsNothing);
      // 저장 디바운스 타이머를 비운다.
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('duration row', () {
    testWidgets('shows a time dial instead of reps', (tester) async {
      final state = await pumpDay(tester, byId('plank'));
      expect(find.byKey(const ValueKey('inline-set-weight-1')), findsNothing);
      expect(find.byKey(const ValueKey('inline-set-reps-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('inline-set-duration-1')),
        findsOneWidget,
      );

      final set = exerciseOf(state).sets.first;
      state.updateSet(set, durationSeconds: 95);
      await state.toggleSet(set, startRest: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('1분 35초'), findsWidgets);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a logged hold time propagates to the waiting sets', (
      tester,
    ) async {
      final state = await pumpDay(tester, byId('plank'));
      final exercise = exerciseOf(state);
      while (exercise.sets.length < 3) {
        state.addSet(exercise);
      }
      final first = exercise.sets.first;
      state.updateSet(first, durationSeconds: 120);
      await state.toggleSet(first, startRest: false);
      state.adoptActualIntoPendingSets(exercise, first);
      expect(exercise.sets[1].durationSeconds, 120);
      expect(exercise.sets[2].durationSeconds, 120);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('custom exercises', () {
    test('carry their measurement through the snapshot', () async {
      final state = AppState();
      await state.initialize();
      final created = state.createCustomExercise(
        name: '한손 플랭크',
        muscle: '복근',
        measurement: ExerciseMeasurement.duration,
      );
      expect(created, isNotNull);

      final encoded = AppSnapshotCodec.toJson(
        AppSnapshot(
          role: UserRole.guest,
          isDarkMode: false,
          weightUnit: 'kg',
          restDefaultSeconds: 90,
          sessions: const {},
          routines: const [],
          customExercises: state.customExercises,
        ),
      );
      final decoded = AppSnapshotCodec.fromJson(encoded, exerciseCatalog)!;
      final restored = decoded.customExercises.single;
      expect(restored.measurement, ExerciseMeasurement.duration);
      state.dispose();
    });

    test('cardio custom exercises ignore the measurement choice', () async {
      final state = AppState();
      await state.initialize();
      final created = state.createCustomExercise(
        name: '계단 오르기',
        muscle: '유산소',
        measurement: ExerciseMeasurement.duration,
      );
      // 유산소는 자체 구간 UI가 우선 — measurement는 기본값으로 남는다.
      expect(created!.measurement, ExerciseMeasurement.weightReps);
      expect(created.isCardio, isTrue);
      state.dispose();
    });
  });
}
