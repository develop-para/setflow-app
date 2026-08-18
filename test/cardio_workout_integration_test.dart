import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/evidence_catalog.dart';
import 'package:setflow/screens/business_routine_flow_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  ExerciseTemplate exerciseById(AppState state, String id) =>
      state.exercises.firstWhere((exercise) => exercise.id == id);

  Future<void> pumpDailyWorkout(
    WidgetTester tester, {
    required AppState state,
    required DateTime date,
  }) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
  }

  group('cardio workout state', () {
    test(
      'adding cardio creates time and RPE instead of lifting sets',
      () async {
        final state = AppState();
        addTearDown(state.dispose);
        await state.initialize();
        state.sessions.clear();
        state.setMemberProfile(goals: const ['체력 향상']);
        final date = DateTime(2026, 8, 17);

        state.addExercise(date, exerciseById(state, 'run'));

        final exercise = state.sessions[date]!.exercises.single;
        expect(exercise.template.isCardio, isTrue);
        expect(exercise.sets, hasLength(1));
        expect(exercise.sets.single.durationSeconds, 30 * 60);
        expect(exercise.sets.single.intensityRpe, inInclusiveRange(3, 4));
        expect(exercise.sets.single.weight, 0);
        expect(exercise.sets.single.reps, 0);
        expect(exercise.sets.single.restSeconds, 0);
        expect(
          exercise.sets.single.distanceKm,
          0,
          reason: '첫 기록에서 사용자의 속도를 임의로 추정하면 안 됩니다.',
        );
      },
    );

    test(
      'fat-loss and endurance next recommendations are time based',
      () async {
        for (final testCase in <({String goal, String id, int minutes})>[
          (goal: '체중 감량', id: 'brisk_walk', minutes: 40),
          (goal: '체력 향상', id: 'run', minutes: 30),
        ]) {
          final state = AppState();
          await state.initialize();
          state.sessions.clear();
          state.setMemberProfile(goals: [testCase.goal]);
          final date = DateTime(2026, 8, 17);
          state.addExercise(date, exerciseById(state, 'bench'));
          final bench = state.sessions[date]!.exercises.single;
          for (final set in bench.sets) {
            state.updateSet(set, weight: 80, reps: 8);
            state.toggleSet(set, startRest: false);
          }

          final recommendation = state.recommendationForDate(date)!;
          expect(recommendation.template.id, testCase.id);
          expect(recommendation.isCardio, isTrue);
          expect(recommendation.cardioDurationSeconds, testCase.minutes * 60);
          expect(recommendation.cardioDistanceKm, isNull);
          expect(recommendation.weight, 0);
          expect(recommendation.minReps, 0);
          expect(recommendation.maxReps, 0);
          expect(recommendation.prescriptionSummary('kg'), contains('분'));
          expect(
            recommendation.prescriptionSummary('kg'),
            isNot(contains('kg')),
          );

          state.applyRecommendation(date, recommendation);
          final applied = state.sessions[date]!.exercises.last;
          expect(applied.template.id, testCase.id);
          expect(applied.sets, hasLength(1));
          expect(applied.sets.single.durationSeconds, testCase.minutes * 60);
          expect(applied.sets.single.distanceKm, 0);
          expect(applied.sets.single.intensityRpe, inInclusiveRange(3, 4));
          expect(applied.sets.single.weight, 0);
          expect(applied.sets.single.reps, 0);
          expect(applied.sets.single.restSeconds, 0);
          state.dispose();
        }
      },
    );

    test(
      'cardio-only history can seed the next empty-day recommendation',
      () async {
        final state = AppState();
        addTearDown(state.dispose);
        await state.initialize();
        state.sessions.clear();
        state.setMemberProfile(goals: const ['건강 유지']);
        final historyDate = DateTime(2026, 8, 17);
        state.addExercise(historyDate, exerciseById(state, 'run'));
        final segment =
            state.sessions[historyDate]!.exercises.single.sets.single;
        state.updateSet(
          segment,
          durationSeconds: 30 * 60,
          distanceKm: 5,
          intensityRpe: 4,
        );
        state.toggleSet(segment, startRest: false);

        final recommendation = state.recommendationForDate(
          DateTime(2026, 8, 18),
        );

        expect(recommendation, isNotNull);
        expect(recommendation!.template.id, 'run');
        expect(recommendation.isCardio, isTrue);
        expect(recommendation.cardioDurationSeconds, 30 * 60);
        expect(recommendation.cardioDistanceKm, 5);
      },
    );

    test('next-card values match the added cardio segment', () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: const ['체중 감량']);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final historyDate = today.subtract(const Duration(days: 1));
      state.addExercise(historyDate, exerciseById(state, 'brisk_walk'));
      final segment = state.sessions[historyDate]!.exercises.single.sets.single;
      state.updateSet(
        segment,
        durationSeconds: 30 * 60,
        distanceKm: 5,
        intensityRpe: 4,
      );
      state.toggleSet(segment, startRest: false);

      state.addExercise(today, exerciseById(state, 'bench'));
      final session = state.sessions[today]!;
      final bench = session.exercises.single;
      for (final set in bench.sets) {
        state.updateSet(set, weight: 40, reps: 8);
        state.toggleSet(set, startRest: false);
      }

      final next = ExerciseRecommendationEngine.recommendNext(
        catalog: state.exercises,
        session: session,
        completedExercise: bench,
        goals: state.goals,
        weeklyHistory: state.sessions.values,
      )!;

      expect(next.template.id, 'brisk_walk');
      expect(next.cardioPrescription, isNotNull);
      expect(next.cardioPrescription!.targetDistanceKm, 6.7);

      expect(state.addRecommendedExercise(today, next), isTrue);
      final added = session.exercises.last.sets.single;
      expect(added.durationSeconds, next.cardioPrescription!.durationSeconds);
      expect(added.distanceKm, next.cardioPrescription!.targetDistanceKm);
      expect(added.intensityRpe, next.cardioPrescription!.minimumRpe);
      expect(added.weight, 0);
      expect(added.reps, 0);
    });

    test('RPE 1-2 cardio is excluded from WHO moderate minutes', () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: const ['체중 감량']);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      WorkoutSession cardioSession(String id, int minutes, double rpe) {
        return WorkoutSession(
          date: today,
          exercises: [
            WorkoutExercise(
              id: '$id-history',
              template: exerciseById(state, id),
              sets: [
                WorkoutSetEntry(
                  number: 1,
                  weight: 0,
                  reps: 0,
                  completed: true,
                  restSeconds: 0,
                  durationSeconds: minutes * 60,
                  intensityRpe: rpe,
                ),
              ],
            ),
          ],
        );
      }

      state.addExercise(today, exerciseById(state, 'bench'));
      final session = state.sessions[today]!;
      final bench = session.exercises.single;
      for (final set in bench.sets) {
        state.updateSet(set, weight: 40, reps: 8);
        state.toggleSet(set, startRest: false);
      }

      final next = ExerciseRecommendationEngine.recommendNext(
        catalog: state.exercises,
        session: session,
        completedExercise: bench,
        goals: state.goals,
        weeklyHistory: [
          session,
          cardioSession('brisk_walk', 30, 4),
          cardioSession('run', 60, 2),
          cardioSession('stationary_bike', 10, 7),
        ],
      )!;

      expect(next.cardioPrescription, isNotNull);
      expect(
        next.cardioPrescription!.completedModerateEquivalentMinutes,
        50,
        reason: 'RPE 2의 60분은 주간 중강도 환산 시간에 포함하면 안 됩니다.',
      );
    });
  });

  group('cardio inline editor', () {
    testWidgets('running shows time distance RPE but no lifting fields', (
      tester,
    ) async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      final date = DateTime(2026, 8, 17);
      state.addExercise(date, exerciseById(state, 'run'));

      await pumpDailyWorkout(tester, state: state, date: date);

      expect(find.byKey(const ValueKey('cardio-duration-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('cardio-distance-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('cardio-rpe-1')), findsOneWidget);
      expect(find.text('시간'), findsWidgets);
      expect(find.text('거리'), findsOneWidget);
      expect(find.text('강도'), findsOneWidget);
      expect(find.text('무게'), findsNothing);
      expect(find.text('횟수'), findsNothing);
      expect(find.text('휴식'), findsNothing);
      expect(find.textContaining('e1RM'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('stair climber does not expose a distance field', (
      tester,
    ) async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      final date = DateTime(2026, 8, 18);
      state.addExercise(date, exerciseById(state, 'stair_climber'));

      await pumpDailyWorkout(tester, state: state, date: date);

      expect(find.byKey(const ValueKey('cardio-duration-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('cardio-distance-1')), findsNothing);
      expect(find.byKey(const ValueKey('cardio-rpe-1')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('editing and completing cardio does not start a rest timer', (
      tester,
    ) async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      final date = DateTime(2026, 8, 19);
      state.addExercise(date, exerciseById(state, 'run'));
      final exercise = state.sessions[date]!.exercises.single;
      // Keep another interval pending so completion does not open the next-
      // exercise recommendation sheet during this editor-focused test.
      state.addSet(exercise);

      await pumpDailyWorkout(tester, state: state, date: date);

      await tester.enterText(
        find.byKey(const ValueKey('cardio-duration-1')),
        '42.5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('cardio-distance-1')),
        '7.25',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('cardio-rpe-1')), '6.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      final edited = exercise.sets.first;
      expect(edited.durationSeconds, 2550);
      expect(edited.distanceKm, 7.25);
      expect(edited.intensityRpe, 6.5);
      expect(state.restRemaining, 0);

      await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
      await tester.pump();

      expect(edited.completed, isTrue);
      expect(state.restRemaining, 0);
      expect(find.text('휴식 중'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  testWidgets(
    'trainer routine cardio row uses time distance RPE and deletes intervals',
    (tester) async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      const routine = OwnedCoachingRoutine(
        id: 'routine-cardio',
        trainerId: 'trainer-id',
        title: '러닝 루틴',
        status: BusinessRoutineStatus.draft,
        difficulty: BusinessRoutineDifficulty.intermediate,
        cumulativeUsers: 0,
        exercises: [
          OwnedRoutineExercise(
            id: 'routine-exercise-run',
            routineId: 'routine-cardio',
            baseExerciseId: 'run',
            name: '트레드밀 러닝',
            targetMuscle: '유산소',
            orderIndex: 0,
            sets: [
              OwnedRoutineSet(
                id: 'routine-set-run-1',
                exerciseId: 'routine-exercise-run',
                setNumber: 1,
                type: 'normal',
                restSeconds: 0,
                durationSeconds: 1200,
                distanceMeters: 3000,
                intensityRpe: 4,
              ),
              OwnedRoutineSet(
                id: 'routine-set-run-2',
                exerciseId: 'routine-exercise-run',
                setNumber: 2,
                type: 'normal',
                restSeconds: 0,
                durationSeconds: 600,
                distanceMeters: 1800,
                intensityRpe: 7,
              ),
            ],
          ),
        ],
      );

      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const BusinessRoutineEditorScreen(
              ownerRole: UserRole.trainer,
              routine: routine,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('시간'), findsNWidgets(2));
      expect(find.text('거리'), findsNWidgets(2));
      expect(find.text('강도'), findsNWidgets(2));
      expect(find.text('중량'), findsNothing);
      expect(find.text('횟수'), findsNothing);
      expect(find.text('휴식'), findsNothing);
      expect(find.byTooltip('구간 삭제'), findsNWidgets(2));

      await tester.tap(find.byTooltip('구간 삭제').first);
      await tester.pump();

      expect(find.text('1구간'), findsOneWidget);
      expect(find.text('2구간'), findsNothing);
      expect(find.byTooltip('구간 삭제'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  test('schema v10 round-trips cardio workout and routine metrics', () {
    const run = ExerciseTemplate(
      id: 'run',
      name: '트레드밀 러닝',
      muscle: '유산소',
      icon: Icons.directions_run,
    );
    final date = DateTime(2026, 8, 17);
    final snapshot = AppSnapshot(
      role: UserRole.member,
      isDarkMode: false,
      weightUnit: 'kg',
      restDefaultSeconds: 90,
      sessions: {
        date: WorkoutSession(
          date: date,
          exercises: [
            WorkoutExercise(
              id: 'run-session',
              template: run,
              sets: [
                WorkoutSetEntry(
                  number: 1,
                  weight: 0,
                  reps: 0,
                  completed: true,
                  restSeconds: 0,
                  durationSeconds: 2700,
                  distanceKm: 7.25,
                  intensityRpe: 6.5,
                ),
              ],
            ),
          ],
        ),
      },
      routines: [
        RoutineData(
          id: 'cardio-routine',
          name: '러닝 루틴',
          description: '시간 중심 유산소',
          color: Colors.teal,
          exercises: const [run],
          setPlans: const {
            'run': [
              RoutineSetPlan(
                number: 1,
                weight: 0,
                reps: 0,
                restSeconds: 0,
                durationSeconds: 1800,
                distanceKm: 5,
                intensityRpe: 4,
              ),
            ],
          },
        ),
      ],
    );

    final encoded = AppSnapshotCodec.encode(snapshot);
    expect(jsonDecode(encoded)['schemaVersion'], 10);
    final decoded = AppSnapshotCodec.decode(encoded, const [run])!;
    final workoutSet = decoded.sessions[date]!.exercises.single.sets.single;
    expect(workoutSet.durationSeconds, 2700);
    expect(workoutSet.distanceKm, 7.25);
    expect(workoutSet.intensityRpe, 6.5);
    expect(workoutSet.weight, 0);
    expect(workoutSet.reps, 0);
    final routineSet = decoded.routines.single.setsFor(run).single;
    expect(routineSet.durationSeconds, 1800);
    expect(routineSet.distanceKm, 5);
    expect(routineSet.intensityRpe, 4);
  });

  group('resistance estimate eligibility', () {
    const bench = ExerciseTemplate(
      id: 'bench',
      name: '바벨 벤치 프레스',
      muscle: '가슴',
      icon: Icons.fitness_center,
    );

    WorkoutSession history(List<WorkoutSetEntry> sets) => WorkoutSession(
      date: DateTime(2026, 8, 17),
      exercises: [
        WorkoutExercise(id: 'bench-history', template: bench, sets: sets),
      ],
    );

    test('11+ reps remain reference-only and do not seed recommendations', () {
      expect(
        PerformanceEngine.estimate(100, 11)!.quality,
        EstimateQuality.reference,
      );
      final onlyReference = history([
        WorkoutSetEntry(number: 1, weight: 100, reps: 11, completed: true),
      ]);

      expect(
        PerformanceEngine.summarize(sessions: [onlyReference], template: bench),
        isNull,
      );
      expect(
        PerformanceEngine.recommend(
          sessions: [onlyReference],
          template: bench,
          goal: TrainingGoal.hypertrophy,
        ),
        isNull,
      );
      expect(
        PerformanceEngine.prTypesForCandidate(
          sessions: const [],
          templateId: bench.id,
          candidate: WorkoutSetEntry(
            number: 1,
            weight: 100,
            reps: 11,
            completed: true,
          ),
        ),
        isNot(contains(PerformancePrType.estimatedOneRepMax)),
      );
    });

    test('only completed normal 1-10 rep sets feed e1RM and PR logic', () {
      final valid = WorkoutSetEntry(
        number: 1,
        weight: 100,
        reps: 10,
        completed: true,
      );
      final mixed = history([
        valid,
        WorkoutSetEntry(
          number: 2,
          weight: 180,
          reps: 5,
          completed: true,
          type: '드랍',
        ),
        WorkoutSetEntry(
          number: 3,
          weight: 170,
          reps: 5,
          completed: true,
          type: '실패',
        ),
        WorkoutSetEntry(
          number: 4,
          weight: 160,
          reps: 5,
          completed: true,
          type: '웜업',
        ),
      ]);

      final summary = PerformanceEngine.summarize(
        sessions: [mixed],
        template: bench,
      )!;
      expect(summary.weightPr.set, same(valid));
      expect(summary.e1rmPr.set, same(valid));

      for (final type in const ['드랍', '실패', '웜업']) {
        expect(
          PerformanceEngine.prTypesForCandidate(
            sessions: [mixed],
            templateId: bench.id,
            candidate: WorkoutSetEntry(
              number: 5,
              weight: 200,
              reps: 5,
              completed: true,
              type: type,
            ),
          ),
          isEmpty,
        );
      }
    });
  });

  test('every generated recommendation source resolves in the catalog', () {
    final unresolved = <String>{};
    for (final goal in TrainingGoal.values) {
      unresolved.addAll(
        PerformanceEngine.prescriptionFor(
          goal,
        ).evidenceIds.where((id) => !evidenceCatalogById.containsKey(id)),
      );
      for (final exerciseId in cardioExerciseDefinitions.keys) {
        final prescription = CardioPrescriptionEngine.recommend(
          exerciseId: exerciseId,
          goal: goal,
          history: const [],
        )!;
        unresolved.addAll(
          prescription.evidenceIds.where(
            (id) => !evidenceCatalogById.containsKey(id),
          ),
        );
      }
    }

    expect(unresolved, isEmpty);
  });
}
