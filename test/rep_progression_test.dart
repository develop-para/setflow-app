import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/services/resistance_prescription_engine.dart';
import 'package:setflow/services/workout_time_budget.dart';
import 'package:setflow/theme.dart';

final day = DateTime(2026, 10, 4);
final bench = exerciseCatalog.firstWhere((item) => item.id == 'bench');
WorkoutSession record({
  int daysAgo = 2,
  List<int> reps = const [10, 9, 8],
  int? rir = 2,
  int rest = 120,
  double weight = 50,
  bool partial = false,
  ExerciseTemplate? template,
}) => WorkoutSession(
  date: day.subtract(Duration(days: daysAgo)),
  exercises: [
    WorkoutExercise(
      id: 'actual-$daysAgo',
      template: template ?? bench,
      sets: [
        for (var index = 0; index < reps.length; index++)
          WorkoutSetEntry(
            number: index + 1,
            weight: weight,
            reps: reps[index],
            rir: rir,
            restSeconds: rest,
            completed: !partial || index < reps.length - 1,
          ),
      ],
    ),
  ],
);
WorkoutRecommendation prescribe(
  List<WorkoutSession> history, {
  ExerciseTemplate? template,
  RecommendationProfile? profile,
}) => ResistancePrescriptionEngine.prescribe(
  template: template ?? bench,
  goal: TrainingGoal.hypertrophy,
  history: history,
  session: WorkoutSession(date: day, exercises: []),
  profile: profile,
);

void main() {
  test('per-set repetitions advance instead of resetting to lower bound', () {
    final result = prescribe([record()]);
    expect(result.weight, 50);
    expect(result.targetRepsBySet, [11, 10, 9]);
    expect(result.minReps, 8);
    expect(result.maxReps, 12);
    expect(result.summary, contains('11 / 10 / 9'));
  });
  test(
    'optional RIR allows progression; failure effort holds actual targets',
    () {
      expect(prescribe([record(rir: null)]).targetRepsBySet, [11, 10, 9]);
      for (final rir in [0, 1, 11]) {
        expect(prescribe([record(rir: rir)]).targetRepsBySet, [10, 9, 8]);
      }
    },
  );
  test('partial records and changing rests do not trigger increases', () {
    expect(prescribe([record(partial: true)]).targetRepsBySet, [10, 9, 9]);
    expect(
      prescribe([
        record(reps: [10]),
      ]).targetRepsBySet,
      [10, 10, 10],
    );
    expect(
      prescribe([record(), record(daysAgo: 9, rest: 90)]).targetRepsBySet,
      [10, 9, 8],
    );
  });
  test('recent declining performance holds rather than adding repetitions', () {
    expect(
      prescribe([
        record(),
        record(daysAgo: 9, reps: [11, 10, 9]),
      ]).targetRepsBySet,
      [10, 9, 8],
    );
  });
  test(
    'upper-bound confirmation increases load and resets repetition targets',
    () {
      final result = prescribe([
        record(reps: [12, 12, 12]),
        record(daysAgo: 9, reps: [12, 12, 12]),
      ]);
      expect(result.weight, 52.5);
      expect(result.targetRepsBySet, [8, 8, 8]);
      final partial = prescribe([
        record(reps: [12, 12, 12, 12], partial: true),
        record(daysAgo: 9, reps: [12, 12, 12]),
      ]);
      expect(partial.weight, 50);
      expect(partial.targetRepsBySet, [12, 12, 12]);
    },
  );
  test(
    'recovery reduction and long pause take priority over repetition growth',
    () {
      final tired = prescribe(
        [record()],
        profile: RecommendationProfile(
          experienceLevel: TrainingExperienceLevel.intermediate,
          availableEquipment: TrainingEquipment.values,
          painRegions: const [],
          painLevel: 0,
          restrictedMovements: const [],
          injuryNote: '',
          recoveryRecordedAt: day,
          updatedAt: day,
          recoveryStatus: TrainingRecoveryStatus.fatigued,
        ),
      );
      expect(tired.weight, 45);
      expect(tired.targetRepsBySet, [8, 8]);
      expect(prescribe([record(daysAgo: 30)]).targetRepsBySet, [8, 8]);
    },
  );
  test(
    'bodyweight progression uses own records and never invents kilograms',
    () {
      final pushup = exerciseCatalog.firstWhere((item) => item.id == 'pushup');
      final result = prescribe([
        record(template: pushup, weight: 0),
      ], template: pushup);
      expect(result.weight, 0);
      expect(result.targetRepsBySet, [11, 10, 9]);
    },
  );
  test('future and warmup records cannot change targets', () {
    final future = record(daysAgo: -2, reps: [12, 12, 12]);
    final warmup = record();
    for (final set in warmup.exercises.single.sets) {
      set.type = '웜업';
    }
    final result = prescribe([future, warmup]);
    expect(result.weight, 0);
    expect(result.targetRepsBySet, [8, 8, 8]);
  });
  test(
    'manual, recommended, and apply paths preserve individual set targets',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: ['근육 증가']);
      final historical = record();
      state.sessions[historical.date] = historical;
      state.addExercise(day, bench);
      expect(
        state.sessionFor(day).exercises.single.sets.map((set) => set.reps),
        [11, 10, 9],
      );
      state.sessions.remove(day);
      final next = ExerciseRecommendationEngine.recommendFirst(
        catalog: [bench],
        session: WorkoutSession(date: day, exercises: []),
        goals: state.goals,
        weeklyHistory: state.sessions.values,
      )!;
      expect(next.targetRepsBySet, [11, 10, 9]);
      state.addRecommendedExercise(day, next);
      final exercise = state.sessionFor(day).exercises.single;
      expect(exercise.sets.map((set) => set.reps), [11, 10, 9]);
      exercise.sets.first.completed = true;
      exercise.sets.first.reps = 7;
      state.applyRecommendation(day, prescribe([historical]));
      expect(exercise.sets.map((set) => set.reps), [7, 10, 9]);
    },
  );
  test(
    'personal routine adapts on application while stored and coach plans remain intact',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: ['근육 증가']);
      state.setPersonalCoaching(enabled: true);
      final historical = record();
      state.sessions[historical.date] = historical;
      final plans = [
        const RoutineSetPlan(number: 1, weight: 20, reps: 12, type: '웜업'),
        for (var index = 0; index < 3; index++)
          RoutineSetPlan(number: index + 2, weight: 30, reps: 8),
      ];
      RoutineData routine({String? trainer}) => RoutineData(
        id: 'my',
        name: '루틴',
        description: '',
        color: RoutineData.defaultColor,
        exercises: [bench],
        setPlans: {bench.id: plans},
        authorTrainerId: trainer,
      );
      state.applyRoutine(routine(), day);
      expect(
        state.sessionFor(day).exercises.single.sets.map((set) => set.reps),
        [12, 11, 10, 9],
      );
      expect(plans.map((set) => set.weight), [20, 30, 30, 30]);
      state.sessions.remove(day);
      state.applyRoutine(routine(trainer: 'trainer'), day);
      expect(
        state.sessionFor(day).exercises.single.sets.map((set) => set.weight),
        [20, 30, 30, 30],
      );
    },
  );
  test(
    'time budget counts actual targets, so longer repetition work cannot overfill',
    () {
      final session = WorkoutSession(
        date: day,
        exercises: [],
        timeBudgetMinutes: 8,
      );
      final count = WorkoutTimeBudget.fittingSets(
        session: session,
        template: bench,
        sets: 3,
        reps: 8,
        targetRepsBySet: [20, 20, 20],
        restSeconds: 120,
      );
      expect(count, 2);
    },
  );
  for (final small in [false, true]) {
    testWidgets(
      'recommendation displays and registers real targets (small=$small)',
      (tester) async {
        await tester.binding.setSurfaceSize(
          small ? const Size(320, 700) : const Size(432, 1000),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final state = AppState();
        addTearDown(state.dispose);
        await state.initialize();
        state.sessions.clear();
        state.exercises
          ..clear()
          ..add(bench);
        state.setMemberProfile(goals: ['근육 증가']);
        state.markPrecisionRecommendationPrompted();
        final historical = record();
        state.sessions[historical.date] = historical;
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: small ? SetflowTheme.dark : SetflowTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
                child: child!,
              ),
              home: DailyWorkoutScreen(date: day),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('운동 선택'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('training-focus-chest')),
        );
        await tester.tap(find.byKey(const ValueKey('training-focus-chest')));
        await tester.ensureVisible(
          find.byKey(const ValueKey('training-focus-apply')),
        );
        await tester.tap(find.byKey(const ValueKey('training-focus-apply')));
        await tester.pumpAndSettle();
        expect(find.textContaining('11 / 10 / 9회'), findsWidgets);
        final add = find.text('추천 운동 추가');
        await tester.ensureVisible(add);
        await tester.tap(add);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(
          state.sessionFor(day).exercises.single.sets.map((set) => set.reps),
          [11, 10, 9],
        );
        if (!small) {
          final first = find.byKey(const ValueKey('inline-set-weight-1'));
          await tester.ensureVisible(first);
          await tester.drag(first, const Offset(400, 0));
          await tester.pumpAndSettle();
          state.cancelRestTimer();
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();
          expect(
            state.sessionFor(day).exercises.single.sets.first.completed,
            isTrue,
          );
          expect(
            state.sessionFor(day).exercises.single.sets.map((set) => set.reps),
            [11, 10, 9],
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
