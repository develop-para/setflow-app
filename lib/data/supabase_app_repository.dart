import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'app_repository.dart';
import 'app_snapshot_codec.dart';

class SupabaseAppSnapshotRow {
  const SupabaseAppSnapshotRow({
    required this.payload,
    required this.updatedAt,
  });

  final Map<String, dynamic> payload;
  final DateTime? updatedAt;
}

/// Small boundary around the Supabase calls so account/outbox behavior can be
/// verified without weakening the production client or using a service key.
abstract interface class SupabaseAppRemoteGateway {
  String? get currentUserId;

  Future<SupabaseAppSnapshotRow?> loadSnapshot(String userId);

  Future<DateTime?> latestWorkoutUpdatedAt(String userId);

  Future<DateTime> saveSnapshot({
    required String expectedUserId,
    required int schemaVersion,
    required Map<String, dynamic> payload,
    required List<Map<String, Object?>> sessions,
    required DateTime? expectedUpdatedAt,
  });

  Future<void> clearSnapshot({
    required String expectedUserId,
    required DateTime? expectedUpdatedAt,
  });
}

class _SupabaseClientAppRemoteGateway implements SupabaseAppRemoteGateway {
  _SupabaseClientAppRemoteGateway(this._client);

  static const _table = 'app_state_snapshots';

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<SupabaseAppSnapshotRow?> loadSnapshot(String userId) async {
    final row = await _client
        .from(_table)
        .select('payload,updated_at')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null || row['payload'] is! Map) return null;
    return SupabaseAppSnapshotRow(
      payload: Map<String, dynamic>.from(row['payload'] as Map),
      updatedAt: DateTime.tryParse(
        row['updated_at']?.toString() ?? '',
      )?.toUtc(),
    );
  }

  @override
  Future<DateTime?> latestWorkoutUpdatedAt(String userId) async {
    final row = await _client
        .from('workout_sessions')
        .select('updated_at')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return DateTime.tryParse(row?['updated_at']?.toString() ?? '')?.toUtc();
  }

  @override
  Future<DateTime> saveSnapshot({
    required String expectedUserId,
    required int schemaVersion,
    required Map<String, dynamic> payload,
    required List<Map<String, Object?>> sessions,
    required DateTime? expectedUpdatedAt,
  }) async {
    final result = await _client.rpc(
      'save_my_account_snapshot',
      params: {
        'expected_user_id': expectedUserId,
        'schema_version': schemaVersion,
        'payload': payload,
        'sessions': sessions,
        'expected_updated_at': expectedUpdatedAt?.toIso8601String(),
      },
    );
    final resultMap = result is Map
        ? Map<String, dynamic>.from(result)
        : const <String, dynamic>{};
    final updatedAt = DateTime.tryParse(
      resultMap['updated_at']?.toString() ?? '',
    );
    if (updatedAt == null) {
      throw StateError('Snapshot save did not return a server version.');
    }
    return updatedAt.toUtc();
  }

  @override
  Future<void> clearSnapshot({
    required String expectedUserId,
    required DateTime? expectedUpdatedAt,
  }) => _client.rpc<void>(
    'clear_my_account_data',
    params: {
      'expected_user_id': expectedUserId,
      'expected_updated_at': expectedUpdatedAt?.toIso8601String(),
    },
  );
}

/// Supabase is authoritative, while the account-scoped local outbox protects
/// the last mutation from process termination and transient network failures.
/// A legacy Hive snapshot is imported only after it has been explicitly
/// claimed for the exact authenticated user id.
class SupabaseAppRepository
    implements
        AppRepository,
        PendingSaveAwareRepository,
        DeferredSyncAppRepository,
        GuestDataAdoption {
  factory SupabaseAppRepository(
    SupabaseClient client, {
    AppRepository? migrationSource,
    AccountSnapshotOutbox? outbox,
  }) {
    return SupabaseAppRepository.withGateway(
      _SupabaseClientAppRemoteGateway(client),
      migrationSource: migrationSource,
      outbox: outbox ?? _accountOutboxFrom(migrationSource),
      cache: _accountCacheFrom(migrationSource),
    );
  }

  SupabaseAppRepository.withGateway(
    this._gateway, {
    this.migrationSource,
    AccountSnapshotOutbox? outbox,
    AccountSnapshotCache? cache,
  }) : _outbox = outbox ?? _accountOutboxFrom(migrationSource),
       _cache = cache ?? _accountCacheFrom(outbox ?? migrationSource);

  final SupabaseAppRemoteGateway _gateway;
  final AppRepository? migrationSource;
  final AccountSnapshotOutbox? _outbox;
  final AccountSnapshotCache? _cache;

  DateTime? _lastServerUpdatedAt;
  DateTime? _pendingExpectedServerUpdatedAt;
  AppSnapshot? _pendingSnapshot;
  String? _loadedUserId;
  bool _hasPendingSave = false;
  Object? _lastSyncError;
  Future<void> _operationTail = Future<void>.value();

  @override
  bool get hasPendingSave => _hasPendingSave;

  @override
  Object? get lastSyncError => _lastSyncError;

  ClaimedLegacySnapshotSource? get _claimedSource {
    final source = migrationSource;
    return source is ClaimedLegacySnapshotSource
        ? source as ClaimedLegacySnapshotSource
        : null;
  }

  @override
  Future<AppSnapshot?> peekGuestSnapshot(
    List<ExerciseTemplate> exerciseCatalog,
  ) async => _claimedSource?.loadUnclaimed(exerciseCatalog);

  @override
  Future<bool> adoptGuestSnapshot(String userId) async =>
      await _claimedSource?.claimFor(userId) ?? false;

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    final userId = _gateway.currentUserId;
    if (userId == null) {
      _loadedUserId = null;
      _lastServerUpdatedAt = null;
      _pendingExpectedServerUpdatedAt = null;
      _pendingSnapshot = null;
      _hasPendingSave = false;
      _lastSyncError = null;
      // The guest gets their own device-local records back. Returning null
      // here made every workout logged before signing up vanish on restart.
      return _claimedSource?.loadUnclaimed(exerciseCatalog);
    }
    if (_loadedUserId != userId) {
      _loadedUserId = userId;
      _lastServerUpdatedAt = null;
      _pendingExpectedServerUpdatedAt = null;
      _pendingSnapshot = null;
      _hasPendingSave = false;
      _lastSyncError = null;
    }

    final pending = await _outbox?.loadPending(userId, exerciseCatalog);
    final cached = await _cache?.loadCached(userId, exerciseCatalog);
    if (pending != null) {
      _hasPendingSave = true;
      _pendingSnapshot = pending.snapshot;
      _pendingExpectedServerUpdatedAt = pending.expectedServerUpdatedAt;
    }

    SupabaseAppSnapshotRow? row;
    try {
      row = await _gateway.loadSnapshot(userId);
      _lastSyncError = null;
    } catch (error) {
      // A network outage must not prevent startup. The pending payload is the
      // newest local mutation; otherwise use the last server-acknowledged cache.
      _lastSyncError = error;
      return pending?.snapshot ?? cached;
    }
    _lastServerUpdatedAt = row?.updatedAt?.toUtc();
    final serverSnapshot = row == null
        ? null
        : AppSnapshotCodec.fromJson(row.payload, exerciseCatalog);

    if (pending != null) {
      if (serverSnapshot != null &&
          _sameSnapshot(serverSnapshot, pending.snapshot)) {
        await _cache?.storeCached(userId, serverSnapshot);
        await _outbox?.clearPending(userId);
        _hasPendingSave = false;
        _pendingSnapshot = null;
        _pendingExpectedServerUpdatedAt = null;
        await _tryReconcileNormalizedWorkouts(serverSnapshot, userId);
        return serverSnapshot;
      }

      if (_sameVersion(pending.expectedServerUpdatedAt, _lastServerUpdatedAt)) {
        try {
          await _saveForUser(
            pending.snapshot,
            userId,
            expectedUpdatedAt: pending.expectedServerUpdatedAt,
            stageFirst: false,
          );
          _lastSyncError = null;
        } catch (error) {
          // Keep showing the newest local mutation and retry via AppState. The
          // durable outbox remains intact until Supabase acknowledges it.
          _lastSyncError = error;
        }
      }
      return pending.snapshot;
    }

    if (serverSnapshot != null) {
      await _cache?.storeCached(userId, serverSnapshot);
      await _tryReconcileNormalizedWorkouts(serverSnapshot, userId);
      return serverSnapshot;
    }

    // A successful empty server response is authoritative. Do not resurrect a
    // stale cache that may have been deleted from another device.
    if (cached != null) await _cache?.clearCached(userId);

    final claimedSource = _claimedSource;
    if (claimedSource == null) return null;
    final claimed = await claimedSource.loadClaimed(userId, exerciseCatalog);
    if (claimed == null) return null;
    final sanitized = _sanitizeClaimedLegacySnapshot(claimed);
    await save(sanitized);
    await syncPending();
    await claimedSource.clearClaimed(userId);
    return sanitized;
  }

  Future<void> _tryReconcileNormalizedWorkouts(
    AppSnapshot snapshot,
    String userId,
  ) async {
    try {
      await _reconcileNormalizedWorkouts(snapshot, userId);
    } catch (error) {
      _lastSyncError = error;
    }
  }

  Future<void> _reconcileNormalizedWorkouts(
    AppSnapshot snapshot,
    String userId,
  ) async {
    final latestWorkoutAt = await _gateway.latestWorkoutUpdatedAt(userId);
    final snapshotUpdatedAt = _lastServerUpdatedAt;
    final hasSnapshotWorkouts = snapshot.sessions.isNotEmpty;
    final needsProjection = latestWorkoutAt == null
        ? hasSnapshotWorkouts
        : !hasSnapshotWorkouts ||
              (snapshotUpdatedAt != null &&
                  latestWorkoutAt.isBefore(snapshotUpdatedAt));
    if (needsProjection) {
      await save(snapshot);
      await syncPending();
    }
  }

  @override
  Future<void> save(AppSnapshot snapshot) => _serialize(() async {
    final currentUserId = _gateway.currentUserId;
    final loadedUserId = _loadedUserId;

    if (currentUserId == null) {
      if (loadedUserId != null) {
        await _stageForUser(loadedUserId, snapshot);
        // Signing out leaves the previous account's data staged under its own
        // uid. Writing it to the unclaimed slot as well would hand it to the
        // next guest, so stop here.
        return;
      }
      // A guest's records live on the device with no owner. They are still not
      // attributed to whoever signs in next -- that needs an explicit claim --
      // but "no provenance" was never a reason to throw the work away, which
      // is what returning here without writing used to do.
      await _claimedSource?.saveUnclaimed(snapshot);
      return;
    }
    if (loadedUserId != currentUserId) {
      if (loadedUserId != null) {
        await _stageForUser(loadedUserId, snapshot);
      }
      throw StateError('Load the authenticated account before saving it.');
    }

    if (_outbox == null) {
      // Tests and non-persistent embedders without a local store retain the
      // original direct-save behavior because there is no durable defer path.
      await _saveForUser(
        snapshot,
        currentUserId,
        expectedUpdatedAt:
            _pendingExpectedServerUpdatedAt ?? _lastServerUpdatedAt,
        stageFirst: false,
      );
      return;
    }

    await _stageForUser(currentUserId, snapshot);
    if (_gateway.currentUserId != currentUserId) {
      throw StateError('Authenticated account changed during local save.');
    }
  });

  @override
  Future<void> syncPending() => _serialize(() async {
    final snapshot = _pendingSnapshot;
    final userId = _loadedUserId;
    if (!_hasPendingSave || snapshot == null || userId == null) return;
    if (_gateway.currentUserId != userId) {
      final error = StateError(
        'Authenticated account changed before snapshot synchronization.',
      );
      _lastSyncError = error;
      throw error;
    }
    try {
      await _saveForUser(
        snapshot,
        userId,
        expectedUpdatedAt:
            _pendingExpectedServerUpdatedAt ?? _lastServerUpdatedAt,
        stageFirst: false,
      );
      _lastSyncError = null;
    } catch (error) {
      _lastSyncError = error;
      rethrow;
    }
  });

  Future<void> _stageForUser(String userId, AppSnapshot snapshot) async {
    final outbox = _outbox;
    if (outbox == null) return;
    final expected = _pendingExpectedServerUpdatedAt ?? _lastServerUpdatedAt;
    await outbox.stagePending(
      userId,
      PendingAppSnapshot(
        snapshot: snapshot,
        queuedAt: DateTime.now().toUtc(),
        expectedServerUpdatedAt: expected,
      ),
    );
    _hasPendingSave = true;
    _pendingSnapshot = snapshot;
    _pendingExpectedServerUpdatedAt = expected;
  }

  Future<void> _saveForUser(
    AppSnapshot snapshot,
    String userId, {
    required DateTime? expectedUpdatedAt,
    required bool stageFirst,
  }) async {
    if (stageFirst) await _stageForUser(userId, snapshot);
    if (_gateway.currentUserId != userId) {
      throw StateError('Authenticated account changed before snapshot save.');
    }
    final updatedAt = await _gateway.saveSnapshot(
      expectedUserId: userId,
      schemaVersion: AppSnapshotCodec.schemaVersion,
      payload: AppSnapshotCodec.toJson(snapshot),
      sessions: _normalizedWorkoutPayload(snapshot),
      expectedUpdatedAt: expectedUpdatedAt,
    );
    _lastServerUpdatedAt = updatedAt.toUtc();
    // Advance the optimistic-lock version immediately after server
    // acknowledgement. If a following Hive operation fails, a retry remains
    // idempotent instead of reusing the stale pre-write version.
    _pendingExpectedServerUpdatedAt = _lastServerUpdatedAt;
    await _cache?.storeCached(userId, snapshot);
    await _outbox?.clearPending(userId);
    _hasPendingSave = false;
    _pendingSnapshot = null;
    _pendingExpectedServerUpdatedAt = null;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  List<Map<String, Object?>> _normalizedWorkoutPayload(AppSnapshot snapshot) {
    final orderedSessions = snapshot.sessions.values.toList(growable: false)
      ..sort((left, right) => left.date.compareTo(right.date));
    return orderedSessions
        .map(
          (session) => <String, Object?>{
            'date': session.date.toIso8601String(),
            'exercises': session.exercises.indexed
                .map(
                  (entry) => <String, Object?>{
                    'client_id': entry.$2.id,
                    'base_exercise_id': entry.$2.template.id,
                    'name': entry.$2.template.name,
                    'target_muscle': entry.$2.template.muscle,
                    'order_index': entry.$1,
                    'sets': entry.$2.sets
                        .map(
                          (set) => <String, Object?>{
                            'set_no': set.number,
                            'type': _databaseSetType(set.type),
                            'weight': entry.$2.template.isCardio
                                ? 0
                                : set.weight,
                            'reps': entry.$2.template.isCardio ? 0 : set.reps,
                            'duration_sec': set.durationSeconds > 0
                                ? set.durationSeconds
                                : null,
                            'distance_m': set.distanceKm > 0
                                ? set.distanceKm * 1000
                                : null,
                            'intensity_rpe': set.intensityRpe > 0
                                ? set.intensityRpe
                                : null,
                            'completed': set.completed,
                            'rest_seconds': set.restSeconds,
                          },
                        )
                        .toList(growable: false),
                  },
                )
                .toList(growable: false),
          },
        )
        .toList(growable: false);
  }

  String _databaseSetType(String value) {
    return switch (value.trim().toLowerCase()) {
      '웜업' || 'warmup' => 'warmup',
      '드랍' || 'drop' => 'drop',
      '실패' || 'failure' || 'fail' => 'fail',
      _ => 'normal',
    };
  }

  @override
  Future<void> clear() => _serialize(() async {
    final userId = _gateway.currentUserId;
    if (userId == null) return;
    if (_loadedUserId != userId) {
      throw StateError('Load the authenticated account before clearing it.');
    }
    await _gateway.clearSnapshot(
      expectedUserId: userId,
      expectedUpdatedAt: _lastServerUpdatedAt,
    );
    await _outbox?.clearPending(userId);
    await _cache?.clearCached(userId);
    _lastServerUpdatedAt = null;
    _pendingExpectedServerUpdatedAt = null;
    _pendingSnapshot = null;
    _hasPendingSave = false;
    _lastSyncError = null;
  });

  bool _sameVersion(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == null && right == null;
    return left.toUtc().isAtSameMomentAs(right.toUtc());
  }

  bool _sameSnapshot(AppSnapshot left, AppSnapshot right) =>
      jsonEncode(AppSnapshotCodec.toJson(left)) ==
      jsonEncode(AppSnapshotCodec.toJson(right));

  AppSnapshot _sanitizeClaimedLegacySnapshot(AppSnapshot source) {
    const seededRoutineIds = {'mine_1', 'mine_2'};
    return AppSnapshot(
      role: source.role,
      isDarkMode: source.isDarkMode,
      weightUnit: source.weightUnit,
      restDefaultSeconds: source.restDefaultSeconds,
      defaultSetCount: source.defaultSetCount,
      defaultRepCount: source.defaultRepCount,
      activeTrainingPartyId: source.activeTrainingPartyId,
      nickname: source.nickname,
      useRir: source.useRir,
      autoStartRestTimer: source.autoStartRestTimer,
      autoRecommendNextExercise: source.autoRecommendNextExercise,
      restTimerNotifications: source.restTimerNotifications,
      timerVibration: source.timerVibration,
      pushCoachingFeedback: source.pushCoachingFeedback,
      communityReactionNotifications: source.communityReactionNotifications,
      sessions: {
        for (final entry in source.sessions.entries)
          if (entry.value.exercises.any(
            (exercise) => !exercise.id.startsWith('seed_'),
          ))
            entry.key: WorkoutSession(
              date: entry.value.date,
              exercises: entry.value.exercises
                  .where((exercise) => !exercise.id.startsWith('seed_'))
                  .toList(growable: false),
            ),
      },
      routines: source.routines
          .where(
            (routine) =>
                !seededRoutineIds.contains(routine.id) &&
                !routine.id.startsWith('market_'),
          )
          .toList(growable: false),
      goals: List<String>.of(source.goals),
      heightCm: source.heightCm,
      weight: source.weight,
      age: source.age,
      gender: source.gender,
      communityPosts: source.communityPosts
          .where((post) => post.isMine)
          .toList(growable: false),
      consultations: source.consultations
          .where((consultation) => consultation.id != 'consult_1')
          .toList(growable: false),
      businessDashboards: const {},
      customExercises: List<ExerciseTemplate>.of(source.customExercises),
    );
  }
}

AccountSnapshotOutbox? _accountOutboxFrom(Object? source) =>
    source is AccountSnapshotOutbox ? source : null;

AccountSnapshotCache? _accountCacheFrom(Object? source) =>
    source is AccountSnapshotCache ? source : null;
