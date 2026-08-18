import '../domain/cardio.dart';
import '../models.dart';
import 'cardio_prescription_engine.dart';
import 'performance_engine.dart';

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
    this.cardioPrescription,
  });

  final ExerciseTemplate template;
  final int sets;
  final int minReps;
  final int maxReps;
  final int restSeconds;
  final double startingWeight;
  final String goalLabel;
  final String reason;
  final CardioPrescription? cardioPrescription;

  bool get isCardio => cardioPrescription != null || template.isCardio;
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
    Iterable<WorkoutSession> weeklyHistory = const [],
  }) {
    if (goals.isEmpty) return null;
    final existing = session.exercises
        .map((exercise) => exercise.template.id)
        .toSet();
    final trainingGoal = PerformanceEngine.goalFromProfile(goals);
    if (trainingGoal == null) return null;
    final focus = _focus(trainingGoal);
    final orderedIds = _candidateIds(
      focus: focus,
      completedId: completedExercise.template.id,
    );
    final templateById = {for (final item in catalog) item.id: item};
    final candidates = <ExerciseTemplate>[];
    for (final id in orderedIds) {
      final item = templateById[id];
      if (item != null &&
          !existing.contains(item.id) &&
          !candidates.any((candidate) => candidate.id == item.id)) {
        candidates.add(item);
      }
    }
    final preferredMuscles = _preferredMuscles(
      focus: focus,
      completedMuscle: completedExercise.template.muscle,
    );
    for (final muscle in preferredMuscles) {
      for (final item in catalog) {
        if (item.muscle == muscle &&
            !existing.contains(item.id) &&
            !candidates.any((candidate) => candidate.id == item.id)) {
          candidates.add(item);
        }
      }
    }
    for (final item in catalog) {
      if (!existing.contains(item.id) &&
          !candidates.any((candidate) => candidate.id == item.id)) {
        candidates.add(item);
      }
    }
    if (focus == _GoalFocus.strength || focus == _GoalFocus.muscleGain) {
      candidates.removeWhere((item) => item.isCardio);
    }
    if (candidates.isEmpty) return null;

    final history = weeklyHistory.isEmpty
        ? <WorkoutSession>[session]
        : weeklyHistory;
    final weeklySets = _weeklyCompletedSetsByMuscle(history, session.date);
    final weeklyCardioMinutes = _weeklyCardioMinutes(history, session.date);
    final originalOrder = {
      for (var index = 0; index < candidates.length; index++)
        candidates[index].id: index,
    };
    if (focus == _GoalFocus.muscleGain) {
      final completedMuscle = completedExercise.template.muscle;
      final completedMuscleSets = weeklySets[completedMuscle] ?? 0;
      final sameMuscle = candidates
          .where((candidate) => candidate.muscle == completedMuscle)
          .toList();
      if (completedMuscleSets < 10 && sameMuscle.isNotEmpty) {
        candidates
          ..removeWhere((candidate) => candidate.muscle == completedMuscle)
          ..insertAll(0, sameMuscle);
      } else {
        candidates.sort((left, right) {
          final byVolume = (weeklySets[left.muscle] ?? 0).compareTo(
            weeklySets[right.muscle] ?? 0,
          );
          if (byVolume != 0) return byVolume;
          return originalOrder[left.id]!.compareTo(originalOrder[right.id]!);
        });
      }
    } else if (weeklyCardioMinutes >= 150) {
      candidates.sort((left, right) {
        if (left.isCardio == right.isCardio) {
          return originalOrder[left.id]!.compareTo(originalOrder[right.id]!);
        }
        return left.isCardio ? 1 : -1;
      });
    }
    final candidate = candidates.first;

    final prescription = PerformanceEngine.prescriptionFor(trainingGoal);
    final cardioPrescription = candidate.isCardio
        ? CardioPrescriptionEngine.recommend(
            exerciseId: candidate.id,
            goal: trainingGoal,
            history: _cardioHistoryRecords(weeklyHistory),
          )
        : null;
    final weeklyMuscleSets = weeklySets[candidate.muscle] ?? 0;
    final remainingCardio = 150 - weeklyCardioMinutes;
    final reason = switch (focus) {
      _GoalFocus.strength => '사용자 우선순위와 오늘 미완료 복합 동작을 기준으로 세션 앞쪽 운동을 제안합니다.',
      _GoalFocus.muscleGain =>
        '${candidate.muscle} 주동근 완료량 $weeklyMuscleSets세트를 기준으로 부족한 주간 볼륨을 보완하는 규칙 제안입니다.',
      _GoalFocus.fatLoss =>
        candidate.isCardio
            ? '주간 중강도 환산 목표까지 약 ${remainingCardio.clamp(0, 150)}분 남아 유산소 활동을 제안합니다.'
            : '제지방 보존을 위한 저항운동과 주간 유산소 활동량을 함께 채우는 규칙 제안입니다.',
      _GoalFocus.fitness =>
        candidate.isCardio
            ? '주간 중강도 환산 목표까지 약 ${remainingCardio.clamp(0, 150)}분 남아 심폐 운동을 제안합니다.'
            : '심폐 체력과 전신 근지구력을 함께 구성하기 위한 규칙 제안입니다.',
      _GoalFocus.health => '밀기·당기기·하체·유산소 활동이 한쪽으로 치우치지 않게 하는 규칙 기반 제안입니다.',
    };
    return NextExerciseRecommendation(
      template: candidate,
      sets: prescription.sets,
      minReps: prescription.minReps,
      maxReps: prescription.maxReps,
      restSeconds: prescription.restSeconds,
      startingWeight: startingWeightFor(candidate),
      goalLabel: trainingGoal.label,
      reason: reason,
      cardioPrescription: cardioPrescription,
    );
  }

  static _GoalFocus _focus(TrainingGoal goal) => switch (goal) {
    TrainingGoal.strength => _GoalFocus.strength,
    TrainingGoal.hypertrophy => _GoalFocus.muscleGain,
    TrainingGoal.fatLoss => _GoalFocus.fatLoss,
    TrainingGoal.endurance => _GoalFocus.fitness,
    TrainingGoal.health => _GoalFocus.health,
  };

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
      _GoalFocus.strength => [
        'squat',
        'bench',
        'deadlift',
        'ohp',
        'row',
        'latpull',
        'front_squat',
        'rack_pull',
        'incline_barbell',
        'tbar_row',
      ],
      _GoalFocus.fatLoss => [
        'brisk_walk',
        'stationary_bike',
        'elliptical',
        'rowing_machine',
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
        'run',
        'rowing_machine',
        'stationary_bike',
        'elliptical',
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
        'brisk_walk',
        'stationary_bike',
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
    final cardioFirst = switch (focus) {
      _GoalFocus.fatLoss || _GoalFocus.fitness || _GoalFocus.health => ['유산소'],
      _ => const <String>[],
    };
    if (completedMuscle == '하체') {
      return [...cardioFirst, '등', '가슴', '어깨', '복근', '팔', '하체'];
    }
    if (completedMuscle == '등') {
      return [...cardioFirst, '하체', '가슴', '어깨', '복근', '팔', '등'];
    }
    return [...cardioFirst, '하체', '등', '복근', '가슴', '어깨', '팔'];
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

  static Map<String, int> _weeklyCompletedSetsByMuscle(
    Iterable<WorkoutSession> sessions,
    DateTime reference,
  ) {
    final day = DateTime(reference.year, reference.month, reference.day);
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 7));
    final result = <String, int>{};
    for (final session in sessions) {
      if (session.date.isBefore(start) || !session.date.isBefore(end)) continue;
      for (final exercise in session.exercises) {
        if (exercise.template.isCardio) continue;
        final completed = exercise.sets
            .where((set) => set.completed && set.type != '웜업')
            .length;
        if (completed > 0) {
          result[exercise.template.muscle] =
              (result[exercise.template.muscle] ?? 0) + completed;
        }
      }
    }
    return result;
  }

  static int _weeklyCardioMinutes(
    Iterable<WorkoutSession> sessions,
    DateTime reference,
  ) {
    final day = DateTime(reference.year, reference.month, reference.day);
    final start = day.subtract(Duration(days: day.weekday - 1));
    final end = start.add(const Duration(days: 7));
    var seconds = 0;
    for (final session in sessions) {
      if (session.date.isBefore(start) || !session.date.isBefore(end)) continue;
      for (final exercise in session.exercises) {
        if (!exercise.template.isCardio) continue;
        for (final set in exercise.sets) {
          if (!set.completed ||
              set.durationSeconds <= 0 ||
              set.intensityRpe < 3) {
            continue;
          }
          final multiplier = set.intensityRpe >= 7 ? 2 : 1;
          seconds += set.durationSeconds * multiplier;
        }
      }
    }
    return seconds ~/ 60;
  }

  static Iterable<CardioSessionRecord> _cardioHistoryRecords(
    Iterable<WorkoutSession> sessions,
  ) sync* {
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        if (!exercise.template.isCardio ||
            cardioDefinitionForExercise(exercise.template.id) == null) {
          continue;
        }
        final completed = exercise.sets
            .where(
              (set) =>
                  set.completed &&
                  set.durationSeconds > 0 &&
                  set.intensityRpe >= 3,
            )
            .toList();
        if (completed.isEmpty) continue;
        final durationSeconds = completed.fold<int>(
          0,
          (sum, set) => sum + set.durationSeconds,
        );
        final distances = completed
            .map((set) => set.distanceKm)
            .where((distance) => distance > 0)
            .toList();
        final averageRpe =
            completed.fold<double>(0, (sum, set) => sum + set.intensityRpe) /
            completed.length;
        yield CardioSessionRecord(
          id: exercise.id,
          exerciseId: exercise.template.id,
          occurredAt: session.date,
          duration: Duration(seconds: durationSeconds),
          intensity: averageRpe >= 7
              ? CardioIntensity.vigorous
              : CardioIntensity.moderate,
          distanceKm: distances.isEmpty
              ? null
              : distances.reduce((left, right) => left + right),
          perceivedExertion: averageRpe,
        );
      }
    }
  }
}

enum _GoalFocus { strength, fatLoss, muscleGain, fitness, health }
