import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/models.dart';
import 'package:setflow/services/exercise_recommendation_engine.dart';

final _day = DateTime(2026, 10, 4);

ExerciseTemplate _exercise(String id) =>
    exerciseCatalog.firstWhere((exercise) => exercise.id == id);

RecommendationProfile _profile({
  Set<TrainingEquipment> equipment = const {TrainingEquipment.bodyweight},
  TrainingExperienceLevel experience = TrainingExperienceLevel.beginner,
  Set<TrainingMovementRestriction> restrictions = const {},
  int pain = 0,
}) => RecommendationProfile(
  experienceLevel: experience,
  availableEquipment: equipment,
  painRegions: pain == 0 ? const {} : const {TrainingPainRegion.shoulder},
  painLevel: pain,
  restrictedMovements: restrictions,
  injuryNote: '',
  recoveryStatus: TrainingRecoveryStatus.normal,
  recoveryRecordedAt: _day,
  updatedAt: _day,
);

WorkoutExercise _record(String id, {int sets = 1}) => WorkoutExercise(
  id: 'record-$id',
  template: _exercise(id),
  sets: [
    for (var index = 0; index < sets; index++)
      WorkoutSetEntry(number: index + 1, weight: 60, reps: 10, completed: true),
  ],
);

ExerciseRecommendationResult _first({
  List<ExerciseTemplate>? catalog,
  WorkoutSession? session,
  List<String> goals = const ['근육 증가'],
  Iterable<WorkoutSession> history = const [],
  RecommendationProfile? profile,
  RecommendationPreferences preferences = const RecommendationPreferences(),
  Set<String> excluded = const {},
  ExerciseTemplate? alternativeTo,
  DateTime? now,
  bool allowAdditionalVolume = false,
}) => ExerciseRecommendationEngine.evaluateFirst(
  catalog: catalog ?? exerciseCatalog,
  session: session ?? WorkoutSession(date: _day, exercises: []),
  goals: goals,
  weeklyHistory: history,
  recommendationProfile: profile,
  preferences: preferences,
  excludedTemplateIds: excluded,
  alternativeTo: alternativeTo,
  now: now,
  allowAdditionalVolume: allowAdditionalVolume,
);

void _expectStop(
  ExerciseRecommendationResult result,
  ExerciseRecommendationStopReason reason,
) {
  expect(result.recommendation, isNull);
  expect(result.stopReason, reason);
}

void main() {
  test('missing and unrecognized goals report the same repairable cause', () {
    for (final goals in <List<String>>[
      [],
      ['알 수 없는 목표'],
    ]) {
      _expectStop(
        _first(goals: goals),
        ExerciseRecommendationStopReason.missingGoal,
      );
    }
  });

  test('severe pain stops before attempting another body part or exercise', () {
    _expectStop(
      _first(profile: _profile(pain: 7)),
      ExerciseRecommendationStopReason.severePain,
    );
    _expectStop(
      _first(profile: _profile(pain: 10), catalog: []),
      ExerciseRecommendationStopReason.severePain,
    );
    expect(_first(profile: _profile(pain: 6)).recommendation, isNotNull);
  });

  test('empty catalog and already planned exercises report exhaustion', () {
    _expectStop(
      _first(catalog: []),
      ExerciseRecommendationStopReason.catalogExhausted,
    );
    final record = _record('bench');
    _expectStop(
      ExerciseRecommendationEngine.evaluateNext(
        catalog: [_exercise('bench')],
        session: WorkoutSession(date: _day, exercises: [record]),
        completedExercise: record,
        goals: ['근육 증가'],
      ),
      ExerciseRecommendationStopReason.catalogExhausted,
    );
  });

  test('body part absent from catalog is distinct from equipment mismatch', () {
    _expectStop(
      _first(
        catalog: [_exercise('latpull')],
        session: WorkoutSession(
          date: _day,
          exercises: [],
          trainingFocus: {TrainingMuscle.chest},
        ),
        profile: _profile(),
      ),
      ExerciseRecommendationStopReason.trainingFocus,
    );
  });

  for (final muscle in [
    TrainingMuscle.back,
    TrainingMuscle.shoulders,
    TrainingMuscle.biceps,
    TrainingMuscle.triceps,
  ]) {
    test('bodyweight-only ${muscle.name} reports profile constraints', () {
      _expectStop(
        _first(
          session: WorkoutSession(
            date: _day,
            exercises: [],
            trainingFocus: {muscle},
          ),
          profile: _profile(),
        ),
        ExerciseRecommendationStopReason.profileConstraints,
      );
    });
  }

  test('explicit movement restrictions remain a profile constraint', () {
    _expectStop(
      _first(
        catalog: [_exercise('bench'), _exercise('pushup')],
        profile: _profile(
          equipment: TrainingEquipment.values.toSet(),
          restrictions: {TrainingMovementRestriction.horizontalPress},
        ),
      ),
      ExerciseRecommendationStopReason.profileConstraints,
    );
  });

  test('experience restrictions never become an automatic fallback', () {
    _expectStop(
      _first(
        catalog: [_exercise('deadlift')],
        profile: _profile(equipment: TrainingEquipment.values.toSet()),
      ),
      ExerciseRecommendationStopReason.profileConstraints,
    );
  });

  test(
    'available bodyweight exercise still produces its normal prescription',
    () {
      final result = _first(
        catalog: [_exercise('pushup')],
        session: WorkoutSession(
          date: _day,
          exercises: [],
          trainingFocus: {TrainingMuscle.chest},
        ),
        profile: _profile(),
      );
      expect(result.stopReason, isNull);
      expect(result.recommendation!.template.id, 'pushup');
      expect(result.recommendation!.sets, 2);
      expect(result.recommendation!.startingWeight, 0);
      expect(result.recommendation!.targetRepsBySet, [8, 8]);
    },
  );

  test(
    'daily, permanent and transient exclusions are diagnosed explicitly',
    () {
      for (final result in [
        _first(catalog: [_exercise('bench')], excluded: {'bench'}),
        _first(
          catalog: [_exercise('bench')],
          preferences: const RecommendationPreferences().exclude('bench', true),
        ),
        _first(
          catalog: [_exercise('bench')],
          session: WorkoutSession(
            date: _day,
            exercises: [],
            skippedRecommendationIds: {'bench'},
          ),
        ),
        _first(
          catalog: [_exercise('bench'), _exercise('row')],
          session: WorkoutSession(
            date: _day,
            exercises: [],
            trainingFocus: {TrainingMuscle.chest},
            unavailableEquipmentExerciseIds: {'row'},
          ),
        ),
      ]) {
        _expectStop(result, ExerciseRecommendationStopReason.excludedExercises);
      }
    },
  );

  test(
    'no equivalent does not substitute another movement in the same muscle',
    () {
      _expectStop(
        _first(
          catalog: [_exercise('bench'), _exercise('cable_fly')],
          alternativeTo: _exercise('bench'),
        ),
        ExerciseRecommendationStopReason.noAlternative,
      );
    },
  );

  test(
    'excluded equivalent reports exclusions instead of missing alternatives',
    () {
      _expectStop(
        _first(
          catalog: [_exercise('bench'), _exercise('dumbbell_bench')],
          alternativeTo: _exercise('bench'),
          session: WorkoutSession(
            date: _day,
            exercises: [],
            skippedRecommendationIds: {'dumbbell_bench'},
          ),
        ),
        ExerciseRecommendationStopReason.excludedExercises,
      );
    },
  );

  test('weekly volume limit reports completion without relaxing the limit', () {
    final historical = _record('bench', sets: 12);
    final session = WorkoutSession(date: _day, exercises: []);
    _expectStop(
      _first(
        catalog: [_exercise('bench')],
        session: session,
        history: [
          WorkoutSession(
            date: _day.subtract(const Duration(days: 1)),
            exercises: [historical],
          ),
        ],
      ),
      ExerciseRecommendationStopReason.volumeReached,
    );
    expect(session.exercises, isEmpty);
    expect(historical.sets, hasLength(12));
    expect(historical.sets.every((set) => set.completed), isTrue);
  });

  test(
    'eight chest sets stop automatic suggestions but an explicit request continues in the same focus',
    () {
      final record = _record('bench', sets: 8);
      final session = WorkoutSession(
        date: _day,
        exercises: [record],
        trainingFocus: {TrainingMuscle.chest},
      );
      final profile = _profile(
        equipment: TrainingEquipment.values.toSet(),
        experience: TrainingExperienceLevel.advanced,
      );
      ExerciseRecommendationResult next({bool extra = false}) =>
          ExerciseRecommendationEngine.evaluateNext(
            catalog: [
              _exercise('bench'),
              _exercise('chest_press'),
              _exercise('latpull'),
            ],
            session: session,
            completedExercise: record,
            goals: ['근육 증가'],
            recommendationProfile: profile,
            allowAdditionalVolume: extra,
          );
      _expectStop(next(), ExerciseRecommendationStopReason.volumeReached);
      final recommendation = next(extra: true).recommendation!;
      expect(recommendation.template.id, 'chest_press');
      expect(recommendation.sets, 3);
      expect(recommendation.targetRepsBySet, [8, 8, 8]);
      expect(recommendation.isAdditionalVolume, isTrue);
      expect(recommendation.reason, contains('추가 추천 요청'));
      expect(recommendation.summary, contains('직접 요청한 추가 운동'));
      _expectStop(next(), ExerciseRecommendationStopReason.volumeReached);
      expect(session.trainingFocus, {TrainingMuscle.chest});
      expect(session.exercises, [record]);
      expect(record.sets, hasLength(8));
    },
  );

  test(
    'an explicit first request may exceed a weekly default without changing history',
    () {
      final historical = _record('bench', sets: 12);
      final history = [
        WorkoutSession(
          date: _day.subtract(const Duration(days: 1)),
          exercises: [historical],
        ),
      ];
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        trainingFocus: {TrainingMuscle.chest},
      );
      _expectStop(
        _first(
          catalog: [_exercise('chest_press')],
          session: session,
          history: history,
        ),
        ExerciseRecommendationStopReason.volumeReached,
      );
      final recommendation = ExerciseRecommendationEngine.recommendFirst(
        catalog: [_exercise('chest_press')],
        session: session,
        goals: ['근육 증가'],
        weeklyHistory: history,
        allowAdditionalVolume: true,
      )!;
      expect(recommendation.sets, 3);
      expect(recommendation.isAdditionalVolume, isTrue);
      expect(session.exercises, isEmpty);
      expect(historical.sets, hasLength(12));
      expect(historical.sets.every((set) => set.completed), isTrue);
    },
  );

  test('an explicit next request may exceed the total session default', () {
    final record = _record('bench', sets: 24);
    final session = WorkoutSession(
      date: _day,
      exercises: [record],
      trainingFocus: {TrainingMuscle.back},
    );
    final profile = _profile(
      equipment: TrainingEquipment.values.toSet(),
      experience: TrainingExperienceLevel.advanced,
    );
    NextExerciseRecommendation? next({bool extra = false}) =>
        ExerciseRecommendationEngine.recommendNext(
          catalog: [_exercise('latpull')],
          session: session,
          completedExercise: record,
          goals: ['근육 증가'],
          recommendationProfile: profile,
          allowAdditionalVolume: extra,
        );
    expect(next(), isNull);
    final recommendation = next(extra: true)!;
    expect(recommendation.template.id, 'latpull');
    expect(recommendation.sets, 3);
    expect(recommendation.isAdditionalVolume, isTrue);
    expect(next(), isNull);
    expect(record.sets, hasLength(24));
  });

  test(
    'additional volume does not relax pain equipment experience movement focus or exclusions',
    () {
      final allEquipment = TrainingEquipment.values.toSet();
      for (final (result, reason) in [
        (
          _first(profile: _profile(pain: 7), allowAdditionalVolume: true),
          ExerciseRecommendationStopReason.severePain,
        ),
        (
          _first(
            catalog: [_exercise('bench')],
            profile: _profile(),
            allowAdditionalVolume: true,
          ),
          ExerciseRecommendationStopReason.profileConstraints,
        ),
        (
          _first(
            catalog: [_exercise('deadlift')],
            profile: _profile(equipment: allEquipment),
            allowAdditionalVolume: true,
          ),
          ExerciseRecommendationStopReason.profileConstraints,
        ),
        (
          _first(
            catalog: [_exercise('bench')],
            profile: _profile(
              equipment: allEquipment,
              restrictions: {TrainingMovementRestriction.horizontalPress},
            ),
            allowAdditionalVolume: true,
          ),
          ExerciseRecommendationStopReason.profileConstraints,
        ),
        (
          _first(
            catalog: [_exercise('bench')],
            session: WorkoutSession(
              date: _day,
              exercises: [],
              trainingFocus: {TrainingMuscle.back},
            ),
            allowAdditionalVolume: true,
          ),
          ExerciseRecommendationStopReason.trainingFocus,
        ),
        (
          _first(
            catalog: [_exercise('bench')],
            excluded: {'bench'},
            allowAdditionalVolume: true,
          ),
          ExerciseRecommendationStopReason.excludedExercises,
        ),
        (
          _first(
            catalog: [_exercise('bench')],
            preferences: const RecommendationPreferences().exclude(
              'bench',
              true,
            ),
            allowAdditionalVolume: true,
          ),
          ExerciseRecommendationStopReason.excludedExercises,
        ),
        (
          _first(
            catalog: [_exercise('bench')],
            session: WorkoutSession(
              date: _day,
              exercises: [],
              skippedRecommendationIds: {'bench'},
            ),
            allowAdditionalVolume: true,
          ),
          ExerciseRecommendationStopReason.excludedExercises,
        ),
      ]) {
        _expectStop(result, reason);
      }
    },
  );

  test(
    'additional volume still respects spent time and fits only sets that remain',
    () {
      final record = _record('bench', sets: 8);
      final startedAt = _day.add(const Duration(hours: 10));
      final session = WorkoutSession(
        date: _day,
        exercises: [record],
        trainingFocus: {TrainingMuscle.chest},
        timeBudgetMinutes: 15,
        startedAt: startedAt,
      );
      _expectStop(
        ExerciseRecommendationEngine.evaluateNext(
          catalog: [_exercise('chest_press')],
          session: session,
          completedExercise: record,
          goals: ['근육 증가'],
          allowAdditionalVolume: true,
          now: startedAt.add(const Duration(minutes: 30)),
        ),
        ExerciseRecommendationStopReason.timeBudget,
      );
      final fitted = _first(
        catalog: [_exercise('bench')],
        session: WorkoutSession(
          date: _day,
          exercises: [],
          timeBudgetMinutes: 5,
        ),
        allowAdditionalVolume: true,
      ).recommendation!;
      expect(fitted.sets, 2);
      expect(fitted.isAdditionalVolume, isFalse);
      expect(fitted.reason, contains('2세트를 제안합니다'));
      expect(fitted.reason, isNot(contains('3세트를 제안합니다')));
      expect(fitted.summary, isNot(contains('기본 추천 계획을 넘어')));
      expect(fitted.estimatedDurationSeconds, lessThanOrEqualTo(300));
      final weeklyRemainingOne = _first(
        catalog: [_exercise('bench')],
        history: [
          WorkoutSession(
            date: _day.subtract(const Duration(days: 1)),
            exercises: [_record('bench', sets: 11)],
          ),
        ],
        session: WorkoutSession(
          date: _day,
          exercises: [],
          timeBudgetMinutes: 3,
        ),
        allowAdditionalVolume: true,
      ).recommendation!;
      expect(weeklyRemainingOne.sets, 1);
      expect(weeklyRemainingOne.isAdditionalVolume, isFalse);
      expect(weeklyRemainingOne.reason, contains('1세트를 제안합니다'));
      expect(weeklyRemainingOne.reason, isNot(contains('기본 추천 계획을 넘어')));
      expect(weeklyRemainingOne.summary, isNot(contains('추가 운동 추천')));
      expect(session.startedAt, startedAt);
      expect(record.sets, hasLength(8));
    },
  );

  test(
    'spent time is distinguished from volume and preserves workout state',
    () {
      final record = _record('bench');
      final startedAt = _day.add(const Duration(hours: 10));
      final session = WorkoutSession(
        date: _day,
        exercises: [record],
        trainingFocus: {TrainingMuscle.chest},
        timeBudgetMinutes: 15,
        startedAt: startedAt,
      );
      _expectStop(
        ExerciseRecommendationEngine.evaluateNext(
          catalog: [_exercise('bench'), _exercise('chest_press')],
          session: session,
          completedExercise: record,
          goals: ['근육 증가'],
          now: startedAt.add(const Duration(minutes: 30)),
        ),
        ExerciseRecommendationStopReason.timeBudget,
      );
      expect(session.timeBudgetMinutes, 15);
      expect(session.startedAt, startedAt);
      expect(session.trainingFocus, {TrainingMuscle.chest});
      expect(session.exercises.single, same(record));
      expect(record.sets.single.completed, isTrue);
      expect(record.sets.single.weight, 60);
    },
  );

  test(
    'cardio minimum duration has a time cause while strength excludes cardio',
    () {
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        timeBudgetMinutes: 5,
      );
      _expectStop(
        _first(catalog: [_exercise('run')], session: session, goals: ['체력 향상']),
        ExerciseRecommendationStopReason.timeBudget,
      );
      _expectStop(
        _first(catalog: [_exercise('run')], goals: ['근력 향상']),
        ExerciseRecommendationStopReason.catalogExhausted,
      );
    },
  );

  test('legacy API keeps the same recommendation and fitted set targets', () {
    final session = WorkoutSession(
      date: _day,
      exercises: [],
      trainingFocus: {TrainingMuscle.chest},
      timeBudgetMinutes: 5,
    );
    final catalog = [_exercise('bench')];
    final result = _first(catalog: catalog, session: session);
    final legacy = ExerciseRecommendationEngine.recommendFirst(
      catalog: catalog,
      session: session,
      goals: ['근육 증가'],
    )!;
    expect(result.stopReason, isNull);
    final recommendation = result.recommendation!;
    expect(recommendation.template.id, 'bench');
    expect(recommendation.sets, 2);
    expect(recommendation.minReps, 8);
    expect(recommendation.maxReps, 12);
    expect(recommendation.targetRepsBySet, [8, 8]);
    expect(recommendation.startingWeight, 0);
    expect(recommendation.estimatedDurationSeconds, 274);
    expect(legacy.template.id, recommendation.template.id);
    expect(legacy.sets, recommendation.sets);
    expect(legacy.targetRepsBySet, recommendation.targetRepsBySet);
    expect(legacy.reason, recommendation.reason);
    expect(legacy.summary, recommendation.summary);
    expect(legacy.evidenceIds, recommendation.evidenceIds);
  });
}
