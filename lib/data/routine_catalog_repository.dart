import '../models.dart';

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
    required this.authorType,
    this.colorHex,
    this.catalogKey,
    this.tags = const [],
    this.durationMinutes,
    this.authorTrainerId,
    this.authorGymId,
  });

  final String id;
  final String coachingRoutineId;
  final String title;
  final String description;
  final String authorName;
  final String difficulty;
  final RoutineCatalogAccessTier accessTier;
  final List<RoutineCatalogExercise> exercises;
  final String? authorTrainerId;
  final String? authorGymId;
  final RoutineAuthorType authorType;
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
    required this.sets,
    this.baseExerciseId,
  });

  final String id;
  final String? baseExerciseId;
  final String name;
  final String targetMuscle;
  final int orderIndex;
  final List<RoutineCatalogSet> sets;
}

class RoutineCatalogSet {
  const RoutineCatalogSet({
    required this.id,
    required this.setNumber,
    required this.type,
    required this.restSeconds,
    this.targetWeight,
    this.targetReps,
    this.durationSeconds,
    this.distanceMeters,
    this.intensityRpe,
  });

  final String id;
  final int setNumber;
  final String type;
  final double? targetWeight;
  final int? targetReps;
  final int restSeconds;
  final int? durationSeconds;
  final double? distanceMeters;
  final double? intensityRpe;
}

abstract interface class RoutineCatalogRepository {
  Future<List<RoutineCatalogItem>> listPublished();

  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  );

  Future<bool> hasActivePaidPlan();
}
