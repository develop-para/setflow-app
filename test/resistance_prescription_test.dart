import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/domain/personal_coaching.dart';
import 'package:setflow/services/resistance_prescription_engine.dart';

final _day = DateTime(2026, 9, 15);
ExerciseTemplate _template(String id) =>
    exerciseCatalog.firstWhere((item) => item.id == id);
WorkoutSession _session(
  String id, {
  int daysAgo = 0,
  int sets = 3,
  int reps = 12,
  double weight = 60,
  bool completed = true,
  int? rir,
  String type = '일반',
}) => WorkoutSession(
  date: _day.subtract(Duration(days: daysAgo)),
  exercises: [
    WorkoutExercise(
      id: '${id}_$daysAgo',
      template: _template(id),
      sets: [
        for (var i = 0; i < sets; i++)
          WorkoutSetEntry(
            number: i + 1,
            weight: weight,
            reps: reps,
            completed: completed,
            rir: rir,
            type: type,
          ),
      ],
    ),
  ],
);
WorkoutRecommendation _prescribe({
  String id = 'bench',
  List<WorkoutSession> history = const [],
  WorkoutSession? session,
  RecommendationProfile? profile,
  PersonalCoachingPlan? coachingPlan,
  bool allowAdditionalVolume = false,
}) => ResistancePrescriptionEngine.prescribe(
  template: _template(id),
  goal: TrainingGoal.hypertrophy,
  history: history,
  session: session ?? WorkoutSession(date: _day, exercises: []),
  profile: profile,
  coachingPlan: coachingPlan,
  allowAdditionalVolume: allowAdditionalVolume,
);

void main() {
  test(
    'weight apply raises only lighter pending working sets and undo preserves new work',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      final session = _session('bench', sets: 6, weight: 40, completed: false);
      state.sessions[_day] = session;
      final exercise = session.exercises.single;
      final sets = exercise.sets;
      sets[1].weight = 80;
      sets[2].completed = true;
      sets[3].type = '웜업';
      final before = state.updateSetWeight(exercise, sets.first, 60);
      expect(sets.map((set) => set.weight), [60, 80, 40, 40, 60, 60]);
      sets[4].completed = true;
      state.restorePendingWeights(exercise, before, 60);
      expect(sets.map((set) => set.weight), [60, 80, 40, 40, 60, 40]);
      final snapshot = AppState.snapshotPendingSets(exercise, sets.first);
      state.adoptActualIntoPendingSets(exercise, sets.first);
      expect(sets[1].weight, 80, reason: '완료 시에도 더 무거운 계획을 낮추지 않는다');
      sets.last.completed = true;
      state.restorePendingSets(snapshot);
      expect(sets.last.weight, 60, reason: '되돌리기가 새로 완료한 기록을 바꾸면 안 된다');
    },
  );

  test('same exercise history supports high repetitions without an e1RM', () {
    final result = _prescribe(
      history: [_session('bench', daysAgo: 2, reps: 15)],
    );
    expect(result.weight, 60);
    expect(result.minReps, 8);
    expect(result.maxReps, 12);
    expect(_prescribe(history: [_session('squat', daysAgo: 2)]).weight, 0);
  });

  test(
    'two complete successful exposures progress once; failure and partial sets do not',
    () {
      final previous = _session('bench', daysAgo: 5, rir: 2);
      expect(
        _prescribe(
          history: [_session('bench', daysAgo: 2, rir: 2), previous],
        ).weight,
        62.5,
      );
      expect(
        _prescribe(
          history: [_session('bench', daysAgo: 2, rir: 0), previous],
        ).weight,
        60,
      );
      expect(
        _prescribe(
          history: [_session('bench', daysAgo: 2, sets: 1), previous],
        ).weight,
        60,
      );
      expect(
        _prescribe(
          history: [_session('bench', daysAgo: 2, completed: false), previous],
        ).weight,
        60,
      );
    },
  );

  test('warmups future records and seeded workouts cannot set the load', () {
    final seed = _session('bench', daysAgo: 1);
    seed.exercises[0] = WorkoutExercise(
      id: 'seed_bench',
      template: _template('bench'),
      sets: seed.exercises[0].sets,
    );
    final result = _prescribe(
      history: [
        seed,
        _session('bench', daysAgo: -1, weight: 200),
        _session('bench', daysAgo: 2, type: '웜업', weight: 20),
      ],
    );
    expect(result.weight, 0);
  });

  test('persistent missed reps and long breaks reduce load', () {
    expect(
      _prescribe(
        history: [
          _session('bench', daysAgo: 2, reps: 6),
          _session('bench', daysAgo: 5, reps: 6),
        ],
      ).weight,
      57,
    );
    expect(_prescribe(history: [_session('bench', daysAgo: 40)]).weight, 54);
  });

  test('load adjustments report the actual rounded weights and app rule', () {
    final returning = _prescribe(
      history: [_session('bench', daysAgo: 40, weight: 3.5)],
    );
    expect(returning.weight, 3);
    expect(returning.reason, contains('이 종목의 마지막 기록'));
    expect(returning.reason, contains('약 10% 감량을 기준으로 한 앱 조정'));
    expect(returning.reason, contains('0.5kg 단위를 반영해 3.5kg → 3kg'));
    expect(returning.summary, contains('3.5kg → 3kg'));

    final missed = _prescribe(
      history: [
        _session('bench', daysAgo: 2, reps: 6, weight: 3.5),
        _session('bench', daysAgo: 5, reps: 6, weight: 3.5),
      ],
    );
    expect(missed.weight, 3);
    expect(missed.reason, contains('약 5% 감량을 기준으로 한 앱 조정'));
    expect(missed.reason, contains('0.5kg 단위를 반영해 3.5kg → 3kg'));
    expect(missed.summary, contains('3.5kg → 3kg'));
  });

  test('load reductions preserve positive small recorded weights', () {
    for (final weight in [0.25, 0.5]) {
      final returningRecord = _session('bench', daysAgo: 40, weight: weight);
      final returning = _prescribe(history: [returningRecord]);
      expect(returning.weight, weight);
      expect(returning.reason, contains('0kg이 되지 않도록 기존 중량을 유지'));
      expect(returning.reason, contains('${weight}kg → ${weight}kg'));
      expect(returningRecord.exercises.single.sets.first.weight, weight);

      final missed = _prescribe(
        history: [
          _session('bench', daysAgo: 2, reps: 6, weight: weight),
          _session('bench', daysAgo: 5, reps: 6, weight: weight),
        ],
      );
      expect(missed.weight, weight);
      expect(missed.reason, contains('0kg이 되지 않도록 기존 중량을 유지'));
    }
  });

  test(
    'different weights and oversized increments cannot trigger a load increase',
    () {
      expect(
        _prescribe(
          history: [
            _session('bench', daysAgo: 2),
            _session('bench', daysAgo: 5, weight: 50),
          ],
        ).weight,
        60,
      );
      expect(
        _prescribe(
          history: [
            _session('bench', daysAgo: 2, weight: 2),
            _session('bench', daysAgo: 5, weight: 2),
          ],
        ).weight,
        2,
      );
    },
  );

  test(
    'total session budget stops full recommendations before an excessive workout',
    () {
      final session = _session('bench', sets: 18)..trainingFocus = {};
      expect(
        ExerciseRecommendationEngine.recommendNext(
          catalog: exerciseCatalog,
          session: session,
          completedExercise: session.exercises.single,
          goals: ['근육 증가'],
        ),
        isNull,
      );
    },
  );

  test(
    'additional volume retains base prescription instead of clipping to one set',
    () {
      final session = _session('bench', sets: 18);
      final defaultResult = _prescribe(session: session);
      final extra = _prescribe(session: session, allowAdditionalVolume: true);
      expect(defaultResult.sets, 1);
      expect(extra.sets, 3);
      expect(extra.targetRepsBySet, [8, 8, 8]);
      expect(extra.reason, contains('앱의 기본 추천 계획을 넘어'));
      expect(extra.summary, contains('직접 요청한 추가 운동'));
      expect(
        _prescribe(
          id: 'curl',
          session: session,
          allowAdditionalVolume: true,
        ).sets,
        2,
      );
      expect(
        _prescribe(session: session).sets,
        1,
        reason: '추가 요청은 이후 처방에 남지 않는다',
      );
      expect(session.exercises.single.sets, hasLength(18));
    },
  );

  test(
    'explicit requests inside the default plan keep ordinary explanations',
    () {
      for (final session in [
        WorkoutSession(date: _day, exercises: []),
        _session('bench', sets: 3),
      ]) {
        final result = _prescribe(
          session: session,
          allowAdditionalVolume: true,
        );
        expect(result.sets, 3);
        expect(result.reason, isNot(contains('추가 추천 요청')));
        expect(result.summary, isNot(contains('추가 운동 추천')));
        expect(result.reason, contains('남은 운동량을 반영해 3세트'));
      }

      final exceeds = _prescribe(
        session: _session('bench', sets: 4),
        allowAdditionalVolume: true,
      );
      expect(exceeds.sets, 3);
      expect(exceeds.reason, contains('앱의 기본 추천 계획을 넘어'));
      expect(exceeds.summary, contains('직접 요청한 추가 운동 추천'));
    },
  );

  test(
    'time-limited coaching sets retain the repetition targets that were fitted',
    () {
      final history = [
        for (final daysAgo in [1, 3, 5, 7])
          _session('bench', daysAgo: daysAgo, sets: 3, reps: 8, rir: 2),
      ];
      final session = WorkoutSession(date: _day, exercises: []);
      final coaching = PersonalCoachingPlan(
        weekStart: _day.subtract(Duration(days: _day.weekday - 1)),
        targets: {
          TrainingMuscle.chest: const MuscleCoachingTarget(
            muscle: TrainingMuscle.chest,
            weeklySets: 20,
            dailySets: 10,
            trainingDays: 2,
            historyDays: 4,
            adjustment: CoachingAdjustment.increase,
            reason: '최근 수행을 참고해 세트 추가를 제안합니다.',
          ),
        },
      );

      WorkoutRecommendation prescribe({int? maximumSets}) =>
          ResistancePrescriptionEngine.prescribe(
            template: _template('bench'),
            goal: TrainingGoal.hypertrophy,
            history: history,
            session: session,
            coachingPlan: coaching,
            maximumSets: maximumSets,
          );

      final full = prescribe();
      final fitted = prescribe(maximumSets: 3);
      expect(full.sets, 4);
      expect(full.targetRepsBySet, [8, 8, 8, 8]);
      expect(fitted.sets, 3);
      expect(fitted.targetRepsBySet, [8, 8, 8]);
      expect(
        fitted.targetRepsBySet,
        full.targetRepsBySet.take(3).toList(),
        reason: '세트를 줄인 뒤 +1회 판단이 새로 켜지면 시간 추정도 늘어난다',
      );
      expect(fitted.weight, full.weight);
      expect(fitted.historyCount, 4);
      expect(fitted.reason, contains('이번 목표는 8 / 8 / 8회'));
      expect(fitted.reason, contains('3세트를 제안합니다'));
      expect(fitted.reason, isNot(contains('4세트를 제안합니다')));
      expect(
        history.map((item) => item.exercises.single.sets.length),
        everyElement(3),
      );
      expect(
        history
            .expand((item) => item.exercises.single.sets)
            .map((set) => set.reps),
        everyElement(8),
      );
      expect(session.exercises, isEmpty);
    },
  );

  test('additional explanation uses the final fatigue-adjusted set count', () {
    final fatigued = RecommendationProfile(
      experienceLevel: TrainingExperienceLevel.intermediate,
      availableEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
      painRegions: const {},
      painLevel: 0,
      restrictedMovements: const {},
      injuryNote: '',
      recoveryStatus: TrainingRecoveryStatus.fatigued,
      recoveryRecordedAt: _day,
      updatedAt: _day,
    );
    final result = _prescribe(
      session: _session('bench', sets: 4),
      history: [_session('bench', daysAgo: 2, weight: 0.5)],
      profile: fatigued,
      allowAdditionalVolume: true,
    );
    expect(result.sets, 2, reason: '피로 조정 후 두 세트는 남은 기본 계획 안에 들어간다');
    expect(result.reason, isNot(contains('추가 추천 요청')));
    expect(result.summary, isNot(contains('추가 운동 추천')));
    expect(result.weight, 0.5);
    expect(result.reason, contains('오늘 입력한 피로'));
    expect(result.reason, contains('약 10% 감량을 기준으로 한 앱 조정'));
    expect(result.reason, contains('0.5kg → 0.5kg'));
  });

  test(
    'additional volume keeps fatigue and return reductions and same-exercise load',
    () {
      final session = _session('bench', sets: 18);
      final fatigued = RecommendationProfile(
        experienceLevel: TrainingExperienceLevel.intermediate,
        availableEquipment: {
          TrainingEquipment.barbell,
          TrainingEquipment.bench,
        },
        painRegions: const {},
        painLevel: 0,
        restrictedMovements: const {},
        injuryNote: '',
        recoveryStatus: TrainingRecoveryStatus.fatigued,
        recoveryRecordedAt: _day,
        updatedAt: _day,
      );
      final fatigueResult = _prescribe(
        history: [_session('bench', daysAgo: 2)],
        session: session,
        profile: fatigued,
        allowAdditionalVolume: true,
      );
      expect(fatigueResult.sets, 2);
      expect(fatigueResult.weight, 54);
      final returnResult = _prescribe(
        history: [_session('bench', daysAgo: 40)],
        session: session,
        allowAdditionalVolume: true,
      );
      expect(returnResult.sets, 2);
      expect(returnResult.weight, 54);
      expect(returnResult.trend, RecommendationTrend.returning);
      expect(
        _prescribe(
          id: 'curl',
          history: [_session('bench', daysAgo: 2)],
          session: session,
          allowAdditionalVolume: true,
        ).weight,
        0,
      );
    },
  );

  test(
    'additional volume keeps personal coaching per-exercise bounds without the budget clamp',
    () {
      final coaching = PersonalCoachingPlan(
        weekStart: ResistancePrescriptionEngine.weekStart(_day),
        targets: {
          TrainingMuscle.chest: const MuscleCoachingTarget(
            muscle: TrainingMuscle.chest,
            weeklySets: 12,
            dailySets: 6,
            trainingDays: 2,
            historyDays: 4,
            adjustment: CoachingAdjustment.maintain,
            reason: '가슴 기록 기반 계획 유지',
          ),
        },
      );
      final history = [
        for (var daysAgo = 1; daysAgo <= 4; daysAgo++)
          _session('bench', daysAgo: daysAgo, sets: 6, reps: 10),
      ];
      final session = _session('bench', sets: 18);
      expect(
        _prescribe(
          history: history,
          session: session,
          coachingPlan: coaching,
        ).sets,
        1,
      );
      final result = _prescribe(
        history: history,
        session: session,
        coachingPlan: coaching,
        allowAdditionalVolume: true,
      );
      expect(result.sets, 5);
      expect(result.weight, 60);
      expect(result.targetRepsBySet, hasLength(5));
      expect(result.reason, contains('가슴 기록 기반 계획 유지'));
    },
  );

  test(
    'catalog preview and added exercise use the same historical load and reps',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      state.setMemberProfile(goals: ['근육 증가']);
      final previous = _session('bench', daysAgo: 2, reps: 15);
      state.sessions[previous.date] = previous;
      state.setDefaultSetPlan(sets: 5, reps: 20);
      final preview = state.recommendationFor(
        _template('bench'),
        before: _day,
      )!;
      state.addExercise(_day, _template('bench'));
      final sets = state.sessionFor(_day).exercises.single.sets;
      expect(sets.first.weight, preview.weight);
      expect(sets.map((set) => set.reps), preview.targetRepsBySet);
      expect(sets.length, preview.sets);
    },
  );

  test(
    'volume includes today once and indirect arms only within the calendar week',
    () {
      final today = _session('bench');
      final volume = ResistancePrescriptionEngine.volume(
        session: today,
        history: [
          today,
          _session('bench', daysAgo: 1, sets: 2),
          _session('bench', daysAgo: 2, sets: 10),
          _session('bench', daysAgo: 7, sets: 10),
          _session('bench', daysAgo: -1, sets: 10),
          _session('bench', daysAgo: 1, sets: 5, type: '웜업'),
        ],
      );
      expect(volume[TrainingMuscle.chest], 5);
      expect(volume[TrainingMuscle.triceps], 2.5);
      expect(volume[TrainingMuscle.biceps], isNull);
      final next = _prescribe(
        id: 'incline',
        session: _session('bench', sets: 5),
        history: [],
      );
      expect(next.sets, 1, reason: '오늘 남은 부위 예산만 제안한다');
    },
  );

  test(
    'first Monday recommendation and prescription ignore last Sunday volume',
    () {
      final monday = DateTime(2026, 10, 12);
      final sunday = DateTime(2026, 10, 11);
      final previous = WorkoutSession(
        date: sunday,
        exercises: _session('bench', sets: 12).exercises,
      );
      final session = WorkoutSession(
        date: monday,
        exercises: [],
        trainingFocus: {TrainingMuscle.chest},
      );
      final history = [previous];
      expect(
        ResistancePrescriptionEngine.volume(
              history: history,
              session: session,
            )[TrainingMuscle.chest] ??
            0,
        0,
      );
      final recommendation = ExerciseRecommendationEngine.recommendFirst(
        catalog: [_template('bench')],
        session: session,
        goals: ['근육 증가'],
        weeklyHistory: history,
      );
      expect(recommendation, isNotNull);
      expect(recommendation!.sets, 3);
      final prescription = _prescribe(history: history, session: session);
      expect(prescription.sets, 3);
      expect(prescription.weight, 60, reason: '지난주 기록은 중량 참고에 계속 사용한다');
      expect(prescription.reason, contains('이번 주 완료량과 오늘 계획은 가슴 0세트'));
      expect(previous.exercises.single.sets, hasLength(12));
      expect(
        previous.exercises.single.sets.every((set) => set.completed),
        isTrue,
      );
      expect(session.exercises, isEmpty);
      expect(
        ResistancePrescriptionEngine.volume(
          history: history,
          session: session,
          since: sunday,
        )[TrainingMuscle.chest],
        12,
        reason: '명시한 집계 시작일은 그대로 적용한다',
      );
      expect(
        ResistancePrescriptionEngine.volume(
          history: history,
          session: session,
          since: sunday,
          todayOnly: true,
        ),
        isEmpty,
      );
    },
  );

  test('current week volume still blocks recommendations through Sunday', () {
    final monday = DateTime(2026, 10, 12);
    final previous = WorkoutSession(
      date: monday,
      exercises: _session('bench', sets: 12).exercises,
    );
    for (final date in [DateTime(2026, 10, 13), DateTime(2026, 10, 18)]) {
      final session = WorkoutSession(
        date: date,
        exercises: [],
        trainingFocus: {TrainingMuscle.chest},
      );
      expect(
        ResistancePrescriptionEngine.volume(
          history: [previous],
          session: session,
        )[TrainingMuscle.chest],
        12,
      );
      final result = ExerciseRecommendationEngine.evaluateFirst(
        catalog: [_template('bench')],
        session: session,
        goals: ['근육 증가'],
        weeklyHistory: [previous],
      );
      expect(result.recommendation, isNull);
      expect(result.stopReason, ExerciseRecommendationStopReason.volumeReached);
      expect(session.exercises, isEmpty);
    }
  });

  test('calendar week volume crosses month and year boundaries', () {
    for (final (date, monday) in [
      (DateTime(2026, 10, 1), DateTime(2026, 9, 28)),
      (DateTime(2027, 1, 1), DateTime(2026, 12, 28)),
    ]) {
      WorkoutSession record(DateTime date, int sets) => WorkoutSession(
        date: date,
        exercises: _session('bench', sets: sets).exercises,
      );
      final session = record(date, 1);
      final volume = ResistancePrescriptionEngine.volume(
        session: session,
        history: [
          record(monday.subtract(const Duration(days: 1)), 12),
          record(monday, 2),
          record(date.subtract(const Duration(days: 1)), 3),
          session,
          record(date.add(const Duration(days: 1)), 12),
        ],
      );
      expect(ResistancePrescriptionEngine.weekStart(date), monday);
      expect(volume[TrainingMuscle.chest], 6);
      expect(volume[TrainingMuscle.triceps], 3);
    }
  });

  test('completion undo preserves later manual changes to pending sets', () {
    final state = AppState();
    addTearDown(state.dispose);
    final exercise = _session('bench', completed: false).exercises.single;
    exercise.sets.first.reps = 8;
    final before = AppState.snapshotPendingSets(exercise, exercise.sets.first);
    state.adoptActualIntoPendingSets(exercise, exercise.sets.first);
    final applied = AppState.snapshotPendingSets(exercise, exercise.sets.first);
    exercise.sets.last.reps = 7;
    state.restorePendingSets(before, expected: applied);
    expect(exercise.sets[1].reps, 12);
    expect(exercise.sets.last.reps, 7);
  });

  test('isolation and beginner plans are smaller than compound plans', () {
    expect(_prescribe(id: 'curl').sets, 2);
    expect(_prescribe(id: 'curl').minReps, 10);
    final profile = RecommendationProfile(
      experienceLevel: TrainingExperienceLevel.beginner,
      availableEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
      painRegions: const {},
      painLevel: 0,
      restrictedMovements: const {},
      injuryNote: '',
      recoveryStatus: TrainingRecoveryStatus.normal,
      recoveryRecordedAt: _day,
      updatedAt: _day,
    );
    expect(_prescribe(profile: profile).sets, 2);
    expect(_prescribe().sets, 3);
  });

  for (final focus in TrainingMuscle.values) {
    test(
      'selected ${focus.label} stays a hard constraint through all alternatives',
      () {
        final session = WorkoutSession(
          date: _day,
          exercises: [],
          trainingFocus: {focus},
        );
        final excluded = <String>{};
        var count = 0;
        while (true) {
          final next = ExerciseRecommendationEngine.recommendFirst(
            catalog: exerciseCatalog,
            session: session,
            goals: ['근육 증가'],
            excludedTemplateIds: excluded,
          );
          if (next == null) break;
          expect(
            ResistancePrescriptionEngine.primaryMuscles(next.template),
            contains(focus),
          );
          expect(excluded.add(next.template.id), isTrue);
          count++;
          expect(count, lessThan(exerciseCatalog.length));
        }
        expect(count, greaterThan(0));
      },
    );
  }

  test(
    'selected body parts stop at daily volume and never fall through to other muscles',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      state.setMemberProfile(goals: ['근육 증가']);
      final session = _session('bench', sets: 6)
        ..trainingFocus = {TrainingMuscle.chest};
      state.sessions[_day] = session;
      expect(
        state.nextExerciseRecommendationForDate(
          _day,
          completedExercise: session.exercises.single,
        ),
        isNull,
      );
      expect(state.recommendationForDate(_day), isNull);
      state.setTrainingFocus(_day, {});
      expect(
        state.nextExerciseRecommendationForDate(
          _day,
          completedExercise: session.exercises.single,
        ),
        isNotNull,
      );
    },
  );

  test(
    'familiar same-muscle exercise stays stable across dates without arbitrary rotation',
    () {
      final history = [_session('bench', daysAgo: 10)];
      for (var offset = 0; offset < 4; offset++) {
        final result = ExerciseRecommendationEngine.recommendFirst(
          catalog: exerciseCatalog,
          session: WorkoutSession(
            date: _day.add(Duration(days: offset)),
            exercises: [],
            trainingFocus: {TrainingMuscle.chest},
          ),
          goals: ['근육 증가'],
          weeklyHistory: history,
        )!;
        expect(result.template.id, 'bench');
        expect(result.startingWeight, 60);
      }
    },
  );

  test(
    'focus and explicit complete recommendation persist before any exercise exists',
    () async {
      final repository = _MemoryRepository();
      final state = AppState(repository: repository);
      await state.initialize();
      state.setTrainingFocus(_day, {
        TrainingMuscle.chest,
        TrainingMuscle.triceps,
      });
      state.setTrainingFocus(_day.add(const Duration(days: 1)), {});
      await state.flushPersistence();
      state.dispose();
      final reloaded = AppState(repository: repository);
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.sessionFor(_day).trainingFocus, {
        TrainingMuscle.chest,
        TrainingMuscle.triceps,
      });
      expect(
        reloaded.sessionFor(_day.add(const Duration(days: 1))).trainingFocus,
        isEmpty,
      );
      expect(
        reloaded.sessionFor(_day.add(const Duration(days: 2))).trainingFocus,
        isNull,
      );
      expect(
        AppSnapshotCodec.sessionFromJson({
          'date': _day.toIso8601String(),
          'exercises': [],
        }, exerciseCatalog)!.trainingFocus,
        isNull,
      );
    },
  );
}

class _MemoryRepository implements AppRepository {
  String? value;
  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> catalog) async =>
      value == null ? null : AppSnapshotCodec.decode(value!, catalog);
  @override
  Future<void> save(AppSnapshot snapshot) async {
    value = AppSnapshotCodec.encode(snapshot);
  }
}
