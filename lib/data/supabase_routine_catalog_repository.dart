import 'package:supabase_flutter/supabase_flutter.dart';

import 'routine_catalog_repository.dart';

class SupabaseRoutineCatalogRepository implements RoutineCatalogRepository {
  const SupabaseRoutineCatalogRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<RoutineCatalogItem>> listPublished() async {
    final rows = await _client
        .from('market_routines')
        .select('''
          id,
          coaching_routine_id,
          title,
          description,
          author_name,
          difficulty,
          access_tier,
          color_hex,
          catalog_key,
          tags,
          duration_min,
          created_at,
          coaching_routine:coaching_routines!inner(
            id,
            status,
            exercises:coaching_routine_exercises(
              id,
              base_exercise_id,
              name,
              target_muscle,
              order_index
            )
          )
        ''')
        .eq('status', 'published')
        .eq('coaching_routine.status', 'approved')
        .order('created_at', ascending: false);

    return rows.map(_catalogItemFromRow).toList(growable: false);
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

RoutineCatalogItem _catalogItemFromRow(Map<String, dynamic> row) {
  final coachingRoutine = _mapValue(row['coaching_routine']);
  if (coachingRoutine == null) {
    throw const FormatException(
      'Catalog routine is missing its coaching routine.',
    );
  }

  final exerciseRows = _mapListValue(coachingRoutine['exercises']);
  final exercises = exerciseRows.map(_exerciseFromRow).toList()
    ..sort((left, right) {
      final byOrder = left.orderIndex.compareTo(right.orderIndex);
      return byOrder != 0 ? byOrder : left.id.compareTo(right.id);
    });

  return RoutineCatalogItem(
    id: _requiredString(row, 'id'),
    coachingRoutineId: _requiredString(coachingRoutine, 'id'),
    title: _requiredString(row, 'title'),
    description: _stringValue(row['description']),
    authorName: _stringValue(row['author_name'], fallback: 'Setflow'),
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
  return RoutineCatalogExercise(
    id: _requiredString(row, 'id'),
    baseExerciseId: _nullableString(row['base_exercise_id']),
    name: _stringValue(row['name'], fallback: '운동'),
    targetMuscle: _stringValue(row['target_muscle'], fallback: '전신'),
    orderIndex: _nullableInt(row['order_index']) ?? 0,
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

num _numberValue(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}
