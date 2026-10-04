import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/hive_app_repository.dart';
import 'package:setflow/domain/exercise_recommendation_traits.dart';
import 'package:setflow/domain/exercise_substitutions.dart';
import 'package:setflow/services/resistance_prescription_engine.dart';
import 'package:setflow/services/workout_time_budget.dart';

final _day = DateTime(2026, 10, 4);
ExerciseTemplate _exercise(String id) =>
    exerciseCatalog.firstWhere((item) => item.id == id);

WorkoutSession _history(
  int daysAgo,
  int reps, {
  double weight = 60,
  int count = 3,
  String type = '일반',
}) => WorkoutSession(
  date: _day.subtract(Duration(days: daysAgo)),
  exercises: [
    WorkoutExercise(
      id: 'history-$daysAgo',
      template: _exercise('bench'),
      sets: [
        for (var index = 0; index < count; index++)
          WorkoutSetEntry(
            number: index + 1,
            weight: weight,
            reps: reps,
            type: type,
            completed: true,
          ),
      ],
    ),
  ],
);

WorkoutRecommendation _prescribe(List<WorkoutSession> history) =>
    ResistancePrescriptionEngine.prescribe(
      template: _exercise('bench'),
      goal: TrainingGoal.hypertrophy,
      history: history,
      session: WorkoutSession(date: _day, exercises: []),
    );

NextExerciseRecommendation? _first({
  WorkoutSession? session,
  List<ExerciseTemplate>? catalog,
  List<WorkoutSession> history = const [],
  RecommendationPreferences preferences = const RecommendationPreferences(),
  ExerciseTemplate? alternativeTo,
  RecommendationProfile? profile,
  List<String> goals = const ['근육 증가'],
}) => ExerciseRecommendationEngine.recommendFirst(
  catalog: catalog ?? exerciseCatalog,
  session: session ?? WorkoutSession(date: _day, exercises: []),
  goals: goals,
  weeklyHistory: history,
  preferences: preferences,
  alternativeTo: alternativeTo,
  recommendationProfile: profile,
);

void main() {
  test(
    'duration holds materialize their recommended work time rather than fake repetitions',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.setMemberProfile(goals: ['근육 증가']);
      state.setTrainingFocus(_day, {TrainingMuscle.core});
      state.setWorkoutTimeBudget(_day, 5);
      final result = state.firstExerciseRecommendationForDate(_day)!;
      expect(result.template.isDurationHold, isTrue);
      state.addRecommendedExercise(_day, result);
      final session = state.sessionFor(_day);
      expect(
        session.exercises.single.sets.map((set) => set.durationSeconds),
        everyElement(60),
      );
      expect(
        session.exercises.single.sets.map((set) => set.reps),
        everyElement(0),
      );
      expect(
        WorkoutTimeBudget.estimateSessionSeconds(session),
        result.estimatedDurationSeconds,
      );
    },
  );
  test(
    'time budget reduces new sets while successful load progression stays based on full history',
    () {
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        timeBudgetMinutes: 5,
        trainingFocus: {TrainingMuscle.chest},
      );
      final result = _first(
        session: session,
        catalog: [_exercise('bench')],
        history: [_history(2, 12), _history(9, 12)],
      )!;
      expect(result.sets, 2);
      expect(result.startingWeight, 62.5);
      expect(result.estimatedDurationSeconds, lessThanOrEqualTo(300));
      expect(result.summary, contains('남은 시간'));
    },
  );

  test(
    'automatic additions including rest and transitions stop inside the cumulative budget',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: ['근육 증가']);
      state.setTrainingFocus(_day, {});
      state.setWorkoutTimeBudget(_day, 15);
      var next = state.firstExerciseRecommendationForDate(_day);
      var count = 0;
      while (next != null) {
        expect(state.addRecommendedExercise(_day, next), isTrue);
        final session = state.sessionFor(_day);
        expect(
          WorkoutTimeBudget.estimateSessionSeconds(session),
          lessThanOrEqualTo(900),
        );
        final last = session.exercises.last;
        for (final set in last.sets) {
          set.completed = true;
        }
        next = state.nextExerciseRecommendationForDate(
          _day,
          completedExercise: last,
        );
        count++;
        expect(count, lessThan(10));
      }
      expect(count, greaterThan(0));
    },
  );

  test(
    'spent time never removes or edits completed and pending records',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.setMemberProfile(goals: ['근육 증가']);
      state.sessions[_day] = _history(0, 12, count: 8);
      final session = state.sessionFor(_day);
      session.exercises.single.sets.last.completed = false;
      final before = AppSnapshotCodec.sessionToJson(session);
      state.setWorkoutTimeBudget(_day, 5);
      expect(
        state.nextExerciseRecommendationForDate(
          _day,
          completedExercise: session.exercises.single,
        ),
        isNull,
      );
      final after = AppSnapshotCodec.sessionToJson(session)
        ..remove('timeBudgetMinutes');
      expect(after, before);
    },
  );

  test(
    'actual elapsed time with pending plans reserves more than the static estimate',
    () {
      final session = _history(0, 10, count: 1);
      session.startedAt = _day.add(const Duration(hours: 10));
      session.exercises.single.sets.single.completed = false;
      final now = _day.add(const Duration(hours: 10, minutes: 29));
      session.timeBudgetMinutes = 30;
      expect(WorkoutTimeBudget.availableSeconds(session, now: now), 0);
    },
  );

  test(
    'continuous cardio fits remaining time and keeps an unknown distance unknown',
    () {
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        timeBudgetMinutes: 15,
      );
      final result = _first(
        session: session,
        catalog: [_exercise('run')],
        goals: ['체력 향상'],
      )!;
      expect(result.cardioPrescription!.durationSeconds, 13 * 60);
      expect(result.cardioPrescription!.targetDistanceKm, isNull);
      expect(result.estimatedDurationSeconds, lessThanOrEqualTo(15 * 60));
      session.timeBudgetMinutes = 5;
      expect(
        _first(session: session, catalog: [_exercise('run')], goals: ['체력 향상']),
        isNull,
      );
    },
  );

  test(
    'replacement keeps the reviewed movement and avoids the explicitly unavailable equipment',
    () {
      final bench = _exercise('bench');
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        trainingFocus: {TrainingMuscle.chest},
        skippedRecommendationIds: {'bench'},
        unavailableEquipmentExerciseIds: {'bench'},
      );
      final result = _first(
        session: session,
        alternativeTo: bench,
        history: [_history(2, 12, weight: 100)],
      )!;
      expect(ExerciseSubstitutions.matches(bench, result.template), isTrue);
      expect(
        exerciseRecommendationTraits[result.template.id]!.requiredEquipment,
        isNot(contains(TrainingEquipment.barbell)),
      );
      expect(result.startingWeight, 0, reason: '벤치 중량을 대체 종목으로 옮기지 않는다');
      expect(result.summary, contains('같은 동작'));
    },
  );

  test(
    'no eligible equivalent ends replacement without changing movement or body part',
    () {
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        skippedRecommendationIds: {'bench'},
      );
      expect(
        _first(
          session: session,
          catalog: [
            _exercise('bench'),
            _exercise('squat'),
            _exercise('cable_fly'),
          ],
          alternativeTo: _exercise('bench'),
        ),
        isNull,
      );
    },
  );

  test(
    'replacement still respects experience restrictions and declared equipment',
    () {
      final profile = RecommendationProfile(
        experienceLevel: TrainingExperienceLevel.beginner,
        availableEquipment: {TrainingEquipment.bodyweight},
        painRegions: {},
        painLevel: 0,
        restrictedMovements: {TrainingMovementRestriction.horizontalPress},
        injuryNote: '',
        recoveryStatus: TrainingRecoveryStatus.normal,
        recoveryRecordedAt: _day,
        updatedAt: _day,
      );
      expect(
        _first(alternativeTo: _exercise('bench'), profile: profile),
        isNull,
      );
    },
  );

  test('all reviewed substitution IDs exist in the curated catalog', () {
    final ids = exerciseCatalog.map((exercise) => exercise.id).toSet();
    for (final group in ExerciseSubstitutions.groups) {
      expect(ids.containsAll(group), isTrue, reason: '$group');
    }
  });

  test(
    'manual choices use distinct days, expire after 90 days, and ignore future dates',
    () {
      var preferences = const RecommendationPreferences();
      preferences = preferences.recordSelection('chest_press', _day);
      preferences = preferences.recordSelection(
        'chest_press',
        _day.add(const Duration(hours: 3)),
      );
      expect(preferences.preferenceFor('chest_press', _day), 1);
      preferences = preferences.recordSelection(
        'chest_press',
        _day.subtract(const Duration(days: 4)),
      );
      preferences = preferences.recordSelection(
        'chest_press',
        _day.subtract(const Duration(days: 91)),
      );
      preferences = preferences.recordSelection(
        'chest_press',
        _day.add(const Duration(days: 1)),
      );
      expect(preferences.preferenceFor('chest_press', _day), 2);
      expect(
        RecommendationPreferences.fromJson(preferences.toJson()).toJson(),
        preferences.toJson(),
      );
    },
  );

  test(
    'repeated manual choices change ranking without overriding explicit exclusion',
    () {
      var preferences = const RecommendationPreferences();
      preferences = preferences.recordSelection(
        'chest_press',
        _day.subtract(const Duration(days: 2)),
      );
      preferences = preferences.recordSelection(
        'chest_press',
        _day.subtract(const Duration(days: 9)),
      );
      final session = WorkoutSession(
        date: _day,
        exercises: [],
        trainingFocus: {TrainingMuscle.chest},
      );
      expect(
        _first(session: session, preferences: preferences)!.template.id,
        'chest_press',
      );
      final excluded = _first(
        session: session,
        preferences: preferences.exclude('chest_press', true),
      )!;
      expect(excluded.template.id, isNot('chest_press'));
      expect(
        _first(
          session: session,
          preferences: preferences
              .exclude('chest_press', true)
              .exclude('chest_press', false),
        )!.template.id,
        'chest_press',
      );
    },
  );

  test('today skip does not imply dislike or affect tomorrow', () {
    final session = WorkoutSession(
      date: _day,
      exercises: [],
      skippedRecommendationIds: {'bench'},
    );
    expect(_first(session: session, catalog: [_exercise('bench')]), isNull);
    expect(
      _first(
        session: WorkoutSession(
          date: _day.add(const Duration(days: 1)),
          exercises: [],
        ),
        catalog: [_exercise('bench')],
      )!.template.id,
      'bench',
    );
  });

  test(
    'accepting automatic recommendations does not record a manual preference',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      state.setMemberProfile(goals: ['근육 증가']);
      final next = state.firstExerciseRecommendationForDate(_day)!;
      state.addRecommendedExercise(_day, next);
      expect(state.recommendationPreferences.manualSelectionDays, isEmpty);
      state.addExercise(_day, _exercise('bench'));
      state.addExercise(_day, _exercise('bench'));
      expect(state.recommendationPreferences.preferenceFor('bench', _day), 1);
    },
  );

  test(
    'four comparable exposures detect decline and plateau without inferring pain or fatigue',
    () {
      final decline = _prescribe([
        _history(2, 9),
        _history(8, 10),
        _history(16, 11),
        _history(24, 12),
      ]);
      expect(decline.trend, RecommendationTrend.declining);
      expect(decline.weight, 60);
      expect(decline.sets, 2);
      expect(decline.summary, contains('1세트를 줄여'));
      expect(decline.summary, isNot(contains('피로')));
      final plateau = _prescribe([
        _history(2, 9),
        _history(8, 9),
        _history(16, 10),
        _history(24, 9),
      ]);
      expect(plateau.trend, RecommendationTrend.plateau);
      expect(plateau.weight, 60);
      expect(plateau.sets, 3);
    },
  );

  test(
    'different loads partial records or old exposures cannot manufacture a decline',
    () {
      for (final invalid in [
        _history(24, 12, weight: 80),
        _history(24, 12, count: 1),
        _history(60, 12),
      ]) {
        final result = _prescribe([
          _history(2, 9),
          _history(8, 10),
          _history(16, 11),
          invalid,
        ]);
        expect(result.trend, isNot(RecommendationTrend.declining));
        expect(result.sets, 3);
      }
    },
  );

  test(
    'duplicate same-day entries are one exposure and never two successful days',
    () {
      final result = _prescribe([_history(2, 12), _history(2, 12)]);
      expect(result.weight, 60);
      expect(result.historyCount, 1);
      expect(result.trend, RecommendationTrend.insufficient);
    },
  );

  test(
    'long break reduces new volume and load while retaining original records',
    () {
      final old = _history(40, 12);
      final result = _prescribe([old]);
      expect(result.trend, RecommendationTrend.returning);
      expect(result.weight, 54);
      expect(result.sets, 2);
      expect(old.exercises.single.sets.first.weight, 60);
    },
  );

  test(
    'summary and record count exclude warmups future and example records',
    () {
      final example = _history(3, 12);
      example.exercises[0] = WorkoutExercise(
        id: 'seed_bench',
        template: _exercise('bench'),
        sets: example.exercises.single.sets,
      );
      final result = _prescribe([
        example,
        _history(-1, 12),
        _history(2, 12, type: '웜업'),
      ]);
      expect(result.historyCount, 0);
      expect(result.summary, contains('기록이 없어'));
      expect(result.weight, 0);
    },
  );

  test(
    'guest restart preserves empty-day time skips unavailable gear and permanent preference',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'setflow_recommendation_',
      );
      HiveAppRepository? repository;
      AppState? state;
      try {
        repository = await HiveAppRepository.openAtPath(
          directory.path,
          boxName: 'advanced_recommendation',
        );
        state = AppState(repository: repository);
        await state.initialize();
        state.setWorkoutTimeBudget(_day, 30);
        state.skipRecommendedExercise(
          _day,
          'bench',
          equipmentUnavailable: true,
        );
        state.setExerciseExcludedFromRecommendations('squat', true);
        state.addExercise(
          _day.subtract(const Duration(days: 2)),
          _exercise('chest_press'),
        );
        await state.flushPersistence();
        state.dispose();
        state = null;
        await repository.close();
        repository = await HiveAppRepository.openAtPath(
          directory.path,
          boxName: 'advanced_recommendation',
        );
        state = AppState(repository: repository);
        await state.initialize();
        expect(state.sessionFor(_day).exercises, isEmpty);
        expect(state.sessionFor(_day).timeBudgetMinutes, 30);
        expect(state.sessionFor(_day).skippedRecommendationIds, {'bench'});
        expect(state.sessionFor(_day).unavailableEquipmentExerciseIds, {
          'bench',
        });
        expect(state.recommendationPreferences.excludedExerciseIds, {'squat'});
        expect(
          state.recommendationPreferences.preferenceFor('chest_press', _day),
          1,
        );
        expect(
          state.sessionFor(_day.add(const Duration(days: 1))).timeBudgetMinutes,
          isNull,
        );
      } finally {
        state?.dispose();
        await repository?.close();
        // 테스트가 직접 만든 임시 디렉터리만 삭제한다.
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'legacy or malformed optional recommendation settings default safely',
    () {
      expect(
        RecommendationPreferences.fromJson({
          'manualSelectionDays': {
            'bench': ['invalid', 1],
          },
          'excludedExerciseIds': [1, 'bench'],
        }).excludedExerciseIds,
        {'bench'},
      );
      final session = AppSnapshotCodec.sessionFromJson({
        'date': _day.toIso8601String(),
        'exercises': [],
        'timeBudgetMinutes': -20,
        'skippedRecommendationIds': 'invalid',
      }, exerciseCatalog)!;
      expect(session.timeBudgetMinutes, isNull);
      expect(session.skippedRecommendationIds, isEmpty);
    },
  );
}
