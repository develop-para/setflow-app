import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/domain/lock_screen_workout.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/services/lock_screen_workout_platform.dart';

class _Platform implements LockScreenWorkoutPlatform {
  Map<String, Object?>? snapshot;
  final events = <Map<String, Object?>>[];
  int acknowledgements = 0, publications = 0;
  bool failAck = false;
  void Function()? beforeAck;
  void Function()? beforePublish;
  @override
  Future<LockScreenWorkoutStatus> status() async => LockScreenWorkoutStatus(
    supported: true,
    enabled: snapshot != null,
    notificationsAllowed: true,
    ownerKey: snapshot?['ownerKey'] as String?,
    workoutDate: snapshot?['workoutDate'] as String?,
    sessionId: snapshot?['sessionId'] as String?,
  );
  @override
  Future<String?> getGuestOwnerKey() async => 'device-guest';
  @override
  Future<bool> publish(Map<String, Object?> value) async {
    beforePublish?.call();
    beforePublish = null;
    if (events.any((event) => event['ownerKey'] == value['ownerKey'])) {
      return false;
    }
    publications++;
    snapshot = Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
    return true;
  }

  @override
  Future<List<Map<String, Object?>>> readEvents() async => List.of(events);
  @override
  Future<void> acknowledge(List<String> ids) async {
    beforeAck?.call();
    acknowledgements++;
    if (failAck) throw StateError('ack unavailable');
    events.removeWhere((event) => ids.contains(event['eventId']));
  }

  @override
  Future<void> clear() async {
    snapshot = null;
  }

  @override
  Future<bool> openSettings() async => true;

  Map<String, Object?> tap({int index = 0, String id = 'event-1'}) {
    final state = snapshot!;
    final target = (state['sets'] as List)[index] as Map;
    final completed = DateTime.now().millisecondsSinceEpoch;
    final event = <String, Object?>{
      'eventId': id,
      'sessionId': state['sessionId'],
      'ownerKey': state['ownerKey'],
      'workoutDate': state['workoutDate'],
      'publishedAtMillis': state['publishedAtMillis'],
      'expiresAtMillis': state['expiresAtMillis'],
      'completedAtMillis': completed,
      'restEndsAtMillis':
          completed + (target['restSeconds'] as num).toInt() * 1000,
      'set': Map<String, Object?>.from(target),
    };
    events.add(event);
    return event;
  }
}

class _Store extends MemoryAppRepository {
  bool fail = false;
  @override
  Future<void> save(AppSnapshot snapshot) async {
    if (fail) throw StateError('device full');
    await super.save(snapshot);
  }
}

class _SignedInAuth extends Fake implements AuthService {
  @override
  bool get hasAuthenticatedUser => true;
  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'new-owner', displayName: '회원');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(Auth.reset);
  tearDown(Auth.reset);
  late AppState state;
  late _Platform platform;
  late _Store store;
  late DateTime today;
  Future<void> prepare() async {
    today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);
    store = _Store();
    platform = _Platform();
    state = AppState(repository: store, lockScreenWorkoutPlatform: platform);
    await state.initialize();
    state.addExercise(today, exerciseCatalog.first);
    for (final set in state.sessions[today]!.exercises.single.sets) {
      state.updateSet(set, weight: 40, reps: 8);
    }
    expect(await state.startLockScreenWorkout(today), isTrue);
    addTearDown(state.dispose);
  }

  test(
    'publication is durable before native controls appear; unchanged ticks do not republish',
    () async {
      await prepare();
      expect(
        store.snapshot!.sessions[today]!.exercises.single.sets.first.weight,
        40,
      );
      final count = platform.publications;
      await state.refreshLockScreenWorkoutProjection();
      await state.refreshLockScreenWorkoutProjection();
      expect(platform.publications, count);
    },
  );

  test(
    'native completion persists before ack and duplicate taps never undo it',
    () async {
      await prepare();
      platform.tap();
      platform.tap(id: 'duplicate-tap');
      platform.beforeAck = () {
        expect(
          store
              .snapshot!
              .sessions[today]!
              .exercises
              .single
              .sets
              .first
              .completed,
          isTrue,
        );
        expect(
          store.snapshot!.lockScreenAppliedEventIds,
          containsAll(['event-1', 'duplicate-tap']),
        );
      };
      final result = await state.reconcileLockScreenWorkout();
      expect(result.applied, 1);
      expect(result.alreadyApplied, 1);
      expect(platform.events, isEmpty);
      expect(
        state.sessions[today]!.exercises.single.sets[1].completed,
        isFalse,
      );
      expect(state.restRemaining, greaterThan(0));
    },
  );

  test(
    'failed device write keeps native performance and never acknowledges',
    () async {
      await prepare();
      platform.tap();
      store.fail = true;
      await expectLater(state.reconcileLockScreenWorkout(), throwsStateError);
      expect(platform.events, hasLength(1));
      expect(platform.acknowledgements, 0);
      store.fail = false;
      await state.reconcileLockScreenWorkout();
      expect(platform.events, isEmpty);
      expect(
        state.sessions[today]!.exercises.single.sets.first.completed,
        isTrue,
      );
    },
  );

  test(
    'cold receipt survives codec and an uncertain ack cannot replay a later undo',
    () async {
      await prepare();
      platform.tap();
      platform.failAck = true;
      await expectLater(state.reconcileLockScreenWorkout(), throwsStateError);
      final snapshot = AppSnapshotCodec.decode(
        AppSnapshotCodec.encode(store.snapshot!),
        state.exercises,
      )!;
      expect(snapshot.lockScreenAppliedEventIds, ['event-1']);
      final restartedStore = MemoryAppRepository(initialSnapshot: snapshot);
      final restarted = AppState(
        repository: restartedStore,
        lockScreenWorkoutPlatform: platform,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      final set = restarted.sessions[today]!.exercises.single.sets.first;
      await restarted.toggleSet(set, startRest: false);
      expect(set.completed, isFalse);
      platform.failAck = false;
      platform.beforeAck = null;
      await restarted.reconcileLockScreenWorkout();
      expect(set.completed, isFalse);
      expect(platform.events, isEmpty);
    },
  );

  test(
    'different owner and out-of-order set remain unmodified in the journal',
    () async {
      await prepare();
      platform.tap(index: 1);
      platform.tap(id: 'other-owner')['ownerKey'] = 'account:other';
      final result = await state.reconcileLockScreenWorkout();
      expect(result.conflicts, 1);
      expect(result.otherOwners, 1);
      expect(platform.events, hasLength(2));
      expect(
        state.sessions[today]!.exercises.single.sets.every(
          (set) => !set.completed,
        ),
        isTrue,
      );
    },
  );

  test(
    'changed values remain untouched and captured performance can be recovered separately once',
    () async {
      await prepare();
      platform.tap();
      final original = state.sessions[today]!.exercises.single;
      state.updateSet(original.sets.first, weight: 50);
      expect((await state.reconcileLockScreenWorkout()).hasConflicts, isTrue);
      expect(state.lockScreenWorkoutPendingEvents, hasLength(1));
      platform.failAck = true;
      await expectLater(
        state.resolveLockScreenWorkoutConflict(
          'event-1',
          restoreAsSeparateRecord: true,
        ),
        throwsStateError,
      );
      platform.failAck = false;
      await state.resolveLockScreenWorkoutConflict(
        'event-1',
        restoreAsSeparateRecord: true,
      );
      expect(original.sets.first.weight, 50);
      expect(original.sets.first.completed, isFalse);
      final recovered = state.sessions[today]!.exercises
          .where((item) => item.id == 'lockscreen_recovered_event-1')
          .single;
      expect(recovered.sets.single.weight, 40);
      expect(recovered.sets.single.reps, 8);
      expect(recovered.sets.single.completed, isTrue);
      expect(platform.events, isEmpty);
      expect(state.lockScreenWorkoutPendingEvents, isEmpty);
    },
  );

  test(
    'explicitly retaining current values acknowledges without inventing a recovery record',
    () async {
      await prepare();
      platform.tap();
      state.updateSet(
        state.sessions[today]!.exercises.single.sets.first,
        weight: 55,
      );
      await state.reconcileLockScreenWorkout();
      await state.resolveLockScreenWorkoutConflict(
        'event-1',
        restoreAsSeparateRecord: false,
      );
      expect(state.sessions[today]!.exercises, hasLength(1));
      expect(state.sessions[today]!.exercises.single.sets.first.weight, 55);
      expect(platform.events, isEmpty);
    },
  );

  test(
    'ordinary undo receives a fresh generation without changing the value fingerprint',
    () async {
      await prepare();
      final initial = platform.snapshot!;
      platform.tap();
      await state.reconcileLockScreenWorkout();
      final set = state.sessions[today]!.exercises.single.sets.first;
      await state.toggleSet(set, startRest: false);
      await state.refreshLockScreenWorkoutProjection();
      expect(platform.snapshot!['sessionId'], isNot(initial['sessionId']));
      expect(
        ((platform.snapshot!['sets'] as List).first as Map)['fingerprint'],
        ((initial['sets'] as List).first as Map)['fingerprint'],
      );
    },
  );

  test(
    'publish race consumes the newly durable event before retrying the projection',
    () async {
      await prepare();
      final first = state.sessions[today]!.exercises.single.sets.first;
      state.updateSet(state.sessions[today]!.exercises.single.sets[1], reps: 9);
      platform.beforePublish = () {
        platform.tap();
      };
      await state.refreshLockScreenWorkoutProjection();
      expect(first.completed, isTrue);
      expect(platform.events, isEmpty);
      expect(
        ((platform.snapshot!['sets'] as List).first as Map)['setNumber'],
        2,
      );
    },
  );

  test(
    'missing values publish an edit invitation rather than a completion action',
    () async {
      await prepare();
      state.updateSet(
        state.sessions[today]!.exercises.single.sets.first,
        weight: 0,
      );
      await state.refreshLockScreenWorkoutProjection();
      final target = (platform.snapshot!['sets'] as List).first as Map;
      expect(target['canComplete'], isFalse);
      platform.tap();
      expect((await state.reconcileLockScreenWorkout()).hasConflicts, isTrue);
      expect(
        state.sessions[today]!.exercises.single.sets.first.completed,
        isFalse,
      );
    },
  );

  test(
    'stopping hides controls but keeps performed events for reconciliation',
    () async {
      await prepare();
      platform.tap();
      await state.stopLockScreenWorkout();
      expect(platform.snapshot, isNull);
      expect(platform.events, hasLength(1));
      await state.reconcileLockScreenWorkout();
      expect(
        state.sessions[today]!.exercises.single.sets.first.completed,
        isTrue,
      );
    },
  );

  test(
    'signing in does not claim or acknowledge guest performed events',
    () async {
      await prepare();
      platform.tap();
      Auth.use(_SignedInAuth());
      final result = await state.reconcileLockScreenWorkout();
      expect(result.otherOwners, 1);
      expect(platform.events, hasLength(1));
      expect(
        state.sessions[today]!.exercises.single.sets.first.completed,
        isFalse,
      );
      expect(state.lockScreenWorkoutActive, isFalse);
    },
  );

  test(
    'a stale notification tap after its date expiry cannot complete a set',
    () async {
      await prepare();
      final event = platform.tap();
      event['expiresAtMillis'] = event['completedAtMillis'];
      final result = await state.reconcileLockScreenWorkout();
      expect(result.conflicts, 1);
      expect(platform.events, hasLength(1));
      expect(
        state.sessions[today]!.exercises.single.sets.first.completed,
        isFalse,
      );
    },
  );

  test(
    'performance committed before midnight restores to its original day on later resume',
    () async {
      await prepare();
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final exercise = WorkoutExercise(
        id: 'yesterday-entry',
        template: exerciseCatalog.first,
        sets: [WorkoutSetEntry(number: 1, weight: 42, reps: 7)],
      );
      state.sessions[yesterday] = WorkoutSession(
        date: yesterday,
        exercises: [exercise],
      );
      final completed = yesterday.add(const Duration(hours: 23, minutes: 59));
      final target = LockScreenWorkoutSet.fromExercise(
        ownerKey: 'guest:device-guest',
        date: yesterday,
        exercise: exercise,
        set: exercise.sets.single,
        unit: 'kg',
      );
      platform.events.add({
        'eventId': 'before-midnight',
        'sessionId': 'yesterday',
        'ownerKey': 'guest:device-guest',
        'workoutDate': lockScreenWorkoutDateKey(yesterday),
        'publishedAtMillis': yesterday
            .add(const Duration(hours: 22))
            .millisecondsSinceEpoch,
        'expiresAtMillis': today.millisecondsSinceEpoch,
        'completedAtMillis': completed.millisecondsSinceEpoch,
        'set': target.toJson(),
      });
      final result = await state.reconcileLockScreenWorkout();
      expect(result.applied, 1);
      expect(exercise.sets.single.completed, isTrue);
      expect(state.sessions[yesterday]!.endedAt, completed);
      expect(
        state.sessions[today]!.exercises.single.sets.first.completed,
        isFalse,
      );
    },
  );

  test(
    'projected coaching sets are never published as personal completion targets',
    () async {
      await prepare();
      state.sessions[today]!.exercises.add(
        WorkoutExercise(
          id: 'coaching-entry',
          template: exerciseCatalog.first,
          coachingWorkoutId: 'coaching-server',
          sets: [WorkoutSetEntry(number: 1, weight: 80, reps: 10)],
        ),
      );
      await state.refreshLockScreenWorkoutProjection();
      expect(
        (platform.snapshot!['sets'] as List).any(
          (raw) => (raw as Map)['exerciseEntryId'] == 'coaching-entry',
        ),
        isFalse,
      );
    },
  );
}
