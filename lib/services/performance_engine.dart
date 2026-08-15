import '../models.dart';

enum EstimateQuality { high, medium, reference }

extension EstimateQualityLabel on EstimateQuality {
  String get label => switch (this) {
    EstimateQuality.high => '높음',
    EstimateQuality.medium => '보통',
    EstimateQuality.reference => '참고용',
  };
}

enum TrainingGoal { strength, hypertrophy, endurance }

extension TrainingGoalLabel on TrainingGoal {
  String get label => switch (this) {
    TrainingGoal.strength => '근력',
    TrainingGoal.hypertrophy => '근비대',
    TrainingGoal.endurance => '근지구력',
  };
}

enum PerformancePrType { weight, reps, estimatedOneRepMax }

extension PerformancePrTypeLabel on PerformancePrType {
  String get label => switch (this) {
    PerformancePrType.weight => '중량 PR',
    PerformancePrType.reps => '반복 PR',
    PerformancePrType.estimatedOneRepMax => 'e1RM PR',
  };
}

class E1rmEstimate {
  const E1rmEstimate({
    required this.value,
    required this.epley,
    required this.brzycki,
    required this.quality,
  });

  final double value;
  final double epley;
  final double brzycki;
  final EstimateQuality quality;
}

class PerformanceSetRecord {
  const PerformanceSetRecord({
    required this.date,
    required this.set,
    required this.estimate,
  });

  final DateTime date;
  final WorkoutSetEntry set;
  final E1rmEstimate estimate;
}

class ExercisePerformanceSummary {
  const ExercisePerformanceSummary({
    required this.template,
    required this.currentE1rm,
    required this.quality,
    required this.sessionCount,
    required this.weightPr,
    required this.repPr,
    required this.e1rmPr,
    required this.latestSessionBest,
    this.changeFromPrevious,
  });

  final ExerciseTemplate template;
  final double currentE1rm;
  final double? changeFromPrevious;
  final EstimateQuality quality;
  final int sessionCount;
  final PerformanceSetRecord weightPr;
  final PerformanceSetRecord repPr;
  final PerformanceSetRecord e1rmPr;
  final PerformanceSetRecord latestSessionBest;
}

class WorkoutRecommendation {
  const WorkoutRecommendation({
    required this.template,
    required this.goal,
    required this.weight,
    required this.minReps,
    required this.maxReps,
    required this.sets,
    required this.nextWeight,
    required this.reason,
    this.restSeconds = 90,
  });

  final ExerciseTemplate template;
  final TrainingGoal goal;
  final double weight;
  final int minReps;
  final int maxReps;
  final int sets;
  final double nextWeight;
  final String reason;
  final int restSeconds;

  String progressionCondition(String unit) =>
      '${List.filled(sets, maxReps).join(' / ')} 성공 → '
      '${PerformanceEngine.formatWeight(nextWeight)}$unit';
}

abstract final class PerformanceEngine {
  static E1rmEstimate? estimate(double weight, int reps) {
    if (weight <= 0 || reps < 1 || reps > 15) return null;
    if (reps == 1) {
      return E1rmEstimate(
        value: weight,
        epley: weight,
        brzycki: weight,
        quality: EstimateQuality.high,
      );
    }
    final epley = weight * (1 + reps / 30);
    final brzycki = weight * 36 / (37 - reps);
    return E1rmEstimate(
      value: (epley + brzycki) / 2,
      epley: epley,
      brzycki: brzycki,
      quality: reps <= 5
          ? EstimateQuality.high
          : reps <= 10
          ? EstimateQuality.medium
          : EstimateQuality.reference,
    );
  }

  static TrainingGoal goalFromProfile(List<String> goals) {
    final joined = goals.join(' ');
    if (joined.contains('지구력') || joined.contains('체력')) {
      return TrainingGoal.endurance;
    }
    if (joined.contains('근력') || joined.contains('파워')) {
      return TrainingGoal.strength;
    }
    return TrainingGoal.hypertrophy;
  }

  static ExercisePerformanceSummary? summarize({
    required Iterable<WorkoutSession> sessions,
    required ExerciseTemplate template,
    DateTime? before,
  }) {
    final records = _records(
      sessions: sessions,
      templateId: template.id,
      before: before,
    );
    if (records.isEmpty) return null;

    final byDay = <DateTime, List<PerformanceSetRecord>>{};
    for (final record in records) {
      final day = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      byDay.putIfAbsent(day, () => []).add(record);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final sessionBests = [
      for (final day in days)
        byDay[day]!.reduce(
          (best, item) =>
              item.estimate.value > best.estimate.value ? item : best,
        ),
    ];
    final recentValues = sessionBests
        .take(5)
        .map((item) => item.estimate.value)
        .toList();
    final current = _median(recentValues);
    final change = sessionBests.length < 2
        ? null
        : sessionBests[0].estimate.value - sessionBests[1].estimate.value;

    final weightPr = records.reduce((best, item) {
      if (item.set.weight != best.set.weight) {
        return item.set.weight > best.set.weight ? item : best;
      }
      return item.set.reps > best.set.reps ? item : best;
    });
    final repPr = records.reduce((best, item) {
      if (item.set.reps != best.set.reps) {
        return item.set.reps > best.set.reps ? item : best;
      }
      return item.set.weight > best.set.weight ? item : best;
    });
    final e1rmPr = records.reduce(
      (best, item) => item.estimate.value > best.estimate.value ? item : best,
    );

    return ExercisePerformanceSummary(
      template: template,
      currentE1rm: current,
      changeFromPrevious: change,
      quality: sessionBests.first.estimate.quality,
      sessionCount: sessionBests.length,
      weightPr: weightPr,
      repPr: repPr,
      e1rmPr: e1rmPr,
      latestSessionBest: sessionBests.first,
    );
  }

  static WorkoutRecommendation? recommend({
    required Iterable<WorkoutSession> sessions,
    required ExerciseTemplate template,
    required TrainingGoal goal,
    double increment = 2.5,
  }) {
    final summary = summarize(sessions: sessions, template: template);
    if (summary == null) return null;
    final (
      int minReps,
      int maxReps,
      int targetSets,
      double intensity,
    ) = switch (goal) {
      TrainingGoal.strength => (4, 6, 3, .825),
      TrainingGoal.hypertrophy => (8, 10, 3, .75),
      TrainingGoal.endurance => (15, 20, 3, .55),
    };

    final history = _sessionWorkSets(
      sessions: sessions,
      templateId: template.id,
    );
    var weight = roundToIncrement(summary.currentE1rm * intensity, increment);
    var reason = '${goal.label} 목표 강도로 계산';
    if (history.isNotEmpty) {
      final latest = history.first;
      final workingWeight = _primaryWeight(latest.$2);
      final latestSets = latest.$2
          .where((set) => set.weight == workingWeight)
          .take(targetSets)
          .toList();
      weight = workingWeight;
      final completedTarget = latestSets.length >= targetSets;
      final upperSuccess =
          completedTarget && latestSets.every((set) => set.reps >= maxReps);
      if (upperSuccess) {
        weight = workingWeight + increment;
        reason = '지난 운동에서 목표 반복을 모두 달성';
      } else if (_missedLowerBound(latestSets, minReps) && history.length > 1) {
        final previousWeight = _primaryWeight(history[1].$2);
        final previousSets = history[1].$2
            .where((set) => set.weight == previousWeight)
            .take(targetSets)
            .toList();
        if (_missedLowerBound(previousSets, minReps)) {
          weight = roundToIncrement(workingWeight * .975, increment);
          reason = '두 번 연속 최소 반복에 미달해 소폭 조정';
        } else {
          reason = '한 번 더 같은 중량으로 반복 범위 확인';
        }
      } else {
        reason = '현재 중량에서 목표 반복 범위 유지';
      }
    }
    weight = weight < increment ? increment : weight;

    return WorkoutRecommendation(
      template: template,
      goal: goal,
      weight: weight,
      minReps: minReps,
      maxReps: maxReps,
      sets: targetSets,
      nextWeight: weight + increment,
      reason: reason,
      restSeconds: switch (goal) {
        TrainingGoal.strength => 180,
        TrainingGoal.hypertrophy => 90,
        TrainingGoal.endurance => 60,
      },
    );
  }

  static Set<PerformancePrType> prTypesForCandidate({
    required Iterable<WorkoutSession> sessions,
    required String templateId,
    required WorkoutSetEntry candidate,
  }) {
    if (candidate.type == '웜업' ||
        candidate.weight <= 0 ||
        candidate.reps <= 0) {
      return {};
    }
    final estimateValue = estimate(candidate.weight, candidate.reps);
    if (estimateValue == null) return {};
    final history = _records(
      sessions: sessions,
      templateId: templateId,
      excludedSet: candidate,
    );
    if (history.isEmpty) {
      return PerformancePrType.values.toSet();
    }
    final result = <PerformancePrType>{};
    if (candidate.weight >
        history.map((item) => item.set.weight).reduce(_max)) {
      result.add(PerformancePrType.weight);
    }
    final sameWeight = history.where(
      (item) => item.set.weight == candidate.weight,
    );
    if (sameWeight.isEmpty ||
        candidate.reps >
            sameWeight.map((item) => item.set.reps).reduce(_maxInt)) {
      result.add(PerformancePrType.reps);
    }
    if (estimateValue.value >
        history.map((item) => item.estimate.value).reduce(_max)) {
      result.add(PerformancePrType.estimatedOneRepMax);
    }
    return result;
  }

  static double roundToIncrement(double value, double increment) {
    if (increment <= 0) return value;
    return (value / increment).round() * increment;
  }

  static String formatWeight(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  static List<PerformanceSetRecord> _records({
    required Iterable<WorkoutSession> sessions,
    required String templateId,
    DateTime? before,
    WorkoutSetEntry? excludedSet,
  }) {
    final records = <PerformanceSetRecord>[];
    for (final session in sessions) {
      if (before != null && !session.date.isBefore(before)) continue;
      for (final exercise in session.exercises) {
        if (exercise.id.startsWith('seed_') ||
            exercise.template.id != templateId) {
          continue;
        }
        for (final set in exercise.sets) {
          if (identical(set, excludedSet) || !_isWorkSet(set)) continue;
          final estimateValue = estimate(set.weight, set.reps);
          if (estimateValue == null) continue;
          records.add(
            PerformanceSetRecord(
              date: session.date,
              set: set,
              estimate: estimateValue,
            ),
          );
        }
      }
    }
    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }

  static List<(DateTime, List<WorkoutSetEntry>)> _sessionWorkSets({
    required Iterable<WorkoutSession> sessions,
    required String templateId,
  }) {
    final result = <(DateTime, List<WorkoutSetEntry>)>[];
    for (final session in sessions) {
      final sets = <WorkoutSetEntry>[];
      for (final exercise in session.exercises) {
        if (exercise.id.startsWith('seed_') ||
            exercise.template.id != templateId) {
          continue;
        }
        sets.addAll(exercise.sets.where(_isWorkSet));
      }
      if (sets.isNotEmpty) result.add((session.date, sets));
    }
    result.sort((a, b) => b.$1.compareTo(a.$1));
    return result;
  }

  static bool _isWorkSet(WorkoutSetEntry set) =>
      set.completed && set.type != '웜업' && set.weight > 0 && set.reps > 0;

  static bool _missedLowerBound(List<WorkoutSetEntry> sets, int minReps) {
    if (sets.length < 2) return false;
    return sets.where((set) => set.reps < minReps).length >= 2;
  }

  static double _primaryWeight(List<WorkoutSetEntry> sets) {
    final counts = <double, int>{};
    for (final set in sets) {
      counts[set.weight] = (counts[set.weight] ?? 0) + 1;
    }
    return counts.keys.reduce((best, value) {
      final bestCount = counts[best]!;
      final valueCount = counts[value]!;
      if (valueCount != bestCount) return valueCount > bestCount ? value : best;
      return value > best ? value : best;
    });
  }

  static double _median(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  static double _max(double a, double b) => a > b ? a : b;
  static int _maxInt(int a, int b) => a > b ? a : b;
}
