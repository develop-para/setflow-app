import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/personal_coaching_repository.dart';
import 'package:setflow/domain/personal_coaching.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/services/personal_coaching_engine.dart';
import 'package:setflow/services/resistance_prescription_engine.dart';

final day = DateTime(2026, 10, 5);
ExerciseTemplate template(String id) =>
    exerciseCatalog.firstWhere((item) => item.id == id);

List<WorkoutSession> history({
  List<int> reps = const [8, 9, 10, 11, 12, 13],
  int? rir = 3,
  List<String> ids = const ['bench'],
  int sets = 3,
}) => [
  for (var i = 0; i < 6; i++)
    WorkoutSession(
      date: day.subtract(Duration(days: [19, 16, 12, 9, 5, 2][i])),
      exercises: [
        for (final id in ids)
          WorkoutExercise(
            id: '${id}_$i',
            template: template(id),
            sets: [
              for (var number = 1; number <= sets; number++)
                WorkoutSetEntry(
                  number: number,
                  weight: 60,
                  reps: reps[i],
                  restSeconds: 120,
                  completed: true,
                  rir: rir,
                ),
            ],
          ),
      ],
    ),
];

PersonalCoachingPlan plan(
  List<WorkoutSession> records, {
  DateTime? date,
  int days = 3,
}) => PersonalCoachingEngine.build(
  date: date ?? day,
  history: records,
  goal: TrainingGoal.hypertrophy,
  plannedTrainingDays: days,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Auth.reset);

  test(
    'insufficient records keep default budgets and missing RIR never authorizes extra volume',
    () {
      expect(plan([]).targets[TrainingMuscle.chest]!.weeklySets, 12);
      expect(
        plan(
          history().take(3).toList(),
        ).targets[TrainingMuscle.chest]!.adjustment,
        CoachingAdjustment.insufficient,
      );
      final target = plan(history(rir: null)).targets[TrainingMuscle.chest]!;
      expect(target.adjustment, CoachingAdjustment.maintain);
      expect(target.weeklySets, 6);
    },
  );

  test(
    'comparable progression plus recorded reserve increases observed volume by two',
    () {
      final result = plan(history());
      final chest = result.targets[TrainingMuscle.chest]!;
      expect(chest.weeklySets, 8);
      expect(chest.dailySets, 4);
      expect(chest.trainingDays, 2);
      expect(chest.historyDays, 6);
      expect(chest.adjustment, CoachingAdjustment.increase);
      expect(chest.reason, contains('RIR 2 이상'));
      // Secondary sets count toward baseline, but cannot manufacture evidence
      // about the performance of this muscle's own exercises.
      expect(
        result.targets[TrainingMuscle.triceps]!.adjustment,
        CoachingAdjustment.insufficient,
      );
    },
  );

  test(
    'one declining exercise maintains volume; two repeatedly declining exercises reduce it',
    () {
      final reps = [13, 12, 11, 10, 9, 8];
      final one = plan(history(reps: reps)).targets[TrainingMuscle.chest]!;
      expect(one.adjustment, CoachingAdjustment.maintain);
      final two = plan(
        history(reps: reps, ids: ['bench', 'incline']),
      ).targets[TrainingMuscle.chest]!;
      expect(two.adjustment, CoachingAdjustment.reduce);
      expect(two.weeklySets, 10);
    },
  );

  test(
    'changed load, changed rest, partial workouts and unrecorded reserve block expansion',
    () {
      for (final change in ['load', 'rest', 'partial', 'reserve']) {
        final records = history();
        final latest = records.last.exercises.single.sets;
        for (final set in latest) {
          if (change == 'load') set.weight = 65;
          if (change == 'rest') set.restSeconds = 180;
          if (change == 'reserve') set.rir = 0;
        }
        if (change == 'partial') latest.last.completed = false;
        expect(
          plan(records).targets[TrainingMuscle.chest]!.adjustment,
          isNot(CoachingAdjustment.increase),
          reason: change,
        );
      }
    },
  );

  test(
    'warmups seeds future work duplicate snapshots and repeated same-day rows cannot inflate evidence',
    () {
      final records = history();
      final baseline = plan(records).targets[TrainingMuscle.chest]!;
      final duplicate = plan([
        ...records,
        ...records,
      ]).targets[TrainingMuscle.chest]!;
      expect(duplicate.weeklySets, baseline.weeklySets);
      expect(duplicate.historyDays, baseline.historyDays);
      final invalid = history();
      for (final session in invalid) {
        for (final set in session.exercises.single.sets) {
          set.type = '웜업';
        }
      }
      expect(plan(invalid).targets[TrainingMuscle.chest]!.historyDays, 0);
      final future = history()
          .map(
            (session) => WorkoutSession(
              date: day.add(const Duration(days: 1)),
              exercises: session.exercises,
            ),
          )
          .toList();
      expect(plan(future).targets[TrainingMuscle.chest]!.historyDays, 0);
      final seeded = history()
          .map(
            (session) => WorkoutSession(
              date: session.date,
              exercises: [
                WorkoutExercise(
                  id: 'seed_bench',
                  template: template('bench'),
                  sets: session.exercises.single.sets,
                ),
              ],
            ),
          )
          .toList();
      expect(plan(seeded).targets[TrainingMuscle.chest]!.historyDays, 0);
      final sameDay = history()
          .map(
            (session) => WorkoutSession(
              date: day.subtract(const Duration(days: 2)),
              exercises: session.exercises,
            ),
          )
          .toList();
      expect(
        plan(sameDay).targets[TrainingMuscle.chest]!.adjustment,
        CoachingAdjustment.insufficient,
      );
    },
  );

  test(
    'targets stay fixed during the week; new work only consumes the remaining budget',
    () {
      final records = history();
      final monday = plan(records);
      final session = WorkoutSession(
        date: day,
        trainingFocus: {TrainingMuscle.chest},
        exercises: [
          WorkoutExercise(
            id: 'today',
            template: template('bench'),
            sets: List.generate(
              4,
              (i) => WorkoutSetEntry(number: i + 1, weight: 60, reps: 10),
            ),
          ),
        ],
      );
      final friday = plan([
        ...records,
        session,
      ], date: day.add(const Duration(days: 4)));
      expect(
        friday.targets[TrainingMuscle.chest]!.weeklySets,
        monday.targets[TrainingMuscle.chest]!.weeklySets,
      );
      final next = ExerciseRecommendationEngine.recommendNext(
        catalog: exerciseCatalog,
        session: session,
        completedExercise: session.exercises.single,
        goals: ['근육 증가'],
        weeklyHistory: [...records, session],
        coachingPlan: monday,
      );
      expect(
        next,
        isNull,
        reason: 'unfinished plans reserve all four daily sets',
      );
    },
  );

  test(
    'personal budgets can recommend past the standard cap without bypassing time or focus',
    () {
      final records = history(sets: 5);
      final coaching = plan(records, days: 1);
      final session = WorkoutSession(
        date: day,
        trainingFocus: {TrainingMuscle.chest},
        exercises: [
          WorkoutExercise(
            id: 'today',
            template: template('bench'),
            sets: List.generate(
              6,
              (i) => WorkoutSetEntry(
                number: i + 1,
                weight: 60,
                reps: 10,
                completed: true,
              ),
            ),
          ),
        ],
      );
      NextExerciseRecommendation? next({PersonalCoachingPlan? coachingPlan}) =>
          ExerciseRecommendationEngine.recommendNext(
            catalog: exerciseCatalog,
            session: session,
            completedExercise: session.exercises.single,
            goals: ['근육 증가'],
            weeklyHistory: records,
            coachingPlan: coachingPlan,
          );
      expect(next(), isNull);
      final recommendation = next(coachingPlan: coaching)!;
      expect(recommendation.template.muscle, '가슴');
      expect(recommendation.personalCoachingReason, isNotEmpty);
      session.timeBudgetMinutes = 5;
      expect(next(coachingPlan: coaching), isNull);
    },
  );

  test(
    'week consumption excludes previous week and manual overload stays intact',
    () {
      final records = history(sets: 5);
      final coaching = plan(records);
      final session = WorkoutSession(date: day, exercises: []);
      final volume = ResistancePrescriptionEngine.volume(
        history: records,
        session: session,
        since: coaching.weekStart,
      );
      expect(volume[TrainingMuscle.chest] ?? 0, 0);
      expect(
        ResistancePrescriptionEngine.remainingSets(
          template: template('bench'),
          goal: TrainingGoal.hypertrophy,
          weeklyVolume: {TrainingMuscle.chest: 40},
          todayVolume: {},
          coachingPlan: coaching,
        ),
        0,
      );
      expect(records.last.exercises.single.sets.length, 5);
    },
  );

  test(
    'personal set progression grows within budget and never grows with a load increase',
    () {
      WorkoutRecommendation prescribe(List<WorkoutSession> records) =>
          ResistancePrescriptionEngine.prescribe(
            template: template('bench'),
            goal: TrainingGoal.hypertrophy,
            history: records,
            session: WorkoutSession(date: day, exercises: []),
            coachingPlan: plan(records),
          );
      final volumeProgress = prescribe(history(reps: [7, 8, 9, 10, 11, 12]));
      expect(volumeProgress.weight, 60);
      expect(volumeProgress.sets, 4);
      final loadProgress = prescribe(history());
      expect(loadProgress.weight, 62.5);
      expect(loadProgress.sets, 3);
      expect(loadProgress.evidenceIds, contains('larsen_2021_autoregulation'));
    },
  );

  test(
    'beta explains an exhausted personal daily budget including unfinished plans',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      state.sessions.clear();
      state.setMemberProfile(goals: ['근육 증가']);
      for (final session in history()) {
        state.sessions[session.date] = session;
      }
      state.setPersonalCoaching(enabled: true);
      final session = state.sessionFor(day)
        ..trainingFocus = {TrainingMuscle.chest};
      session.exercises.add(
        WorkoutExercise(
          id: 'today',
          template: template('bench'),
          sets: List.generate(
            4,
            (i) => WorkoutSetEntry(number: i + 1, weight: 60, reps: 10),
          ),
        ),
      );
      expect(
        state.personalCoachingStopReasonForDate(day),
        contains('가슴 오늘 4/4세트'),
      );
      expect(
        state.personalCoachingStopReasonForDate(day),
        contains('미완료 계획도 포함'),
      );
      state.setPersonalCoaching(enabled: false);
      expect(state.personalCoachingStopReasonForDate(day), isNull);
    },
  );

  test(
    'beta is opt-in, persists in guest snapshots, and preserves other preferences',
    () async {
      final repository = MemoryAppRepository();
      final state = AppState(repository: repository);
      addTearDown(state.dispose);
      await state.initialize();
      state.sessions.clear();
      state.setMemberProfile(goals: ['근육 증가']);
      expect(state.personalCoachingPlanForDate(day), isNull);
      state.setPersonalCoaching(enabled: true, trainingDays: 4);
      state.setExerciseExcludedFromRecommendations('bench', true);
      state.recommendationPreferences = state.recommendationPreferences
          .recordSelection('row', day);
      state.setPersonalCoaching(trainingDays: 4);
      expect(state.personalCoachingPlanForDate(day), isNotNull);
      await state.flushPersistence();
      final decoded = AppSnapshotCodec.decode(
        AppSnapshotCodec.encode(repository.snapshot!),
        exerciseCatalog,
      );
      final restarted = AppState(
        repository: MemoryAppRepository(initialSnapshot: decoded),
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(
        restarted.recommendationPreferences.personalCoachingEnabled,
        isTrue,
      );
      expect(restarted.recommendationPreferences.plannedTrainingDays, 4);
      expect(
        restarted.recommendationPreferences.excludedExerciseIds,
        contains('bench'),
      );
      restarted.setPersonalCoaching(enabled: false);
      expect(restarted.personalCoachingPlanForDate(day), isNull);
      expect(restarted.recommendationPreferences.manualSelectionDays['row'], [
        day,
      ]);
    },
  );

  test(
    'non-beta grants are account bound, fail closed, and cannot be forged in snapshots',
    () async {
      final auth = _Auth();
      Auth.use(auth);
      final repository = _AccessRepository();
      final state = AppState(
        personalCoachingBetaAvailable: false,
        personalCoachingRepository: repository,
      );
      addTearDown(state.dispose);
      expect(() => state.setPersonalCoaching(enabled: true), throwsStateError);
      repository.access = PersonalCoachingAccess(
        userId: 'a',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      await state.refreshPersonalCoachingAccess();
      expect(state.canUsePersonalCoaching, isTrue);
      state.setPersonalCoaching(enabled: true);
      auth.id = 'b';
      expect(state.canUsePersonalCoaching, isFalse);
      auth.id = 'a';
      repository.access = PersonalCoachingAccess(
        userId: 'a',
        expiresAt: DateTime.now(),
      );
      await state.refreshPersonalCoachingAccess();
      expect(state.canUsePersonalCoaching, isFalse);
      repository.error = StateError('offline');
      await state.refreshPersonalCoachingAccess();
      expect(state.personalCoachingAccessError, isNotNull);
      expect(state.canUsePersonalCoaching, isFalse);
    },
  );

  test(
    'late entitlement responses cannot restore access after logout',
    () async {
      final auth = _Auth();
      Auth.use(auth);
      final response = Completer<PersonalCoachingAccess?>();
      final state = AppState(
        personalCoachingBetaAvailable: false,
        personalCoachingRepository: _AccessRepository()
          ..pending = response.future,
        authSignOut: auth.signOut,
      );
      addTearDown(state.dispose);
      final loading = state.refreshPersonalCoachingAccess();
      await state.logout();
      response.complete(
        PersonalCoachingAccess(
          userId: 'a',
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      await loading;
      expect(state.canUsePersonalCoaching, isFalse);
      expect(state.personalCoachingAccessLoading, isFalse);
      expect(state.recommendationPreferences.personalCoachingEnabled, isFalse);
    },
  );
}

class _AccessRepository implements PersonalCoachingRepository {
  PersonalCoachingAccess? access;
  Object? error;
  Future<PersonalCoachingAccess?>? pending;
  @override
  Future<PersonalCoachingAccess?> loadMyPersonalCoachingAccess() async {
    if (error != null) throw error!;
    return pending ?? access;
  }
}

class _Auth implements AuthService {
  String? id = 'a';
  @override
  AuthUser? get currentUser =>
      id == null ? null : AuthUser(id: id!, displayName: '회원');
  @override
  bool get hasAuthenticatedUser => id != null;
  @override
  String get currentDisplayName => '회원';
  @override
  Future<void> signOut() async {
    id = null;
  }

  @override
  Future<bool> isVerifiedAdmin() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
