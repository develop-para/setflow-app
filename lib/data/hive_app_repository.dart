import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models.dart';
import 'app_repository.dart';
import 'app_snapshot_codec.dart';

class HiveAppRepository
    implements
        AppRepository,
        AccountSnapshotOutbox,
        AccountSnapshotCache,
        ClaimedLegacySnapshotSource {
  HiveAppRepository._(this._box);

  static const _snapshotKey = 'snapshot';
  static const _snapshotOwnerKey = 'snapshot_owner_user_id';
  static const _pendingPrefix = 'pending_snapshot:';
  static const _accountSnapshotPrefix = 'account_snapshot:';
  static const _boxName = 'setflow_app_state_v1';

  final Box<String> _box;

  static Future<HiveAppRepository> open() async {
    await Hive.initFlutter('setflow');
    final box = await Hive.openBox<String>(_boxName);
    return HiveAppRepository._(box);
  }

  /// Isolated path variant used by persistence tests and migration tools.
  static Future<HiveAppRepository> openAtPath(
    String path, {
    String boxName = _boxName,
  }) async {
    Hive.init(path);
    final box = await Hive.openBox<String>(boxName);
    return HiveAppRepository._(box);
  }

  Future<void> close() => _box.close();

  /// Marks an existing pre-auth snapshot as belonging to [userId]. This must
  /// only be called after an explicit migration confirmation in authenticated
  /// UI. Merely being the first user to sign in is not sufficient provenance.
  Future<bool> claimLegacySnapshotForUser(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || !_box.containsKey(_snapshotKey)) {
      return false;
    }
    final existingOwner = _box.get(_snapshotOwnerKey)?.trim();
    if (existingOwner != null &&
        existingOwner.isNotEmpty &&
        existingOwner != normalizedUserId) {
      return false;
    }
    await _box.put(_snapshotOwnerKey, normalizedUserId);
    return true;
  }

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    final source = _box.get(_snapshotKey);
    if (source == null || source.isEmpty) return null;
    return AppSnapshotCodec.decode(source, exerciseCatalog);
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    await _box.put(_snapshotKey, AppSnapshotCodec.encode(snapshot));
  }

  @override
  Future<void> clear() => _box.delete(_snapshotKey);

  @override
  Future<AppSnapshot?> loadClaimed(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  ) async {
    if (_box.get(_snapshotOwnerKey)?.trim() != userId.trim()) return null;
    return load(exerciseCatalog);
  }

  @override
  Future<void> clearClaimed(String userId) async {
    if (_box.get(_snapshotOwnerKey)?.trim() != userId.trim()) return;
    await _box.deleteAll([_snapshotKey, _snapshotOwnerKey]);
  }

  @override
  Future<PendingAppSnapshot?> loadPending(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  ) async {
    final source = _box.get('$_pendingPrefix${userId.trim()}');
    if (source == null || source.isEmpty) return null;
    try {
      final envelope = jsonDecode(source) as Map<String, dynamic>;
      final payload = envelope['payload'];
      if (payload is! Map) return null;
      final snapshot = AppSnapshotCodec.fromJson(
        Map<String, dynamic>.from(payload),
        exerciseCatalog,
      );
      final queuedAt = DateTime.tryParse(
        envelope['queuedAt']?.toString() ?? '',
      );
      if (snapshot == null || queuedAt == null) return null;
      return PendingAppSnapshot(
        snapshot: snapshot,
        queuedAt: queuedAt.toUtc(),
        expectedServerUpdatedAt: DateTime.tryParse(
          envelope['expectedServerUpdatedAt']?.toString() ?? '',
        )?.toUtc(),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<AppSnapshot?> loadCached(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  ) async {
    final source = _box.get('$_accountSnapshotPrefix${userId.trim()}');
    if (source == null || source.isEmpty) return null;
    return AppSnapshotCodec.decode(source, exerciseCatalog);
  }

  @override
  Future<void> storeCached(String userId, AppSnapshot snapshot) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }
    await _box.put(
      '$_accountSnapshotPrefix$normalizedUserId',
      AppSnapshotCodec.encode(snapshot),
    );
  }

  @override
  Future<void> clearCached(String userId) =>
      _box.delete('$_accountSnapshotPrefix${userId.trim()}');

  @override
  Future<void> stagePending(String userId, PendingAppSnapshot pending) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }
    final encodedSnapshot = AppSnapshotCodec.encode(pending.snapshot);
    final encodedPending = jsonEncode({
      'queuedAt': pending.queuedAt.toUtc().toIso8601String(),
      'expectedServerUpdatedAt': pending.expectedServerUpdatedAt
          ?.toUtc()
          .toIso8601String(),
      'payload': AppSnapshotCodec.toJson(pending.snapshot),
    });
    await _box.putAll({
      '$_accountSnapshotPrefix$normalizedUserId': encodedSnapshot,
      '$_pendingPrefix$normalizedUserId': encodedPending,
    });
  }

  @override
  Future<void> clearPending(String userId) =>
      _box.delete('$_pendingPrefix${userId.trim()}');
}
