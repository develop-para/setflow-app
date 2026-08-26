import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/hive_app_repository.dart';
import 'package:setflow/data/routine_catalog_repository.dart';
import 'package:setflow/data/supabase_app_repository.dart';

void main() {
  group('AppState account boundaries', () {
    test('A to empty B switch clears every core account value', () async {
      final repository = _SwitchingAccountRepository()
        ..currentUserId = 'account-a'
        ..snapshots['account-a'] = _snapshot(
          goals: const ['근육 증가'],
          isDarkMode: true,
          weightUnit: 'lb',
          heightCm: 181,
          routines: [_routine('account-a-routine')],
        );
      final state = AppState(repository: repository);
      addTearDown(state.dispose);

      await state.initialize();
      expect(state.goals, ['근육 증가']);
      expect(state.isDarkMode, isTrue);
      expect(state.weightUnit, 'lb');
      expect(state.heightCm, 181);
      expect(
        state.routines.any((item) => item.id == 'account-a-routine'),
        isTrue,
      );

      repository.currentUserId = 'account-b';
      await state.syncAfterAuthentication();

      expect(state.goals, isEmpty);
      expect(state.isDarkMode, isFalse);
      expect(state.weightUnit, 'kg');
      expect(state.heightCm, isNull);
      expect(state.sessions, isEmpty);
      expect(
        state.routines.any((item) => item.id == 'account-a-routine'),
        isFalse,
      );
    });

    test(
      'immediate logout flushes the latest mutation before sign-out',
      () async {
        final repository = _RecordingRepository();
        var signOutCalled = false;
        final state = AppState(
          repository: repository,
          authSignOut: () async {
            expect(repository.savedSnapshots, isNotEmpty);
            expect(repository.savedSnapshots.last.goals, ['근력 향상']);
            signOutCalled = true;
          },
        );
        addTearDown(state.dispose);
        await state.initialize();

        state.setMemberProfile(goals: const ['근력 향상']);
        await state.logout();

        expect(signOutCalled, isTrue);
        expect(repository.savedSnapshots.last.goals, ['근력 향상']);
        expect(state.goals, isEmpty);
        expect(state.role, UserRole.guest);
      },
    );

    test(
      'authentication merges a staged signup profile once and uploads it',
      () async {
        final gateway = _FakeSupabaseGateway();
        final outbox = _MemoryOutbox();
        final state = AppState(
          repository: SupabaseAppRepository.withGateway(
            gateway,
            outbox: outbox,
            cache: outbox,
          ),
        );
        addTearDown(state.dispose);
        await state.initialize();
        state.stageMemberProfileForAuthentication(
          MemberProfileDraft(
            goals: const ['근력 향상'],
            heightCm: 178,
            weight: 76,
            age: 31,
            gender: 'M',
          ),
        );
        gateway.currentUserId = 'account-a';

        final firstSync = state.syncAfterAuthentication();
        final duplicateSync = state.syncAfterAuthentication();
        expect(identical(firstSync, duplicateSync), isTrue);
        await Future.wait([firstSync, duplicateSync]);

        expect(state.goals, ['근력 향상']);
        expect(state.heightCm, 178);
        expect(state.weight, 76);
        expect(state.age, 31);
        expect(state.gender, 'M');
        expect(gateway.expectedSaveUserIds, ['account-a']);
        expect(gateway.rows['account-a']?.payload['profile']['goals'], [
          '근력 향상',
        ]);
        expect(outbox.pendingByUser, isNot(contains('account-a')));
      },
    );

    test(
      'authentication draft fills missing fields without replacing cloud goals',
      () async {
        final gateway = _FakeSupabaseGateway();
        final existing = _snapshot(goals: const ['체중 감량'], heightCm: 181);
        gateway.rows['account-a'] = SupabaseAppSnapshotRow(
          payload: AppSnapshotCodec.toJson(existing),
          updatedAt: DateTime.utc(2026, 8, 20),
        );
        final state = AppState(
          repository: SupabaseAppRepository.withGateway(
            gateway,
            outbox: _MemoryOutbox(),
          ),
        );
        addTearDown(state.dispose);
        await state.initialize();
        state.stageMemberProfileForAuthentication(
          MemberProfileDraft(goals: const ['근력 향상'], heightCm: 170, weight: 70),
        );
        gateway.currentUserId = 'account-a';

        await state.syncAfterAuthentication();

        expect(state.goals, ['체중 감량']);
        expect(state.heightCm, 181);
        expect(state.weight, 70);
        expect(gateway.rows['account-a']?.payload['profile']['goals'], [
          '체중 감량',
        ]);
      },
    );

    test(
      'precision survey decision and answers survive a fresh cloud login',
      () async {
        final gateway = _FakeSupabaseGateway(currentUserId: 'account-a');
        final firstState = AppState(
          repository: SupabaseAppRepository.withGateway(
            gateway,
            outbox: _MemoryOutbox(),
          ),
        );
        addTearDown(firstState.dispose);
        await firstState.initialize();
        final recordedAt = DateTime.utc(2026, 8, 21, 4, 30);
        firstState.setRecommendationProfile(
          RecommendationProfile(
            experienceLevel: TrainingExperienceLevel.intermediate,
            availableEquipment: const {
              TrainingEquipment.bodyweight,
              TrainingEquipment.dumbbells,
            },
            painRegions: const {TrainingPainRegion.shoulder},
            painLevel: 3,
            restrictedMovements: const {
              TrainingMovementRestriction.overheadPress,
            },
            injuryNote: '오른쪽 어깨를 올릴 때 불편함',
            recoveryStatus: TrainingRecoveryStatus.normal,
            recoveryRecordedAt: recordedAt,
            updatedAt: recordedAt,
          ),
        );
        await firstState.syncPersistenceToServer();

        final restoredState = AppState(
          repository: SupabaseAppRepository.withGateway(
            gateway,
            outbox: _MemoryOutbox(),
          ),
        );
        addTearDown(restoredState.dispose);
        await restoredState.initialize();

        expect(restoredState.precisionRecommendationPrompted, isTrue);
        expect(
          restoredState.recommendationProfile?.experienceLevel,
          TrainingExperienceLevel.intermediate,
        );
        expect(restoredState.recommendationProfile?.availableEquipment, {
          TrainingEquipment.bodyweight,
          TrainingEquipment.dumbbells,
        });
        expect(restoredState.recommendationProfile?.painLevel, 3);
        expect(
          restoredState.recommendationProfile?.recoveryRecordedAt,
          recordedAt,
        );
      },
    );

    test('failed signup cloud upload remains durable and retries', () async {
      final gateway = _FakeSupabaseGateway()..saveFailuresRemaining = 1;
      final outbox = _MemoryOutbox();
      final state = AppState(
        repository: SupabaseAppRepository.withGateway(
          gateway,
          outbox: outbox,
          cache: outbox,
        ),
      );
      addTearDown(state.dispose);
      await state.initialize();
      state.stageMemberProfileForAuthentication(
        MemberProfileDraft(goals: const ['체력 향상']),
      );
      gateway.currentUserId = 'account-a';

      await state.syncAfterAuthentication();

      expect(state.goals, ['체력 향상']);
      expect(outbox.pendingByUser['account-a']?.snapshot.goals, ['체력 향상']);
      expect(state.persistenceSyncError, isA<StateError>());

      await state.syncPersistenceToServer();
      expect(outbox.pendingByUser, isNot(contains('account-a')));
      expect(gateway.rows['account-a']?.payload['profile']['goals'], ['체력 향상']);
    });

    test(
      'auxiliary cloud failure does not send a signed-in member back',
      () async {
        final repository = MemoryAppRepository(
          initialSnapshot: _snapshot(goals: const ['근력 향상']),
        );
        final state = AppState(
          repository: repository,
          routineCatalogRepository: const _FailingRoutineCatalogRepository(),
        );
        addTearDown(state.dispose);
        await state.initialize();

        await expectLater(state.syncAfterAuthentication(), completes);

        expect(state.role, UserRole.member);
        expect(state.goals, ['근력 향상']);
        expect(state.cloudSyncError, isA<StateError>());
        expect(state.persistenceError, isNull);
      },
    );
  });

  group('SupabaseAppRepository durable account outbox', () {
    test(
      'completed set weight survives an offline restart before cloud sync',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'setflow_weight_restart_',
        );
        HiveAppRepository? localStore;
        AppState? firstState;
        AppState? restoredState;
        try {
          final gateway = _FakeSupabaseGateway(currentUserId: 'account-a');
          localStore = await HiveAppRepository.openAtPath(
            directory.path,
            boxName: 'completed_weight_restart',
          );
          final repository = SupabaseAppRepository.withGateway(
            gateway,
            outbox: localStore,
            cache: localStore,
          );
          firstState = AppState(repository: repository);
          await firstState.initialize();
          final date = DateTime(2026, 8, 18);
          final bench = firstState.exercises.firstWhere(
            (exercise) => exercise.id == 'bench',
          );
          firstState.addExercise(date, bench);
          final set = firstState.sessions[date]!.exercises.single.sets.first;
          firstState.updateSet(set, weight: 87.5, reps: 8);
          await firstState.toggleSet(set, startRest: false);

          expect(gateway.rows, isEmpty);
          await localStore.close();
          localStore = await HiveAppRepository.openAtPath(
            directory.path,
            boxName: 'completed_weight_restart',
          );
          gateway.loadFailuresRemaining = 1;
          restoredState = AppState(
            repository: SupabaseAppRepository.withGateway(
              gateway,
              outbox: localStore,
              cache: localStore,
            ),
          );
          await restoredState.initialize();

          final restoredSet =
              restoredState.sessions[date]!.exercises.single.sets.first;
          expect(restoredSet.weight, 87.5);
          expect(restoredSet.reps, 8);
          expect(restoredSet.completed, isTrue);
          await restoredState.flushPersistence();
        } finally {
          firstState?.dispose();
          restoredState?.dispose();
          await localStore?.close();
          if (await directory.exists()) await directory.delete(recursive: true);
        }
      },
    );

    test('failed save is recovered from outbox after app restart', () async {
      final gateway = _FakeSupabaseGateway(currentUserId: 'account-a')
        ..saveFailuresRemaining = 1;
      final outbox = _MemoryOutbox();
      final first = SupabaseAppRepository.withGateway(gateway, outbox: outbox);
      await first.load(const []);
      final latest = _snapshot(goals: const ['체력 향상'], heightCm: 177);

      await first.save(latest);
      expect(outbox.pendingByUser['account-a']?.snapshot.goals, ['체력 향상']);
      expect(gateway.rows, isEmpty);
      await expectLater(first.syncPending(), throwsA(isA<StateError>()));

      final restarted = SupabaseAppRepository.withGateway(
        gateway,
        outbox: outbox,
      );
      final restored = await restarted.load(const []);

      expect(restored?.goals, ['체력 향상']);
      expect(restored?.heightCm, 177);
      expect(outbox.pendingByUser, isNot(contains('account-a')));
      expect(gateway.rows['account-a']?.payload['profile']['goals'], ['체력 향상']);
      expect(restarted.hasPendingSave, isFalse);
    });

    test(
      'direct auth switch stages A only under A and never writes it to B',
      () async {
        final gateway = _FakeSupabaseGateway(currentUserId: 'account-a');
        final outbox = _MemoryOutbox();
        final repository = SupabaseAppRepository.withGateway(
          gateway,
          outbox: outbox,
        );
        await repository.load(const []);
        final accountA = _snapshot(goals: const ['근력 향상']);

        gateway.currentUserId = 'account-b';
        await expectLater(
          repository.save(accountA),
          throwsA(isA<StateError>()),
        );

        expect(outbox.pendingByUser['account-a']?.snapshot.goals, ['근력 향상']);
        expect(outbox.pendingByUser, isNot(contains('account-b')));
        expect(gateway.rows, isNot(contains('account-b')));
        expect(await repository.load(const []), isNull);
      },
    );

    test(
      'auth change during outbox staging cannot write A payload as B',
      () async {
        final gateway = _FakeSupabaseGateway(currentUserId: 'account-a');
        final outbox = _BlockingOutbox();
        final repository = SupabaseAppRepository.withGateway(
          gateway,
          outbox: outbox,
        );
        await repository.load(const []);

        final save = repository.save(
          _snapshot(goals: const ['account-a-goal']),
        );
        await outbox.stageStarted.future;
        gateway.currentUserId = 'account-b';
        outbox.allowStageToFinish.complete();

        await expectLater(save, throwsA(isA<StateError>()));
        expect(gateway.rows, isNot(contains('account-b')));
        expect(outbox.pendingByUser['account-a']?.snapshot.goals, [
          'account-a-goal',
        ]);
      },
    );

    test(
      'server expected UID rejects auth flip after client recheck',
      () async {
        final gateway = _FakeSupabaseGateway(currentUserId: 'account-a');
        final outbox = _MemoryOutbox();
        final repository = SupabaseAppRepository.withGateway(
          gateway,
          outbox: outbox,
        );
        await repository.load(const []);
        gateway.beforeServerAuthorization = () {
          gateway.currentUserId = 'account-b';
        };

        await repository.save(_snapshot(goals: const ['account-a-goal']));
        await expectLater(repository.syncPending(), throwsA(isA<StateError>()));

        expect(gateway.expectedSaveUserIds, ['account-a']);
        expect(gateway.rows, isNot(contains('account-b')));
        expect(outbox.pendingByUser['account-a']?.snapshot.goals, [
          'account-a-goal',
        ]);
      },
    );

    test(
      'acknowledged snapshot remains available during an offline start',
      () async {
        final gateway = _FakeSupabaseGateway(currentUserId: 'account-a');
        final localStore = _MemoryOutbox();
        final repository = SupabaseAppRepository.withGateway(
          gateway,
          outbox: localStore,
        );
        await repository.load(const []);
        await repository.save(_snapshot(goals: const ['근력 향상'], heightCm: 180));

        expect(gateway.rows, isEmpty);
        expect(localStore.cachedByUser['account-a']?.heightCm, 180);
        await repository.syncPending();
        expect(localStore.pendingByUser, isNot(contains('account-a')));
        expect(localStore.cachedByUser['account-a']?.heightCm, 180);

        gateway.loadFailuresRemaining = 1;
        final restarted = SupabaseAppRepository.withGateway(
          gateway,
          outbox: localStore,
        );
        final restored = await restarted.load(const []);

        expect(restored?.goals, ['근력 향상']);
        expect(restored?.heightCm, 180);
        expect(restarted.lastSyncError, isA<StateError>());
      },
    );

    test('legacy snapshot requires an exact explicit user claim', () async {
      final gateway = _FakeSupabaseGateway(currentUserId: 'account-b');
      final source = _ClaimedLegacySource(
        _snapshot(
          goals: const ['근육 증가'],
          routines: [
            _routine('mine_1'),
            _routine('market_demo'),
            _routine('user-created'),
          ],
          posts: [
            _post('post_1', isMine: false),
            _post('my-post', isMine: true),
          ],
          consultations: [
            _consultation('consult_1'),
            _consultation('my-consultation'),
          ],
        ),
      );
      final repository = SupabaseAppRepository.withGateway(
        gateway,
        migrationSource: source,
      );

      expect(await repository.load(const []), isNull);
      expect(gateway.rows, isEmpty);

      source.claimedUserId = 'account-a';
      expect(await repository.load(const []), isNull);
      expect(gateway.rows, isEmpty);

      gateway.currentUserId = 'account-a';
      final imported = await repository.load(const []);

      expect(imported?.routines.map((item) => item.id), ['user-created']);
      expect(imported?.communityPosts.map((item) => item.id), ['my-post']);
      expect(imported?.consultations.map((item) => item.id), [
        'my-consultation',
      ]);
      expect(source.clearedFor, 'account-a');
      expect(gateway.rows, contains('account-a'));
    });
  });

  test('Hive keeps UID outbox durable and requires a legacy claim', () async {
    final directory = await Directory.systemTemp.createTemp('setflow_hive_');
    HiveAppRepository? repository;
    try {
      repository = await HiveAppRepository.openAtPath(
        directory.path,
        boxName: 'account_persistence_test',
      );
      final legacy = _snapshot(goals: const ['근육 증가']);
      await repository.save(legacy);

      expect(await repository.loadClaimed('account-a', const []), isNull);
      expect(await repository.claimLegacySnapshotForUser('account-a'), isTrue);
      expect((await repository.loadClaimed('account-a', const []))?.goals, [
        '근육 증가',
      ]);
      expect(await repository.loadClaimed('account-b', const []), isNull);

      await repository.stagePending(
        'account-a',
        PendingAppSnapshot(
          snapshot: _snapshot(goals: const ['근력 향상']),
          queuedAt: DateTime.utc(2026, 8, 17),
        ),
      );
      await repository.close();
      repository = await HiveAppRepository.openAtPath(
        directory.path,
        boxName: 'account_persistence_test',
      );

      expect(
        (await repository.loadPending('account-a', const []))?.snapshot.goals,
        ['근력 향상'],
      );
      expect(await repository.loadPending('account-b', const []), isNull);
    } finally {
      await repository?.close();
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  });

  group('a guest owns their records until they say otherwise', () {
    Future<T> withHive<T>(
      Future<T> Function(HiveAppRepository hive) body,
    ) async {
      final directory = await Directory.systemTemp.createTemp('setflow_guest_');
      HiveAppRepository? hive;
      try {
        hive = await HiveAppRepository.openAtPath(
          directory.path,
          boxName: 'guest_data_test',
        );
        return await body(hive);
      } finally {
        await hive?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    }

    test('a workout logged while signed out survives a restart', () async {
      // The app is usable without an account, so this is the common case for a
      // new user -- and it used to be discarded on every relaunch.
      await withHive((hive) async {
        final gateway = _FakeSupabaseGateway();
        final repository = SupabaseAppRepository.withGateway(
          gateway,
          migrationSource: hive,
        );
        await repository.load(const []);
        await repository.save(_snapshot(goals: const ['게스트가 기록한 것']));

        final restarted = SupabaseAppRepository.withGateway(
          gateway,
          migrationSource: hive,
        );
        expect((await restarted.load(const []))?.goals, ['게스트가 기록한 것']);
      });
    });

    test('signing in does not silently absorb them', () async {
      // Being the first account to sign in on a shared phone is not evidence
      // of ownership, so the import waits for an explicit claim.
      await withHive((hive) async {
        final gateway = _FakeSupabaseGateway();
        final repository = SupabaseAppRepository.withGateway(
          gateway,
          migrationSource: hive,
        );
        await repository.load(const []);
        await repository.save(_snapshot(goals: const ['게스트가 기록한 것']));

        gateway.currentUserId = 'account-a';
        expect(await repository.load(const []), isNull);
        expect(gateway.rows, isEmpty);
      });
    });

    test('adopting them imports and uploads exactly once', () async {
      await withHive((hive) async {
        final gateway = _FakeSupabaseGateway();
        final repository = SupabaseAppRepository.withGateway(
          gateway,
          migrationSource: hive,
        );
        await repository.load(const []);
        await repository.save(_snapshot(goals: const ['게스트가 기록한 것']));

        gateway.currentUserId = 'account-a';
        expect(await repository.adoptGuestSnapshot('account-a'), isTrue);
        expect((await repository.load(const []))?.goals, ['게스트가 기록한 것']);
        expect(gateway.rows, contains('account-a'));

        // Claimed data belongs to that account now; the next guest on this
        // device must not inherit someone else's training log.
        gateway.currentUserId = null;
        expect(await repository.load(const []), isNull);
      });
    });

    test(
      'peeking is what the prompt decides on, and it does not claim',
      () async {
        await withHive((hive) async {
          final gateway = _FakeSupabaseGateway();
          final repository = SupabaseAppRepository.withGateway(
            gateway,
            migrationSource: hive,
          );
          await repository.load(const []);
          await repository.save(_snapshot(goals: const ['게스트가 기록한 것']));

          expect((await repository.peekGuestSnapshot(const []))?.goals, [
            '게스트가 기록한 것',
          ]);
          // Declining must leave the records exactly where they were.
          gateway.currentUserId = 'account-a';
          expect(await repository.load(const []), isNull);
          gateway.currentUserId = null;
          expect((await repository.load(const []))?.goals, ['게스트가 기록한 것']);
        });
      },
    );

    test(
      'signing out does not hand that account data to the next guest',
      () async {
        await withHive((hive) async {
          final gateway = _FakeSupabaseGateway(currentUserId: 'account-a');
          final repository = SupabaseAppRepository.withGateway(
            gateway,
            migrationSource: hive,
          );
          await repository.load(const []);
          await repository.save(_snapshot(goals: const ['계정 A의 기록']));

          gateway.currentUserId = null;
          await repository.save(_snapshot(goals: const ['계정 A의 기록']));

          final restarted = SupabaseAppRepository.withGateway(
            _FakeSupabaseGateway(),
            migrationSource: hive,
          );
          expect(await restarted.load(const []), isNull);
        });
      },
    );
  });
}

AppSnapshot _snapshot({
  List<String> goals = const [],
  bool isDarkMode = false,
  String weightUnit = 'kg',
  double? heightCm,
  double? weight,
  int? age,
  String? gender,
  List<RoutineData> routines = const [],
  List<CommunityPost> posts = const [],
  List<ConsultationData> consultations = const [],
}) => AppSnapshot(
  role: UserRole.member,
  isDarkMode: isDarkMode,
  weightUnit: weightUnit,
  restDefaultSeconds: 90,
  sessions: const {},
  routines: routines,
  goals: goals,
  heightCm: heightCm,
  weight: weight,
  age: age,
  gender: gender,
  communityPosts: posts,
  consultations: consultations,
);

RoutineData _routine(String id) => RoutineData(
  id: id,
  name: id,
  description: '',
  color: Colors.teal,
  exercises: const [],
);

CommunityPost _post(String id, {required bool isMine}) => CommunityPost(
  id: id,
  author: '회원',
  content: id,
  metric: '',
  createdAt: DateTime.utc(2026, 8, 16),
  visualKey: 'workout',
  color: Colors.teal,
  isMine: isMine,
);

ConsultationData _consultation(String id) => ConsultationData(
  id: id,
  trainerName: '트레이너',
  specialty: '근력',
  goal: '목표',
  level: '초급',
  question: id,
  createdAt: DateTime.utc(2026, 8, 16),
);

class _SwitchingAccountRepository implements AppRepository {
  String? currentUserId;
  final Map<String, AppSnapshot> snapshots = {};

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async =>
      snapshots[currentUserId];

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final userId = currentUserId;
    if (userId != null) snapshots[userId] = snapshot;
  }

  @override
  Future<void> clear() async {
    final userId = currentUserId;
    if (userId != null) snapshots.remove(userId);
  }
}

class _RecordingRepository implements AppRepository {
  final List<AppSnapshot> savedSnapshots = [];

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async =>
      null;

  @override
  Future<void> save(AppSnapshot snapshot) async {
    savedSnapshots.add(snapshot);
  }

  @override
  Future<void> clear() async => savedSnapshots.clear();
}

class _FailingRoutineCatalogRepository implements RoutineCatalogRepository {
  const _FailingRoutineCatalogRepository();

  @override
  Future<bool> hasActivePaidPlan() async => false;

  @override
  Future<List<RoutineCatalogItem>> listPublished() async =>
      throw StateError('catalog unavailable');

  @override
  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  ) async {}
}

class _MemoryOutbox implements AccountSnapshotOutbox, AccountSnapshotCache {
  final Map<String, PendingAppSnapshot> pendingByUser = {};
  final Map<String, AppSnapshot> cachedByUser = {};

  @override
  Future<void> clearCached(String userId) async {
    cachedByUser.remove(userId);
  }

  @override
  Future<void> clearPending(String userId) async {
    pendingByUser.remove(userId);
  }

  @override
  Future<AppSnapshot?> loadCached(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  ) async => cachedByUser[userId];

  @override
  Future<PendingAppSnapshot?> loadPending(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  ) async => pendingByUser[userId];

  @override
  Future<void> stagePending(String userId, PendingAppSnapshot pending) async {
    pendingByUser[userId] = pending;
    cachedByUser[userId] = pending.snapshot;
  }

  @override
  Future<void> storeCached(String userId, AppSnapshot snapshot) async {
    cachedByUser[userId] = snapshot;
  }
}

class _BlockingOutbox extends _MemoryOutbox {
  final stageStarted = Completer<void>();
  final allowStageToFinish = Completer<void>();

  @override
  Future<void> stagePending(String userId, PendingAppSnapshot pending) async {
    pendingByUser[userId] = pending;
    if (!stageStarted.isCompleted) stageStarted.complete();
    await allowStageToFinish.future;
  }
}

class _FakeSupabaseGateway implements SupabaseAppRemoteGateway {
  _FakeSupabaseGateway({this.currentUserId});

  @override
  String? currentUserId;
  final Map<String, SupabaseAppSnapshotRow> rows = {};
  int saveFailuresRemaining = 0;
  int loadFailuresRemaining = 0;
  int _version = 0;
  void Function()? beforeServerAuthorization;
  final List<String> expectedSaveUserIds = [];

  @override
  Future<void> clearSnapshot({
    required String expectedUserId,
    required DateTime? expectedUpdatedAt,
  }) async {
    final userId = currentUserId;
    if (userId == expectedUserId) rows.remove(userId);
  }

  @override
  Future<Map<String, dynamic>> requestAccountDeletion(String? reason) async {
    final purgeAfter = DateTime.utc(2026, 9, 25);
    deletionRequests[currentUserId ?? ''] = {
      'requestedAt': DateTime.utc(2026, 8, 26).toIso8601String(),
      'purgeAfter': purgeAfter.toIso8601String(),
      'reason': reason,
    };
    return deletionRequests[currentUserId ?? '']!;
  }

  @override
  Future<bool> cancelAccountDeletion() async =>
      deletionRequests.remove(currentUserId ?? '') != null;

  @override
  Future<Map<String, dynamic>?> pendingAccountDeletion(String userId) async =>
      deletionRequests[userId];

  /// 탈퇴 요청을 사용자별로 담아 두는 자리 — 서버 테이블 대역.
  final Map<String, Map<String, dynamic>> deletionRequests = {};

  @override
  Future<DateTime?> latestWorkoutUpdatedAt(String userId) async => null;

  @override
  Future<SupabaseAppSnapshotRow?> loadSnapshot(String userId) async {
    if (loadFailuresRemaining > 0) {
      loadFailuresRemaining--;
      throw StateError('network unavailable');
    }
    return rows[userId];
  }

  @override
  Future<DateTime> saveSnapshot({
    required String expectedUserId,
    required int schemaVersion,
    required Map<String, dynamic> payload,
    required List<Map<String, Object?>> sessions,
    required DateTime? expectedUpdatedAt,
  }) async {
    expectedSaveUserIds.add(expectedUserId);
    beforeServerAuthorization?.call();
    if (saveFailuresRemaining > 0) {
      saveFailuresRemaining--;
      throw StateError('network unavailable');
    }
    final userId = currentUserId;
    if (userId == null) throw StateError('not authenticated');
    if (userId != expectedUserId) {
      throw StateError('authenticated user changed before server execution');
    }
    final serverVersion = rows[userId]?.updatedAt;
    if (!_sameVersion(serverVersion, expectedUpdatedAt)) {
      throw StateError('snapshot version conflict');
    }
    final updatedAt = DateTime.utc(2026, 8, 16, 0, 0, ++_version);
    rows[userId] = SupabaseAppSnapshotRow(
      payload: Map<String, dynamic>.from(payload),
      updatedAt: updatedAt,
    );
    return updatedAt;
  }

  bool _sameVersion(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == null && right == null;
    return left.isAtSameMomentAs(right);
  }
}

class _ClaimedLegacySource
    implements AppRepository, ClaimedLegacySnapshotSource {
  _ClaimedLegacySource(this.snapshot);

  final AppSnapshot snapshot;
  String? claimedUserId;
  String? clearedFor;

  @override
  Future<void> clear() async {}

  @override
  Future<void> clearClaimed(String userId) async {
    if (claimedUserId == userId) clearedFor = userId;
  }

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async =>
      snapshot;

  @override
  Future<AppSnapshot?> loadClaimed(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  ) async => claimedUserId == userId ? snapshot : null;

  @override
  Future<AppSnapshot?> loadUnclaimed(
    List<ExerciseTemplate> exerciseCatalog,
  ) async => claimedUserId == null ? snapshot : null;

  @override
  Future<void> saveUnclaimed(AppSnapshot snapshot) async {}

  @override
  Future<bool> claimFor(String userId) async {
    if (claimedUserId != null && claimedUserId != userId) return false;
    claimedUserId = userId;
    return true;
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {}
}
