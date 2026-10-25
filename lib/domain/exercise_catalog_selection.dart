import '../models.dart';

/// A presentation-only catalog. The source registry still resolves saved IDs.
///
/// Referenced and personally added templates retain their own identities and
/// labels, including templates which a later shared-catalog refresh omitted.
/// Matching never uses a movement name: different machines can share a label
/// while requiring separate histories and measurements.
List<ExerciseTemplate> buildSelectableExerciseCatalog({
  required Iterable<ExerciseTemplate> catalog,
  Iterable<ExerciseTemplate> preservedExercises = const [],
}) {
  final preservedById = <String, ExerciseTemplate>{};
  final preservedByReference = <String, ExerciseTemplate>{};
  for (final exercise in preservedExercises) {
    preservedById.putIfAbsent(exercise.id, () => exercise);
    preservedByReference.putIfAbsent(exercise.id, () => exercise);
    final databaseId = exercise.databaseReferenceId;
    if (databaseId != null) {
      preservedByReference.putIfAbsent(databaseId, () => exercise);
    }
  }

  final selected = <String, ExerciseTemplate>{};
  for (final exercise in catalog) {
    final preserved =
        preservedById[exercise.id] ??
        preservedByReference[exercise.id] ??
        preservedByReference[exercise.databaseReferenceId];
    if (preserved != null) {
      selected.putIfAbsent(preserved.id, () => preserved);
    } else if (_isPersonalExercise(exercise)) {
      selected.putIfAbsent(exercise.id, () => exercise);
    } else if (!_isManufacturerExercise(exercise)) {
      selected.putIfAbsent(
        exercise.id,
        () => _withoutBodyweightPrefix(exercise),
      );
    }
  }
  for (final exercise in preservedById.values) {
    selected[exercise.id] = exercise;
  }
  return List.unmodifiable(selected.values);
}

/// Resolve a saved routine against the full registry, preserving its identity.
/// Prefer stable identity before considering labels. A simplified label alone
/// cannot replace a missing explicit reference. If a server reference is uncached,
/// an exact, unique source label can retain its domain mapping. The caller keeps
/// that server reference separately when saving the routine again.
ExerciseTemplate? resolveCatalogExerciseReference({
  required Iterable<ExerciseTemplate> catalog,
  String? referenceId,
  required String name,
}) {
  final candidates = catalog.toList(growable: false);
  final reference = referenceId?.trim();
  ExerciseTemplate? resolved;
  if (reference != null && reference.isNotEmpty) {
    final exactMatches = candidates
        .where((exercise) => exercise.id == reference)
        .toList(growable: false);
    if (exactMatches.length == 1) {
      resolved = exactMatches.single;
    } else if (exactMatches.isEmpty) {
      final databaseMatches = candidates
          .where((exercise) => exercise.databaseReferenceId == reference)
          .toList(growable: false);
      if (databaseMatches.length == 1) resolved = databaseMatches.single;
    }
  }
  if (resolved == null) {
    final exactMatches = candidates
        .where(
          (exercise) => exercise.name == name || exercise.storedName == name,
        )
        .toList(growable: false);
    if (exactMatches.length == 1) {
      resolved = exactMatches.single;
    } else if (exactMatches.isEmpty &&
        (reference == null || reference.isEmpty)) {
      final simplifiedMatches = candidates
          .where(
            (exercise) =>
                !_isPersonalExercise(exercise) &&
                _withoutBodyweightPrefix(exercise).name == name,
          )
          .toList(growable: false);
      if (simplifiedMatches.length == 1) resolved = simplifiedMatches.single;
    }
  }
  if (resolved == null || _isPersonalExercise(resolved)) return resolved;
  final simplified = _withoutBodyweightPrefix(resolved);
  return simplified.name == name ? simplified : resolved;
}

bool _isPersonalExercise(ExerciseTemplate exercise) =>
    exercise.id.startsWith('custom_') ||
    exercise.id.startsWith('equipment_') ||
    exercise.sourceName == 'local-equipment';

bool _isManufacturerExercise(ExerciseTemplate exercise) =>
    exercise.id.startsWith('machine_') ||
    exercise.sourceName == 'manufacturer-catalog';

final _bodyweightPrefix = RegExp(r'^\s*맨몸\s+');

ExerciseTemplate _withoutBodyweightPrefix(ExerciseTemplate exercise) {
  if (!_bodyweightPrefix.hasMatch(exercise.storedName)) return exercise;
  final name = exercise.storedName.replaceFirst(_bodyweightPrefix, '').trim();
  if (name.isEmpty || name == exercise.storedName) return exercise;
  return exercise.withDisplayNameOverride(name);
}
