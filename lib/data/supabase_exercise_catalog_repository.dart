import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'backend_cache.dart';
import 'exercise_catalog.dart';
import 'exercise_catalog_crosswalk.dart';
import 'exercise_catalog_repository.dart';

class SupabaseExerciseCatalogRepository
    implements ExerciseCatalogRepository, CachedBackendReadStatus {
  SupabaseExerciseCatalogRepository(this._client, {this.cache});

  static const _cacheKey = 'shared-exercise-catalog-v3';
  static const _pageSize = 500;

  final SupabaseClient _client;
  final BackendDocumentCache? cache;
  Object? _lastReadError;

  @override
  bool get isUsingCachedData => _lastReadError != null;

  @override
  Object? get lastReadError => _lastReadError;

  @override
  Future<List<ExerciseTemplate>> loadCached() async {
    try {
      final document = await cache?.loadDocument(_cacheKey);
      final rows = document?['rows'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .map(exerciseTemplateFromCatalogRow)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<ExerciseTemplate>> refreshCatalog() async {
    try {
      final rows = <Map<String, dynamic>>[];
      String? afterName;
      String? afterId;
      while (true) {
        final response = await _client.rpc(
          'list_master_exercises',
          params: {
            'p_after_name': afterName,
            'p_after_id': afterId,
            'p_limit': _pageSize,
          },
        );
        final page = (response as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        rows.addAll(page);
        if (page.length < _pageSize) break;
        final last = page.last;
        final nextName = _stringValue(last['name']);
        final nextId = _stringValue(last['id']);
        if (nextName.isEmpty || nextId.isEmpty) {
          throw const FormatException('Exercise catalog cursor is missing.');
        }
        afterName = nextName;
        afterId = nextId;
      }
      _lastReadError = null;
      await _storeCache(rows);
      return rows.map(exerciseTemplateFromCatalogRow).toList(growable: false);
    } catch (error, stackTrace) {
      _lastReadError = error;
      final cached = await loadCached();
      if (cached.isNotEmpty) return cached;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _storeCache(List<Map<String, dynamic>> rows) async {
    try {
      await cache?.storeDocument(_cacheKey, {
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'rows': rows,
      });
    } catch (_) {
      // A cache failure must not hide a successfully refreshed catalog.
    }
  }
}

ExerciseTemplate exerciseTemplateFromCatalogRow(Map<String, dynamic> row) {
  final databaseId = _stringValue(row['id']);
  final sourceId = _nullableString(row['source_id']);
  final builtInId = _stringValue(row['source_name']) == 'free-exercise-db'
      ? freeExerciseDbBuiltInIds[sourceId]
      : null;
  final builtIn = builtInId == null
      ? null
      : exerciseCatalog.where((item) => item.id == builtInId).firstOrNull;
  final englishName = _stringValue(row['name_en']);
  final koreanName = _stringValue(row['name_ko']);
  final fallbackName = _stringValue(row['name']);
  final name = koreanName.isNotEmpty
      ? koreanName
      : fallbackName.isNotEmpty
      ? fallbackName
      : englishName;
  final muscle = _stringValue(row['target_muscle']).isEmpty
      ? '기타'
      : _stringValue(row['target_muscle']);
  final inputType = _stringValue(row['input_type']);
  final measurement = switch (inputType) {
    'reps_only' => ExerciseMeasurement.repsOnly,
    'duration' || 'time' || 'weight_time' => ExerciseMeasurement.duration,
    _ => ExerciseMeasurement.weightReps,
  };
  final displayName = builtIn?.name ?? name;
  final builtInEquipmentKey = builtIn?.resolvedEquipmentKey;
  final preferBuiltInEquipment =
      builtInEquipmentKey != null && builtInEquipmentKey != 'unspecified';
  return ExerciseTemplate(
    id: builtIn?.id ?? databaseId,
    name: displayName,
    nameEnglish: englishName.isEmpty || englishName == displayName
        ? null
        : englishName,
    muscle: builtIn?.muscle ?? muscle,
    icon: builtIn?.icon ?? exerciseIconForMuscle(muscle),
    measurement: builtIn?.measurement ?? measurement,
    equipmentKey: preferBuiltInEquipment
        ? builtInEquipmentKey
        : _nullableString(row['equipment_key']),
    equipmentName: preferBuiltInEquipment
        ? builtIn!.resolvedEquipmentName
        : _nullableString(row['equipment']),
    aliases: _stringList(row['aliases']),
    difficulty: _nullableString(row['difficulty']),
    category: _nullableString(row['category']),
    primaryMuscles: _stringList(row['primary_muscles']),
    secondaryMuscles: _stringList(row['secondary_muscles']),
    sourceName: _nullableString(row['source_name']),
    sourceId: sourceId,
    databaseId: databaseId,
  );
}

String _stringValue(Object? value) => value?.toString().trim() ?? '';

String? _nullableString(Object? value) {
  final result = _stringValue(value);
  return result.isEmpty ? null : result;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map(_stringValue)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
