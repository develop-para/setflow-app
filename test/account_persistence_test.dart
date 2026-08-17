import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/hive_app_repository.dart';
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
  });

  group('SupabaseAppRepository durable account outbox', () {
    test('failed save is recovered from outbox after app restart', () async {
      final gateway = _FakeSupabaseGateway(currentUserId: 'account-a')
        ..saveFailuresRemaining = 1;
      final outbox = _MemoryOutbox();
      final first = SupabaseAppRepository.withGateway(gateway, outbox: outbox);
      await first.load(const []);
      final latest = _snapshot(goals: const ['체력 향상'], heightCm: 177);

      await expectLater(first.save(latest), throwsA(isA<StateError>()));
      expect(outbox.pendingByUser['account-a']?.snapshot.goals, ['체력 향상']);

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

        await expectLater(
          repository.save(_snapshot(goals: const ['account-a-goal'])),
          throwsA(isA<StateError>()),
        );

        expect(gateway.expectedSaveUserIds, ['account-a']);
        expect(gateway.rows, isNot(contains('account-b')));
        expect(outbox.pendingByUser['account-a']?.snapshot.goals, [
          'account-a-goal',
        ]);
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
}

AppSnapshot _snapshot({
  List<String> goals = const [],
  bool isDarkMode = false,
  String weightUnit = 'kg',
  double? heightCm,
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

class _MemoryOutbox implements AccountSnapshotOutbox {
  final Map<String, PendingAppSnapshot> pendingByUser = {};

  @override
  Future<void> clearPending(String userId) async {
    pendingByUser.remove(userId);
  }

  @override
  Future<PendingAppSnapshot?> loadPending(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  ) async => pendingByUser[userId];

  @override
  Future<void> stagePending(String userId, PendingAppSnapshot pending) async {
    pendingByUser[userId] = pending;
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
  Future<DateTime?> latestWorkoutUpdatedAt(String userId) async => null;

  @override
  Future<SupabaseAppSnapshotRow?> loadSnapshot(String userId) async =>
      rows[userId];

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
  Future<void> save(AppSnapshot snapshot) async {}
}
