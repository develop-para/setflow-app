import '../models.dart';

class NextExerciseRecommendation {
  const NextExerciseRecommendation({
    required this.template,
    required this.sets,
    required this.minReps,
    required this.maxReps,
    required this.restSeconds,
    required this.startingWeight,
    required this.goalLabel,
    required this.reason,
  });

  final ExerciseTemplate template;
  final int sets;
  final int minReps;
  final int maxReps;
  final int restSeconds;
  final double startingWeight;
  final String goalLabel;
  final String reason;
}

/// A conservative, deterministic exercise-order rule set. It uses the member's
/// selected goal and only recommends catalog exercises that are not already in
/// the current session.
abstract final class ExerciseRecommendationEngine {
  static NextExerciseRecommendation? recommendNext({
    required List<ExerciseTemplate> catalog,
    required WorkoutSession session,
    required WorkoutExercise completedExercise,
    required List<String> goals,
  }) {
    if (goals.isEmpty) return null;
    final existing = session.exercises
        .map((exercise) => exercise.template.id)
        .toSet();
    final focus = _focus(goals);
    final orderedIds = _candidateIds(
      focus: focus,
      completedId: completedExercise.template.id,
    );
    final templateById = {for (final item in catalog) item.id: item};
    ExerciseTemplate? candidate;
    for (final id in orderedIds) {
      final item = templateById[id];
      if (item != null && !existing.contains(item.id)) {
        candidate = item;
        break;
      }
    }
    if (candidate == null) {
      final preferredMuscles = _preferredMuscles(
        focus: focus,
        completedMuscle: completedExercise.template.muscle,
      );
      for (final muscle in preferredMuscles) {
        for (final item in catalog) {
          if (item.muscle == muscle &&
              item.muscle != '유산소' &&
              !existing.contains(item.id)) {
            candidate = item;
            break;
          }
        }
        if (candidate != null) break;
      }
    }
    if (candidate == null) {
      for (final item in catalog) {
        if (item.muscle != '유산소' && !existing.contains(item.id)) {
          candidate = item;
          break;
        }
      }
    }
    if (candidate == null) return null;

    final (sets, minReps, maxReps, restSeconds, reason) = switch (focus) {
      _GoalFocus.muscleGain => (
        3,
        8,
        12,
        90,
        '주요 동작 뒤에 관련 보조 동작을 배치해 근육군별 다중 세트 볼륨을 이어갑니다.',
      ),
      _GoalFocus.fatLoss => (
        3,
        10,
        15,
        60,
        '큰 근육군을 번갈아 사용해 전신 훈련 밀도를 유지하도록 구성했습니다.',
      ),
      _GoalFocus.fitness => (
        3,
        12,
        15,
        60,
        '서로 다른 큰 근육군을 이어 전신 근지구력과 기초 체력을 함께 훈련합니다.',
      ),
      _GoalFocus.health => (
        2,
        8,
        12,
        90,
        '전신의 밀기·당기기·하체 움직임이 한쪽으로 치우치지 않게 구성했습니다.',
      ),
    };
    return NextExerciseRecommendation(
      template: candidate,
      sets: sets,
      minReps: minReps,
      maxReps: maxReps,
      restSeconds: restSeconds,
      startingWeight: startingWeightFor(candidate),
      goalLabel: switch (focus) {
        _GoalFocus.muscleGain => '근육 증가',
        _GoalFocus.fatLoss => '체중 감량',
        _GoalFocus.fitness => '체력 향상',
        _GoalFocus.health => '건강 유지',
      },
      reason: reason,
    );
  }

  static _GoalFocus _focus(List<String> goals) {
    if (goals.contains('근육 증가')) return _GoalFocus.muscleGain;
    if (goals.contains('체중 감량')) return _GoalFocus.fatLoss;
    if (goals.contains('체력 향상')) return _GoalFocus.fitness;
    return _GoalFocus.health;
  }

  static List<String> _candidateIds({
    required _GoalFocus focus,
    required String completedId,
  }) {
    if (focus == _GoalFocus.muscleGain) {
      return [
        ...?_muscleGainChains[completedId],
        'squat',
        'bench',
        'latpull',
        'row',
        'ohp',
        'legpress',
        'incline',
        'lateral',
        'curl',
        'deadlift',
        'chest_press',
        'seated_cable_row',
        'dumbbell_shoulder_press',
        'romanian_deadlift',
        'cable_fly',
        'leg_extension',
        'leg_curl',
        'face_pull',
        'triceps_pushdown',
        'hammer_curl',
      ];
    }
    return switch (focus) {
      _GoalFocus.fatLoss => [
        'squat',
        'bench',
        'row',
        'deadlift',
        'legpress',
        'latpull',
        'ohp',
        'walking_lunge',
        'seated_cable_row',
        'dumbbell_bench',
      ],
      _GoalFocus.fitness => [
        'squat',
        'latpull',
        'bench',
        'row',
        'ohp',
        'legpress',
        'romanian_deadlift',
        'dumbbell_shoulder_press',
        'walking_lunge',
        'seated_cable_row',
        'plank',
      ],
      _GoalFocus.health => [
        'squat',
        'bench',
        'latpull',
        'ohp',
        'row',
        'legpress',
        'romanian_deadlift',
        'dumbbell_bench',
        'seated_cable_row',
        'plank',
        'bird_dog',
      ],
      _GoalFocus.muscleGain => const [],
    };
  }

  static const Map<String, List<String>> _muscleGainChains = {
    'bench': [
      'incline',
      'chest_press',
      'cable_fly',
      'pec_deck',
      'triceps_pushdown',
    ],
    'incline': [
      'chest_press',
      'cable_fly',
      'pec_deck',
      'lateral',
      'triceps_pushdown',
    ],
    'incline_barbell': ['chest_press', 'cable_fly', 'pec_deck', 'lateral'],
    'dumbbell_bench': ['incline', 'cable_fly', 'pec_deck', 'dips'],
    'chest_press': ['cable_fly', 'pec_deck', 'triceps_pushdown'],
    'cable_fly': ['pec_deck', 'triceps_pushdown', 'lateral'],
    'pec_deck': ['triceps_pushdown', 'lateral'],
    'squat': [
      'legpress',
      'romanian_deadlift',
      'leg_extension',
      'leg_curl',
      'calf_raise',
    ],
    'legpress': [
      'romanian_deadlift',
      'leg_extension',
      'leg_curl',
      'calf_raise',
    ],
    'deadlift': ['legpress', 'leg_curl', 'back_extension', 'calf_raise'],
    'romanian_deadlift': [
      'legpress',
      'leg_curl',
      'leg_extension',
      'calf_raise',
    ],
    'latpull': [
      'row',
      'seated_cable_row',
      'straight_arm_pulldown',
      'face_pull',
      'barbell_curl',
    ],
    'pullup': [
      'row',
      'seated_cable_row',
      'straight_arm_pulldown',
      'face_pull',
      'barbell_curl',
    ],
    'row': ['latpull', 'seated_cable_row', 'face_pull', 'barbell_curl'],
    'seated_cable_row': ['latpull', 'face_pull', 'barbell_curl'],
    'ohp': [
      'lateral',
      'rear_delt_raise',
      'reverse_pec_deck',
      'triceps_pushdown',
    ],
    'dumbbell_shoulder_press': [
      'lateral',
      'rear_delt_raise',
      'reverse_pec_deck',
      'triceps_pushdown',
    ],
    'lateral': ['rear_delt_raise', 'reverse_pec_deck', 'face_pull'],
    'curl': ['hammer_curl', 'preacher_curl', 'cable_curl'],
    'barbell_curl': ['hammer_curl', 'preacher_curl', 'cable_curl'],
    'triceps_pushdown': [
      'overhead_triceps_extension',
      'skull_crusher',
      'bench_dip',
    ],
    'plank': ['cable_crunch', 'hanging_leg_raise', 'dead_bug'],
  };

  static List<String> _preferredMuscles({
    required _GoalFocus focus,
    required String completedMuscle,
  }) {
    if (focus == _GoalFocus.muscleGain) {
      final related = switch (completedMuscle) {
        '가슴' => ['가슴', '팔', '어깨', '등', '하체', '복근'],
        '등' => ['등', '팔', '어깨', '가슴', '하체', '복근'],
        '하체' => ['하체', '복근', '등', '가슴', '어깨', '팔'],
        '어깨' => ['어깨', '팔', '등', '가슴', '하체', '복근'],
        '팔' => ['팔', '가슴', '등', '어깨', '하체', '복근'],
        _ => ['복근', '하체', '등', '가슴', '어깨', '팔'],
      };
      return related;
    }
    if (completedMuscle == '하체') {
      return ['등', '가슴', '어깨', '복근', '팔', '하체'];
    }
    if (completedMuscle == '등') {
      return ['하체', '가슴', '어깨', '복근', '팔', '등'];
    }
    return ['하체', '등', '복근', '가슴', '어깨', '팔'];
  }

  static double startingWeightFor(ExerciseTemplate template) {
    if (template.muscle == '유산소' || template.muscle == '복근') return 0;
    return switch (template.id) {
      'pushup' ||
      'dips' ||
      'pullup' ||
      'assisted_pullup' ||
      'bench_dip' ||
      'back_extension' ||
      'glute_bridge' => 0,
      'squat' ||
      'deadlift' ||
      'romanian_deadlift' ||
      'front_squat' ||
      'legpress' ||
      'hack_squat' ||
      'hip_thrust' => 40,
      'bench' ||
      'latpull' ||
      'row' ||
      'chest_press' ||
      'seated_cable_row' ||
      'tbar_row' ||
      'rack_pull' => 30,
      'incline' ||
      'incline_barbell' ||
      'dumbbell_bench' ||
      'decline_bench' ||
      'ohp' ||
      'dumbbell_shoulder_press' ||
      'arnold_press' ||
      'goblet_squat' ||
      'bulgarian_split_squat' ||
      'walking_lunge' => 20,
      'lateral' ||
      'cable_lateral_raise' ||
      'front_raise' ||
      'rear_delt_raise' ||
      'reverse_pec_deck' ||
      'curl' ||
      'barbell_curl' ||
      'hammer_curl' ||
      'preacher_curl' ||
      'cable_curl' ||
      'reverse_curl' => 8,
      _ => 15,
    };
  }
}

enum _GoalFocus { fatLoss, muscleGain, fitness, health }
