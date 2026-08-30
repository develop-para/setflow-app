/// Asset paths for the illustrated muscle-category mascot set.
abstract final class SetflowMuscleIllustrations {
  static const chest = 'assets/icons/muscles/chest.png';
  static const back = 'assets/icons/muscles/back.png';
  static const shoulders = 'assets/icons/muscles/shoulders.png';
  static const legs = 'assets/icons/muscles/legs.png';
  static const arms = 'assets/icons/muscles/arms.png';
  static const core = 'assets/icons/muscles/core.png';
  static const cardio = 'assets/icons/muscles/cardio.png';

  static String forMuscle(String muscle) => switch (muscle) {
    '가슴' => chest,
    '등' => back,
    '어깨' => shoulders,
    '하체' => legs,
    '팔' => arms,
    '복근' => core,
    '유산소' => cardio,
    _ => chest,
  };
}
