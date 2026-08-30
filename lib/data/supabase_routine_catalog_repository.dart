import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'backend_cache.dart';
import 'routine_catalog_repository.dart';

class SupabaseRoutineCatalogRepository
    implements RoutineCatalogRepository, CachedBackendReadStatus {
  SupabaseRoutineCatalogRepository(
    this._client, {
    this.cache,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const _cacheKey = 'published-routine-catalog-v1';

  final SupabaseClient _client;
  final BackendDocumentCache? cache;
  final DateTime Function() _now;
  Object? _lastReadError;

  @override
  bool get isUsingCachedData => _lastReadError != null;

  @override
  Object? get lastReadError => _lastReadError;

  @override
  Future<List<RoutineCatalogItem>> listPublished() async {
    try {
      final rows = await _client
          .from('market_routines')
          .select('''
          id,
          coaching_routine_id,
          title,
          description,
          author_name,
          trainer_id,
          gym_id,
          difficulty,
          access_tier,
          color_hex,
          catalog_key,
          tags,
          duration_min,
          created_at,
          coaching_routine:coaching_routines(
            id,
            status,
            exercises:coaching_routine_exercises(
              id,
              base_exercise_id,
              name,
              target_muscle,
              order_index,
              sets:coaching_routine_sets(
                id,
                set_no,
                type,
                target_weight,
                target_reps,
                rest_seconds,
                duration_sec,
                distance_m,
                intensity_rpe
              )
            )
          )
          ''')
          .eq('status', 'published')
          .eq('coaching_routine.status', 'approved')
          .order('created_at', ascending: false);

      final normalizedRows = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      final items = normalizedRows
          .map(routineCatalogItemFromSupabaseRow)
          .toList(growable: false);
      _lastReadError = null;
      await _storeCache(normalizedRows);
      return items;
    } catch (error, stackTrace) {
      _lastReadError = error;
      final cached = await _loadCache();
      if (cached != null) return cached;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _storeCache(List<Map<String, dynamic>> rows) async {
    try {
      await cache?.storeDocument(_cacheKey, {
        'cachedAt': _now().toUtc().toIso8601String(),
        'rows': rows,
      });
    } catch (_) {
      // A cache write must never turn a successful server refresh into an
      // error. The previous cache remains a valid fallback.
    }
  }

  Future<List<RoutineCatalogItem>?> _loadCache() async {
    try {
      final document = await cache?.loadDocument(_cacheKey);
      final rawRows = document?['rows'];
      if (rawRows is! List) return null;
      return rawRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .map(routineCatalogItemFromSupabaseRow)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  ) async {
    final updated = await _client
        .from('market_routines')
        .update({'access_tier': accessTier.databaseValue})
        .eq('id', routineId)
        .select('id')
        .maybeSingle();

    if (updated == null) {
      throw StateError(
        'Routine was not updated. Administrator access required.',
      );
    }
  }

  @override
  Future<bool> hasActivePaidPlan() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final rows = await _client
        .from('subscriptions')
        .select('''
          status,
          current_period_end,
          plan:plans!inner(
            audience,
            price
          )
        ''')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .order('created_at', ascending: false);

    final now = DateTime.now().toUtc();
    for (final row in rows) {
      final periodEnd = DateTime.tryParse(
        _stringValue(row['current_period_end']),
      );
      if (periodEnd != null && periodEnd.toUtc().isBefore(now)) continue;

      final plan = _mapValue(row['plan']);
      if (plan == null || plan['audience'] != 'b2c') continue;
      if (_numberValue(plan['price']) > 0) return true;
    }
    return false;
  }
}

/// Maps the Data API response while preserving the UUID of its real author.
/// Public for focused repository contract tests.
RoutineCatalogItem routineCatalogItemFromSupabaseRow(Map<String, dynamic> row) {
  final coachingRoutine = _mapValue(row['coaching_routine']);
  final authorTrainerId = _nullableString(row['trainer_id']);
  final authorGymId = _nullableString(row['gym_id']);
  if (authorTrainerId != null && authorGymId != null) {
    throw const FormatException(
      'A catalog routine cannot have both a trainer and gym author.',
    );
  }
  final exerciseRows = _mapListValue(coachingRoutine?['exercises']);
  final exercises = exerciseRows.map(_exerciseFromRow).toList()
    ..sort((left, right) {
      final byOrder = left.orderIndex.compareTo(right.orderIndex);
      return byOrder != 0 ? byOrder : left.id.compareTo(right.id);
    });

  return RoutineCatalogItem(
    id: _requiredString(row, 'id'),
    coachingRoutineId: _requiredString(row, 'coaching_routine_id'),
    title: _requiredString(row, 'title'),
    description: _stringValue(row['description']),
    authorName: _stringValue(row['author_name'], fallback: 'Setflow'),
    authorTrainerId: authorTrainerId,
    authorGymId: authorGymId,
    authorType: authorTrainerId != null
        ? RoutineAuthorType.trainer
        : authorGymId != null
        ? RoutineAuthorType.gym
        : RoutineAuthorType.system,
    difficulty: _stringValue(row['difficulty'], fallback: 'beginner'),
    accessTier: RoutineCatalogAccessTier.fromDatabase(row['access_tier']),
    colorHex: _nullableString(row['color_hex']),
    catalogKey: _nullableString(row['catalog_key']),
    tags: _stringListValue(row['tags']),
    durationMinutes: _nullableInt(row['duration_min']),
    exercises: List.unmodifiable(exercises),
  );
}

RoutineCatalogExercise _exerciseFromRow(Map<String, dynamic> row) {
  final sets = _mapListValue(row['sets']).map(_setFromRow).toList()
    ..sort((left, right) => left.setNumber.compareTo(right.setNumber));
  return RoutineCatalogExercise(
    id: _requiredString(row, 'id'),
    baseExerciseId: _nullableString(row['base_exercise_id']),
    name: _stringValue(row['name'], fallback: '운동'),
    targetMuscle: _stringValue(row['target_muscle'], fallback: '전신'),
    orderIndex: _nullableInt(row['order_index']) ?? 0,
    sets: List.unmodifiable(sets),
  );
}

RoutineCatalogSet _setFromRow(Map<String, dynamic> row) {
  return RoutineCatalogSet(
    id: _requiredString(row, 'id'),
    setNumber: _nullableInt(row['set_no']) ?? 1,
    type: _stringValue(row['type'], fallback: 'normal'),
    targetWeight: _nullableDouble(row['target_weight']),
    targetReps: _nullableInt(row['target_reps']),
    restSeconds: _nullableInt(row['rest_seconds']) ?? 90,
    durationSeconds: _nullableInt(row['duration_sec']),
    distanceMeters: _nullableDouble(row['distance_m']),
    intensityRpe: _nullableDouble(row['intensity_rpe']),
  );
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return null;
}

List<Map<String, dynamic>> _mapListValue(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

List<String> _stringListValue(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = _nullableString(row[key]);
  if (value == null) throw FormatException('Missing required field: $key');
  return value;
}

String _stringValue(Object? value, {String fallback = ''}) {
  return _nullableString(value) ?? fallback;
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _nullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

num _numberValue(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}
