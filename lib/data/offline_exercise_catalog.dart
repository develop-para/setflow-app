import '../models.dart';
import 'bodyweight_exercise_catalog.dart';
import 'exercise_catalog.dart';
import 'machine_exercise_catalog.dart';

/// Selectable offline library. Automatic recommendations still use only the
/// original reviewed exerciseCatalog and its safety traits.
final offlineExerciseCatalog = <ExerciseTemplate>[
  ...exerciseCatalog,
  ...bodyweightExerciseCatalog,
  ...machineExerciseCatalog,
];
