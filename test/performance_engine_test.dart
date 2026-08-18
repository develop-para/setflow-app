import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';

void main() {
  const bench = ExerciseTemplate(
    id: 'bench',
    name: '바벨 벤치 프레스',
    muscle: '가슴',
    icon: Icons.fitness_center,
  );

  WorkoutSession session(
    DateTime date,
    List<(double, int)> values, {
    String id = 'bench_record',
    String type = '일반',
  }) {
    return WorkoutSession(
      date: date,
      exercises: [
        WorkoutExercise(
          id: id,
          template: bench,
          sets: [
            for (var index = 0; index < values.length; index++)
              WorkoutSetEntry(
                number: index + 1,
                weight: values[index].$1,
                reps: values[index].$2,
                completed: true,
                type: type,
              ),
          ],
        ),
      ],
    );
  }

  group('PerformanceEngine e1RM', () {
    test('averages Epley and Brzycki and assigns rep confidence', () {
      final estimate = PerformanceEngine.estimate(100, 8)!;

      expect(estimate.epley, closeTo(126.6667, .001));
      expect(estimate.brzycki, closeTo(124.1379, .001));
      expect(estimate.value, closeTo(125.4023, .001));
      expect(estimate.quality, EstimateQuality.medium);
      expect(PerformanceEngine.estimate(100, 5)!.quality, EstimateQuality.high);
      expect(
        PerformanceEngine.estimate(100, 12)!.quality,
        EstimateQuality.reference,
      );
      expect(PerformanceEngine.estimate(40, 16), isNull);
    });

    test('uses recent session bests and ignores invalid workout sets', () {
      final sessions = [
        session(DateTime(2026, 8, 1), [(100, 8), (40, 20)]),
        session(DateTime(2026, 8, 5), [(102.5, 7)]),
        session(DateTime(2026, 8, 10), [(102.5, 8)]),
        session(DateTime(2026, 8, 12), [(200, 1)], id: 'seed_12'),
        session(DateTime(2026, 8, 13), [(150, 5)], type: '웜업'),
      ];

      final summary = PerformanceEngine.summarize(
        sessions: sessions,
        template: bench,
      )!;

      expect(summary.sessionCount, 3);
      expect(summary.weightPr.set.weight, 102.5);
      expect(summary.repPr.set.reps, 8);
      expect(summary.currentE1rm, greaterThan(125));
      expect(summary.currentE1rm, lessThan(130));
      expect(summary.e1rmPr.date, DateTime(2026, 8, 10));
    });
  });

  group('PerformanceEngine training goal contract', () {
    test('maps all current and legacy profile goal labels', () {
      const cases = <String, TrainingGoal>{
        '근력 향상': TrainingGoal.strength,
        '근력': TrainingGoal.strength,
        '근육 증가': TrainingGoal.hypertrophy,
        '근비대': TrainingGoal.hypertrophy,
        '체중 감량': TrainingGoal.fatLoss,
        '다이어트': TrainingGoal.fatLoss,
        '체지방 감소': TrainingGoal.fatLoss,
        '체력 향상': TrainingGoal.endurance,
        '근지구력': TrainingGoal.endurance,
        '건강 유지': TrainingGoal.health,
        '유지': TrainingGoal.health,
      };

      for (final MapEntry(key: label, value: expected) in cases.entries) {
        expect(
          PerformanceEngine.goalFromProfile([label]),
          expected,
          reason: '$label should map to ${expected.name}',
        );
      }
    });

    test('returns null for empty and unknown profile goals', () {
      expect(PerformanceEngine.goalFromProfile(const []), isNull);
      expect(
        PerformanceEngine.goalFromProfile(const ['목표 미정', '즐겁게 운동']),
        isNull,
      );
      expect(
        PerformanceEngine.goalFromProfile(const ['파워 향상']),
        isNull,
        reason: '전용 파워 처방 없이 근력의 82.5% 1RM 규칙으로 대체하지 않습니다.',
      );
    });

    test('uses the first selected goal when multiple goals are present', () {
      expect(
        PerformanceEngine.goalFromProfile(const ['체력 향상', '근육 증가']),
        TrainingGoal.endurance,
      );
      expect(
        PerformanceEngine.goalFromProfile(const ['근육 증가', '체력 향상']),
        TrainingGoal.hypertrophy,
      );
      expect(
        PerformanceEngine.goalFromProfile(const ['체중 감량', '근력 향상']),
        TrainingGoal.fatLoss,
      );
    });

    test('defines the exact prescription for all five goals', () {
      const expected =
          <
            TrainingGoal,
            ({int min, int max, int sets, double intensity, int rest})
          >{
            TrainingGoal.strength: (
              min: 4,
              max: 6,
              sets: 3,
              intensity: .825,
              rest: 180,
            ),
            TrainingGoal.hypertrophy: (
              min: 6,
              max: 15,
              sets: 3,
              intensity: .75,
              rest: 120,
            ),
            TrainingGoal.fatLoss: (
              min: 8,
              max: 12,
              sets: 3,
              intensity: .70,
              rest: 90,
            ),
            TrainingGoal.endurance: (
              min: 15,
              max: 20,
              sets: 3,
              intensity: .55,
              rest: 60,
            ),
            TrainingGoal.health: (
              min: 8,
              max: 12,
              sets: 2,
              intensity: .65,
              rest: 90,
            ),
          };

      for (final MapEntry(key: goal, value: values) in expected.entries) {
        final prescription = PerformanceEngine.prescriptionFor(goal);
        expect(prescription.minReps, values.min, reason: goal.name);
        expect(prescription.maxReps, values.max, reason: goal.name);
        expect(prescription.sets, values.sets, reason: goal.name);
        expect(prescription.intensity, values.intensity, reason: goal.name);
        expect(prescription.restSeconds, values.rest, reason: goal.name);
      }
    });

    test('same workout history produces each goal-specific recommendation', () {
      final history = [
        session(DateTime(2026, 8, 10), [(100, 8), (100, 8), (100, 8)]),
      ];
      const expected =
          <
            TrainingGoal,
            ({int min, int max, int sets, int rest, double weight})
          >{
            TrainingGoal.strength: (
              min: 4,
              max: 6,
              sets: 3,
              rest: 180,
              weight: 100,
            ),
            TrainingGoal.hypertrophy: (
              min: 6,
              max: 15,
              sets: 3,
              rest: 120,
              weight: 100,
            ),
            TrainingGoal.fatLoss: (
              min: 8,
              max: 12,
              sets: 3,
              rest: 90,
              weight: 87.5,
            ),
            TrainingGoal.endurance: (
              min: 15,
              max: 20,
              sets: 3,
              rest: 60,
              weight: 70,
            ),
            TrainingGoal.health: (
              min: 8,
              max: 12,
              sets: 2,
              rest: 90,
              weight: 82.5,
            ),
          };

      for (final MapEntry(key: goal, value: values) in expected.entries) {
        final recommendation = PerformanceEngine.recommend(
          sessions: history,
          template: bench,
          goal: goal,
        )!;
        expect(recommendation.minReps, values.min, reason: goal.name);
        expect(recommendation.maxReps, values.max, reason: goal.name);
        expect(recommendation.sets, values.sets, reason: goal.name);
        expect(recommendation.restSeconds, values.rest, reason: goal.name);
        expect(recommendation.weight, values.weight, reason: goal.name);
      }
    });

    test('next exercise and performance engines share goal prescriptions', () {
      final state = AppState();
      addTearDown(state.dispose);
      final completedExercise = WorkoutExercise(
        id: 'bench_today',
        template: bench,
        sets: [
          WorkoutSetEntry(number: 1, weight: 100, reps: 8, completed: true),
        ],
      );
      final workout = WorkoutSession(
        date: DateTime(2026, 8, 10),
        exercises: [completedExercise],
      );

      for (final goal in TrainingGoal.values) {
        final performance = PerformanceEngine.recommend(
          sessions: [workout],
          template: bench,
          goal: goal,
        )!;
        final nextExercise = ExerciseRecommendationEngine.recommendNext(
          catalog: state.exercises,
          session: workout,
          completedExercise: completedExercise,
          goals: [goal.label],
        )!;

        expect(
          nextExercise.goalLabel,
          performance.goal.label,
          reason: goal.name,
        );
        expect(nextExercise.minReps, performance.minReps, reason: goal.name);
        expect(nextExercise.maxReps, performance.maxReps, reason: goal.name);
        expect(nextExercise.sets, performance.sets, reason: goal.name);
        expect(
          nextExercise.restSeconds,
          performance.restSeconds,
          reason: goal.name,
        );
      }
    });
  });

  group('PerformanceEngine recommendation', () {
    test('keeps weight after the first upper-target success', () {
      final recommendation = PerformanceEngine.recommend(
        sessions: [
          session(DateTime(2026, 8, 5), [(100, 10)]),
          session(DateTime(2026, 8, 10), [(100, 15), (100, 15), (100, 15)]),
        ],
        template: bench,
        goal: TrainingGoal.hypertrophy,
      )!;

      expect(recommendation.weight, 100);
      expect(recommendation.minReps, 6);
      expect(recommendation.maxReps, 15);
      expect(recommendation.sets, 3);
      expect(recommendation.reason, contains('한 번 더 확인'));
      expect(recommendation.progressionCondition('kg'), contains('2회 연속'));
    });

    test('raises weight after two consecutive upper-target successes', () {
      final recommendation = PerformanceEngine.recommend(
        sessions: [
          // Deliberately unordered: the engine must compare the two latest
          // sessions by date, not by the caller's iterable order.
          session(DateTime(2026, 8, 10), [(100, 15), (100, 15), (100, 15)]),
          session(DateTime(2026, 8, 1), [(100, 10)]),
          session(DateTime(2026, 8, 5), [(100, 15), (100, 15), (100, 15)]),
        ],
        template: bench,
        goal: TrainingGoal.hypertrophy,
      )!;

      expect(recommendation.weight, 102.5);
      expect(recommendation.reason, contains('두 번 연속'));
    });

    test('does not count upper-target successes at different weights', () {
      final recommendation = PerformanceEngine.recommend(
        sessions: [
          session(DateTime(2026, 8, 1), [(100, 10)]),
          session(DateTime(2026, 8, 5), [(97.5, 15), (97.5, 15), (97.5, 15)]),
          session(DateTime(2026, 8, 10), [(100, 15), (100, 15), (100, 15)]),
        ],
        template: bench,
        goal: TrainingGoal.hypertrophy,
      )!;

      expect(recommendation.weight, 100);
      expect(recommendation.reason, contains('한 번 더 확인'));
    });

    test('requires successes to be consecutive in date order', () {
      final recommendation = PerformanceEngine.recommend(
        sessions: [
          session(DateTime(2026, 8, 12), [(100, 15), (100, 15), (100, 15)]),
          session(DateTime(2026, 8, 1), [(100, 10)]),
          session(DateTime(2026, 8, 8), [(100, 15), (100, 15), (100, 15)]),
          session(DateTime(2026, 8, 10), [(100, 14), (100, 14), (100, 14)]),
        ],
        template: bench,
        goal: TrainingGoal.hypertrophy,
      )!;

      expect(recommendation.weight, 100);
      expect(recommendation.reason, contains('한 번 더 확인'));
    });

    test('reduces weight only after two lower-bound misses', () {
      final recommendation = PerformanceEngine.recommend(
        sessions: [
          session(DateTime(2026, 8, 1), [(100, 8), (100, 5), (100, 5)]),
          session(DateTime(2026, 8, 5), [(100, 8), (100, 5), (100, 5)]),
        ],
        template: bench,
        goal: TrainingGoal.hypertrophy,
      )!;

      expect(recommendation.weight, 97.5);
      expect(recommendation.reason, contains('두 번 연속'));
    });
  });

  test(
    'AppState applies a recommendation without overwriting completed sets',
    () {
      final state = AppState();
      final date = DateTime(2026, 8, 15);
      final recommendation = WorkoutRecommendation(
        template: state.exercises.first,
        goal: TrainingGoal.hypertrophy,
        weight: 102.5,
        minReps: 8,
        maxReps: 10,
        sets: 3,
        nextWeight: 105,
        reason: '테스트',
      );

      state.applyRecommendation(date, recommendation);
      final exercise = state.sessions[date]!.exercises.single;
      exercise.sets.first.completed = true;
      exercise.sets.first.weight = 100;
      state.applyRecommendation(date, recommendation);

      expect(exercise.sets, hasLength(3));
      expect(exercise.sets.first.weight, 100);
      expect(
        exercise.sets.skip(1).map((set) => set.weight),
        everyElement(102.5),
      );
      state.dispose();
    },
  );

  test(
    'legacy seed exercises are excluded when a snapshot is loaded',
    () async {
      final state = AppState(
        repository: MemoryAppRepository(
          initialSnapshot: AppSnapshot(
            role: UserRole.member,
            isDarkMode: false,
            weightUnit: 'kg',
            restDefaultSeconds: 90,
            sessions: {
              DateTime(2026, 8, 7): session(DateTime(2026, 8, 7), [
                (40, 10),
              ], id: 'seed_7'),
              DateTime(2026, 8, 8): session(DateTime(2026, 8, 8), [
                (100, 8),
              ], id: 'user_bench'),
            },
            routines: const [],
          ),
        ),
      );

      await state.initialize();

      expect(state.sessions.containsKey(DateTime(2026, 8, 7)), isFalse);
      expect(state.sessions.containsKey(DateTime(2026, 8, 8)), isTrue);
      state.dispose();
    },
  );

  group('goal-based next exercise recommendation', () {
    test('exercise catalog is broad and keeps stable unique ids', () {
      final state = AppState();
      final ids = state.exercises.map((exercise) => exercise.id).toSet();

      expect(state.exercises.length, greaterThanOrEqualTo(70));
      expect(ids.length, state.exercises.length);
      expect(
        state.exercises.map((exercise) => exercise.name),
        containsAll([
          '체스트 프레스 머신',
          '시티드 케이블 로우',
          '루마니안 데드리프트',
          '트라이셉스 푸시다운',
          '행잉 레그 레이즈',
        ]),
      );
      state.dispose();
    });

    test('muscle gain follows a related exercise without duplicates', () {
      final state = AppState();
      final benchTemplate = state.exercises.firstWhere(
        (exercise) => exercise.id == 'bench',
      );
      final workout = WorkoutSession(
        date: DateTime(2026, 8, 15),
        exercises: [
          WorkoutExercise(
            id: 'bench_today',
            template: benchTemplate,
            sets: [
              WorkoutSetEntry(number: 1, weight: 100, reps: 8, completed: true),
            ],
          ),
        ],
      );

      final recommendation = ExerciseRecommendationEngine.recommendNext(
        catalog: state.exercises,
        session: workout,
        completedExercise: workout.exercises.single,
        goals: const ['근육 증가'],
      )!;

      expect(recommendation.template.id, isNot('bench'));
      expect(recommendation.template.isCardio, isFalse);
      expect(recommendation.sets, 3);
      expect(recommendation.restSeconds, 120);
      workout.exercises.add(
        WorkoutExercise(
          id: 'incline_today',
          template: recommendation.template,
          sets: [],
        ),
      );
      final next = ExerciseRecommendationEngine.recommendNext(
        catalog: state.exercises,
        session: workout,
        completedExercise: workout.exercises.first,
        goals: const ['근육 증가'],
      )!;
      expect(next.template.id, isNot('incline'));
      state.dispose();
    });

    test('date recommendation advances after every completed exercise', () {
      final state = AppState();
      state.setMemberProfile(goals: const ['근육 증가']);
      final date = DateTime(2026, 8, 15);
      final bench = state.exercises.firstWhere(
        (exercise) => exercise.id == 'bench',
      );
      state.addExercise(date, bench);
      final benchExercise = state.sessions[date]!.exercises.single;
      for (final set in benchExercise.sets) {
        state.updateSet(set, weight: 100, reps: 10);
        state.toggleSet(set);
      }
      state.cancelRestTimer();

      final afterBench = state.recommendationForDate(date)!;
      expect(afterBench.template.id, isNot(bench.id));
      expect(afterBench.template.isCardio, isFalse);
      state.applyRecommendation(date, afterBench);

      final whileInclinePending = state.recommendationForDate(date)!;
      expect(whileInclinePending.template.id, afterBench.template.id);
      final inclineExercise = state.sessions[date]!.exercises.last;
      for (final set in inclineExercise.sets) {
        state.toggleSet(set);
      }
      state.cancelRestTimer();

      final afterIncline = state.recommendationForDate(date)!;
      expect(afterIncline.template.id, isNot(bench.id));
      expect(afterIncline.template.id, isNot(afterBench.template.id));
      state.dispose();
    });

    test('AppState adds the approved recommendation with per-set rest', () {
      final state = AppState();
      final date = DateTime(2026, 8, 15);
      final recommendation = NextExerciseRecommendation(
        template: state.exercises.first,
        sets: 3,
        minReps: 8,
        maxReps: 12,
        restSeconds: 120,
        startingWeight: 30,
        goalLabel: '근육 증가',
        reason: '테스트',
      );

      expect(state.addRecommendedExercise(date, recommendation), isTrue);
      expect(state.addRecommendedExercise(date, recommendation), isFalse);
      final sets = state.sessions[date]!.exercises.single.sets;
      expect(sets, hasLength(3));
      expect(sets.map((set) => set.restSeconds), everyElement(120));
      state.dispose();
    });
  });
}
