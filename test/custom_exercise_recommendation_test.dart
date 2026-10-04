import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/hive_app_repository.dart';
import 'package:setflow/domain/custom_exercise_recommendation_rules.dart';
import 'package:setflow/domain/exercise_substitutions.dart';
import 'package:setflow/services/resistance_prescription_engine.dart';

final _day = DateTime(2026, 10, 4);
ExerciseTemplate _builtIn(String id) =>
    exerciseCatalog.firstWhere((e) => e.id == id);
ExerciseTemplate _custom({
  String id = 'custom_press',
  String muscle = '가슴',
  ExerciseMeasurement measurement = ExerciseMeasurement.weightReps,
  CustomExerciseRecommendation? info,
}) => ExerciseTemplate(
  id: id,
  name: '내 종목',
  muscle: muscle,
  icon: _builtIn('bench').icon,
  measurement: measurement,
  customRecommendation: info,
);
CustomExerciseRecommendation _info({
  bool enabled = true,
  TrainingMuscle primary = TrainingMuscle.chest,
  CustomExerciseMovement movement = CustomExerciseMovement.horizontalPress,
  Set<TrainingEquipment> equipment = const {TrainingEquipment.bands},
  TrainingExperienceLevel experience = TrainingExperienceLevel.beginner,
  Set<TrainingMuscle> secondary = const {},
  Set<TrainingMovementRestriction> additional = const {},
}) => CustomExerciseRecommendation(
  enabled: enabled,
  primaryMuscle: primary,
  movement: movement,
  requiredEquipment: equipment,
  minimumExperience: experience,
  secondaryMuscles: secondary,
  additionalMovements: additional,
);
RecommendationProfile _profile({
  Set<TrainingEquipment> equipment = const {TrainingEquipment.bands},
  TrainingExperienceLevel experience = TrainingExperienceLevel.beginner,
  Set<TrainingMovementRestriction> restrictions = const {},
  int pain = 0,
}) => RecommendationProfile(
  experienceLevel: experience,
  availableEquipment: equipment,
  painRegions: pain == 0 ? {} : {TrainingPainRegion.shoulder},
  painLevel: pain,
  restrictedMovements: restrictions,
  injuryNote: '',
  recoveryStatus: TrainingRecoveryStatus.normal,
  recoveryRecordedAt: _day,
  updatedAt: _day,
);
NextExerciseRecommendation? _recommend(
  List<ExerciseTemplate> catalog, {
  RecommendationProfile? profile,
  Set<TrainingMuscle> focus = const {TrainingMuscle.chest},
  List<String> goals = const ['근육 증가'],
  List<WorkoutSession> history = const [],
  RecommendationPreferences preferences = const RecommendationPreferences(),
  ExerciseTemplate? alternative,
  WorkoutSession? session,
}) => ExerciseRecommendationEngine.recommendFirst(
  catalog: catalog,
  session:
      session ??
      WorkoutSession(date: _day, exercises: [], trainingFocus: focus),
  goals: goals,
  weeklyHistory: history,
  recommendationProfile: profile,
  preferences: preferences,
  alternativeTo: alternative,
);
WorkoutSession _history(ExerciseTemplate template, {double weight = 60}) =>
    WorkoutSession(
      date: _day.subtract(const Duration(days: 2)),
      exercises: [
        WorkoutExercise(
          id: 'record',
          template: template,
          sets: [
            for (var i = 1; i <= 3; i++)
              WorkoutSetEntry(
                number: i,
                weight: weight,
                reps: 10,
                completed: true,
              ),
          ],
        ),
      ],
    );

void main() {
  test(
    'custom duration hold produces actual duration sets with no invented load',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: ['근육 증가']);
      state.setTrainingFocus(_day, {TrainingMuscle.core});
      final template = state.createCustomExercise(
        name: '나의 한손 버티기',
        muscle: '복근',
        measurement: ExerciseMeasurement.duration,
      )!;
      state.saveCustomExerciseRecommendation(
        template.id,
        _info(
          primary: TrainingMuscle.core,
          movement: CustomExerciseMovement.coreHold,
          equipment: {TrainingEquipment.bodyweight},
        ),
      );
      for (final builtin in exerciseCatalog) {
        state.setExerciseExcludedFromRecommendations(builtin.id, true);
      }
      final result = state.firstExerciseRecommendationForDate(_day)!;
      expect(state.addRecommendedExercise(_day, result), isTrue);
      expect(
        state
            .sessionFor(_day)
            .exercises
            .single
            .sets
            .map((set) => set.durationSeconds),
        everyElement(60),
      );
      expect(
        state.sessionFor(_day).exercises.single.sets.map((set) => set.weight),
        everyElement(0),
      );
      expect(
        state.sessionFor(_day).exercises.single.sets.map((set) => set.reps),
        everyElement(0),
      );
    },
  );
  test(
    'custom main equipment excludes auxiliary bench when smith machine is required',
    () {
      final template = _custom(
        info: _info(
          equipment: {TrainingEquipment.bench, TrainingEquipment.smithMachine},
        ),
      );
      expect(
        ExerciseSubstitutions.unavailableEquipmentFor(template),
        TrainingEquipment.smithMachine,
      );
    },
  );
  test('simple creation stays manual until explicit metadata opt in', () async {
    final state = AppState();
    addTearDown(state.dispose);
    await state.initialize();
    final template = state.createCustomExercise(
      name: '나의 밴드 프레스',
      muscle: '가슴',
    )!;
    expect(template.customRecommendation, isNull);
    expect(_recommend([template]), isNull);
    state.addExercise(_day, template);
    expect(state.sessionFor(_day).exercises.single.template.id, template.id);
    expect(state.sessionFor(_day).exercises.single.sets, isNotEmpty);
  });

  test(
    'opt in joins real AppState recommendation catalog and opt out preserves records and routine',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: ['근육 증가']);
      state.setTrainingFocus(_day, {TrainingMuscle.chest});
      final original = state.createCustomExercise(
        name: '나의 스미스 프레스',
        muscle: '가슴',
      )!;
      for (final template in exerciseCatalog) {
        state.setExerciseExcludedFromRecommendations(template.id, true);
      }
      expect(state.firstExerciseRecommendationForDate(_day), isNull);
      state.sessions[_day.subtract(const Duration(days: 2))] = _history(
        original,
      );
      final record = state.sessions.values
          .firstWhere((s) => s.exercises.isNotEmpty)
          .exercises
          .single;
      state.sessions[_day.subtract(const Duration(days: 2))]!.exercises[0] =
          WorkoutExercise(
            id: record.id,
            template: record.template,
            sets: record.sets,
            coachingWorkoutId: 'coach-plan',
            coachingAuthor: '코치',
          );
      state.routines.add(
        RoutineData(
          id: 'personal',
          name: '내 루틴',
          description: '',
          color: RoutineData.defaultColor,
          exercises: [original],
        ),
      );
      final info = _info(equipment: {TrainingEquipment.smithMachine});
      state.saveCustomExerciseRecommendation(original.id, info);
      final result = state.firstExerciseRecommendationForDate(_day)!;
      expect(result.template.id, original.id);
      expect(result.startingWeight, 60);
      expect(state.routines.last.exercises.single.customRecommendation, info);
      final reboundRecord = state.sessions.values
          .firstWhere((s) => s.exercises.isNotEmpty)
          .exercises
          .single;
      expect(reboundRecord.sets, same(record.sets));
      expect(reboundRecord.coachingWorkoutId, 'coach-plan');
      expect(reboundRecord.coachingAuthor, '코치');
      state.saveCustomExerciseRecommendation(
        original.id,
        info.withEnabled(false),
      );
      expect(state.firstExerciseRecommendationForDate(_day), isNull);
      expect(
        state.customExercises.single.customRecommendation!.requiredEquipment,
        {TrainingEquipment.smithMachine},
      );
      expect(
        state.sessions.values
            .firstWhere((s) => s.exercises.isNotEmpty)
            .exercises
            .single
            .sets
            .first
            .weight,
        60,
      );
      state.saveCustomExerciseRecommendation(original.id, info);
      expect(
        state.firstExerciseRecommendationForDate(_day)!.template.id,
        original.id,
      );
    },
  );

  test(
    'same name or movement never borrows starting load from another exercise',
    () {
      final template = _custom(info: _info());
      final result = _recommend(
        [template],
        history: [_history(_builtIn('bench'), weight: 100)],
      )!;
      expect(result.startingWeight, 0);
      expect(result.historyCount, 0);
      expect(
        _recommend(
          [template],
          history: [_history(template, weight: 25)],
        )!.startingWeight,
        25,
      );
    },
  );

  test(
    'equipment experience and explicit movement restrictions constrain custom candidates',
    () {
      final template = _custom(
        info: _info(
          experience: TrainingExperienceLevel.intermediate,
          additional: {TrainingMovementRestriction.hipHinge},
        ),
      );
      expect(_recommend([template]), isNull);
      expect(_recommend([template], profile: _profile()), isNull);
      expect(
        _recommend(
          [template],
          profile: _profile(
            experience: TrainingExperienceLevel.advanced,
            equipment: {TrainingEquipment.bodyweight},
          ),
        ),
        isNull,
      );
      expect(
        _recommend(
          [template],
          profile: _profile(
            experience: TrainingExperienceLevel.advanced,
            restrictions: {TrainingMovementRestriction.horizontalPress},
          ),
        ),
        isNull,
      );
      expect(
        _recommend(
          [template],
          profile: _profile(
            experience: TrainingExperienceLevel.advanced,
            restrictions: {TrainingMovementRestriction.hipHinge},
          ),
        ),
        isNull,
      );
      expect(
        _recommend([
          template,
        ], profile: _profile(experience: TrainingExperienceLevel.advanced)),
        isNotNull,
      );
      expect(
        _recommend(
          [template],
          profile: _profile(
            experience: TrainingExperienceLevel.advanced,
            pain: 7,
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'focus date exclusions permanent exclusions and time budgets still apply',
    () {
      final template = _custom(info: _info());
      expect(_recommend([template], focus: {TrainingMuscle.back}), isNull);
      expect(
        _recommend(
          [template],
          preferences: RecommendationPreferences(
            excludedExerciseIds: {template.id},
          ),
        ),
        isNull,
      );
      expect(
        _recommend(
          [template],
          session: WorkoutSession(
            date: _day,
            exercises: [],
            skippedRecommendationIds: {template.id},
          ),
        ),
        isNull,
      );
      expect(
        _recommend(
          [template],
          session: WorkoutSession(
            date: _day,
            exercises: [],
            timeBudgetMinutes: 1,
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'manual preference can prioritize custom exercise without bypassing constraints',
    () {
      final template = _custom(info: _info());
      var preferences = const RecommendationPreferences();
      for (final days in [2, 9]) {
        preferences = preferences.recordSelection(
          template.id,
          _day.subtract(Duration(days: days)),
        );
      }
      expect(
        _recommend([
          _builtIn('bench'),
          template,
        ], preferences: preferences)!.template.id,
        template.id,
      );
      expect(
        _recommend(
          [_builtIn('bench'), template],
          preferences: preferences,
          focus: {TrainingMuscle.back},
        ),
        isNull,
      );
    },
  );

  test('explicit arm metadata separates biceps and triceps', () {
    final curl = _custom(
      muscle: '팔',
      info: _info(
        primary: TrainingMuscle.biceps,
        movement: CustomExerciseMovement.elbowFlexion,
      ),
    );
    expect(_recommend([curl], focus: {TrainingMuscle.biceps}), isNotNull);
    expect(_recommend([curl], focus: {TrainingMuscle.triceps}), isNull);
    expect(ResistancePrescriptionEngine.primaryMuscles(curl), {
      TrainingMuscle.biceps,
    });
  });

  test(
    'authored compound and secondary metadata informs sets rest and volume even when disabled',
    () {
      final template = _custom(
        info: _info(enabled: false, secondary: {TrainingMuscle.triceps}),
      );
      final session = _history(template);
      final volume = ResistancePrescriptionEngine.volume(
        history: [],
        session: session,
      );
      expect(volume[TrainingMuscle.chest], 3);
      expect(volume[TrainingMuscle.triceps], 1.5);
      expect(volume[TrainingMuscle.shoulders], isNull);
      final prescription = ResistancePrescriptionEngine.prescribe(
        template: template,
        goal: TrainingGoal.hypertrophy,
        history: [],
        session: WorkoutSession(date: _day, exercises: []),
      );
      expect(prescription.restSeconds, 120);
      expect(prescription.sets, 3);
      expect(_recommend([template]), isNull);
    },
  );

  test(
    'authored movement substitutions require same movement and enabled metadata',
    () {
      final press = _custom(info: _info());
      final fly = _custom(
        id: 'custom_fly',
        info: _info(movement: CustomExerciseMovement.chestFly),
      );
      expect(ExerciseSubstitutions.matches(_builtIn('bench'), press), isTrue);
      expect(ExerciseSubstitutions.matches(_builtIn('bench'), fly), isFalse);
      expect(
        _recommend([press, fly], alternative: _builtIn('bench'))!.template.id,
        press.id,
      );
      expect(
        ExerciseSubstitutions.matches(
          _builtIn('bench'),
          press.withCustomRecommendation(_info(enabled: false)),
        ),
        isFalse,
      );
      expect(
        ExerciseSubstitutions.matches(
          _builtIn('bench'),
          press.withCustomRecommendation(
            _info(movement: CustomExerciseMovement.other),
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'unavailable custom equipment excludes other custom candidates for that day',
    () {
      final first = _custom(info: _info());
      final sameEquipment = _custom(id: 'custom_other_press', info: _info());
      final differentEquipment = _custom(
        id: 'custom_dumbbell_press',
        info: _info(equipment: {TrainingEquipment.dumbbells}),
      );
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        skippedRecommendationIds: {first.id},
        unavailableEquipmentExerciseIds: {first.id},
      );
      expect(
        _recommend([
          first,
          sameEquipment,
          differentEquipment,
        ], session: session)!.template.id,
        differentEquipment.id,
      );
    },
  );

  test(
    'metadata validation rejects mismatched body parts holds and incomplete cardio without deleting exercise',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      final template = state.createCustomExercise(name: '내 프레스', muscle: '가슴')!;
      expect(
        () => state.saveCustomExerciseRecommendation(
          template.id,
          _info(primary: TrainingMuscle.back),
        ),
        throwsArgumentError,
      );
      expect(state.customExercises.single.customRecommendation, isNull);
      expect(
        () => state.saveCustomExerciseRecommendation('bench', _info()),
        throwsStateError,
      );
      expect(
        CustomExerciseRecommendationRules.isValid(
          _custom(muscle: '복근', measurement: ExerciseMeasurement.duration),
          _info(
            primary: TrainingMuscle.core,
            movement: CustomExerciseMovement.coreFlexionRotation,
          ),
        ),
        isFalse,
      );
      expect(
        _recommend(
          [_custom(muscle: '유산소', info: _info())],
          focus: {},
          goals: ['체력 향상'],
        ),
        isNull,
      );
    },
  );

  test(
    'metadata survives root snapshot and inline routine and session encoding',
    () {
      final template = _custom(
        info: _info(secondary: {TrainingMuscle.triceps}),
      );
      final session = _history(template);
      final routine = RoutineData(
        id: 'routine',
        name: '내 루틴',
        description: '',
        color: RoutineData.defaultColor,
        exercises: [template],
      );
      final snapshot = AppSnapshot(
        role: UserRole.guest,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: {session.date: session},
        routines: [routine],
        customExercises: [template],
      );
      final restored = AppSnapshotCodec.decode(
        AppSnapshotCodec.encode(snapshot),
        exerciseCatalog,
      )!;
      expect(
        restored.customExercises.single.customRecommendation!.toJson(),
        template.customRecommendation!.toJson(),
      );
      expect(
        restored
            .sessions
            .values
            .single
            .exercises
            .single
            .template
            .customRecommendation!
            .toJson(),
        template.customRecommendation!.toJson(),
      );
      expect(
        restored.routines.single.exercises.single.customRecommendation!
            .toJson(),
        template.customRecommendation!.toJson(),
      );
      expect(
        AppSnapshotCodec.sessionFromJson(
          AppSnapshotCodec.sessionToJson(session),
          [],
        )!.exercises.single.template.customRecommendation!.enabled,
        isTrue,
      );
      expect(
        AppSnapshotCodec.routineFromJson(
          AppSnapshotCodec.routineToJson(routine),
          [],
        )!.exercises.single.customRecommendation!.enabled,
        isTrue,
      );
    },
  );

  test(
    'legacy and malformed optional metadata keep manual exercise and records usable',
    () {
      final template = _custom(info: _info());
      final snapshot = AppSnapshot(
        role: UserRole.guest,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: {},
        routines: [],
        customExercises: [template],
      );
      for (final broken in [
        null,
        'invalid',
        {'version': 99},
        {
          ..._info().toJson(),
          'requiredEquipment': ['future-gear'],
        },
        {..._info().toJson(), 'movement': 'future-movement'},
      ]) {
        final json =
            jsonDecode(AppSnapshotCodec.encode(snapshot))
                as Map<String, dynamic>;
        final rows = json['customExercises'] as List;
        rows[0] = Map<String, dynamic>.from(rows.single as Map)
          ..['customRecommendation'] = broken;
        final restored = AppSnapshotCodec.fromJson(json, exerciseCatalog)!;
        expect(restored.customExercises.single.id, template.id);
        expect(_recommend(restored.customExercises), isNull);
      }
    },
  );

  test('guest restart restores opt in and own completed history', () async {
    final directory = await Directory.systemTemp.createTemp(
      'setflow_custom_recommendation_',
    );
    HiveAppRepository? repository;
    AppState? state;
    try {
      repository = await HiveAppRepository.openAtPath(
        directory.path,
        boxName: 'custom_recommendation',
      );
      state = AppState(repository: repository);
      await state.initialize();
      final template = state.createCustomExercise(
        name: '내 밴드 운동',
        muscle: '가슴',
      )!;
      state.sessions[_day.subtract(const Duration(days: 2))] = _history(
        template,
        weight: 15,
      );
      state.saveCustomExerciseRecommendation(template.id, _info());
      await state.flushPersistence();
      state.dispose();
      state = null;
      await repository.close();
      repository = await HiveAppRepository.openAtPath(
        directory.path,
        boxName: 'custom_recommendation',
      );
      state = AppState(repository: repository);
      await state.initialize();
      expect(
        state.customExercises.single.customRecommendation!.enabled,
        isTrue,
      );
      final restored = state.sessions.values
          .firstWhere((s) => s.exercises.isNotEmpty)
          .exercises
          .single;
      expect(restored.template.customRecommendation!.enabled, isTrue);
      expect(restored.sets.first.weight, 15);
      expect(
        _recommend(
          state.customExercises,
          history: state.sessions.values.toList(),
        )!.startingWeight,
        15,
      );
    } finally {
      state?.dispose();
      await repository?.close();
      await directory.delete(recursive: true);
    }
  });

  test('custom cardio uses selected modality and only its own baseline', () {
    final template = _custom(
      muscle: '유산소',
      info: CustomExerciseRecommendation(
        enabled: true,
        requiredEquipment: {TrainingEquipment.rowingMachine},
        minimumExperience: TrainingExperienceLevel.beginner,
        cardioDefinitionId: 'rowing_machine',
      ),
    );
    final builtinHistory = CardioSessionRecord(
      id: 'builtin',
      exerciseId: 'rowing_machine',
      occurredAt: _day.subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 20),
      intensity: CardioIntensity.moderate,
      distanceKm: 5,
    );
    final ownHistory = CardioSessionRecord(
      id: 'own',
      exerciseId: template.id,
      definitionExerciseId: 'rowing_machine',
      occurredAt: _day.subtract(const Duration(days: 3)),
      duration: const Duration(minutes: 20),
      intensity: CardioIntensity.moderate,
      distanceKm: 2,
    );
    final withoutOwn = CardioPrescriptionEngine.recommend(
      exerciseId: template.id,
      definitionExerciseId: 'rowing_machine',
      goal: TrainingGoal.endurance,
      history: [builtinHistory],
      now: _day,
    )!;
    expect(withoutOwn.definition.exerciseId, template.id);
    expect(withoutOwn.definition.modality, CardioModality.rowingErgometer);
    expect(withoutOwn.targetDistanceKm, isNull);
    final withOwn = CardioPrescriptionEngine.recommend(
      exerciseId: template.id,
      definitionExerciseId: 'rowing_machine',
      goal: TrainingGoal.endurance,
      history: [builtinHistory, ownHistory],
      now: _day,
    )!;
    expect(withOwn.targetDistanceKm, 3);
    expect(withOwn.completedModerateEquivalentMinutes, 40);
    expect(ownHistory.validate(), isEmpty);
    expect(
      CardioPrescriptionEngine.recommend(
        exerciseId: template.id,
        goal: TrainingGoal.endurance,
        history: [],
        now: _day,
      ),
      isNull,
    );
    expect(
      _recommend([template], focus: {}, goals: ['체력 향상'])!.template.id,
      template.id,
    );
  });

  test(
    'custom cardio impact restriction is enforced and invalid reference history is ignored',
    () {
      final template = _custom(
        muscle: '유산소',
        info: CustomExerciseRecommendation(
          enabled: true,
          requiredEquipment: {TrainingEquipment.bodyweight},
          minimumExperience: TrainingExperienceLevel.beginner,
          cardioDefinitionId: 'run',
        ),
      );
      expect(
        _recommend(
          [template],
          focus: {},
          goals: ['체력 향상'],
          profile: _profile(
            equipment: {TrainingEquipment.bodyweight},
            restrictions: {TrainingMovementRestriction.impact},
          ),
        ),
        isNull,
      );
      final invalid = CardioSessionRecord(
        id: 'old-kind',
        exerciseId: template.id,
        definitionExerciseId: 'rowing_machine',
        occurredAt: _day.subtract(const Duration(days: 2)),
        duration: const Duration(minutes: 20),
        intensity: CardioIntensity.moderate,
        distanceKm: 5,
      );
      final result = CardioPrescriptionEngine.recommend(
        exerciseId: template.id,
        definitionExerciseId: 'run',
        goal: TrainingGoal.endurance,
        history: [invalid],
        now: _day,
      )!;
      expect(result.targetDistanceKm, isNull);
      expect(result.completedModerateEquivalentMinutes, 0);
    },
  );
}
