import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/domain/exercise_recommendation_traits.dart';

void main() {
  group('RecommendationProfile', () {
    test('round-trips a validated, canonical snapshot', () {
      final recordedAt = DateTime.utc(2026, 8, 21, 3, 10);
      final profile = RecommendationProfile(
        experienceLevel: TrainingExperienceLevel.intermediate,
        availableEquipment: const {
          TrainingEquipment.dumbbells,
          TrainingEquipment.bodyweight,
        },
        painRegions: const {TrainingPainRegion.knee},
        painLevel: 4,
        restrictedMovements: const {TrainingMovementRestriction.squatLunge},
        injuryNote: '무릎 굽힘이 불편함',
        recoveryStatus: TrainingRecoveryStatus.fatigued,
        recoveryRecordedAt: recordedAt,
        updatedAt: recordedAt,
      );

      final restored = RecommendationProfile.tryFromJson(profile.toJson())!;

      expect(restored.experienceLevel, TrainingExperienceLevel.intermediate);
      expect(restored.availableEquipment, {
        TrainingEquipment.bodyweight,
        TrainingEquipment.dumbbells,
      });
      expect(restored.painRegions, {TrainingPainRegion.knee});
      expect(restored.painLevel, 4);
      expect(restored.injuryNote, '무릎 굽힘이 불편함');
      expect(restored.recoveryRecordedAt, recordedAt);
      expect(profile.toJson()['availableEquipment'], [
        'bodyweight',
        'dumbbells',
      ]);
    });

    test('rejects unsupported or malformed profile snapshots', () {
      expect(RecommendationProfile.tryFromJson({'schemaVersion': 2}), isNull);
      final valid = _profile().toJson();
      expect(
        RecommendationProfile.tryFromJson({
          ...valid,
          'availableEquipment': ['bodyweight', 'bodyweight'],
        }),
        isNull,
      );
      expect(
        RecommendationProfile.tryFromJson({...valid, 'painLevel': 11}),
        isNull,
      );
      expect(
        RecommendationProfile.tryFromJson({
          ...valid,
          'painRegions': ['unknown-region'],
        }),
        isNull,
      );
      expect(
        RecommendationProfile.tryFromJson({...valid, 'painLevel': 1.5}),
        isNull,
      );
      expect(
        RecommendationProfile.tryFromJson({...valid, 'schemaVersion': 1.5}),
        isNull,
      );
      expect(
        RecommendationProfile.tryFromJson({...valid, 'painLevel': 3}),
        isNull,
      );
    });

    test('constructor enforces profile invariants', () {
      final recordedAt = DateTime(2026, 8, 21);
      expect(
        () => RecommendationProfile(
          experienceLevel: TrainingExperienceLevel.beginner,
          availableEquipment: const {},
          painRegions: const {},
          painLevel: 0,
          restrictedMovements: const {},
          injuryNote: '',
          recoveryStatus: TrainingRecoveryStatus.normal,
          recoveryRecordedAt: recordedAt,
          updatedAt: recordedAt,
        ),
        throwsArgumentError,
      );
      expect(
        () => RecommendationProfile(
          experienceLevel: TrainingExperienceLevel.beginner,
          availableEquipment: const {TrainingEquipment.bodyweight},
          painRegions: const {},
          painLevel: 4,
          restrictedMovements: const {},
          injuryNote: '',
          recoveryStatus: TrainingRecoveryStatus.normal,
          recoveryRecordedAt: recordedAt,
          updatedAt: recordedAt,
        ),
        throwsArgumentError,
      );
    });
  });

  group('precision recommendation constraints', () {
    test('trait metadata covers every built-in exercise exactly once', () {
      expect(
        exerciseRecommendationTraits.keys.toSet(),
        exerciseCatalog.map((exercise) => exercise.id).toSet(),
      );
    });

    test('only recommends exercises supported by selected equipment', () {
      final day = DateTime(2026, 8, 21);
      final profile = _profile(equipment: const {TrainingEquipment.bodyweight});

      final recommendation = ExerciseRecommendationEngine.recommendFirst(
        catalog: exerciseCatalog,
        session: WorkoutSession(date: day, exercises: []),
        goals: const ['근력 향상'],
        recommendationProfile: profile,
      );

      expect(recommendation, isNotNull);
      final traits = exerciseRecommendationTraits[recommendation!.template.id]!;
      expect(
        profile.availableEquipment.containsAll(traits.requiredEquipment),
        isTrue,
      );
    });

    test('distinguishes each cardio machine instead of over-permitting', () {
      final day = DateTime(2026, 8, 21);
      final treadmillRun = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'run',
      );
      final bike = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'stationary_bike',
      );
      final profile = _profile(
        equipment: const {TrainingEquipment.stationaryBike},
      );

      final recommendation = ExerciseRecommendationEngine.recommendFirst(
        catalog: [treadmillRun, bike],
        session: WorkoutSession(date: day, exercises: []),
        goals: const ['체력 향상'],
        recommendationProfile: profile,
      );

      expect(recommendation?.template.id, 'stationary_bike');
    });

    test('excludes movements the member explicitly chose to avoid', () {
      final day = DateTime(2026, 8, 21);
      final profile = _profile(
        equipment: TrainingEquipment.values.toSet(),
        restrictions: const {
          TrainingMovementRestriction.squatLunge,
          TrainingMovementRestriction.hipHinge,
        },
      );

      final recommendation = ExerciseRecommendationEngine.recommendFirst(
        catalog: exerciseCatalog,
        session: WorkoutSession(date: day, exercises: []),
        goals: const ['근력 향상'],
        recommendationProfile: profile,
      );

      expect(recommendation, isNotNull);
      final movements =
          exerciseRecommendationTraits[recommendation!.template.id]!.movements;
      expect(movements.intersection(profile.restrictedMovements), isEmpty);
    });

    test('does not offer intermediate-only lifts to a beginner', () {
      final deadlift = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'deadlift',
      );
      final pushup = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'pushup',
      );
      final beginner = _profile(equipment: TrainingEquipment.values.toSet());

      final recommendation = ExerciseRecommendationEngine.recommendFirst(
        catalog: [deadlift, pushup],
        session: WorkoutSession(date: DateTime(2026, 8, 21), exercises: []),
        goals: const ['근력 향상'],
        recommendationProfile: beginner,
      );

      expect(recommendation!.template.id, 'pushup');
      expect(
        exerciseRecommendationTraits['deadlift']!.isEligibleFor(beginner),
        isFalse,
      );
    });

    test('keeps advanced-only lifts out of intermediate suggestions', () {
      final frontSquat = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'front_squat',
      );
      final recordedAt = DateTime(2026, 8, 21);
      RecommendationProfile profile(TrainingExperienceLevel level) =>
          RecommendationProfile(
            experienceLevel: level,
            availableEquipment: const {
              TrainingEquipment.barbell,
              TrainingEquipment.squatRack,
            },
            painRegions: const {},
            painLevel: 0,
            restrictedMovements: const {},
            injuryNote: '',
            recoveryStatus: TrainingRecoveryStatus.normal,
            recoveryRecordedAt: recordedAt,
            updatedAt: recordedAt,
          );

      expect(
        ExerciseRecommendationEngine.recommendFirst(
          catalog: [frontSquat],
          session: WorkoutSession(date: recordedAt, exercises: []),
          goals: const ['근력 향상'],
          recommendationProfile: profile(TrainingExperienceLevel.intermediate),
        ),
        isNull,
      );
      expect(
        ExerciseRecommendationEngine.recommendFirst(
          catalog: [frontSquat],
          session: WorkoutSession(date: recordedAt, exercises: []),
          goals: const ['근력 향상'],
          recommendationProfile: profile(TrainingExperienceLevel.advanced),
        )?.template.id,
        'front_squat',
      );
    });

    test('does not treat shoulder raises as overhead presses', () {
      final lateralRaise = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'lateral',
      );
      final day = DateTime(2026, 8, 21);

      expect(
        ExerciseRecommendationEngine.recommendFirst(
          catalog: [lateralRaise],
          session: WorkoutSession(date: day, exercises: []),
          goals: const ['근육 증가'],
          recommendationProfile: _profile(
            equipment: const {TrainingEquipment.dumbbells},
            restrictions: const {TrainingMovementRestriction.overheadPress},
          ),
        )?.template.id,
        'lateral',
      );
      expect(
        ExerciseRecommendationEngine.recommendFirst(
          catalog: [lateralRaise],
          session: WorkoutSession(date: day, exercises: []),
          goals: const ['근육 증가'],
          recommendationProfile: _profile(
            equipment: const {TrainingEquipment.dumbbells},
            restrictions: const {TrainingMovementRestriction.shoulderRaise},
          ),
        ),
        isNull,
      );
    });

    test('omits custom exercises without safety metadata from auto picks', () {
      final custom = ExerciseTemplate(
        id: 'custom_test',
        name: '나만의 운동',
        muscle: '가슴',
        icon: exerciseIconForMuscle('가슴'),
      );

      expect(
        ExerciseRecommendationEngine.recommendFirst(
          catalog: [custom],
          session: WorkoutSession(date: DateTime(2026, 8, 21), exercises: []),
          goals: const ['근육 증가'],
          recommendationProfile: _profile(),
        ),
        isNull,
      );
    });

    test('low recovery adjusts only the recorded calendar day', () {
      final day = DateTime(2026, 8, 21);
      final bench = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'bench',
      );
      final history = WorkoutSession(
        date: day.subtract(const Duration(days: 1)),
        exercises: [
          WorkoutExercise(
            id: 'bench-history',
            template: bench,
            sets: [
              for (var index = 1; index <= 3; index++)
                WorkoutSetEntry(
                  number: index,
                  weight: 80,
                  reps: 5,
                  completed: true,
                ),
            ],
          ),
        ],
      );
      final base = ExerciseRecommendationEngine.recommendFirst(
        catalog: [bench],
        session: WorkoutSession(date: day, exercises: []),
        goals: const ['근력 향상'],
        weeklyHistory: [history],
        recommendationProfile: _profile(
          equipment: const {TrainingEquipment.barbell, TrainingEquipment.bench},
          recovery: TrainingRecoveryStatus.normal,
          recoveryAt: day,
        ),
      )!;
      final fatiguedToday = ExerciseRecommendationEngine.recommendFirst(
        catalog: [bench],
        session: WorkoutSession(date: day, exercises: []),
        goals: const ['근력 향상'],
        weeklyHistory: [history],
        recommendationProfile: _profile(
          equipment: const {TrainingEquipment.barbell, TrainingEquipment.bench},
          recovery: TrainingRecoveryStatus.fatigued,
          recoveryAt: day,
        ),
      )!;
      final staleFatigue = ExerciseRecommendationEngine.recommendFirst(
        catalog: [bench],
        session: WorkoutSession(date: day, exercises: []),
        goals: const ['근력 향상'],
        weeklyHistory: [history],
        recommendationProfile: _profile(
          equipment: const {TrainingEquipment.barbell, TrainingEquipment.bench},
          recovery: TrainingRecoveryStatus.fatigued,
          recoveryAt: day.subtract(const Duration(days: 1)),
        ),
      )!;

      expect(fatiguedToday.sets, base.sets - 1);
      expect(fatiguedToday.startingWeight, lessThan(base.startingWeight));
      expect(fatiguedToday.evidenceIds, contains('craven_2022_sleep_loss'));
      expect(staleFatigue.sets, base.sets);
      expect(staleFatigue.startingWeight, base.startingWeight);
      expect(
        staleFatigue.evidenceIds,
        isNot(contains('craven_2022_sleep_loss')),
      );
    });

    test('pauses automatic suggestions for severe self-reported pain', () {
      final recordedAt = DateTime(2026, 8, 21);
      final profile = RecommendationProfile(
        experienceLevel: TrainingExperienceLevel.beginner,
        availableEquipment: const {TrainingEquipment.bodyweight},
        painRegions: const {TrainingPainRegion.knee},
        painLevel: 7,
        restrictedMovements: const {},
        injuryNote: '',
        recoveryStatus: TrainingRecoveryStatus.normal,
        recoveryRecordedAt: recordedAt,
        updatedAt: recordedAt,
      );

      expect(
        ExerciseRecommendationEngine.recommendFirst(
          catalog: exerciseCatalog,
          session: WorkoutSession(date: recordedAt, exercises: []),
          goals: const ['건강 관리'],
          recommendationProfile: profile,
        ),
        isNull,
      );
    });
  });
}

RecommendationProfile _profile({
  Set<TrainingEquipment>? equipment,
  Set<TrainingMovementRestriction> restrictions = const {},
  TrainingRecoveryStatus recovery = TrainingRecoveryStatus.normal,
  DateTime? recoveryAt,
}) {
  final recordedAt = recoveryAt ?? DateTime(2026, 8, 21);
  return RecommendationProfile(
    experienceLevel: TrainingExperienceLevel.beginner,
    availableEquipment: equipment ?? const {TrainingEquipment.bodyweight},
    painRegions: const {},
    painLevel: 0,
    restrictedMovements: restrictions,
    injuryNote: '',
    recoveryStatus: recovery,
    recoveryRecordedAt: recordedAt,
    updatedAt: recordedAt,
  );
}
