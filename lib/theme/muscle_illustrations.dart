/// Asset paths for the illustrated muscle-category SVG set.
abstract final class SetflowMuscleIllustrations {
  static const chest = 'assets/icons/muscles/chest.svg';
  static const back = 'assets/icons/muscles/back.svg';
  static const shoulders = 'assets/icons/muscles/shoulders.svg';
  static const legs = 'assets/icons/muscles/legs.svg';
  static const arms = 'assets/icons/muscles/arms.svg';
  static const core = 'assets/icons/muscles/core.svg';
  static const cardio = 'assets/icons/muscles/cardio.svg';

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
