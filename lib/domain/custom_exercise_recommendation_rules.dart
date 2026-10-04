import '../models.dart';
import 'cardio.dart';

abstract final class CustomExerciseRecommendationRules {
  static bool isValid(
    ExerciseTemplate exercise,
    CustomExerciseRecommendation info,
  ) {
    if (!exercise.id.startsWith('custom_') || info.requiredEquipment.isEmpty) {
      return false;
    }
    if (exercise.isCardio) {
      return info.cardioDefinitionId != null &&
          cardioDefinitionForExercise(info.cardioDefinitionId!) != null &&
          info.primaryMuscle == null &&
          info.movement == null &&
          info.secondaryMuscles.isEmpty;
    }
    final primary = info.primaryMuscle;
    final movement = info.movement;
    return info.cardioDefinitionId == null &&
        primary != null &&
        movement != null &&
        (exercise.muscle == '기타' ||
            primary.exerciseCategory == exercise.muscle) &&
        movement.allowedMuscles.contains(primary) &&
        (!exercise.isDurationHold ||
            movement == CustomExerciseMovement.coreHold ||
            movement == CustomExerciseMovement.other) &&
        !info.secondaryMuscles.contains(primary) &&
        (movement.isCompound || info.secondaryMuscles.isEmpty);
  }

  static CustomExerciseRecommendation? infoFor(ExerciseTemplate exercise) {
    final info = exercise.customRecommendation;
    return info != null && isValid(exercise, info) ? info : null;
  }

  static bool participates(ExerciseTemplate exercise) =>
      infoFor(exercise)?.enabled == true;

  static String? cardioDefinitionIdFor(ExerciseTemplate exercise) {
    if (cardioDefinitionForExercise(exercise.id) != null) return exercise.id;
    return infoFor(exercise)?.cardioDefinitionId;
  }

  static Set<TrainingMovementRestriction> movementsFor(
    ExerciseTemplate exercise,
  ) {
    final info = infoFor(exercise);
    if (info == null) return const {};
    final cardio = cardioDefinitionForExercise(info.cardioDefinitionId ?? '');
    return {
      ...?info.movement?.restrictions,
      ...info.additionalMovements,
      if (cardio != null &&
          {
            CardioModality.treadmillRunning,
            CardioModality.outdoorRunning,
            CardioModality.jumpRope,
          }.contains(cardio.modality))
        TrainingMovementRestriction.impact,
    };
  }
}
