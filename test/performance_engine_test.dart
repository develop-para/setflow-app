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

  group('PerformanceEngine recommendation', () {
    test('raises weight after all target reps are completed', () {
      final recommendation = PerformanceEngine.recommend(
        sessions: [
          session(DateTime(2026, 8, 10), [(100, 10), (100, 10), (100, 10)]),
        ],
        template: bench,
        goal: TrainingGoal.hypertrophy,
      )!;

      expect(recommendation.weight, 102.5);
      expect(recommendation.minReps, 8);
      expect(recommendation.maxReps, 10);
      expect(recommendation.sets, 3);
    });

    test('reduces weight only after two lower-bound misses', () {
      final recommendation = PerformanceEngine.recommend(
        sessions: [
          session(DateTime(2026, 8, 1), [(100, 8), (100, 6), (100, 5)]),
          session(DateTime(2026, 8, 5), [(100, 8), (100, 6), (100, 5)]),
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

      expect(recommendation.template.id, 'incline');
      expect(recommendation.sets, 3);
      expect(recommendation.restSeconds, 90);
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
