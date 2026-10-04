import 'dart:math' as math;

import '../domain/personal_coaching.dart';
import '../models.dart';
import 'performance_engine.dart' show TrainingGoal;
import 'resistance_prescription_engine.dart';

/// Research-informed feedback rules, not a claim of individual optimal dose.
/// A week is fixed using the preceding three complete calendar weeks. New work
/// affects remaining volume, never increases its own target during the week.
abstract final class PersonalCoachingEngine {
  static PersonalCoachingPlan build({
    required DateTime date,
    required Iterable<WorkoutSession> history,
    required TrainingGoal goal,
    RecommendationProfile? profile,
    int plannedTrainingDays = 3,
  }) {
    if (plannedTrainingDays < 1 || plannedTrainingDays > 7) {
      throw RangeError.range(plannedTrainingDays, 1, 7, 'plannedTrainingDays');
    }
    final reference = ResistancePrescriptionEngine.day(date);
    final weekStart = DateTime(
      reference.year,
      reference.month,
      reference.day - (reference.weekday - DateTime.monday),
    );
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day - 21);
    final beginner =
        profile?.experienceLevel == TrainingExperienceLevel.beginner;
    final advanced =
        profile?.experienceLevel == TrainingExperienceLevel.advanced;
    final baseWeekly = goal == TrainingGoal.hypertrophy
        ? (beginner
              ? 8
              : advanced
              ? 16
              : 12)
        : (beginner ? 6 : 10);
    final baseDaily = beginner
        ? 4
        : advanced
        ? 8
        : 6;
    // Merge repeated rows by calendar date so one day cannot manufacture
    // several successful exposures. Seed, warmup, unfinished and future work
    // never establishes a training baseline.
    final byDay = <DateTime, Map<String, _Exposure>>{};
    final seen = <String>{};
    for (final session in history) {
      final day = ResistancePrescriptionEngine.day(session.date);
      if (day.isBefore(start) || !day.isBefore(weekStart)) continue;
      for (final exercise in session.exercises) {
        if (exercise.id.startsWith('seed_') || exercise.template.isCardio) {
          continue;
        }
        if (!seen.add('${day.toIso8601String()}/${exercise.id}')) continue;
        final sets = exercise.sets
            .where(
              (set) =>
                  set.completed &&
                  set.type == '일반' &&
                  set.weight.isFinite &&
                  set.weight >= 0 &&
                  (exercise.template.usesWeight ? set.weight > 0 : true) &&
                  (exercise.template.isDurationHold
                      ? set.durationSeconds > 0
                      : set.reps > 0),
            )
            .toList();
        if (sets.isEmpty) continue;
        final rows = byDay.putIfAbsent(day, () => {});
        final exposure = rows.putIfAbsent(
          exercise.template.id,
          () => _Exposure(day, exercise.template),
        );
        exposure.sets.addAll(sets);
        exposure.complete =
            exposure.complete &&
            exercise.sets
                .where((set) => set.type == '일반')
                .every((set) => set.completed);
      }
    }
    final targets = <TrainingMuscle, MuscleCoachingTarget>{};
    for (final muscle in TrainingMuscle.values) {
      final weekly = List<double>.filled(3, 0);
      final days = List<Set<DateTime>>.generate(3, (_) => {});
      final primaryDays = <DateTime>{};
      final exercises = <String, List<_Exposure>>{};
      for (final entry in byDay.entries) {
        // Use UTC date arithmetic so a DST transition cannot shift week bins.
        final offset = DateTime.utc(
          entry.key.year,
          entry.key.month,
          entry.key.day,
        ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
        final index = offset ~/ 7;
        for (final exposure in entry.value.values) {
          final primary = ResistancePrescriptionEngine.primaryMuscles(
            exposure.template,
          ).contains(muscle);
          final secondary = ResistancePrescriptionEngine.secondaryMuscles(
            exposure.template,
          ).contains(muscle);
          if (!primary && !secondary) continue;
          weekly[index] += exposure.sets.length * (primary ? 1 : .5);
          days[index].add(entry.key);
          if (primary) {
            primaryDays.add(entry.key);
            exercises.putIfAbsent(exposure.template.id, () => []).add(exposure);
          }
        }
      }
      final activeWeeks = weekly.where((count) => count > 0).length;
      final sufficient =
          primaryDays.length >= 4 && activeWeeks >= 2 && weekly.last > 0;
      var target = baseWeekly;
      var daily = baseDaily;
      var frequency = math.min(2, plannedTrainingDays);
      var adjustment = CoachingAdjustment.insufficient;
      var reason =
          '${muscle.label}: 비교할 기록이 부족해 기본 주간 $baseWeekly세트를 유지합니다. 최근 3주에 2주 이상, 4일 이상의 주동근 기록이 필요합니다.';
      if (sufficient) {
        final observed = (weekly.reduce((a, b) => a + b) / activeWeeks).ceil();
        // 12/20/24 and the +/-2 step are bounded product defaults.
        final maximum = beginner
            ? 12
            : advanced
            ? 24
            : 20;
        final baseline = observed.clamp(4, maximum);
        frequency =
            (days.fold<int>(0, (sum, item) => sum + item.length) / activeWeeks)
                .round()
                .clamp(1, math.min(3, plannedTrainingDays));
        final signals = exercises.values
            .map(_signal)
            .whereType<_Signal>()
            .toList();
        final declining = signals.where((signal) => signal.declining).length;
        final progressing = signals
            .where((signal) => signal.progressing)
            .length;
        // Reducing volume needs repeated decline in at least two exercises;
        // a single exercise falling behind cannot diagnose whole-body fatigue.
        final reduce = declining >= 2;
        final increase =
            declining == 0 &&
            progressing > 0 &&
            signals.length == exercises.length &&
            signals.every((signal) => signal.hasReserve);
        adjustment = reduce
            ? CoachingAdjustment.reduce
            : increase
            ? CoachingAdjustment.increase
            : CoachingAdjustment.maintain;
        target =
            (baseline +
                    (reduce
                        ? -2
                        : increase
                        ? 2
                        : 0))
                .clamp(4, maximum);
        if (target == baseline) adjustment = CoachingAdjustment.maintain;
        daily = (target / frequency).ceil().clamp(2, beginner ? 6 : 10);
        final explanation = reduce
            ? '$declining개 종목에서 같은 중량·비슷한 휴식의 반복수가 연속 하락해 2세트 줄였습니다.'
            : increase && target > baseline
            ? '$progressing개 종목에서 반복수가 늘고 비교 세트에 RIR 2 이상이 기록돼 2세트 늘렸습니다.'
            : '증가·감소 근거가 충분하지 않아 최근 수행량을 유지합니다.';
        reason =
            '${muscle.label}: 최근 $activeWeeks주 ${primaryDays.length}일, 주당 평균 $observed세트를 반영해 $target세트 · 주 $frequency회로 제안합니다. $explanation';
      }
      targets[muscle] = MuscleCoachingTarget(
        muscle: muscle,
        weeklySets: target,
        dailySets: daily,
        trainingDays: frequency,
        historyDays: primaryDays.length,
        adjustment: adjustment,
        reason: reason,
      );
    }
    return PersonalCoachingPlan(weekStart: weekStart, targets: targets);
  }

  static _Signal? _signal(List<_Exposure> exposures) {
    exposures.sort((a, b) => b.day.compareTo(a.day));
    if (exposures.length < 3 ||
        exposures.take(3).any((item) => !item.complete)) {
      return null;
    }
    final recent = exposures.take(3).toList();
    if (recent.any((item) => item.template.isDurationHold)) return null;
    final latest = recent.first.sets;
    final counts = <double, int>{};
    for (final set in latest) {
      counts[set.weight] = (counts[set.weight] ?? 0) + 1;
    }
    final weights = counts.keys.toList()
      ..sort((a, b) {
        final count = counts[b]!.compareTo(counts[a]!);
        return count == 0 ? a.compareTo(b) : count;
      });
    final work = recent
        .map(
          (item) =>
              item.sets.where((set) => set.weight == weights.first).toList(),
        )
        .toList();
    if (work.any((sets) => sets.length < 2)) return null;
    // Compare equal numbers of sets; added sets must not depress the average.
    final count = work.map((sets) => sets.length).reduce(math.min).clamp(2, 3);
    final selected = work.map((sets) => sets.take(count).toList()).toList();
    final rest = selected
        .map(
          (sets) =>
              sets.fold<int>(0, (sum, set) => sum + set.restSeconds) / count,
        )
        .toList();
    if (rest.reduce(math.max) - rest.reduce(math.min) > 15) return null;
    final reps = selected
        .map((sets) => sets.fold<int>(0, (sum, set) => sum + set.reps) / count)
        .toList();
    return _Signal(
      progressing: reps[0] >= reps[1] + 1 && reps[1] >= reps[2] + 1,
      declining: reps[0] <= reps[1] - 1 && reps[1] <= reps[2] - 1,
      hasReserve: work
          .expand((sets) => sets)
          .every((set) => set.rir != null && set.rir! >= 2 && set.rir! <= 10),
    );
  }
}

class _Exposure {
  _Exposure(this.day, this.template);
  final DateTime day;
  final ExerciseTemplate template;
  final List<WorkoutSetEntry> sets = [];
  bool complete = true;
}

class _Signal {
  const _Signal({
    required this.progressing,
    required this.declining,
    required this.hasReserve,
  });
  final bool progressing;
  final bool declining;
  final bool hasReserve;
}
