import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/coaching_workout_repository.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/services/auth_service.dart';

const _memberId = 'member-a';
final _day = DateTime(2026, 9, 11);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => Auth.use(_MemberAuth()));
  tearDown(Auth.reset);

  test(
    'personal workouts and coaching share a day without sharing objects',
    () async {
      final personal = _personalSession();
      final lesson = _workout('lesson', kind: CoachingWorkoutKind.lesson);
      final assignment = _workout('assignment');
      final coaching = _CoachingRepository([lesson, assignment]);
      final state = await _createState(coaching, personal: personal);

      final combined = state.sessions[_day]!;
      expect(combined.exercises, hasLength(3));
      expect(combined.exercises.first.id, 'personal');
      expect(combined.startedAt, personal.startedAt);
      expect(combined.endedAt, personal.endedAt);
      expect(combined.isComplete, isFalse);
      expect(combined.isTimedWorkoutComplete, isTrue);
      expect(
        combined.elapsedUntil(_day.add(const Duration(days: 1))),
        personal.endedAt!.difference(personal.startedAt!),
      );
      expect(combined.totalSets, 5);
      expect(combined.completedSets, 3);
      expect(combined.volume, 920);

      final projected = combined.exercises[1];
      final source = lesson.session.exercises.single;
      expect(projected.coachingWorkoutId, 'lesson');
      expect(projected.coachingAuthor, '담당 트레이너');
      expect(projected, isNot(same(source)));
      expect(projected.sets, isNot(same(source.sets)));
      expect(projected.sets.first, isNot(same(source.sets.first)));
      expect(projected.sets.first.completed, isTrue);
      expect(projected.sets.last.completed, isFalse);
      expect(projected.sets.first.rir, 2);
      expect(projected.sets.first.restSeconds, 120);

      projected.sets.first.weight = 1;
      expect(source.sets.first.weight, 50);
      await state.refreshCoachingWorkouts();
      expect(combined.exercises, hasLength(3));
      expect(combined.exercises[1].sets.first.weight, 50);
      expect(combined.volume, 920);
    },
  );

  test(
    'personal set actions cannot rewrite or remove a coaching record',
    () async {
      final workout = _workout('lesson', kind: CoachingWorkoutKind.lesson);
      final state = await _createState(_CoachingRepository([workout]));
      final session = state.sessions[_day]!;
      final exercise = session.exercises.single;
      final completed = exercise.sets.first;
      final pending = exercise.sets.last;

      state.updateSet(
        completed,
        weight: 90,
        reps: 3,
        type: '드랍',
        restSeconds: 30,
        clearRir: true,
      );
      await state.toggleSet(completed);
      await state.toggleSet(pending);
      state.addSet(exercise);
      state.removeSet(exercise, completed);
      state.removeExercise(session, exercise);

      expect(session.exercises, [exercise]);
      expect(exercise.sets, [completed, pending]);
      expect(completed.weight, 50);
      expect(completed.reps, 8);
      expect(completed.type, '일반');
      expect(completed.restSeconds, 120);
      expect(completed.rir, 2);
      expect(completed.completed, isTrue);
      expect(pending.completed, isFalse);
      expect(state.restRemaining, 0);
      expect(workout.session.exercises.single.sets.first.weight, 50);
    },
  );

  test(
    'personal propagation and whole-day deletion preserve coaching records',
    () async {
      final state = await _createState(
        _CoachingRepository([_workout('lesson')]),
        personal: _personalSession(),
      );
      final session = state.sessions[_day]!;
      final exercise = session.exercises.last;
      final pending = exercise.sets.last;

      expect(
        state.adoptActualIntoPendingSets(exercise, exercise.sets.first),
        0,
      );
      expect(pending.weight, 45);
      expect(pending.reps, 10);
      state.restorePendingSets({
        pending: {
          'weight': 99,
          'reps': 1,
          'durationSeconds': 0,
          'distanceKm': 0,
          'intensityRpe': 0,
        },
      });
      expect(pending.weight, 45);
      expect(pending.reps, 10);

      state.deleteSession(_day);
      expect(state.sessions[_day]?.exercises, hasLength(1));
      expect(
        state.sessions[_day]!.exercises.single.coachingWorkoutId,
        exercise.coachingWorkoutId,
      );
      expect(state.sessions[_day]!.completedSets, 1);
      expect(state.coachingWorkouts.single.id, 'lesson');
    },
  );

  test('persisting a combined diary saves only personal records', () async {
    final coachingOnlyDay = _day.add(const Duration(days: 1));
    final repository = MemoryAppRepository(
      initialSnapshot: _snapshot(_personalSession()),
    );
    final state = await _createState(
      _CoachingRepository([
        _workout('same-day'),
        _workout('coaching-only', date: coachingOnlyDay),
      ]),
      repository: repository,
    );

    final personalSet = state.sessions[_day]!.exercises.first.sets.single;
    state.updateSet(personalSet, weight: 32.5);
    await state.syncPersistenceToServer();

    final saved = repository.snapshot!;
    expect(saved.sessions.keys, [_day]);
    expect(saved.sessions[_day]!.exercises.single.id, 'personal');
    expect(saved.sessions[_day]!.exercises.single.sets.single.weight, 32.5);
    expect(saved.sessions[_day]!.startedAt, DateTime(2026, 9, 11, 18));
    expect(saved.sessions[_day]!.endedAt, DateTime(2026, 9, 11, 18, 10));
    expect(state.sessions[_day]!.exercises, hasLength(2));
    expect(state.sessions[coachingOnlyDay]!.exercises, hasLength(1));

    final restored = AppSnapshotCodec.decode(
      AppSnapshotCodec.encode(saved),
      exerciseCatalog,
    )!;
    expect(restored.sessions.keys, [_day]);
    expect(restored.sessions[_day]!.exercises.single.id, 'personal');
    expect(restored.sessions[_day]!.completedSets, 1);
  });

  test(
    'refresh removes revoked records and ignores cancelled or other members',
    () async {
      final coaching = _CoachingRepository([
        _workout('mine'),
        _workout(
          'cancelled',
          status: CoachingWorkoutStatus.cancelled,
          hasCompletedSets: false,
          date: _day.add(const Duration(days: 1)),
        ),
        _workout('other-member', memberId: 'member-b'),
      ]);
      final state = await _createState(coaching, personal: _personalSession());
      expect(
        state.sessions[_day]!.exercises.map((item) => item.coachingWorkoutId),
        [null, 'mine'],
      );
      expect(state.sessions.keys, [_day]);

      coaching.records = [];
      await state.refreshCoachingWorkouts();
      expect(state.sessions[_day]!.exercises.single.id, 'personal');
      expect(state.coachingWorkouts, isEmpty);
    },
  );

  test(
    'cancelling a partly performed assignment keeps only completed history',
    () async {
      final coaching = _CoachingRepository([_workout('assignment')]);
      final state = await _createState(coaching, personal: _personalSession());
      expect(state.sessions[_day]!.totalSets, 3);

      final cancelled = _workout(
        'assignment',
        status: CoachingWorkoutStatus.cancelled,
      );
      coaching.records = [cancelled];
      await state.refreshCoachingWorkouts();

      final session = state.sessions[_day]!;
      expect(session.exercises.first.id, 'personal');
      final projection = session.exercises.last;
      expect(projection.coachingWorkoutId, 'assignment');
      expect(projection.sets, hasLength(1));
      expect(projection.sets.single.completed, isTrue);
      expect(projection.sets.single.weight, 50);
      expect(projection.sets.single.reps, 8);
      expect(session.completedSets, 2);
      expect(session.totalSets, 2);
      expect(session.volume, 520);
      expect(cancelled.session.exercises.single.sets, hasLength(2));
      expect(cancelled.session.exercises.single.sets.last.completed, isFalse);
    },
  );

  test(
    'out-of-order refresh cannot restore an older coaching response',
    () async {
      final coaching = _CoachingRepository([_workout('initial')]);
      final state = await _createState(coaching);
      final oldResponse = Completer<List<CoachingWorkout>>();
      coaching.nextResponse = oldResponse.future;
      final oldRefresh = state.refreshCoachingWorkouts();
      coaching.records = [_workout('latest')];

      await state.refreshCoachingWorkouts();
      oldResponse.complete([_workout('outdated')]);
      await oldRefresh;

      expect(state.coachingWorkouts.single.id, 'latest');
      expect(
        state.sessions[_day]!.exercises.single.coachingWorkoutId,
        'latest',
      );
      expect(state.coachingWorkoutsLoading, isFalse);
      expect(state.coachingWorkoutsError, isNull);
    },
  );

  test(
    'logout clears coaching records and ignores a delayed refresh',
    () async {
      final coaching = _CoachingRepository([_workout('lesson')]);
      final state = await _createState(coaching, personal: _personalSession());
      final delayedResponse = Completer<List<CoachingWorkout>>();
      coaching.nextResponse = delayedResponse.future;
      final refresh = state.refreshCoachingWorkouts();
      expect(state.coachingWorkoutsLoading, isTrue);

      await state.logout();
      expect(state.sessions, isEmpty);
      expect(state.coachingWorkouts, isEmpty);
      expect(state.coachingWorkoutsLoading, isFalse);
      expect(state.coachingWorkoutsError, isNull);
      expect(Auth.instance.hasAuthenticatedUser, isFalse);

      delayedResponse.complete([_workout('late-private-data')]);
      await refresh;
      expect(state.sessions, isEmpty);
      expect(state.coachingWorkouts, isEmpty);
      expect(state.coachingWorkoutsLoading, isFalse);
      expect(state.coachingWorkoutsError, isNull);
    },
  );

  test(
    'temporary refresh failure keeps known coaching records and can recover',
    () async {
      final coaching = _CoachingRepository([_workout('lesson')]);
      final state = await _createState(coaching, personal: _personalSession());
      final failure = TimeoutException('수업 기록 새로고침 시간이 초과되었습니다.');
      coaching.nextResponse = Future<List<CoachingWorkout>>.error(failure);

      await expectLater(
        state.refreshCoachingWorkouts(),
        throwsA(same(failure)),
      );
      expect(state.sessions[_day]!.exercises.first.id, 'personal');
      expect(state.sessions[_day]!.exercises, hasLength(2));
      expect(state.sessions[_day]!.exercises.last.coachingWorkoutId, 'lesson');
      expect(state.coachingWorkouts.single.id, 'lesson');
      expect(state.coachingWorkoutsLoading, isFalse);
      expect(state.coachingWorkoutsError, same(failure));

      await state.refreshCoachingWorkouts();
      expect(state.sessions[_day]!.exercises, hasLength(2));
      expect(state.coachingWorkoutsError, isNull);
    },
  );

  test('guests do not request private coaching records', () async {
    Auth.reset();
    final coaching = _CoachingRepository([_workout('lesson')]);
    final state = await _createState(coaching);
    await state.refreshCoachingWorkouts();
    expect(coaching.listCalls, 0);
    expect(state.coachingWorkouts, isEmpty);
    expect(state.sessions, isEmpty);
  });
}

Future<AppState> _createState(
  _CoachingRepository coaching, {
  WorkoutSession? personal,
  MemoryAppRepository? repository,
}) async {
  final state = AppState(
    repository:
        repository ??
        MemoryAppRepository(
          initialSnapshot: personal == null ? null : _snapshot(personal),
        ),
    coachingWorkoutRepository: coaching,
  );
  addTearDown(state.dispose);
  await state.initialize();
  await state.flushPersistence();
  return state;
}

AppSnapshot _snapshot(WorkoutSession session) => AppSnapshot(
  role: UserRole.member,
  isDarkMode: false,
  weightUnit: 'kg',
  restDefaultSeconds: 90,
  sessions: {_day: session},
  routines: const [],
);

WorkoutSession _personalSession() => WorkoutSession(
  date: _day,
  startedAt: DateTime(2026, 9, 11, 18),
  endedAt: DateTime(2026, 9, 11, 18, 10),
  exercises: [
    WorkoutExercise(
      id: 'personal',
      template: exerciseCatalog.first,
      sets: [WorkoutSetEntry(number: 1, weight: 20, reps: 6, completed: true)],
    ),
  ],
);

CoachingWorkout _workout(
  String id, {
  String memberId = _memberId,
  DateTime? date,
  CoachingWorkoutKind kind = CoachingWorkoutKind.assignment,
  CoachingWorkoutStatus status = CoachingWorkoutStatus.inProgress,
  bool hasCompletedSets = true,
}) => CoachingWorkout(
  id: id,
  kind: kind,
  status: status,
  trainerId: 'trainer-a',
  memberUserId: memberId,
  trainerName: '담당 트레이너',
  memberName: '회원',
  title: '하체 운동',
  instruction: '자세를 유지해주세요.',
  date: (date ?? _day).add(const Duration(hours: 19)),
  version: 2,
  canEdit: false,
  recordingAllowed: true,
  session: WorkoutSession(
    date: date ?? _day,
    exercises: [
      WorkoutExercise(
        id: 'exercise',
        template: exerciseCatalog.lastWhere((item) => !item.isCardio),
        sets: [
          WorkoutSetEntry(
            number: 1,
            weight: 50,
            reps: 8,
            completed: hasCompletedSets,
            restSeconds: 120,
            rir: 2,
          ),
          WorkoutSetEntry(number: 2, weight: 45, reps: 10),
        ],
      ),
    ],
  ),
);

class _CoachingRepository implements CoachingWorkoutRepository {
  _CoachingRepository(this.records);

  List<CoachingWorkout> records;
  Future<List<CoachingWorkout>>? nextResponse;
  int listCalls = 0;

  @override
  Future<List<CoachingWorkout>> listCoachingWorkouts({String? memberUserId}) {
    listCalls++;
    final response = nextResponse;
    nextResponse = null;
    return response ?? Future.value(records);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemberAuth implements AuthService {
  AuthUser? _user = const AuthUser(id: _memberId, displayName: '회원');

  @override
  AuthUser? get currentUser => _user;

  @override
  bool get hasAuthenticatedUser => _user != null;

  @override
  String get currentDisplayName => _user?.displayName ?? '게스트';

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  Future<void> signOut() async => _user = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
