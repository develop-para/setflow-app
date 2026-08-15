import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'app_repository.dart';
import 'app_snapshot_codec.dart';

/// Supabase is the authoritative store. [migrationSource] is read once only to
/// move an existing Hive snapshot into the first authenticated account.
class SupabaseAppRepository implements AppRepository {
  SupabaseAppRepository(this._client, {this.migrationSource});

  static const _table = 'app_state_snapshots';

  final SupabaseClient _client;
  final AppRepository? migrationSource;
  AppSnapshot? _pendingSnapshot;

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final row = await _client
        .from(_table)
        .select('payload')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row != null) {
      final rawPayload = row['payload'];
      if (rawPayload is Map) {
        return AppSnapshotCodec.fromJson(
          Map<String, dynamic>.from(rawPayload),
          exerciseCatalog,
        );
      }
    }

    final legacySnapshot = await migrationSource?.load(exerciseCatalog);
    final snapshot = legacySnapshot ?? _pendingSnapshot;
    if (snapshot == null) return null;

    await save(snapshot);
    if (legacySnapshot != null) await migrationSource?.clear();
    return snapshot;
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _pendingSnapshot = snapshot;
      return;
    }

    final payload = AppSnapshotCodec.toJson(snapshot);
    await _client.from(_table).upsert({
      'user_id': user.id,
      'schema_version': AppSnapshotCodec.schemaVersion,
      'payload': payload,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');

    // Keep the existing normalized preference/profile records useful while the
    // rest of the product moves from snapshots to feature-specific tables.
    await _client.from('user_settings').upsert({
      'user_id': user.id,
      'weight_unit': snapshot.weightUnit,
      'theme': snapshot.isDarkMode ? 'dark' : 'light',
      'default_rest_seconds': snapshot.restDefaultSeconds,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
    await _client.from('user_profiles').upsert({
      'user_id': user.id,
      'weight': snapshot.weight,
      'height': snapshot.heightCm,
      'age': snapshot.age,
      'gender': snapshot.gender,
      'goal': snapshot.goals.isEmpty ? null : snapshot.goals.join(', '),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');

    _pendingSnapshot = null;
  }

  @override
  Future<void> clear() async {
    _pendingSnapshot = null;
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from(_table).delete().eq('user_id', user.id);
  }
}
