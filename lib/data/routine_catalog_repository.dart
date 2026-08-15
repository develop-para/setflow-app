enum RoutineCatalogAccessTier {
  free('free'),
  paid('paid');

  const RoutineCatalogAccessTier(this.databaseValue);

  final String databaseValue;

  static RoutineCatalogAccessTier fromDatabase(Object? value) {
    return value == paid.databaseValue ? paid : free;
  }
}

/// Database-facing DTO for a published routine in the global catalog.
///
/// The app's editable `RoutineData` model deliberately stays separate from
/// this DTO: catalog routines are shared, read-only content until a member
/// imports one into their personal routine list.
class RoutineCatalogItem {
  const RoutineCatalogItem({
    required this.id,
    required this.coachingRoutineId,
    required this.title,
    required this.description,
    required this.authorName,
    required this.difficulty,
    required this.accessTier,
    required this.exercises,
    this.colorHex,
    this.catalogKey,
    this.tags = const [],
    this.durationMinutes,
  });

  final String id;
  final String coachingRoutineId;
  final String title;
  final String description;
  final String authorName;
  final String difficulty;
  final RoutineCatalogAccessTier accessTier;
  final List<RoutineCatalogExercise> exercises;
  final String? colorHex;
  final String? catalogKey;
  final List<String> tags;
  final int? durationMinutes;
}

class RoutineCatalogExercise {
  const RoutineCatalogExercise({
    required this.id,
    required this.name,
    required this.targetMuscle,
    required this.orderIndex,
    this.baseExerciseId,
  });

  final String id;
  final String? baseExerciseId;
  final String name;
  final String targetMuscle;
  final int orderIndex;
}

abstract interface class RoutineCatalogRepository {
  Future<List<RoutineCatalogItem>> listPublished();

  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  );

  Future<bool> hasActivePaidPlan();
}
