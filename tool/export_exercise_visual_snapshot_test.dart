import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/bodyweight_exercise_catalog.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/machine_exercise_catalog.dart';
import 'package:setflow/data/offline_exercise_catalog.dart';
import 'package:setflow/data/supabase_exercise_catalog_repository.dart';
import 'package:setflow/models.dart';

/// Invoked by the pure-Dart exporter to evaluate Flutter domain models exactly
/// as AppState does. This helper never opens an authenticated connection.
void main() {
  test('exports canonical selectable exercise identities and metadata', () async {
    final output = Platform.environment['SETFLOW_VISUAL_CATALOG_OUTPUT'];
    if (output == null || output.isEmpty) {
      throw StateError(
        'Invoke tool/export_exercise_visual_catalog.dart instead.',
      );
    }
    final sharedPath =
        Platform.environment['SETFLOW_VISUAL_SHARED_SNAPSHOT'] ?? '';
    final sharedRows = <Map<String, dynamic>>[];
    if (sharedPath.isNotEmpty) {
      final decoded = jsonDecode(await File(sharedPath).readAsString()) as Map;
      final rows = decoded['rows'] as List;
      sharedRows.addAll(
        rows.map((row) => Map<String, dynamic>.from(row as Map)),
      );
    }
    final shared = sharedRows.map(exerciseTemplateFromCatalogRow).toList();
    final offlineIds = offlineExerciseCatalog.map((item) => item.id).toSet();
    final sharedIds = shared.map((item) => item.id).toSet();
    expect(offlineIds.length, offlineExerciseCatalog.length);
    expect(sharedIds.length, shared.length);
    final byId = <String, ExerciseTemplate>{
      for (final item in offlineExerciseCatalog) item.id: item,
      for (final item in shared) item.id: item,
      for (final item in bodyweightExerciseCatalog) item.id: item,
    };
    final curatedIds = exerciseCatalog.map((item) => item.id).toSet();
    final bodyweightIds = bodyweightExerciseCatalog
        .map((item) => item.id)
        .toSet();
    final machines = {
      for (final item in machineCatalog) item.exercise.id: item,
    };
    final rows = byId.values.map((exercise) {
      final machine = machines[exercise.id];
      return {
        'exerciseId': exercise.id,
        'name': exercise.name,
        'storedName': exercise.storedName,
        'nameEnglish': exercise.nameEnglish,
        'muscle': exercise.muscle,
        'category': exercise.category,
        'measurement': exercise.measurement.name,
        'equipmentKey': exercise.resolvedEquipmentKey,
        'equipmentName': exercise.resolvedEquipmentName,
        'primaryMuscles': exercise.primaryMuscles,
        'secondaryMuscles': exercise.secondaryMuscles,
        'aliases': exercise.aliases,
        'difficulty': exercise.difficulty,
        'sourceName': exercise.sourceName,
        'sourceId': exercise.sourceId,
        'databaseId': exercise.databaseReferenceId,
        'brand': machine?.brand,
        'model': machine?.model,
        'line': machine?.line,
        'focus': machine?.focus,
        'sourceUrl':
            machine?.sourceUrl ??
            (exercise.sourceName == 'free-exercise-db'
                ? 'https://github.com/yuhonas/free-exercise-db/blob/'
                      'a859101d633a01c4a1a920d6a8ce41dabba0705f/dist/exercises.json'
                : null),
        'metadata': {
          'catalogOrigins': [
            if (curatedIds.contains(exercise.id)) 'curated',
            if (bodyweightIds.contains(exercise.id)) 'bodyweight-offline',
            if (machine != null) 'manufacturer',
            if (sharedIds.contains(exercise.id)) 'shared-public',
          ],
          'manufacturerIdentityRequiresSeparateMotionReview': machine != null,
        },
      };
    }).toList();
    final file = File(output);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'counts': {
          'offlineExercises': offlineIds.length,
          'curatedExercises': curatedIds.length,
          'bodyweightOfflineExercises': bodyweightIds.length,
          'manufacturerExercises': machines.length,
          'sharedExercises': sharedIds.length,
          'offlineSharedOverlap': offlineIds.intersection(sharedIds).length,
          'canonicalExercises': byId.length,
        },
        'exercises': rows,
      }),
    );
  });
}
