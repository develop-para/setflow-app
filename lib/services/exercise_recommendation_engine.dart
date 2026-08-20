import '../domain/cardio.dart';
import '../domain/exercise_recommendation_traits.dart';
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
    this.evidenceIds = const {},
    this.evidenceNote = '',
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
  final Set<String> evidenceIds;
  final String evidenceNote;
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
    Set<String> excludedTemplateIds = const {},
    RecommendationProfile? recommendationProfile,
  }) => _recommend(
    catalog: catalog,
    session: session,
    completedExercise: completedExercise,
    goals: goals,
    weeklyHistory: weeklyHistory,
    excludedTemplateIds: excludedTemplateIds,
    recommendationProfile: recommendationProfile,
  );

  static NextExerciseRecommendation? recommendFirst({
    required List<ExerciseTemplate> catalog,
    required WorkoutSession session,
    required List<String> goals,
    Iterable<WorkoutSession> weeklyHistory = const [],
    Set<String> excludedTemplateIds = const {},
    RecommendationProfile? recommendationProfile,
  }) => _recommend(
    catalog: catalog,
    session: session,
    goals: goals,
    weeklyHistory: weeklyHistory,
    excludedTemplateIds: excludedTemplateIds,
    recommendationProfile: recommendationProfile,
  );

  static NextExerciseRecommendation? _recommend({
    required List<ExerciseTemplate> catalog,
    required WorkoutSession session,
    required List<String> goals,
    required Iterable<WorkoutSession> weeklyHistory,
    required Set<String> excludedTemplateIds,
    required RecommendationProfile? recommendationProfile,
    WorkoutExercise? completedExercise,
  }) {
    if (goals.isEmpty) return null;
    if (recommendationProfile?.shouldPauseAutomaticRecommendation ?? false) {
      return null;
    }
    final existing = session.exercises
        .map((exercise) => exercise.template.id)
        .toSet();
    final trainingGoal = PerformanceEngine.goalFromProfile(goals);
    if (trainingGoal == null) return null;
    final focus = _focus(trainingGoal);
    final orderedIds = _candidateIds(
      focus: focus,
      completedId: completedExercise?.template.id ?? '',
    );
    final templateById = {for (final item in catalog) item.id: item};
    final candidates = <ExerciseTemplate>[];
    for (final id in orderedIds) {
      final item = templateById[id];
      if (item != null &&
          _isEligibleForProfile(item, recommendationProfile) &&
          !existing.contains(item.id) &&
          !excludedTemplateIds.contains(item.id) &&
          !candidates.any((candidate) => candidate.id == item.id)) {
        candidates.add(item);
      }
    }
    final preferredMuscles = _preferredMuscles(
      focus: focus,
      completedMuscle: completedExercise?.template.muscle ?? '',
    );
    for (final muscle in preferredMuscles) {
      for (final item in catalog) {
        if (item.muscle == muscle &&
            _isEligibleForProfile(item, recommendationProfile) &&
            !existing.contains(item.id) &&
            !excludedTemplateIds.contains(item.id) &&
            !candidates.any((candidate) => candidate.id == item.id)) {
          candidates.add(item);
        }
      }
    }
    for (final item in catalog) {
      if (_isEligibleForProfile(item, recommendationProfile) &&
          !existing.contains(item.id) &&
          !excludedTemplateIds.contains(item.id) &&
          !candidates.any((candidate) => candidate.id == item.id)) {
        candidates.add(item);
      }
    }
    if (focus == _GoalFocus.strength || focus == _GoalFocus.muscleGain) {
      candidates.removeWhere((item) => item.isCardio);
    }
    if (candidates.isEmpty) return null;

    final referenceDay = DateTime(
      session.date.year,
      session.date.month,
      session.date.day,
    );
    final historySource = weeklyHistory.isEmpty
        ? <WorkoutSession>[session]
        : weeklyHistory;
    final history = historySource
        .where((item) {
          final day = DateTime(item.date.year, item.date.month, item.date.day);
          return !day.isAfter(referenceDay);
        })
        .toList(growable: false);
    final weeklySets = _weeklyCompletedSetsByMuscle(history, session.date);
    final weeklyCardioMinutes = _weeklyCardioMinutes(history, session.date);
    final originalOrder = {
      for (var index = 0; index < candidates.length; index++)
        candidates[index].id: index,
    };
    if (focus == _GoalFocus.muscleGain) {
      final completedMuscle = completedExercise?.template.muscle;
      final completedMuscleSets = completedMuscle == null
          ? 0
          : weeklySets[completedMuscle] ?? 0;
      final sameMuscle = completedMuscle == null
          ? const <ExerciseTemplate>[]
          : candidates
                .where((candidate) => candidate.muscle == completedMuscle)
                .toList();
      if (completedMuscle != null &&
          completedMuscleSets < 10 &&
          sameMuscle.isNotEmpty) {
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
    final primaryCandidate = candidates.first;
    final candidate = _selectVariedCandidate(
      candidates: candidates,
      history: history,
      referenceDay: referenceDay,
      focus: focus,
      rotateTies: completedExercise == null,
    );

    final prescription = PerformanceEngine.prescriptionFor(trainingGoal);
    final recoveryIsCurrent =
        recommendationProfile?.hasRecoveryFor(referenceDay) ?? false;
    final recoveryIsLow =
        recoveryIsCurrent &&
        recommendationProfile?.recoveryStatus ==
            TrainingRecoveryStatus.fatigued;
    final baseCardioPrescription = candidate.isCardio
        ? CardioPrescriptionEngine.recommend(
            exerciseId: candidate.id,
            goal: trainingGoal,
            history: _cardioHistoryRecords(history),
            now: referenceDay,
            experience: _cardioExperience(
              recommendationProfile?.experienceLevel,
            ),
          )
        : null;
    final cardioPrescription = recoveryIsLow && baseCardioPrescription != null
        ? _reduceCardioForLowRecovery(baseCardioPrescription)
        : baseCardioPrescription;
    final historicalRecommendation = candidate.isCardio
        ? null
        : PerformanceEngine.recommend(
            sessions: history,
            template: candidate,
            goal: trainingGoal,
          );
    final weeklyMuscleSets = weeklySets[candidate.muscle] ?? 0;
    final remainingCardio = 150 - weeklyCardioMinutes;
    final baseReason = switch (focus) {
      _GoalFocus.strength =>
        completedExercise == null
            ? '근력 목표의 종목 우선순위와 주간 완료 기록을 기준으로 세션의 첫 운동을 제안합니다.'
            : '근력 목표의 종목 우선순위와 오늘 미완료 복합 동작을 기준으로 세션 앞쪽 운동을 제안합니다.',
      _GoalFocus.muscleGain =>
        '${candidate.muscle} 주동근 완료량 $weeklyMuscleSets세트와 주간 볼륨 연구를 참고한 규칙 제안입니다. 10세트는 개인의 절대 최소값이 아닙니다.',
      _GoalFocus.fatLoss =>
        candidate.isCardio
            ? '앱에 기록된 주간 중강도 환산 목표까지 약 ${remainingCardio.clamp(0, 150)}분 남아 유산소 활동을 제안합니다.'
            : '제지방 보존을 위한 저항운동과 주간 유산소 활동량을 함께 채우는 규칙 제안입니다.',
      _GoalFocus.fitness =>
        candidate.isCardio
            ? '앱에 기록된 주간 중강도 환산 목표까지 약 ${remainingCardio.clamp(0, 150)}분 남아 심폐 운동을 제안합니다.'
            : '심폐 체력과 전신 근지구력을 함께 구성하기 위한 규칙 제안입니다.',
      _GoalFocus.health => '밀기·당기기·하체·유산소 활동이 한쪽으로 치우치지 않게 하는 규칙 기반 제안입니다.',
    };
    final reason = candidate.id == primaryCandidate.id
        ? baseReason
        : '$baseReason 최근 4주의 반복을 줄이고 종목을 고르게 순환했습니다.';
    final personalizedReason = [
      reason,
      if (recommendationProfile != null) '입력한 장비·숙련도와 직접 지정한 제외 동작을 반영했습니다.',
      if (recoveryIsLow) '오늘 회복 상태가 낮아 운동량과 기록 기반 시작 중량을 보수적으로 낮췄습니다.',
    ].join(' ');
    final startingWeight = historicalRecommendation?.weight ?? 0;
    final evidenceIds = <String>{
      ...(cardioPrescription?.evidenceIds ??
          {...prescription.evidenceIds, 'nunes_2021_exercise_order'}),
      if (recoveryIsLow) 'craven_2022_sleep_loss',
    };
    return NextExerciseRecommendation(
      template: candidate,
      sets: recoveryIsLow && prescription.sets > 1
          ? prescription.sets - 1
          : prescription.sets,
      minReps: prescription.minReps,
      maxReps: prescription.maxReps,
      restSeconds: prescription.restSeconds,
      // A population-level paper cannot determine a safe kilogram value for
      // someone with no history on this exact exercise. Reuse only the
      // member's own eligible records; otherwise leave weight for direct input.
      startingWeight: recoveryIsLow
          ? _reducedStartingWeight(startingWeight)
          : startingWeight,
      goalLabel: trainingGoal.label,
      reason: personalizedReason,
      evidenceIds: evidenceIds,
      evidenceNote:
          cardioPrescription?.safetyNote ??
          '세트·반복·휴식과 운동 우선순위는 연구 원칙을 반영합니다. '
              '특정 종목, 장비, 숙련도, 제외 동작 필터는 설문과 기록을 조합한 앱 규칙이며 의학적 진단이 아닙니다.',
      cardioPrescription: cardioPrescription,
    );
  }

  static bool _isEligibleForProfile(
    ExerciseTemplate exercise,
    RecommendationProfile? profile,
  ) {
    if (profile == null) return true;
    return exerciseRecommendationTraits[exercise.id]?.isEligibleFor(profile) ??
        false;
  }

  static CardioExperience _cardioExperience(
    TrainingExperienceLevel? experience,
  ) => switch (experience) {
    TrainingExperienceLevel.intermediate => CardioExperience.regular,
    TrainingExperienceLevel.advanced => CardioExperience.advanced,
    TrainingExperienceLevel.beginner || null => CardioExperience.beginner,
  };

  static double _reducedStartingWeight(double weight) {
    if (weight <= 0) return 0;
    return (weight * .9 * 2).floorToDouble() / 2;
  }

  static CardioPrescription _reduceCardioForLowRecovery(
    CardioPrescription prescription,
  ) {
    final reducedSeconds = (prescription.sessionDuration.inSeconds * .75)
        .round();
    final safeSeconds = reducedSeconds < 600 ? 600 : reducedSeconds;
    final maximumRpe = prescription.maximumRpe > 5
        ? 5
        : prescription.maximumRpe;
    final minimumRpe = prescription.minimumRpe > maximumRpe
        ? maximumRpe
        : prescription.minimumRpe;
    return CardioPrescription(
      definition: prescription.definition,
      goal: prescription.goal,
      structure: CardioSessionStructure.continuous,
      sessionDuration: Duration(seconds: safeSeconds),
      intensity: CardioIntensity.moderate,
      minimumRpe: minimumRpe,
      maximumRpe: maximumRpe,
      weeklyTargetModerateEquivalentMinutes:
          prescription.weeklyTargetModerateEquivalentMinutes,
      completedModerateEquivalentMinutes:
          prescription.completedModerateEquivalentMinutes,
      metrics: prescription.metrics,
      evidenceIds: {...prescription.evidenceIds, 'craven_2022_sleep_loss'},
      reason: '${prescription.reason} 오늘 회복 설문을 반영해 지속시간과 강도를 낮췄습니다.',
      safetyNote:
          '${prescription.safetyNote} 회복 조정 폭은 연구 결과를 개인에게 그대로 대입한 값이 아니라 보수적인 앱 규칙입니다.',
      targetDistanceKm: prescription.targetDistanceKm == null
          ? null
          : prescription.targetDistanceKm! * .75,
      targetHeartRate: null,
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

  static ExerciseTemplate _selectVariedCandidate({
    required List<ExerciseTemplate> candidates,
    required List<WorkoutSession> history,
    required DateTime referenceDay,
    required _GoalFocus focus,
    required bool rotateTies,
  }) {
    final desiredPoolSize = switch (focus) {
      _GoalFocus.strength => 6,
      _GoalFocus.muscleGain => 8,
      _GoalFocus.fatLoss || _GoalFocus.fitness => 6,
      _GoalFocus.health => 7,
    };
    final poolSize = candidates.length < desiredPoolSize
        ? candidates.length
        : desiredPoolSize;
    final pool = candidates.take(poolSize).toList(growable: false);
    if (pool.length < 2) return pool.first;

    final recentStart = referenceDay.subtract(const Duration(days: 28));
    final usage = <String, _ExerciseUsage>{};
    for (final session in history) {
      final day = DateTime(
        session.date.year,
        session.date.month,
        session.date.day,
      );
      if (day.isAfter(referenceDay)) continue;
      final completedIds = <String>{};
      for (final exercise in session.exercises) {
        if (exercise.sets.any((set) => set.completed)) {
          completedIds.add(exercise.template.id);
        }
      }
      for (final id in completedIds) {
        final item = usage.putIfAbsent(id, _ExerciseUsage.new);
        if (!day.isBefore(recentStart)) item.recentSessionCount++;
        if (item.lastCompletedAt == null ||
            day.isAfter(item.lastCompletedAt!)) {
          item.lastCompletedAt = day;
        }
      }
    }

    // Keep one follow-up exposure for a known cardio modality so duration and
    // distance progression can use that member's own baseline. After the
    // second recent exposure, the normal novelty ranking rotates modalities.
    if (focus == _GoalFocus.fatLoss ||
        focus == _GoalFocus.fitness ||
        focus == _GoalFocus.health) {
      final familiarCardio =
          pool
              .where(
                (candidate) =>
                    candidate.isCardio &&
                    (usage[candidate.id]?.recentSessionCount ?? 0) == 1,
              )
              .toList(growable: false)
            ..sort((left, right) {
              final leftDate = usage[left.id]!.lastCompletedAt!;
              final rightDate = usage[right.id]!.lastCompletedAt!;
              return rightDate.compareTo(leftDate);
            });
      if (familiarCardio.isNotEmpty) return familiarCardio.first;
    }

    final dayNumber =
        DateTime.utc(
          referenceDay.year,
          referenceDay.month,
          referenceDay.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
    final rotationOffset = rotateTies ? dayNumber % pool.length : 0;
    int rotatedRank(ExerciseTemplate item) {
      final index = pool.indexWhere((candidate) => candidate.id == item.id);
      return (index - rotationOffset + pool.length) % pool.length;
    }

    final ranked = List<ExerciseTemplate>.of(pool)
      ..sort((left, right) {
        final leftUsage = usage[left.id] ?? _ExerciseUsage();
        final rightUsage = usage[right.id] ?? _ExerciseUsage();
        final byFrequency = leftUsage.recentSessionCount.compareTo(
          rightUsage.recentSessionCount,
        );
        if (byFrequency != 0) return byFrequency;
        final leftLast = leftUsage.lastCompletedAt;
        final rightLast = rightUsage.lastCompletedAt;
        if (leftLast == null && rightLast != null) return -1;
        if (leftLast != null && rightLast == null) return 1;
        if (leftLast != null && rightLast != null) {
          final byRecency = leftLast.compareTo(rightLast);
          if (byRecency != 0) return byRecency;
        }
        return rotatedRank(left).compareTo(rotatedRank(right));
      });
    return ranked.first;
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

class _ExerciseUsage {
  _ExerciseUsage({this.recentSessionCount = 0, this.lastCompletedAt});

  int recentSessionCount;
  DateTime? lastCompletedAt;
}
