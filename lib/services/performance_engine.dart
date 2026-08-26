import '../models.dart';

enum EstimateQuality { high, medium, reference }

extension EstimateQualityLabel on EstimateQuality {
  String get label => switch (this) {
    EstimateQuality.high => '높음',
    EstimateQuality.medium => '보통',
    EstimateQuality.reference => '참고용',
  };
}

enum TrainingGoal { strength, hypertrophy, fatLoss, endurance, health }

extension TrainingGoalLabel on TrainingGoal {
  String get label => switch (this) {
    TrainingGoal.strength => '근력 향상',
    TrainingGoal.hypertrophy => '근육 증가',
    TrainingGoal.fatLoss => '체중 감량',
    TrainingGoal.endurance => '체력 향상',
    TrainingGoal.health => '건강 유지',
  };

  String get methodLabel => switch (this) {
    TrainingGoal.strength => '고중량 근력',
    TrainingGoal.hypertrophy => '주간 볼륨 중심 근비대',
    TrainingGoal.fatLoss => '제지방 보존 + 유산소',
    TrainingGoal.endurance => '근지구력',
    TrainingGoal.health => '균형 훈련',
  };
}

class TrainingPrescription {
  const TrainingPrescription({
    required this.minReps,
    required this.maxReps,
    required this.sets,
    required this.intensity,
    required this.restSeconds,
    required this.evidenceIds,
    required this.evidenceNote,
  });

  final int minReps;
  final int maxReps;
  final int sets;
  final double intensity;
  final int restSeconds;
  final Set<String> evidenceIds;
  final String evidenceNote;
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
    this.evidenceIds = const {},
    this.evidenceNote = '',
    this.cardioDurationSeconds,
    this.cardioDistanceKm,
    this.cardioMinimumRpe,
    this.cardioMaximumRpe,
    this.cardioSupportsDistance = false,
    this.cardioStructure,
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
  final Set<String> evidenceIds;
  final String evidenceNote;
  final int? cardioDurationSeconds;
  final double? cardioDistanceKm;
  final int? cardioMinimumRpe;
  final int? cardioMaximumRpe;
  final bool cardioSupportsDistance;
  final String? cardioStructure;

  bool get isCardio => cardioDurationSeconds != null || template.isCardio;

  String prescriptionSummary(String unit) {
    if (!isCardio) {
      return '${PerformanceEngine.formatWeight(weight)}$unit · '
          '$minReps–$maxReps회 · $sets세트';
    }
    final minutes = ((cardioDurationSeconds ?? 0) / 60).round();
    final distance = cardioDistanceKm;
    final distanceText = distance != null && distance > 0
        ? ' · ${distance.toStringAsFixed(distance < 10 ? 1 : 0)}km'
        : '';
    final rpeText = cardioMinimumRpe == null || cardioMaximumRpe == null
        ? ''
        : ' · RPE $cardioMinimumRpe–$cardioMaximumRpe';
    return '$minutes분$distanceText$rpeText';
  }

  String progressionCondition(String unit) {
    if (isCardio) {
      return cardioDistanceKm == null
          ? '먼저 시간과 RPE를 안정적으로 완료한 뒤 점진적으로 늘려요.'
          : '최근 페이스를 기준으로 한 거리이며 컨디션에 따라 조절하세요.';
    }
    return '${List.filled(sets, maxReps).join(' / ')} 2회 연속 성공 → '
        '${PerformanceEngine.formatWeight(nextWeight)}$unit';
  }
}

abstract final class PerformanceEngine {
  static E1rmEstimate? estimate(
    double weight,
    int reps, {
    OneRepMaxFormula formula = OneRepMaxFormula.average,
  }) {
    if (weight <= 0 || reps < 1 || reps > 15) return null;
    if (reps == 1) {
      // 1회는 공식이 필요 없다 — 그 무게가 곧 1RM이다.
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
      value: switch (formula) {
        OneRepMaxFormula.average => (epley + brzycki) / 2,
        OneRepMaxFormula.epley => epley,
        OneRepMaxFormula.brzycki => brzycki,
      },
      epley: epley,
      brzycki: brzycki,
      quality: reps <= 5
          ? EstimateQuality.high
          : reps <= 10
          ? EstimateQuality.medium
          : EstimateQuality.reference,
    );
  }

  static TrainingGoal? goalFromProfile(List<String> goals) {
    // The first selected goal is the primary recommendation goal. Both the set
    // and next-exercise engines use this same mapping.
    for (final rawGoal in goals) {
      final goal = rawGoal.trim().toLowerCase();
      if (goal.contains('근력')) {
        return TrainingGoal.strength;
      }
      if (goal.contains('근육') || goal.contains('근비대')) {
        return TrainingGoal.hypertrophy;
      }
      if (goal.contains('감량') ||
          goal.contains('다이어트') ||
          goal.contains('체지방')) {
        return TrainingGoal.fatLoss;
      }
      if (goal.contains('지구력') || goal.contains('체력')) {
        return TrainingGoal.endurance;
      }
      if (goal.contains('건강') || goal.contains('유지')) {
        return TrainingGoal.health;
      }
    }
    return null;
  }

  static TrainingPrescription prescriptionFor(TrainingGoal goal) {
    return switch (goal) {
      TrainingGoal.strength => const TrainingPrescription(
        minReps: 4,
        maxReps: 6,
        sets: 3,
        intensity: .825,
        restSeconds: 180,
        evidenceIds: {'acsm_currier_2026_resistance', 'acsm-2009'},
        evidenceNote: '≥80% 1RM과 다중 작업세트 권고를 보수적인 기본값으로 적용합니다.',
      ),
      TrainingGoal.hypertrophy => const TrainingPrescription(
        minReps: 6,
        maxReps: 15,
        sets: 3,
        intensity: .75,
        restSeconds: 120,
        evidenceIds: {
          'acsm_currier_2026_resistance',
          'schoenfeld_2017_weekly_volume',
        },
        evidenceNote: '폭넓은 부하가 유효하며, 이 범위보다 근육군별 주간 작업세트가 더 중요합니다.',
      ),
      TrainingGoal.fatLoss => const TrainingPrescription(
        minReps: 8,
        maxReps: 12,
        sets: 3,
        intensity: .70,
        restSeconds: 90,
        evidenceIds: {
          'acsm_currier_2026_resistance',
          'acsm_jakicic_2024_adiposity',
        },
        evidenceNote: '저항운동은 제지방 보존을 위한 기본값이며 감량 효과는 유산소·총활동량과 함께 봅니다.',
      ),
      TrainingGoal.endurance => const TrainingPrescription(
        minReps: 15,
        maxReps: 20,
        sets: 3,
        intensity: .55,
        restSeconds: 60,
        evidenceIds: {'acsm-2009', 'acsm_currier_2026_resistance'},
        evidenceNote: '국소 근지구력의 실무 기본값이며 최적 변수의 근거 확실성은 낮습니다.',
      ),
      TrainingGoal.health => const TrainingPrescription(
        minReps: 8,
        maxReps: 12,
        sets: 2,
        intensity: .65,
        restSeconds: 90,
        evidenceIds: {
          'acsm_currier_2026_resistance',
          'acsm_garber_2011_prescription',
        },
        evidenceNote: '정확한 숫자보다 주요 근육군을 주 2회 이상 꾸준히 훈련하는 것이 우선입니다.',
      ),
    };
  }

  static ExercisePerformanceSummary? summarize({
    required Iterable<WorkoutSession> sessions,
    required ExerciseTemplate template,
    DateTime? before,
    OneRepMaxFormula formula = OneRepMaxFormula.average,
  }) {
    // Cardio uses elapsed time, distance, pace/power and intensity. Treating a
    // machine level or distance as lifting weight would create a false e1RM.
    if (template.muscle == '유산소') return null;
    final records = _records(
      sessions: sessions,
      templateId: template.id,
      before: before,
      formula: formula,
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
    double? increment,
  }) {
    if (template.muscle == '유산소') return null;
    final summary = summarize(sessions: sessions, template: template);
    if (summary == null) return null;
    final prescription = prescriptionFor(goal);
    final minReps = prescription.minReps;
    final maxReps = prescription.maxReps;
    final targetSets = prescription.sets;

    final history = _sessionWorkSets(
      sessions: sessions,
      templateId: template.id,
    );
    final provisionalWeight = summary.currentE1rm * prescription.intensity;
    final workingIncrement =
        increment ?? recommendedIncrement(provisionalWeight);
    final baselineWeight = roundToIncrement(
      provisionalWeight,
      workingIncrement,
    );
    var weight = baselineWeight;
    var reason =
        '${goal.label} · ${goal.methodLabel} '
        '${(prescription.intensity * 100).toStringAsFixed(0)}% e1RM 기준';
    if (history.isNotEmpty) {
      final latest = history.first;
      final workingWeight = _primaryWeight(latest.$2);
      final baselineTolerance = _max(
        workingIncrement * 2,
        baselineWeight * .075,
      );
      final followsCurrentGoal =
          (workingWeight - baselineWeight).abs() <= baselineTolerance;
      if (followsCurrentGoal) {
        final latestSets = latest.$2
            .where((set) => set.weight == workingWeight)
            .take(targetSets)
            .toList();
        weight = workingWeight;
        final completedTarget = latestSets.length >= targetSets;
        final upperSuccess =
            completedTarget && latestSets.every((set) => set.reps >= maxReps);
        if (upperSuccess) {
          final previousUpperSuccess =
              history.length > 1 &&
              _primaryWeight(history[1].$2) == workingWeight &&
              _meetsUpperTarget(
                history[1].$2
                    .where((set) => set.weight == workingWeight)
                    .take(targetSets)
                    .toList(),
                targetSets: targetSets,
                maxReps: maxReps,
              );
          if (previousUpperSuccess) {
            weight = workingWeight + workingIncrement;
            reason = '${goal.label} 목표 상단을 두 번 연속 달성해 중량 상승';
          } else {
            reason = '${goal.label} 목표 상단을 한 번 달성해 같은 중량으로 한 번 더 확인';
          }
        } else if (_missedLowerBound(latestSets, minReps) &&
            history.length > 1) {
          final previousWeight = _primaryWeight(history[1].$2);
          final previousSets = history[1].$2
              .where((set) => set.weight == previousWeight)
              .take(targetSets)
              .toList();
          if (_missedLowerBound(previousSets, minReps)) {
            weight = roundToIncrement(workingWeight * .975, workingIncrement);
            reason = '두 번 연속 최소 반복에 미달해 소폭 조정';
          } else {
            reason = '${goal.label} 목표로 한 번 더 같은 중량 확인';
          }
        } else {
          reason = '${goal.label} 목표 반복 범위에서 현재 중량 유지';
        }
      } else {
        reason =
            '${goal.label} 목표로 변경되어 '
            '${(prescription.intensity * 100).toStringAsFixed(0)}% e1RM에 맞춤';
      }
    }
    weight = weight < workingIncrement ? workingIncrement : weight;

    return WorkoutRecommendation(
      template: template,
      goal: goal,
      weight: weight,
      minReps: minReps,
      maxReps: maxReps,
      sets: targetSets,
      nextWeight: weight + workingIncrement,
      reason: reason,
      restSeconds: prescription.restSeconds,
      evidenceIds: prescription.evidenceIds,
      evidenceNote: prescription.evidenceNote,
    );
  }

  static Set<PerformancePrType> prTypesForCandidate({
    required Iterable<WorkoutSession> sessions,
    required String templateId,
    required WorkoutSetEntry candidate,
    OneRepMaxFormula formula = OneRepMaxFormula.average,
  }) {
    if (candidate.type != '일반' ||
        candidate.weight <= 0 ||
        candidate.reps <= 0) {
      return {};
    }
    final allHistory = _completedResistanceSets(
      sessions: sessions,
      templateId: templateId,
      excludedSet: candidate,
    );
    final estimateValue = candidate.reps <= 10
        ? estimate(candidate.weight, candidate.reps, formula: formula)
        : null;
    if (allHistory.isEmpty) {
      return {
        PerformancePrType.weight,
        PerformancePrType.reps,
        if (estimateValue != null) PerformancePrType.estimatedOneRepMax,
      };
    }
    final result = <PerformancePrType>{};
    if (candidate.weight > allHistory.map((item) => item.weight).reduce(_max)) {
      result.add(PerformancePrType.weight);
    }
    final sameWeight = allHistory.where(
      (item) => item.weight == candidate.weight,
    );
    if (sameWeight.isEmpty ||
        candidate.reps > sameWeight.map((item) => item.reps).reduce(_maxInt)) {
      result.add(PerformancePrType.reps);
    }
    if (estimateValue != null) {
      final e1rmHistory = _records(
        sessions: sessions,
        templateId: templateId,
        excludedSet: candidate,
        formula: formula,
      );
      if (e1rmHistory.isEmpty ||
          estimateValue.value >
              e1rmHistory.map((item) => item.estimate.value).reduce(_max)) {
        result.add(PerformancePrType.estimatedOneRepMax);
      }
    }
    return result;
  }

  static double roundToIncrement(double value, double increment) {
    if (increment <= 0) return value;
    return (value / increment).round() * increment;
  }

  /// Practical plate/machine increments kept within the commonly recommended
  /// small-step range. The actual available increment remains equipment
  /// dependent and can be overridden by the caller.
  static double recommendedIncrement(double workingWeight) {
    if (workingWeight <= 0) return 0.5;
    if (workingWeight < 10) return 0.5;
    if (workingWeight < 25) return 1;
    if (workingWeight <= 125) return 2.5;
    return 5;
  }

  static String formatWeight(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  static List<PerformanceSetRecord> _records({
    required Iterable<WorkoutSession> sessions,
    required String templateId,
    DateTime? before,
    WorkoutSetEntry? excludedSet,
    OneRepMaxFormula formula = OneRepMaxFormula.average,
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
          if (identical(set, excludedSet) || !_isE1rmSet(set)) continue;
          final estimateValue = estimate(
            set.weight,
            set.reps,
            formula: formula,
          );
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
        sets.addAll(exercise.sets.where(_isProgressionSet));
      }
      if (sets.isNotEmpty) result.add((session.date, sets));
    }
    result.sort((a, b) => b.$1.compareTo(a.$1));
    return result;
  }

  static List<WorkoutSetEntry> _completedResistanceSets({
    required Iterable<WorkoutSession> sessions,
    required String templateId,
    WorkoutSetEntry? excludedSet,
  }) {
    final result = <WorkoutSetEntry>[];
    for (final session in sessions) {
      for (final exercise in session.exercises) {
        if (exercise.id.startsWith('seed_') ||
            exercise.template.id != templateId) {
          continue;
        }
        result.addAll(
          exercise.sets.where(
            (set) => !identical(set, excludedSet) && _isProgressionSet(set),
          ),
        );
      }
    }
    return result;
  }

  static bool _isE1rmSet(WorkoutSetEntry set) =>
      set.completed &&
      set.type == '일반' &&
      set.weight > 0 &&
      set.reps > 0 &&
      set.reps <= 10;

  static bool _isProgressionSet(WorkoutSetEntry set) =>
      set.completed && set.type == '일반' && set.weight > 0 && set.reps > 0;

  static bool _missedLowerBound(List<WorkoutSetEntry> sets, int minReps) {
    if (sets.length < 2) return false;
    return sets.where((set) => set.reps < minReps).length >= 2;
  }

  static bool _meetsUpperTarget(
    List<WorkoutSetEntry> sets, {
    required int targetSets,
    required int maxReps,
  }) => sets.length >= targetSets && sets.every((set) => set.reps >= maxReps);

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
