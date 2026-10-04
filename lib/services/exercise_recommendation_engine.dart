import '../domain/cardio.dart';
import '../domain/exercise_recommendation_traits.dart';
import '../domain/exercise_substitutions.dart';
import '../domain/custom_exercise_recommendation_rules.dart';
import '../models.dart';
import '../domain/personal_coaching.dart';
import 'cardio_prescription_engine.dart';
import 'performance_engine.dart';
import 'resistance_prescription_engine.dart';
import 'workout_time_budget.dart';

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
    this.summary = '',
    this.historyCount = 0,
    this.trend = RecommendationTrend.insufficient,
    this.estimatedDurationSeconds = 0,
    this.personalCoachingReason = '',
    this.targetRepsBySet = const [],
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
  final String summary;
  final int historyCount;
  final RecommendationTrend trend;
  final int estimatedDurationSeconds;
  final String personalCoachingReason;
  final List<int> targetRepsBySet;
  int repsForSet(int index) =>
      index < targetRepsBySet.length ? targetRepsBySet[index] : minReps;
  String get targetRepsLabel => List.generate(sets, repsForSet).join(' / ');

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
    RecommendationPreferences preferences = const RecommendationPreferences(),
    ExerciseTemplate? alternativeTo,
    DateTime? now,
    PersonalCoachingPlan? coachingPlan,
  }) => _recommend(
    catalog: catalog,
    session: session,
    completedExercise: completedExercise,
    goals: goals,
    weeklyHistory: weeklyHistory,
    excludedTemplateIds: excludedTemplateIds,
    recommendationProfile: recommendationProfile,
    preferences: preferences,
    alternativeTo: alternativeTo,
    now: now,
    coachingPlan: coachingPlan,
  );

  static NextExerciseRecommendation? recommendFirst({
    required List<ExerciseTemplate> catalog,
    required WorkoutSession session,
    required List<String> goals,
    Iterable<WorkoutSession> weeklyHistory = const [],
    Set<String> excludedTemplateIds = const {},
    RecommendationProfile? recommendationProfile,
    RecommendationPreferences preferences = const RecommendationPreferences(),
    ExerciseTemplate? alternativeTo,
    DateTime? now,
    PersonalCoachingPlan? coachingPlan,
  }) => _recommend(
    catalog: catalog,
    session: session,
    goals: goals,
    weeklyHistory: weeklyHistory,
    excludedTemplateIds: excludedTemplateIds,
    recommendationProfile: recommendationProfile,
    preferences: preferences,
    alternativeTo: alternativeTo,
    now: now,
    coachingPlan: coachingPlan,
  );

  static NextExerciseRecommendation? _recommend({
    required List<ExerciseTemplate> catalog,
    required WorkoutSession session,
    required List<String> goals,
    required Iterable<WorkoutSession> weeklyHistory,
    required Set<String> excludedTemplateIds,
    required RecommendationProfile? recommendationProfile,
    required RecommendationPreferences preferences,
    required ExerciseTemplate? alternativeTo,
    required DateTime? now,
    WorkoutExercise? completedExercise,
    PersonalCoachingPlan? coachingPlan,
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
    candidates.removeWhere(
      (item) => !ResistancePrescriptionEngine.matchesFocus(
        item,
        session.trainingFocus,
      ),
    );
    candidates.removeWhere(
      (item) =>
          preferences.excludedExerciseIds.contains(item.id) ||
          session.skippedRecommendationIds.contains(item.id) ||
          (alternativeTo != null &&
              !ExerciseSubstitutions.matches(alternativeTo, item)),
    );
    {
      // 버튼에 명시한 주 장비를 오늘의 다음 추천에서도 제외한다.
      final blocked = [
        ?alternativeTo,
        ...catalog.where(
          (item) => session.unavailableEquipmentExerciseIds.contains(item.id),
        ),
      ];
      final blockedEquipment = blocked
          .map(ExerciseSubstitutions.unavailableEquipmentFor)
          .whereType<TrainingEquipment>()
          .toSet();
      candidates.removeWhere(
        (item) =>
            recommendationTraitsFor(
              item,
            )?.requiredEquipment.any(blockedEquipment.contains) ??
            false,
      );
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
    final weeklyVolume = ResistancePrescriptionEngine.volume(
      history: history,
      session: session,
      since: coachingPlan?.weekStart,
    );
    final todayVolume = ResistancePrescriptionEngine.volume(
      history: history,
      session: session,
      todayOnly: true,
    );
    candidates.removeWhere(
      (item) =>
          !item.isCardio &&
          ResistancePrescriptionEngine.remainingSets(
                template: item,
                goal: trainingGoal,
                weeklyVolume: weeklyVolume,
                todayVolume: todayVolume,
                profile: recommendationProfile,
                plannedSessionSets:
                    ResistancePrescriptionEngine.plannedSessionSets(session),
                coachingPlan: coachingPlan,
              ) ==
              0,
    );
    if (candidates.isEmpty) return null;
    final recoveryIsLow =
        recommendationProfile?.hasRecoveryFor(referenceDay) == true &&
        recommendationProfile?.recoveryStatus ==
            TrainingRecoveryStatus.fatigued;
    final resistanceById = <String, WorkoutRecommendation>{};
    final cardioById = <String, CardioPrescription?>{};
    final setsById = <String, int>{};
    WorkoutRecommendation resistanceFor(ExerciseTemplate item) =>
        resistanceById.putIfAbsent(
          item.id,
          () => ResistancePrescriptionEngine.prescribe(
            template: item,
            goal: trainingGoal,
            history: history,
            session: session,
            profile: recommendationProfile,
            coachingPlan: coachingPlan,
          ),
        );
    CardioPrescription? cardioFor(ExerciseTemplate item) =>
        cardioById.putIfAbsent(item.id, () {
          var cardio = CardioPrescriptionEngine.recommend(
            exerciseId: item.id,
            definitionExerciseId:
                CustomExerciseRecommendationRules.cardioDefinitionIdFor(item),
            goal: trainingGoal,
            history: _cardioHistoryRecords(history),
            now: referenceDay,
            experience: _cardioExperience(
              recommendationProfile?.experienceLevel,
            ),
          );
          if (cardio == null) return null;
          if (recoveryIsLow) cardio = _reduceCardioForLowRecovery(cardio);
          cardio = _fitCardioToTime(cardio, session, now);
          return cardio;
        });
    if (session.timeBudgetMinutes != null) {
      for (final item in candidates.where((item) => !item.isCardio)) {
        final prescription = resistanceFor(item);
        setsById[item.id] = WorkoutTimeBudget.fittingSets(
          session: session,
          template: item,
          sets: prescription.sets,
          reps: prescription.minReps,
          targetRepsBySet: prescription.targetRepsBySet,
          restSeconds: prescription.restSeconds,
          now: now,
        );
      }
    }
    candidates.removeWhere(
      (item) => item.isCardio
          ? (session.timeBudgetMinutes == null
                ? CustomExerciseRecommendationRules.cardioDefinitionIdFor(
                        item,
                      ) ==
                      null
                : cardioFor(item) == null)
          : session.timeBudgetMinutes != null && (setsById[item.id] ?? 0) == 0,
    );
    if (candidates.isEmpty) return null;
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
    final candidate = primaryCandidate.isCardio
        ? _selectVariedCandidate(
            candidates: candidates,
            history: history,
            referenceDay: referenceDay,
            focus: focus,
            rotateTies: completedExercise == null,
            preferences: preferences,
          )
        : _selectResistanceCandidate(
            candidates: candidates.where((item) => !item.isCardio).toList(),
            history: history,
            session: session,
            completedExercise: completedExercise,
            weeklyVolume: weeklyVolume,
            preferences: preferences,
          );

    final prescription = PerformanceEngine.prescriptionFor(trainingGoal);
    final cardioPrescription = candidate.isCardio ? cardioFor(candidate) : null;
    final historicalRecommendation = candidate.isCardio
        ? null
        : resistanceFor(candidate);
    final recommendedSets =
        setsById[candidate.id] ??
        historicalRecommendation?.sets ??
        prescription.sets;
    final preferredCount = preferences.preferenceFor(
      candidate.id,
      referenceDay,
    );
    final timeReason = session.timeBudgetMinutes == null
        ? ''
        : '오늘 ${session.timeBudgetMinutes}분 안에 준비·종목 전환·세트·휴식을 포함하도록 ${candidate.isCardio ? '${cardioPrescription!.durationMinutes}분' : '$recommendedSets세트'}를 제안합니다. 소요시간은 추정치입니다.';
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
    final reason = candidate.isCardio
        ? baseReason
        : historicalRecommendation!.reason;
    final personalizedReason = [
      reason,
      if (session.trainingFocus?.isNotEmpty ?? false)
        '오늘 선택한 ${session.trainingFocus!.map((item) => item.label).join(' · ')} 안에서 추천합니다.',
      if (recommendationProfile != null) '입력한 장비·숙련도와 직접 지정한 제외 동작을 반영했습니다.',
      if (recoveryIsLow) '오늘 회복 상태가 낮아 운동량과 기록 기반 시작 중량을 보수적으로 낮췄습니다.',
      if (alternativeTo != null)
        '${alternativeTo.name}과 같은 동작의 대안입니다. 중량은 이 종목 자체의 기록만 사용합니다.',
      if (preferredCount >= 2) '최근 90일 중 $preferredCount일 직접 선택한 운동을 우선했습니다.',
      if (timeReason.isNotEmpty) timeReason,
      if (candidate.customRecommendation != null)
        '직접 작성한 종목 정보로 추천에 포함했습니다. 첫 중량은 같은 종목의 기록만 사용합니다.',
    ].join(' ');
    final startingWeight = historicalRecommendation?.weight ?? 0;
    final evidenceIds = <String>{
      ...(cardioPrescription?.evidenceIds ??
          {
            ...historicalRecommendation!.evidenceIds,
            'nunes_2021_exercise_order',
            'ramos_2024_split_full_body',
          }),
      if (recoveryIsLow) 'craven_2022_sleep_loss',
    };
    return NextExerciseRecommendation(
      personalCoachingReason: candidate.isCardio
          ? ''
          : coachingPlan?.reasonFor(
                  ResistancePrescriptionEngine.primaryMuscles(candidate),
                ) ??
                '',
      template: candidate,
      sets: recommendedSets,
      minReps: historicalRecommendation?.minReps ?? prescription.minReps,
      targetRepsBySet:
          historicalRecommendation?.targetRepsBySet
              .take(recommendedSets)
              .toList() ??
          const [],
      maxReps: historicalRecommendation?.maxReps ?? prescription.maxReps,
      restSeconds:
          historicalRecommendation?.restSeconds ?? prescription.restSeconds,
      // A population-level paper cannot determine a safe kilogram value for
      // someone with no history on this exact exercise. Reuse only the
      // member's own eligible records; otherwise leave weight for direct input.
      startingWeight: startingWeight,
      goalLabel: trainingGoal.label,
      reason: personalizedReason,
      summary: [
        if (alternativeTo != null) '${alternativeTo.name} 대신 같은 동작을 이어갑니다.',
        if (preferredCount >= 2) '여러 날 직접 선택한 운동입니다.',
        historicalRecommendation?.summary ?? cardioPrescription!.reason,
        if (historicalRecommendation != null &&
            recommendedSets < historicalRecommendation.sets)
          '남은 시간에 맞춰 $recommendedSets세트로 줄여 제안합니다.',
      ].join(' '),
      historyCount:
          historicalRecommendation?.historyCount ??
          history
              .where(
                (session) =>
                    session.date.isBefore(referenceDay) &&
                    session.exercises.any(
                      (exercise) =>
                          exercise.template.id == candidate.id &&
                          !exercise.id.startsWith('seed_') &&
                          exercise.sets.any(
                            (set) => set.completed && set.durationSeconds > 0,
                          ),
                    ),
              )
              .map((session) => ResistancePrescriptionEngine.day(session.date))
              .toSet()
              .length,
      trend:
          historicalRecommendation?.trend ?? RecommendationTrend.insufficient,
      estimatedDurationSeconds: candidate.isCardio
          ? cardioPrescription!.durationSeconds +
                WorkoutTimeBudget.transitionSeconds +
                WorkoutTimeBudget.previousRestSeconds(session)
          : WorkoutTimeBudget.addedSeconds(
              session: session,
              template: candidate,
              sets: recommendedSets,
              reps: historicalRecommendation!.minReps,
              targetRepsBySet: historicalRecommendation.targetRepsBySet,
              restSeconds: historicalRecommendation.restSeconds,
            ),
      evidenceIds: evidenceIds,
      evidenceNote:
          cardioPrescription?.safetyNote ??
          historicalRecommendation!.evidenceNote,
      cardioPrescription: cardioPrescription,
    );
  }

  static bool _isEligibleForProfile(
    ExerciseTemplate exercise,
    RecommendationProfile? profile,
  ) {
    final traits = recommendationTraitsFor(exercise);
    if (traits == null) return false;
    if (profile == null) {
      return !exercise.id.startsWith('custom_') ||
          traits.minimumExperience == TrainingExperienceLevel.beginner;
    }
    return traits.isEligibleFor(profile);
  }

  static CardioPrescription? _fitCardioToTime(
    CardioPrescription prescription,
    WorkoutSession session,
    DateTime? now,
  ) {
    if (session.timeBudgetMinutes == null) return prescription;
    final seconds =
        WorkoutTimeBudget.availableSeconds(session, now: now) -
        WorkoutTimeBudget.transitionSeconds -
        WorkoutTimeBudget.previousRestSeconds(session);
    if (seconds >= prescription.durationSeconds) return prescription;
    // 인터벌 구조는 잘라내지 않는다. 지속 운동만 분 단위로 줄인다.
    if (seconds < 300 ||
        prescription.structure != CardioSessionStructure.continuous) {
      return null;
    }
    final duration = seconds ~/ 60 * 60;
    return CardioPrescription(
      definition: prescription.definition,
      goal: prescription.goal,
      structure: prescription.structure,
      sessionDuration: Duration(seconds: duration),
      intensity: prescription.intensity,
      minimumRpe: prescription.minimumRpe,
      maximumRpe: prescription.maximumRpe,
      weeklyTargetModerateEquivalentMinutes:
          prescription.weeklyTargetModerateEquivalentMinutes,
      completedModerateEquivalentMinutes:
          prescription.completedModerateEquivalentMinutes,
      metrics: prescription.metrics,
      evidenceIds: prescription.evidenceIds,
      reason: '${prescription.reason} 남은 시간에 맞춰 ${duration ~/ 60}분을 제안합니다.',
      safetyNote: prescription.safetyNote,
      targetHeartRate: prescription.targetHeartRate,
      targetDistanceKm: prescription.targetDistanceKm == null
          ? null
          : prescription.targetDistanceKm! *
                duration /
                prescription.durationSeconds,
    );
  }

  static CardioExperience _cardioExperience(
    TrainingExperienceLevel? experience,
  ) => switch (experience) {
    TrainingExperienceLevel.intermediate => CardioExperience.regular,
    TrainingExperienceLevel.advanced => CardioExperience.advanced,
    TrainingExperienceLevel.beginner || null => CardioExperience.beginner,
  };

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

  static ExerciseTemplate _selectResistanceCandidate({
    required List<ExerciseTemplate> candidates,
    required List<WorkoutSession> history,
    required WorkoutSession session,
    required WorkoutExercise? completedExercise,
    required Map<TrainingMuscle, double> weeklyVolume,
    required RecommendationPreferences preferences,
  }) {
    final order = {
      for (var i = 0; i < candidates.length; i++) candidates[i].id: i,
    };
    final recentStart = DateTime(
      session.date.year,
      session.date.month,
      session.date.day - 28,
    );
    final familiar = history
        .where(
          (item) =>
              !item.date.isBefore(recentStart) &&
              item.date.isBefore(
                ResistancePrescriptionEngine.day(session.date),
              ),
        )
        .expand((item) => item.exercises)
        .where(
          (item) =>
              !item.id.startsWith('seed_') &&
              item.sets.any((set) => set.completed && set.type == '일반'),
        )
        .map((item) => item.template.id)
        .toSet();
    final completedMuscles = completedExercise == null
        ? <TrainingMuscle>{}
        : ResistancePrescriptionEngine.primaryMuscles(
            completedExercise.template,
          );
    bool continuesMuscle(ExerciseTemplate item) =>
        ResistancePrescriptionEngine.primaryMuscles(
          item,
        ).any(completedMuscles.contains);
    double volumeFor(ExerciseTemplate item) =>
        ResistancePrescriptionEngine.primaryMuscles(
          item,
        ).fold<double>(0, (sum, muscle) => sum + (weeklyVolume[muscle] ?? 0));
    int movementPriority(ExerciseTemplate item) {
      final priorCompounds = session.exercises
          .where(
            (exercise) =>
                ResistancePrescriptionEngine.categoryFor(exercise.template) ==
                    ResistancePrescriptionEngine.categoryFor(item) &&
                ResistancePrescriptionEngine.isCompound(exercise.template),
          )
          .length;
      final preferCompound = priorCompounds < 2;
      return ResistancePrescriptionEngine.isCompound(item) == preferCompound
          ? 0
          : 1;
    }

    candidates.sort((left, right) {
      // 부위와 동작 우선순위가 먼저다. 날짜별 임의 순환은 기록의 연속성을 끊는다.
      if (continuesMuscle(left) != continuesMuscle(right)) {
        return continuesMuscle(left) ? -1 : 1;
      }
      final byMovement = movementPriority(
        left,
      ).compareTo(movementPriority(right));
      if (byMovement != 0) return byMovement;
      if (ResistancePrescriptionEngine.categoryFor(left) !=
          ResistancePrescriptionEngine.categoryFor(right)) {
        final byVolume = volumeFor(left).compareTo(volumeFor(right));
        if (byVolume != 0) return byVolume;
      }
      final leftPreference = preferences.preferenceFor(left.id, session.date);
      final rightPreference = preferences.preferenceFor(right.id, session.date);
      final byPreference = (rightPreference >= 2 ? rightPreference : 0)
          .compareTo(leftPreference >= 2 ? leftPreference : 0);
      if (byPreference != 0) return byPreference;
      if (familiar.contains(left.id) != familiar.contains(right.id)) {
        return familiar.contains(left.id) ? -1 : 1;
      }
      return order[left.id]!.compareTo(order[right.id]!);
    });
    return candidates.first;
  }

  static ExerciseTemplate _selectVariedCandidate({
    required List<ExerciseTemplate> candidates,
    required List<WorkoutSession> history,
    required DateTime referenceDay,
    required _GoalFocus focus,
    required bool rotateTies,
    required RecommendationPreferences preferences,
  }) {
    final preferred =
        candidates
            .where(
              (item) =>
                  item.isCardio &&
                  preferences.preferenceFor(item.id, referenceDay) >= 2,
            )
            .toList()
          ..sort(
            (a, b) => preferences
                .preferenceFor(b.id, referenceDay)
                .compareTo(preferences.preferenceFor(a.id, referenceDay)),
          );
    if (preferred.isNotEmpty) return preferred.first;
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
            CustomExerciseRecommendationRules.cardioDefinitionIdFor(
                  exercise.template,
                ) ==
                null) {
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
          definitionExerciseId: exercise.template.id.startsWith('custom_')
              ? CustomExerciseRecommendationRules.cardioDefinitionIdFor(
                  exercise.template,
                )
              : null,
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
