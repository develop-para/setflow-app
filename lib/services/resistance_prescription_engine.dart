import 'dart:math' as math;

import '../models.dart';
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
  }) {
    final reference = day(session.date);
    final start = DateTime(reference.year, reference.month, reference.day - 6);
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
    var remaining = math.min(dailyBudget, sessionBudget - plannedSessionSets);
    for (final muscle in primaryMuscles(template)) {
      remaining = math.min(
        remaining,
        (weeklyBudget - (weeklyVolume[muscle] ?? 0)).floor(),
      );
      remaining = math.min(
        remaining,
        (dailyBudget - (todayVolume[muscle] ?? 0)).floor(),
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
  }) {
    final base = PerformanceEngine.prescriptionFor(goal);
    final compound = compoundIds.contains(template.id);
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
    final weeklyVolume = volume(history: history, session: session);
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
    );
    var sets = beginner || !compound ? 2 : base.sets;
    if (fatigued) sets = math.max(1, sets - 1);
    sets = sets.clamp(1, math.max(1, remaining));

    // 실제 같은 종목의 작업세트만 기준으로 삼는다. e1RM을 반복 곱해
    // 수행한 적 없는 무게를 만들어 내거나, 다른 기구의 kg을 옮기지 않는다.
    final previous = <(DateTime, List<WorkoutSetEntry>)>[];
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
      if (work.isNotEmpty) previous.add((day(item.date), work));
    }
    previous.sort((left, right) => right.$1.compareTo(left.$1));
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
      final step = PerformanceEngine.recommendedIncrement(weight);
      bool upperSuccess(List<WorkoutSetEntry> work) {
        final sameWeight = work.where((set) => set.weight == weight).toList();
        return sameWeight.length >= sets &&
            sameWeight.every(
              (set) =>
                  set.reps >= maxReps && (set.rir == null || set.rir! >= 2),
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
        weight = (weight * .9 * 2).floorToDouble() / 2;
        loadReason = stale
            ? '4주 넘게 쉬어 최근 중량에서 10% 낮춰 다시 시작합니다.'
            : '오늘 피로를 반영해 최근 중량에서 10% 낮췄습니다.';
      } else if (previous.length >= 2 &&
          upperSuccess(latest) &&
          upperSuccess(previous[1].$2) &&
          previous.first.$1.difference(previous[1].$1).inDays <= 28 &&
          step / weight <= .1) {
        weight += step;
        loadReason =
            '같은 중량에서 반복 상단을 두 번 연속 달성해 ${PerformanceEngine.formatWeight(step)}kg 올립니다.';
      } else if (previous.length >= 2 &&
          missed(latest) &&
          missed(previous[1].$2)) {
        weight = (weight * .95 * 2).floorToDouble() / 2;
        loadReason = '두 번 연속 최소 반복에 미달해 중량을 5% 낮췄습니다.';
      }
    }
    final muscles = primaryMuscles(template);
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
      sets: sets,
      nextWeight: (weight + PerformanceEngine.recommendedIncrement(weight))
          .clamp(0, 999),
      restSeconds: compound ? (goal == TrainingGoal.strength ? 180 : 120) : 90,
      reason:
          '$loadReason 최근 7일 완료량과 오늘 계획은 $volumeLabel입니다. '
          '${beginner ? '입문 단계와 ' : ''}${fatigued ? '오늘 피로와 ' : ''}남은 운동량을 반영해 $sets세트를 제안합니다.',
      evidenceIds: {
        ...base.evidenceIds,
        'acsm-2009',
        'grgic-2018',
        'pelland_2026_dose_response',
        'refalo_2023_proximity_failure',
        if (fatigued) 'craven_2022_sleep_loss',
      },
      evidenceNote:
          '주동근은 1세트, 보조근은 0.5세트로 계산합니다. '
          '세트 예산·반복 범위·중량 증감 폭은 연구 원칙을 적용한 앱 기본값입니다. '
          '가능하면 2–3회 더 할 여유를 두고, 수행 결과에 맞게 조절해주세요.',
    );
  }
}
