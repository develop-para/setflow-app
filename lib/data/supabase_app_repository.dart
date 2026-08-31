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

  Future<Map<String, dynamic>> requestAccountDeletion(String? reason);

  Future<bool> cancelAccountDeletion();

  Future<Map<String, dynamic>?> pendingAccountDeletion(String userId);

  Future<void> registerPushToken(String token, String platform);

  Future<void> unregisterPushToken(String token);
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
    late final dynamic result;
    try {
      result = await _client.rpc(
        'save_my_account_snapshot',
        params: {
          'expected_user_id': expectedUserId,
          'schema_version': schemaVersion,
          'payload': payload,
          'sessions': sessions,
          'expected_updated_at': expectedUpdatedAt?.toIso8601String(),
        },
      );
    } on PostgrestException catch (error) {
      if (_isSnapshotConflict(error)) {
        throw AppSnapshotVersionConflict(error.message);
      }
      rethrow;
    }
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
  }) async {
    try {
      await _client.rpc<void>(
        'clear_my_account_data',
        params: {
          'expected_user_id': expectedUserId,
          'expected_updated_at': expectedUpdatedAt?.toIso8601String(),
        },
      );
    } on PostgrestException catch (error) {
      if (_isSnapshotConflict(error)) {
        throw AppSnapshotVersionConflict(error.message);
      }
      rethrow;
    }
  }

  static bool _isSnapshotConflict(PostgrestException error) =>
      error.code == 'PT409' || error.code == '40001';

  @override
  Future<Map<String, dynamic>> requestAccountDeletion(String? reason) async {
    final result = await _client.rpc(
      'request_account_deletion',
      params: {'p_reason': reason},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : const <String, dynamic>{};
  }

  @override
  Future<bool> cancelAccountDeletion() async {
    final result = await _client.rpc('cancel_account_deletion');
    return result is Map && result['cancelled'] == true;
  }

  @override
  Future<void> registerPushToken(String token, String platform) =>
      _client.rpc<void>(
        'register_push_token',
        params: {'p_token': token, 'p_platform': platform},
      );

  @override
  Future<void> unregisterPushToken(String token) =>
      _client.rpc<void>('unregister_push_token', params: {'p_token': token});

  @override
  Future<Map<String, dynamic>?> pendingAccountDeletion(String userId) async {
    final rows = await _client
        .from('account_deletion_requests')
        .select('requested_at, purge_after, reason, cancelled_at, purged_at')
        .eq('user_id', userId)
        .isFilter('cancelled_at', null)
        .isFilter('purged_at', null)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }
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
        LocalFirstAppRepository,
        GuestDataAdoption,
        AccountDeletion,
        PushTokenRegistry {
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
  DateTime? _pendingQueuedAt;
  AppSnapshot? _pendingSnapshot;
  AppSnapshot? _cachedSnapshot;
  List<ExerciseTemplate> _exerciseCatalog = const [];
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
  Future<AccountDeletionRequest> requestAccountDeletion({
    String? reason,
  }) async {
    final result = await _gateway.requestAccountDeletion(reason);
    final request = _accountDeletionFromRow(result);
    if (request == null) {
      throw StateError('탈퇴 요청이 유예 기간을 돌려주지 않았습니다.');
    }
    return request;
  }

  @override
  Future<bool> cancelAccountDeletion() => _gateway.cancelAccountDeletion();

  @override
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) => _gateway.registerPushToken(token, platform);

  @override
  Future<void> unregisterPushToken(String token) =>
      _gateway.unregisterPushToken(token);

  @override
  Future<AccountDeletionRequest?> pendingAccountDeletion() async {
    final userId = _gateway.currentUserId;
    if (userId == null) return null;
    final row = await _gateway.pendingAccountDeletion(userId);
    return row == null ? null : _accountDeletionFromRow(row);
  }

  /// RPC는 camelCase로, 테이블 조회는 snake_case로 같은 값을 준다.
  static AccountDeletionRequest? _accountDeletionFromRow(
    Map<String, dynamic> row,
  ) {
    final requestedAt = DateTime.tryParse(
      (row['requestedAt'] ?? row['requested_at'])?.toString() ?? '',
    );
    final purgeAfter = DateTime.tryParse(
      (row['purgeAfter'] ?? row['purge_after'])?.toString() ?? '',
    );
    if (requestedAt == null || purgeAfter == null) return null;
    final reason = row['reason']?.toString();
    return AccountDeletionRequest(
      requestedAt: requestedAt.toLocal(),
      purgeAfter: purgeAfter.toLocal(),
      reason: reason == null || reason.isEmpty ? null : reason,
    );
  }

  @override
  Future<AppSnapshot?> loadLocal(List<ExerciseTemplate> exerciseCatalog) async {
    _exerciseCatalog = List<ExerciseTemplate>.of(exerciseCatalog);
    final userId = _gateway.currentUserId;
    if (userId == null) {
      _loadedUserId = null;
      _lastServerUpdatedAt = null;
      _pendingExpectedServerUpdatedAt = null;
      _pendingQueuedAt = null;
      _pendingSnapshot = null;
      _cachedSnapshot = null;
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
      _pendingQueuedAt = null;
      _pendingSnapshot = null;
      _cachedSnapshot = null;
      _hasPendingSave = false;
      _lastSyncError = null;
    }

    final pending = await _outbox?.loadPending(userId, exerciseCatalog);
    final cached = await _cache?.loadCached(userId, exerciseCatalog);
    _cachedSnapshot = cached;
    if (pending != null) {
      _hasPendingSave = true;
      _pendingSnapshot = pending.snapshot;
      _pendingExpectedServerUpdatedAt = pending.expectedServerUpdatedAt;
      _pendingQueuedAt = pending.queuedAt.toUtc();
    } else {
      _hasPendingSave = false;
      _pendingSnapshot = null;
      _pendingExpectedServerUpdatedAt = null;
      _pendingQueuedAt = null;
    }
    return pending?.snapshot ?? cached;
  }

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    final localSnapshot = await loadLocal(exerciseCatalog);
    final userId = _gateway.currentUserId;
    if (userId == null) return localSnapshot;
    final pending = _pendingSnapshot == null
        ? null
        : PendingAppSnapshot(
            snapshot: _pendingSnapshot!,
            queuedAt: _pendingQueuedAt ?? DateTime.now().toUtc(),
            expectedServerUpdatedAt: _pendingExpectedServerUpdatedAt,
          );
    final cached = _cachedSnapshot;

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
        _pendingQueuedAt = null;
        _cachedSnapshot = serverSnapshot;
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
          return pending.snapshot;
        } on AppSnapshotVersionConflict {
          try {
            final resolved = await _resolveVersionConflict(
              pending.snapshot,
              userId,
              pendingQueuedAt: pending.queuedAt,
            );
            _lastSyncError = null;
            return resolved;
          } catch (resolutionError) {
            _lastSyncError = resolutionError;
          }
        } catch (error) {
          // Keep showing the newest local mutation and retry via AppState. The
          // durable outbox remains intact until Supabase acknowledges it.
          _lastSyncError = error;
        }
      } else {
        try {
          final resolved = await _resolveVersionConflict(
            pending.snapshot,
            userId,
            pendingQueuedAt: pending.queuedAt,
            currentRow: row,
          );
          _lastSyncError = null;
          return resolved;
        } catch (error) {
          _lastSyncError = error;
        }
      }
      return pending.snapshot;
    }

    if (serverSnapshot != null) {
      await _cache?.storeCached(userId, serverSnapshot);
      _cachedSnapshot = serverSnapshot;
      await _tryReconcileNormalizedWorkouts(serverSnapshot, userId);
      return serverSnapshot;
    }

    // A successful empty server response is authoritative. Do not resurrect a
    // stale cache that may have been deleted from another device.
    if (cached != null) await _cache?.clearCached(userId);
    _cachedSnapshot = null;

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
    } on AppSnapshotVersionConflict {
      try {
        await _resolveVersionConflict(
          snapshot,
          userId,
          pendingQueuedAt: _pendingQueuedAt ?? DateTime.now().toUtc(),
        );
        _lastSyncError = null;
      } catch (resolutionError) {
        _lastSyncError = resolutionError;
        Error.throwWithStackTrace(resolutionError, StackTrace.current);
      }
    } catch (error) {
      _lastSyncError = error;
      rethrow;
    }
  });

  Future<AppSnapshot> _resolveVersionConflict(
    AppSnapshot localSnapshot,
    String userId, {
    required DateTime pendingQueuedAt,
    SupabaseAppSnapshotRow? currentRow,
  }) async {
    final row = currentRow ?? await _gateway.loadSnapshot(userId);
    if (_gateway.currentUserId != userId) {
      throw StateError(
        'Authenticated account changed during conflict recovery.',
      );
    }
    final remoteSnapshot = row == null
        ? null
        : AppSnapshotCodec.fromJson(row.payload, _exerciseCatalog);
    if (remoteSnapshot != null &&
        _sameSnapshot(remoteSnapshot, localSnapshot)) {
      _lastServerUpdatedAt = row!.updatedAt?.toUtc();
      await _cache?.storeCached(userId, remoteSnapshot);
      await _outbox?.clearPending(userId);
      _cachedSnapshot = remoteSnapshot;
      _hasPendingSave = false;
      _pendingSnapshot = null;
      _pendingExpectedServerUpdatedAt = null;
      _pendingQueuedAt = null;
      return remoteSnapshot;
    }

    _lastServerUpdatedAt = row?.updatedAt?.toUtc();
    final preferLocal =
        row?.updatedAt == null ||
        !pendingQueuedAt.toUtc().isBefore(row!.updatedAt!.toUtc());
    final resolved = remoteSnapshot == null
        ? localSnapshot
        : _mergeSnapshots(
            remoteSnapshot,
            localSnapshot,
            preferLocal: preferLocal,
          );
    await _stageForUser(
      userId,
      resolved,
      expectedUpdatedAt: _lastServerUpdatedAt,
    );
    await _saveForUser(
      resolved,
      userId,
      expectedUpdatedAt: _lastServerUpdatedAt,
      stageFirst: false,
    );
    return resolved;
  }

  Future<void> _stageForUser(
    String userId,
    AppSnapshot snapshot, {
    DateTime? expectedUpdatedAt,
  }) async {
    final outbox = _outbox;
    if (outbox == null) return;
    final expected =
        expectedUpdatedAt ??
        _pendingExpectedServerUpdatedAt ??
        _lastServerUpdatedAt;
    final queuedAt = DateTime.now().toUtc();
    await outbox.stagePending(
      userId,
      PendingAppSnapshot(
        snapshot: snapshot,
        queuedAt: queuedAt,
        expectedServerUpdatedAt: expected,
      ),
    );
    _hasPendingSave = true;
    _pendingSnapshot = snapshot;
    _pendingExpectedServerUpdatedAt = expected;
    _pendingQueuedAt = queuedAt;
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
    _cachedSnapshot = snapshot;
    await _outbox?.clearPending(userId);
    _hasPendingSave = false;
    _pendingSnapshot = null;
    _pendingExpectedServerUpdatedAt = null;
    _pendingQueuedAt = null;
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
                    'base_exercise_id': entry.$2.template.databaseReferenceId,
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
    _pendingQueuedAt = null;
    _pendingSnapshot = null;
    _cachedSnapshot = null;
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

  AppSnapshot _mergeSnapshots(
    AppSnapshot remote,
    AppSnapshot local, {
    required bool preferLocal,
  }) {
    final remotePayload = AppSnapshotCodec.toJson(remote);
    final localPayload = AppSnapshotCodec.toJson(local);
    final preferred = preferLocal ? localPayload : remotePayload;
    final secondary = preferLocal ? remotePayload : localPayload;
    final merged = <String, dynamic>{
      ...secondary,
      ...preferred,
      'preferences': _mergeJsonMaps(
        secondary['preferences'],
        preferred['preferences'],
      ),
      'profile': _mergeJsonMaps(secondary['profile'], preferred['profile']),
      'customExercises': _mergeJsonLists(
        secondary['customExercises'],
        preferred['customExercises'],
        key: 'id',
      ),
      'sessions': _mergeJsonLists(
        secondary['sessions'],
        preferred['sessions'],
        key: 'date',
      ),
      'routines': _mergeJsonLists(
        secondary['routines'],
        preferred['routines'],
        key: 'id',
      ),
      'communityPosts': _mergeJsonLists(
        secondary['communityPosts'],
        preferred['communityPosts'],
        key: 'id',
      ),
      'consultations': _mergeJsonLists(
        secondary['consultations'],
        preferred['consultations'],
        key: 'id',
      ),
      'businessDashboards': _mergeJsonLists(
        secondary['businessDashboards'],
        preferred['businessDashboards'],
        key: 'role',
      ),
    };
    return AppSnapshotCodec.fromJson(merged, _exerciseCatalog) ?? local;
  }

  Map<String, dynamic> _mergeJsonMaps(Object? secondary, Object? preferred) => {
    if (secondary is Map) ...Map<String, dynamic>.from(secondary),
    if (preferred is Map) ...Map<String, dynamic>.from(preferred),
  };

  List<Map<String, dynamic>> _mergeJsonLists(
    Object? secondary,
    Object? preferred, {
    required String key,
  }) {
    final merged = <String, Map<String, dynamic>>{};
    for (final source in [secondary, preferred]) {
      if (source is! List) continue;
      for (final value in source.whereType<Map>()) {
        final item = Map<String, dynamic>.from(value);
        final itemKey = item[key]?.toString();
        if (itemKey != null && itemKey.isNotEmpty) merged[itemKey] = item;
      }
    }
    return merged.values.toList(growable: false);
  }

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
      // 소리 설정과 1RM 공식도 사용자가 고른 값이다. 여기서 빠지면 게스트
      // 기록을 계정에 넣는 순간 조용히 기본값으로 되돌아간다.
      timerSound: source.timerSound,
      timerCountdownSeconds: source.timerCountdownSeconds,
      oneRepMaxFormula: source.oneRepMaxFormula,
      pushCoachingFeedback: source.pushCoachingFeedback,
      communityReactionNotifications: source.communityReactionNotifications,
      pushTogether: source.pushTogether,
      pushWorkoutReminder: source.pushWorkoutReminder,
      workoutReminderHour: source.workoutReminderHour,
      businessNotifications: source.businessNotifications,
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
