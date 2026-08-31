import '../models.dart';

/// Backend-neutral access to the shared exercise library.
///
/// Cached rows are loaded before the account snapshot so an offline restart
/// can still resolve every exercise template referenced by a saved workout.
abstract interface class ExerciseCatalogRepository {
  Future<List<ExerciseTemplate>> loadCached();

  Future<List<ExerciseTemplate>> refreshCatalog();
}
