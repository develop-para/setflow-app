import 'dart:ui';

import 'tokens.dart';

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

  /// 마스코트를 고를 수 있는 부위 목록 — 편집기 선택지와 역매핑이 같이 쓴다.
  static const muscles = ['가슴', '등', '어깨', '하체', '팔', '복근', '유산소'];

  /// 대표 부위를 고른 루틴은 그 부위의 면 색([SetflowMuscleFill])을 루틴
  /// color로 저장한다 — 개인 루틴 서버 레코드에 color가 이미 왕복하므로
  /// 스키마 변경 없이 기기 간에 보존된다. 역매핑이 실패하면(전문가 루틴 등
  /// 다른 색) 고른 적 없는 것으로 보고 화면이 부위 자동 판정으로 돌아간다.
  static Color fillForMuscle(String muscle) => switch (muscle) {
    '가슴' => SetflowMuscleFill.chest,
    '등' => SetflowMuscleFill.back,
    '어깨' => SetflowMuscleFill.shoulders,
    '하체' => SetflowMuscleFill.legs,
    '팔' => SetflowMuscleFill.arms,
    '복근' => SetflowMuscleFill.core,
    '유산소' => SetflowMuscleFill.cardio,
    _ => SetflowMuscleFill.chest,
  };

  static String? muscleForFill(Color color) {
    for (final muscle in muscles) {
      if (fillForMuscle(muscle).toARGB32() == color.toARGB32()) return muscle;
    }
    return null;
  }

  /// 종목이 가장 많은 부위. 같으면 먼저 나온 쪽, 비어 있으면 null.
  /// 루틴의 "옷"(마스코트·틴트)을 고르는 판정이 화면마다 갈리면 같은
  /// 루틴이 다른 부위로 보인다 — 그래서 판정도 한 곳이다.
  static String? dominantMuscle(Iterable<String> muscles) {
    final counts = <String, int>{};
    for (final muscle in muscles) {
      counts[muscle] = (counts[muscle] ?? 0) + 1;
    }
    String? best;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }
}
