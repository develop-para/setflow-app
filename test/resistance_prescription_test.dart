import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
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
}) => ResistancePrescriptionEngine.prescribe(
  template: _template(id),
  goal: TrainingGoal.hypertrophy,
  history: history,
  session: session ?? WorkoutSession(date: _day, exercises: []),
  profile: profile,
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
      expect(sets.first.reps, preview.minReps);
      expect(sets.length, preview.sets);
    },
  );

  test(
    'volume includes today once and indirect arms, spanning Sunday to Monday',
    () {
      final today = _session('bench');
      final volume = ResistancePrescriptionEngine.volume(
        session: today,
        history: [
          today,
          _session('bench', daysAgo: 2, sets: 2),
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
