import '../models.dart';

class ExerciseRecommendationTraits {
  const ExerciseRecommendationTraits({
    required this.requiredEquipment,
    required this.movements,
    this.minimumExperience = TrainingExperienceLevel.beginner,
  });

  final Set<TrainingEquipment> requiredEquipment;
  final Set<TrainingMovementRestriction> movements;
  final TrainingExperienceLevel minimumExperience;

  bool isEligibleFor(RecommendationProfile profile) {
    if (!profile.availableEquipment.containsAll(requiredEquipment)) {
      return false;
    }
    if (profile.experienceLevel.index < minimumExperience.index) {
      return false;
    }
    return movements.every(
      (movement) => !profile.restrictedMovements.contains(movement),
    );
  }
}

/// Product metadata for every built-in catalog exercise.
///
/// These tags implement the member's explicit equipment and movement choices.
/// They are not a diagnosis, rehabilitation protocol, or claim that a painful
/// body region makes a movement universally unsafe.
const exerciseRecommendationTraits = <String, ExerciseRecommendationTraits>{
  'bench': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'incline': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'squat': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.squatRack},
    movements: {TrainingMovementRestriction.squatLunge},
  ),
  'legpress': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.squatLunge},
  ),
  'latpull': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {TrainingMovementRestriction.verticalPull},
  ),
  'row': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {
      TrainingMovementRestriction.rowing,
      TrainingMovementRestriction.hipHinge,
    },
  ),
  'ohp': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {TrainingMovementRestriction.overheadPress},
  ),
  'lateral': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.shoulderRaise},
  ),
  'curl': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {},
  ),
  'plank': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {},
  ),
  'run': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.treadmill},
    movements: {TrainingMovementRestriction.impact},
  ),
  'dumbbell_bench': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'incline_barbell': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'decline_bench': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
    minimumExperience: TrainingExperienceLevel.advanced,
  ),
  'chest_press': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'cable_fly': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'pec_deck': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'pushup': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'dips': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dipBars},
    movements: {TrainingMovementRestriction.horizontalPress},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'pullup': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.pullupBar},
    movements: {TrainingMovementRestriction.verticalPull},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'assisted_pullup': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.verticalPull},
  ),
  'seated_cable_row': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {TrainingMovementRestriction.rowing},
  ),
  'one_arm_dumbbell_row': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.rowing},
  ),
  'tbar_row': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {
      TrainingMovementRestriction.rowing,
      TrainingMovementRestriction.hipHinge,
    },
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'chest_supported_row': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.rowing},
  ),
  'straight_arm_pulldown': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {TrainingMovementRestriction.verticalPull},
  ),
  'face_pull': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {TrainingMovementRestriction.rowing},
  ),
  'reverse_fly': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.rowing},
  ),
  'rack_pull': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.squatRack},
    movements: {TrainingMovementRestriction.hipHinge},
    minimumExperience: TrainingExperienceLevel.advanced,
  ),
  'back_extension': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.hipHinge},
  ),
  'dumbbell_shoulder_press': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.overheadPress},
  ),
  'arnold_press': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.overheadPress},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'front_raise': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.shoulderRaise},
  ),
  'rear_delt_raise': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.rowing},
  ),
  'reverse_pec_deck': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.rowing},
  ),
  'upright_row': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {TrainingMovementRestriction.shoulderRaise},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'cable_lateral_raise': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {TrainingMovementRestriction.shoulderRaise},
  ),
  'deadlift': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {TrainingMovementRestriction.hipHinge},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'romanian_deadlift': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {TrainingMovementRestriction.hipHinge},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'hack_squat': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.squatLunge},
  ),
  'front_squat': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.squatRack},
    movements: {TrainingMovementRestriction.squatLunge},
    minimumExperience: TrainingExperienceLevel.advanced,
  ),
  'goblet_squat': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.squatLunge},
  ),
  'bulgarian_split_squat': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.squatLunge},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'walking_lunge': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {TrainingMovementRestriction.squatLunge},
  ),
  'leg_extension': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {TrainingMovementRestriction.squatLunge},
  ),
  'leg_curl': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {},
  ),
  'hip_thrust': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.hipHinge},
  ),
  'glute_bridge': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {TrainingMovementRestriction.hipHinge},
  ),
  'calf_raise': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {},
  ),
  'seated_calf_raise': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {},
  ),
  'adductor_machine': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {},
  ),
  'barbell_curl': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {},
  ),
  'hammer_curl': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {},
  ),
  'preacher_curl': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.machines},
    movements: {},
  ),
  'cable_curl': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {},
  ),
  'triceps_pushdown': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {},
  ),
  'skull_crusher': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'overhead_triceps_extension': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.dumbbells},
    movements: {TrainingMovementRestriction.overheadPress},
  ),
  'close_grip_bench': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell, TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'bench_dip': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bench},
    movements: {TrainingMovementRestriction.horizontalPress},
  ),
  'reverse_curl': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.barbell},
    movements: {},
  ),
  'crunch': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {TrainingMovementRestriction.trunkFlexionRotation},
  ),
  'cable_crunch': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.cableStation},
    movements: {TrainingMovementRestriction.trunkFlexionRotation},
  ),
  'hanging_leg_raise': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.pullupBar},
    movements: {
      TrainingMovementRestriction.verticalPull,
      TrainingMovementRestriction.trunkFlexionRotation,
    },
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'leg_raise': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {TrainingMovementRestriction.trunkFlexionRotation},
  ),
  'ab_wheel': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.abWheel},
    movements: {TrainingMovementRestriction.trunkFlexionRotation},
    minimumExperience: TrainingExperienceLevel.intermediate,
  ),
  'russian_twist': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {TrainingMovementRestriction.trunkFlexionRotation},
  ),
  'dead_bug': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {},
  ),
  'bird_dog': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {},
  ),
  'stationary_bike': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.stationaryBike},
    movements: {},
  ),
  'stair_climber': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.stairClimber},
    movements: {TrainingMovementRestriction.squatLunge},
  ),
  'rowing_machine': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.rowingMachine},
    movements: {
      TrainingMovementRestriction.rowing,
      TrainingMovementRestriction.hipHinge,
    },
  ),
  'elliptical': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.elliptical},
    movements: {},
  ),
  'brisk_walk': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.bodyweight},
    movements: {},
  ),
  'jump_rope': ExerciseRecommendationTraits(
    requiredEquipment: {TrainingEquipment.jumpRope},
    movements: {TrainingMovementRestriction.impact},
  ),
};
