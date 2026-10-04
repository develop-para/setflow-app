import '../models.dart';
import 'exercise_recommendation_traits.dart';
import 'custom_exercise_recommendation_rules.dart';

/// 검토된 같은 동작의 대안. 부위가 같다는 이유만으로 서로 바꾸지 않는다.
abstract final class ExerciseSubstitutions {
  static const groups = <Set<String>>[
    {'bench', 'dumbbell_bench', 'chest_press', 'pushup'},
    {'incline', 'incline_barbell'},
    {'decline_bench', 'dips'},
    {'cable_fly', 'pec_deck'},
    {'latpull', 'pullup', 'assisted_pullup'},
    {
      'row',
      'seated_cable_row',
      'one_arm_dumbbell_row',
      'tbar_row',
      'chest_supported_row',
    },
    {'ohp', 'dumbbell_shoulder_press', 'arnold_press'},
    {'lateral', 'cable_lateral_raise'},
    {'reverse_fly', 'rear_delt_raise', 'reverse_pec_deck'},
    {
      'squat',
      'front_squat',
      'goblet_squat',
      'bodyweight_squat',
      'hack_squat',
      'legpress',
    },
    {'walking_lunge', 'bulgarian_split_squat'},
    {'deadlift', 'romanian_deadlift', 'rack_pull'},
    {'hip_thrust', 'glute_bridge'},
    {'calf_raise', 'seated_calf_raise'},
    {'curl', 'barbell_curl', 'preacher_curl', 'cable_curl'},
    {'triceps_pushdown', 'overhead_triceps_extension', 'skull_crusher'},
    {'close_grip_bench', 'bench_dip'},
  ];

  static bool matches(ExerciseTemplate original, ExerciseTemplate candidate) =>
      original.id != candidate.id &&
      original.isCardio == candidate.isCardio &&
      (groups.any(
            (group) =>
                group.contains(original.id) && group.contains(candidate.id),
          ) ||
          _matchesCustom(original, candidate));

  static CustomExerciseMovement? movementFor(ExerciseTemplate exercise) {
    final info = CustomExerciseRecommendationRules.infoFor(exercise);
    if (info?.enabled == true) return info!.movement;
    for (var index = 0; index < groups.length; index++) {
      if (groups[index].contains(exercise.id)) {
        return const [
          CustomExerciseMovement.horizontalPress,
          CustomExerciseMovement.inclinePress,
          CustomExerciseMovement.declinePress,
          CustomExerciseMovement.chestFly,
          CustomExerciseMovement.verticalPull,
          CustomExerciseMovement.rowing,
          CustomExerciseMovement.overheadPress,
          CustomExerciseMovement.shoulderRaise,
          CustomExerciseMovement.reverseFly,
          CustomExerciseMovement.squat,
          CustomExerciseMovement.lunge,
          CustomExerciseMovement.hipHinge,
          CustomExerciseMovement.hipExtension,
          CustomExerciseMovement.calfRaise,
          CustomExerciseMovement.elbowFlexion,
          CustomExerciseMovement.elbowExtension,
          CustomExerciseMovement.closeGripPress,
        ][index];
      }
    }
    return null;
  }

  static bool _matchesCustom(
    ExerciseTemplate original,
    ExerciseTemplate candidate,
  ) {
    if (!original.id.startsWith('custom_') &&
        !candidate.id.startsWith('custom_')) {
      return false;
    }
    if (original.isCardio) {
      final originalDefinition =
          CustomExerciseRecommendationRules.infoFor(
            original,
          )?.cardioDefinitionId ??
          original.id;
      final candidateDefinition =
          CustomExerciseRecommendationRules.infoFor(
            candidate,
          )?.cardioDefinitionId ??
          candidate.id;
      return originalDefinition == candidateDefinition &&
          (!original.id.startsWith('custom_') ||
              CustomExerciseRecommendationRules.participates(original)) &&
          (!candidate.id.startsWith('custom_') ||
              CustomExerciseRecommendationRules.participates(candidate));
    }
    final movement = movementFor(original);
    final candidateMovement = movementFor(candidate);
    return movement != null &&
        movement != CustomExerciseMovement.other &&
        movement == candidateMovement &&
        original.isDurationHold == candidate.isDurationHold &&
        (CustomExerciseRecommendationRules.infoFor(
                  original,
                )?.primaryMuscle?.exerciseCategory ??
                original.muscle) ==
            (CustomExerciseRecommendationRules.infoFor(
                  candidate,
                )?.primaryMuscle?.exerciseCategory ??
                candidate.muscle);
  }

  /// 버튼에 명시하는 주 장비. 벤치·랙 같은 보조 설비를 임의로 함께 제외하지 않는다.
  static TrainingEquipment? unavailableEquipmentFor(ExerciseTemplate template) {
    final required =
        recommendationTraitsFor(template)?.requiredEquipment ??
        const <TrainingEquipment>{};
    final available = TrainingEquipment.values
        .where(
          (equipment) =>
              equipment != TrainingEquipment.bodyweight &&
              required.contains(equipment),
        )
        .toList();
    return available
            .where(
              (equipment) =>
                  equipment != TrainingEquipment.bench &&
                  equipment != TrainingEquipment.squatRack,
            )
            .firstOrNull ??
        available.firstOrNull;
  }
}
