import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';

void main() {
  group('precision recommendation materialization', () {
    test(
      'fatigued resistance recommendation is copied into every added set',
      () async {
        final state = AppState();
        addTearDown(state.dispose);
        await state.initialize();
        state.sessions.clear();
        state.setMemberProfile(goals: const ['근력 향상']);

        final targetDate = DateTime(2026, 8, 21);
        final historyDate = targetDate.subtract(const Duration(days: 1));
        final bench = state.exercises.firstWhere(
          (exercise) => exercise.id == 'bench',
        );
        state.sessions[historyDate] = WorkoutSession(
          date: historyDate,
          exercises: [
            WorkoutExercise(
              id: 'bench-history',
              template: bench,
              sets: [
                for (var number = 1; number <= 3; number++)
                  WorkoutSetEntry(
                    number: number,
                    weight: 80,
                    reps: 5,
                    completed: true,
                  ),
              ],
            ),
          ],
        );
        final profile = _fatiguedProfile(
          targetDate,
          equipment: const {TrainingEquipment.barbell, TrainingEquipment.bench},
        );
        state.setRecommendationProfile(profile);

        final recommendation = ExerciseRecommendationEngine.recommendFirst(
          catalog: [bench],
          session: WorkoutSession(date: targetDate, exercises: []),
          goals: state.goals,
          weeklyHistory: state.sessions.values,
          recommendationProfile: profile,
        )!;

        expect(recommendation.startingWeight, greaterThan(0));
        expect(recommendation.startingWeight, lessThan(80));
        expect(
          state.addRecommendedExercise(targetDate, recommendation),
          isTrue,
        );

        final added = state.sessions[targetDate]!.exercises.single;
        expect(added.sets, hasLength(recommendation.sets));
        expect(
          added.sets.map((set) => set.weight),
          everyElement(recommendation.startingWeight),
        );
        expect(
          added.sets.map((set) => set.reps),
          everyElement(recommendation.minReps),
        );
        expect(
          added.sets.map((set) => set.restSeconds),
          everyElement(recommendation.restSeconds),
        );
      },
    );

    test(
      'fatigued cardio values survive date conversion and added segment',
      () async {
        final state = AppState();
        addTearDown(state.dispose);
        await state.initialize();
        state.sessions.clear();
        state.setMemberProfile(goals: const ['체력 향상']);

        final targetDate = DateTime(2026, 8, 21);
        final historyDate = targetDate.subtract(const Duration(days: 1));
        final bench = state.exercises.firstWhere(
          (exercise) => exercise.id == 'bench',
        );
        final run = state.exercises.firstWhere(
          (exercise) => exercise.id == 'run',
        );
        state.exercises
          ..clear()
          ..addAll([bench, run]);
        state.sessions[historyDate] = WorkoutSession(
          date: historyDate,
          exercises: [
            WorkoutExercise(
              id: 'run-history',
              template: run,
              sets: [
                WorkoutSetEntry(
                  number: 1,
                  weight: 0,
                  reps: 0,
                  completed: true,
                  restSeconds: 0,
                  durationSeconds: 30 * 60,
                  distanceKm: 5,
                  intensityRpe: 4,
                ),
              ],
            ),
          ],
        );
        final currentExercise = WorkoutExercise(
          id: 'bench-current',
          template: bench,
          sets: [
            WorkoutSetEntry(number: 1, weight: 40, reps: 8, completed: true),
          ],
        );
        final currentSession = WorkoutSession(
          date: targetDate,
          exercises: [currentExercise],
        );
        state.sessions[targetDate] = currentSession;
        final profile = _fatiguedProfile(
          targetDate,
          equipment: const {TrainingEquipment.treadmill},
        );
        state.setRecommendationProfile(profile);

        final recommendation = ExerciseRecommendationEngine.recommendNext(
          catalog: state.exercises,
          session: currentSession,
          completedExercise: currentExercise,
          goals: state.goals,
          weeklyHistory: state.sessions.values,
          recommendationProfile: profile,
        )!;
        final cardio = recommendation.cardioPrescription!;

        expect(recommendation.template.id, 'run');
        expect(cardio.durationSeconds, lessThan(30 * 60));
        expect(cardio.targetDistanceKm, isNotNull);

        final converted = state.recommendationForDate(targetDate)!;
        expect(converted.template.id, recommendation.template.id);
        expect(converted.cardioDurationSeconds, cardio.durationSeconds);
        expect(converted.cardioDistanceKm, cardio.targetDistanceKm);
        expect(converted.cardioMinimumRpe, cardio.minimumRpe);
        expect(converted.cardioMaximumRpe, cardio.maximumRpe);
        expect(converted.evidenceIds, recommendation.evidenceIds);

        expect(
          state.addRecommendedExercise(targetDate, recommendation),
          isTrue,
        );
        final added = currentSession.exercises.last.sets.single;
        expect(added.durationSeconds, cardio.durationSeconds);
        expect(added.distanceKm, cardio.targetDistanceKm);
        expect(added.intensityRpe, cardio.minimumRpe);
        expect(added.weight, 0);
        expect(added.reps, 0);
      },
    );
  });
}

RecommendationProfile _fatiguedProfile(
  DateTime recordedAt, {
  required Set<TrainingEquipment> equipment,
}) {
  return RecommendationProfile(
    experienceLevel: TrainingExperienceLevel.beginner,
    availableEquipment: equipment,
    painRegions: const {},
    painLevel: 0,
    restrictedMovements: const {},
    injuryNote: '',
    recoveryStatus: TrainingRecoveryStatus.fatigued,
    recoveryRecordedAt: recordedAt,
    updatedAt: recordedAt,
  );
}
