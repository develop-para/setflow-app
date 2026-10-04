import 'dart:math' as math;

import '../models.dart';
import '../domain/personal_coaching.dart';
import '../domain/custom_exercise_recommendation_rules.dart';
import 'performance_engine.dart';

/// 연구 원칙을 기록에 적용하는 제품 규칙. 정확한 세트 상한·증감 폭은
/// 개인에게 검증된 최적값이 아니다. 근거와 결정표: docs/workout-recommendations.md.
abstract final class ResistancePrescriptionEngine {
  static const compoundIds = {
    'bench',
    'incline',
    'incline_barbell',
    'dumbbell_bench',
    'decline_bench',
    'chest_press',
    'pushup',
    'dips',
    'squat',
    'front_squat',
    'legpress',
    'bodyweight_squat',
    'walking_lunge',
    'bulgarian_split_squat',
    'goblet_squat',
    'deadlift',
    'romanian_deadlift',
    'hip_thrust',
    'rack_pull',
    'latpull',
    'pullup',
    'assisted_pullup',
    'row',
    'seated_cable_row',
    'tbar_row',
    'one_arm_dumbbell_row',
    'chest_supported_row',
    'hack_squat',
    'close_grip_bench',
    'bench_dip',
    'ohp',
    'dumbbell_shoulder_press',
    'arnold_press',
  };
  static const _bicepsIds = {
    'curl',
    'barbell_curl',
    'hammer_curl',
    'preacher_curl',
    'cable_curl',
  };
  static const _tricepsIds = {
    'triceps_pushdown',
    'overhead_triceps_extension',
    'skull_crusher',
    'bench_dip',
    'close_grip_bench',
  };

  static Set<TrainingMuscle> primaryMuscles(ExerciseTemplate template) {
    if (template.isCardio) return const {};
    final primary = CustomExerciseRecommendationRules.infoFor(
      template,
    )?.primaryMuscle;
    if (primary != null) return {primary};
    // 팔만 세분화한다. 등의 척추기립근과 하체의 둔근 등을 이중 집계하지 않는다.
    return switch (template.muscle) {
      '가슴' => {TrainingMuscle.chest},
      '등' => {TrainingMuscle.back},
      '하체' => {TrainingMuscle.legs},
      '어깨' => {TrainingMuscle.shoulders},
      '복근' => {TrainingMuscle.core},
      '팔' => {
        if (_bicepsIds.contains(template.id) ||
            template.primaryMuscles.contains('biceps'))
          TrainingMuscle.biceps,
        if (_tricepsIds.contains(template.id) ||
            template.primaryMuscles.contains('triceps'))
          TrainingMuscle.triceps,
      },
      _ => const {},
    };
  }

  static Set<TrainingMuscle> secondaryMuscles(ExerciseTemplate template) {
    final custom = CustomExerciseRecommendationRules.infoFor(template);
    if (custom != null) return custom.secondaryMuscles;
    if (!compoundIds.contains(template.id)) return const {};
    return switch (template.muscle) {
      '가슴' => {TrainingMuscle.shoulders, TrainingMuscle.triceps},
      '등' when !{'deadlift', 'rack_pull'}.contains(template.id) => {
        TrainingMuscle.biceps,
      },
      '어깨' => {TrainingMuscle.triceps},
      _ => const {},
    };
  }

  static bool isCompound(ExerciseTemplate template) =>
      CustomExerciseRecommendationRules.infoFor(
        template,
      )?.movement?.isCompound ??
      compoundIds.contains(template.id);

  static String categoryFor(ExerciseTemplate template) =>
      CustomExerciseRecommendationRules.infoFor(
        template,
      )?.primaryMuscle?.exerciseCategory ??
      template.muscle;

  static bool matchesFocus(
    ExerciseTemplate template,
    Set<TrainingMuscle>? focus,
  ) =>
      focus == null ||
      focus.isEmpty ||
      primaryMuscles(template).any(focus.contains);

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// 오늘 계획도 예약량으로 센다. 과거는 완료한 세트만, 미래·웜업·예시 기록 제외.
  /// 같은 날짜의 history 사본 대신 현재 세션을 한 번만 사용한다.
  static Map<TrainingMuscle, double> volume({
    required Iterable<WorkoutSession> history,
    required WorkoutSession session,
    bool todayOnly = false,
    DateTime? since,
  }) {
    final reference = day(session.date);
    final start =
        since ?? DateTime(reference.year, reference.month, reference.day - 6);
    final result = <TrainingMuscle, double>{};
    for (final item in [
      if (!todayOnly)
        ...history.where(
          (item) =>
              day(item.date).isBefore(reference) &&
              !day(item.date).isBefore(start),
        ),
      session,
    ]) {
      final isToday = day(item.date) == reference;
      for (final exercise in item.exercises) {
        if (exercise.id.startsWith('seed_') || exercise.template.isCardio) {
          continue;
        }
        final count = exercise.sets
            .where(
              (set) =>
                  set.type != '웜업' &&
                  (isToday || set.completed) &&
                  (exercise.template.isDurationHold
                      ? set.durationSeconds > 0
                      : set.reps > 0),
            )
            .length;
        for (final muscle in primaryMuscles(exercise.template)) {
          result[muscle] = (result[muscle] ?? 0) + count;
        }
        for (final muscle in secondaryMuscles(exercise.template)) {
          result[muscle] = (result[muscle] ?? 0) + count * .5;
        }
      }
    }
    return result;
  }

  static int remainingSets({
    required ExerciseTemplate template,
    required TrainingGoal goal,
    required Map<TrainingMuscle, double> weeklyVolume,
    required Map<TrainingMuscle, double> todayVolume,
    RecommendationProfile? profile,
    int plannedSessionSets = 0,
    PersonalCoachingPlan? coachingPlan,
  }) {
    final beginner =
        profile?.experienceLevel == TrainingExperienceLevel.beginner;
    final advanced =
        profile?.experienceLevel == TrainingExperienceLevel.advanced;
    // 자동 추천의 보수적인 예산. 수동 세트 추가를 막는 한계값은 아니다.
    final weeklyBudget = goal == TrainingGoal.hypertrophy
        ? (beginner
              ? 8
              : advanced
              ? 16
              : 12)
        : (beginner ? 6 : 10);
    final dailyBudget = beginner
        ? 4
        : advanced
        ? 8
        : 6;
    final sessionBudget = beginner
        ? 12
        : advanced
        ? 24
        : 18;
    var remaining = math.min(
      coachingPlan == null ? dailyBudget : 10,
      sessionBudget - plannedSessionSets,
    );
    for (final muscle in primaryMuscles(template)) {
      remaining = math.min(
        remaining,
        ((coachingPlan?.weeklyBudget(muscle, weeklyBudget) ?? weeklyBudget) -
                (weeklyVolume[muscle] ?? 0))
            .floor(),
      );
      remaining = math.min(
        remaining,
        ((coachingPlan?.dailyBudget(muscle, dailyBudget) ?? dailyBudget) -
                (todayVolume[muscle] ?? 0))
            .floor(),
      );
    }
    return math.max(0, remaining);
  }

  static int plannedSessionSets(WorkoutSession session) => session.exercises
      .where(
        (exercise) =>
            !exercise.template.isCardio && !exercise.id.startsWith('seed_'),
      )
      .expand((exercise) => exercise.sets)
      .where((set) => set.type != '웜업')
      .length;

  static WorkoutRecommendation prescribe({
    required ExerciseTemplate template,
    required TrainingGoal goal,
    required Iterable<WorkoutSession> history,
    required WorkoutSession session,
    RecommendationProfile? profile,
    PersonalCoachingPlan? coachingPlan,
  }) {
    final base = PerformanceEngine.prescriptionFor(goal);
    final compound = isCompound(template);
    final beginner =
        profile?.experienceLevel == TrainingExperienceLevel.beginner;
    final fatigued =
        profile?.hasRecoveryFor(day(session.date)) == true &&
        profile?.recoveryStatus == TrainingRecoveryStatus.fatigued;
    final (minReps, maxReps) = switch (goal) {
      TrainingGoal.strength when compound && !beginner => (4, 6),
      TrainingGoal.hypertrophy => compound ? (8, 12) : (10, 15),
      TrainingGoal.endurance => (15, 20),
      _ => (8, 12),
    };
    final weeklyVolume = volume(
      history: history,
      session: session,
      since: coachingPlan?.weekStart,
    );
    final todayVolume = volume(
      history: history,
      session: session,
      todayOnly: true,
    );
    final remaining = remainingSets(
      template: template,
      goal: goal,
      weeklyVolume: weeklyVolume,
      todayVolume: todayVolume,
      profile: profile,
      plannedSessionSets: plannedSessionSets(session),
      coachingPlan: coachingPlan,
    );
    var sets = beginner || !compound ? 2 : base.sets;
    if (fatigued) sets = math.max(1, sets - 1);
    sets = sets.clamp(1, math.max(1, remaining));

    // 실제 같은 종목의 작업세트만 기준으로 삼는다. e1RM을 반복 곱해
    // 수행한 적 없는 무게를 만들어 내거나, 다른 기구의 kg을 옮기지 않는다.
    final previousByDay = <DateTime, List<WorkoutSetEntry>>{};
    final completeByDay = <DateTime, bool>{};
    for (final item in history) {
      if (!day(item.date).isBefore(day(session.date))) continue;
      final work = item.exercises
          .where(
            (exercise) =>
                exercise.template.id == template.id &&
                !exercise.id.startsWith('seed_'),
          )
          .expand((exercise) => exercise.sets)
          .where(
            (set) =>
                set.completed &&
                set.type == '일반' &&
                set.weight.isFinite &&
                set.weight >= 0 &&
                (!template.usesWeight || set.weight > 0) &&
                (template.isDurationHold
                    ? set.durationSeconds > 0
                    : set.reps > 0),
          )
          .toList();
      if (work.isNotEmpty) {
        previousByDay.putIfAbsent(day(item.date), () => []).addAll(work);
        final complete = item.exercises
            .where(
              (exercise) =>
                  exercise.template.id == template.id &&
                  !exercise.id.startsWith('seed_'),
            )
            .every(
              (exercise) => exercise.sets
                  .where((set) => set.type == '일반')
                  .every(
                    (set) =>
                        set.completed &&
                        set.reps > 0 &&
                        set.weight.isFinite &&
                        (!template.usesWeight || set.weight > 0),
                  ),
            );
        completeByDay.update(
          day(item.date),
          (value) => value && complete,
          ifAbsent: () => complete,
        );
      }
    }
    final previous = previousByDay.entries
        .map((entry) => (entry.key, entry.value))
        .toList();
    previous.sort((left, right) => right.$1.compareTo(left.$1));
    var trend = previous.length < 2
        ? RecommendationTrend.insufficient
        : RecommendationTrend.stable;
    var weight = 0.0;
    var loadReason = template.usesWeight
        ? '이 종목의 기록이 없어 첫 중량은 직접 정해주세요.'
        : '맨몸으로 시작해 목표 범위 안에서 수행해주세요.';
    if (template.usesWeight && previous.isNotEmpty) {
      final latest = previous.first.$2;
      // 가장 자주 사용한 무게, 동률이면 낮은 무게를 기준으로 한다.
      final counts = <double, int>{};
      for (final set in latest) {
        counts[set.weight] = (counts[set.weight] ?? 0) + 1;
      }
      final weights = counts.keys.toList()
        ..sort((a, b) {
          final byCount = counts[b]!.compareTo(counts[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
      weight = weights.first;
      final requiredSets = beginner || !compound ? 2 : base.sets;
      // 네 날짜의 같은 중량·충분한 일반 세트만 비교한다. 부분 기록과 중량 변경은 제외.
      final comparable = previous.take(4).toList();
      final comparableReps = <double>[];
      if (comparable.length == 4 &&
          day(session.date).difference(comparable.last.$1).inDays <= 42) {
        for (final exposure in comparable) {
          final work = exposure.$2
              .where((set) => set.weight == weight)
              .toList();
          if (work.length < requiredSets) break;
          // 세트 추가로 평균이 달라지는 것을 피한다.
          comparableReps.add(
            work.take(requiredSets).fold<int>(0, (sum, set) => sum + set.reps) /
                requiredSets,
          );
        }
      }
      final declining =
          comparableReps.length == 4 &&
          comparableReps[0] <= comparableReps[1] - 1 &&
          comparableReps[1] <= comparableReps[2] - 1 &&
          comparableReps[2] <= comparableReps[3] - 1;
      final plateau =
          comparableReps.length == 4 &&
          comparableReps.every((reps) => reps >= minReps && reps < maxReps) &&
          comparableReps.reduce(math.max) - comparableReps.reduce(math.min) <=
              1;
      final step = PerformanceEngine.recommendedIncrement(weight);
      bool upperSuccess((DateTime, List<WorkoutSetEntry>) exposure) {
        final sameWeight = exposure.$2
            .where((set) => set.weight == weight)
            .toList();
        return sameWeight.length >= requiredSets &&
            completeByDay[exposure.$1] == true &&
            sameWeight.every(
              (set) =>
                  set.reps >= maxReps &&
                  (set.rir == null || (set.rir! >= 2 && set.rir! <= 10)),
            );
      }

      bool missed(List<WorkoutSetEntry> work) {
        final sameWeight = work.where((set) => set.weight == weight).toList();
        return sameWeight.length >= 2 &&
            sameWeight.where((set) => set.reps < minReps).length >= 2;
      }

      loadReason =
          '최근 ${PerformanceEngine.formatWeight(weight)}kg 기록을 유지하며 $minReps–$maxReps회를 쌓아보세요.';
      final stale = day(session.date).difference(previous.first.$1).inDays > 28;
      if (stale || fatigued) {
        if (stale) {
          trend = RecommendationTrend.returning;
          sets = math.max(1, sets - 1);
        }
        weight = (weight * .9 * 2).floorToDouble() / 2;
        loadReason = stale
            ? '4주 넘게 쉬어 최근 중량에서 10% 낮춰 다시 시작합니다.'
            : '오늘 피로를 반영해 최근 중량에서 10% 낮췄습니다.';
      } else if (previous.length >= 2 &&
          upperSuccess(previous.first) &&
          upperSuccess(previous[1]) &&
          previous.first.$1.difference(previous[1].$1).inDays <= 28 &&
          step / weight <= .1) {
        weight += step;
        trend = RecommendationTrend.progressing;
        loadReason =
            '같은 중량에서 반복 상단을 두 번 연속 달성해 ${PerformanceEngine.formatWeight(step)}kg 올립니다.';
      } else if (previous.length >= 2 &&
          missed(latest) &&
          missed(previous[1].$2) &&
          previous.first.$1.difference(previous[1].$1).inDays <= 28) {
        weight = (weight * .95 * 2).floorToDouble() / 2;
        trend = RecommendationTrend.declining;
        loadReason = '두 번 연속 최소 반복에 미달해 중량을 5% 낮췄습니다.';
      } else if (declining) {
        trend = RecommendationTrend.declining;
        sets = math.max(1, sets - 1);
        loadReason = '최근 네 번 같은 중량의 반복수가 계속 줄어 중량을 유지하고 1세트를 줄여 제안합니다.';
      } else if (plateau) {
        trend = RecommendationTrend.plateau;
        loadReason = '최근 네 번 같은 중량의 반복수가 비슷해 중량을 유지하고 목표 상단을 다시 시도합니다.';
      }
    }
    final coachingReason =
        coachingPlan?.reasonFor(primaryMuscles(template)) ?? '';
    if (coachingPlan != null &&
        previous.length >= 4 &&
        !fatigued &&
        trend != RecommendationTrend.returning &&
        trend != RecommendationTrend.declining &&
        trend != RecommendationTrend.progressing) {
      final latest = previous.first.$2
          .where((set) => set.weight == weight)
          .toList();
      final targets = primaryMuscles(template)
          .map((muscle) => coachingPlan.targets[muscle])
          .whereType<MuscleCoachingTarget>();
      if (targets.isNotEmpty &&
          targets.every(
            (target) => target.adjustment != CoachingAdjustment.insufficient,
          )) {
        final addSet = targets.every(
          (target) => target.adjustment == CoachingAdjustment.increase,
        );
        sets = (latest.length + (addSet ? 1 : 0))
            .clamp(2, 5)
            .clamp(1, math.max(1, remaining));
      }
    }
    final muscles = primaryMuscles(template);
    // 반복 범위와 이번에 실제 등록할 목표를 분리한다. 중량을 바꾸면 하한에서
    // 시작하고, 유지할 때는 같은 중량의 세트별 실적을 이어간다.
    var targetRepsBySet = List<int>.filled(sets, minReps);
    if (!template.isDurationHold &&
        previous.isNotEmpty &&
        day(session.date).difference(previous.first.$1).inDays <= 28 &&
        !fatigued &&
        trend != RecommendationTrend.returning &&
        trend != RecommendationTrend.progressing &&
        trend != RecommendationTrend.declining) {
      final latest = previous.first.$2
          .where((set) => set.weight == weight)
          .toList();
      if (latest.isNotEmpty) {
        final requiredSets = beginner || !compound ? 2 : base.sets;
        final full =
            completeByDay[previous.first.$1] == true &&
            latest.length >= requiredSets;
        final comparableRest =
            previous.length < 2 ||
            (() {
              final older = previous[1].$2
                  .where((set) => set.weight == weight)
                  .toList();
              if (older.length < requiredSets ||
                  previous.first.$1.difference(previous[1].$1).inDays > 28) {
                return false;
              }
              final count = math.min(latest.length, older.length);
              return List.generate(
                count,
                (index) =>
                    (latest[index].restSeconds - older[index].restSeconds)
                            .abs() <=
                        15 &&
                    latest[index].reps >= older[index].reps,
              ).every((value) => value);
            })();
        final canAdd =
            full &&
            comparableRest &&
            sets <= latest.length &&
            latest.every(
              (set) =>
                  set.reps >= minReps &&
                  (set.rir == null || (set.rir! >= 2 && set.rir! <= 10)),
            );
        targetRepsBySet = List.generate(sets, (index) {
          // 추가 세트에는 이전 마지막 작업세트보다 높은 목표를 주지 않는다.
          final existing = index < latest.length;
          final prior = latest[math.min(index, latest.length - 1)].reps;
          return (prior + (canAdd && existing ? 1 : 0)).clamp(minReps, maxReps);
        });
        final targets = targetRepsBySet.join(' / ');
        loadReason += canAdd && latest.any((set) => set.reps < maxReps)
            ? ' 완료한 세트별 기록에 1회씩 더해 이번 목표는 $targets회입니다.'
            : ' 이번 목표는 $targets회입니다. ${full ? '반복 여유·수행 변화 또는 증량 조건을 확인하며 유지합니다.' : '완전한 작업세트 기록이 부족해 횟수 증가를 보류합니다.'}';
      }
    }
    final volumeLabel = muscles
        .map(
          (muscle) =>
              '${muscle.label} ${PerformanceEngine.formatWeight(weeklyVolume[muscle] ?? 0)}세트',
        )
        .join(' · ');
    return WorkoutRecommendation(
      template: template,
      goal: goal,
      weight: weight.clamp(0, 999),
      minReps: minReps,
      maxReps: maxReps,
      targetRepsBySet: List.unmodifiable(targetRepsBySet),
      sets: sets,
      nextWeight: (weight + PerformanceEngine.recommendedIncrement(weight))
          .clamp(0, 999),
      restSeconds: compound ? (goal == TrainingGoal.strength ? 180 : 120) : 90,
      reason:
          '$loadReason ${coachingPlan == null ? '최근 7일 완료량' : '이번 주 완료량'}과 오늘 계획은 $volumeLabel입니다. '
          '${beginner ? '입문 단계와 ' : ''}${fatigued ? '오늘 피로와 ' : ''}남은 운동량을 반영해 $sets세트를 제안합니다. '
          '$coachingReason',
      summary: coachingReason.isEmpty
          ? loadReason
          : '$loadReason 개인 코칭 기준을 반영했습니다.',
      historyCount: previous.length,
      trend: trend,
      evidenceIds: {
        ...base.evidenceIds,
        'acsm-2009',
        'grgic-2018',
        'pelland_2026_dose_response',
        'refalo_2023_proximity_failure',
        if (fatigued) 'craven_2022_sleep_loss',
        if (coachingPlan != null) 'larsen_2021_autoregulation',
      },
      evidenceNote:
          '주동근은 1세트, 보조근은 0.5세트로 계산합니다. '
          '세트 예산·반복 범위·중량 증감 폭은 연구 원칙을 적용한 앱 기본값입니다. '
          '가능하면 2–3회 더 할 여유를 두고, 수행 결과에 맞게 조절해주세요. '
          '$coachingReason',
    );
  }
}
