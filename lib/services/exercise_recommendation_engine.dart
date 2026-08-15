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
      startingWeight: _startingWeight(candidate.id),
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
      final paired = switch (completedId) {
        'bench' => 'incline',
        'incline' => 'ohp',
        'squat' => 'legpress',
        'legpress' => 'squat',
        'latpull' => 'row',
        'row' => 'curl',
        'ohp' => 'lateral',
        'lateral' => 'ohp',
        _ => null,
      };
      return [
        ?paired,
        'squat',
        'bench',
        'latpull',
        'row',
        'ohp',
        'legpress',
        'incline',
        'lateral',
        'curl',
      ];
    }
    return switch (focus) {
      _GoalFocus.fatLoss => [
        'squat',
        'bench',
        'row',
        'legpress',
        'latpull',
        'ohp',
      ],
      _GoalFocus.fitness => [
        'squat',
        'latpull',
        'bench',
        'row',
        'ohp',
        'legpress',
      ],
      _GoalFocus.health => [
        'squat',
        'bench',
        'latpull',
        'ohp',
        'row',
        'legpress',
      ],
      _GoalFocus.muscleGain => const [],
    };
  }

  static double _startingWeight(String id) => switch (id) {
    'squat' || 'legpress' => 40,
    'bench' || 'latpull' || 'row' => 30,
    'incline' || 'ohp' => 20,
    'lateral' || 'curl' => 8,
    _ => 20,
  };
}

enum _GoalFocus { fatLoss, muscleGain, fitness, health }
