import '../domain/cardio.dart';
import 'performance_engine.dart';

abstract final class CardioEvidenceIds {
  /// Bull et al. (2020), DOI 10.1136/bjsports-2020-102955.
  static const whoPhysicalActivity2020 = 'who_bull_2020_pa_guideline';

  /// Garber et al. / ACSM (2011), DOI 10.1249/MSS.0b013e318213fefb.
  static const acsmExercisePrescription2011 = 'acsm_garber_2011_prescription';

  /// Jakicic et al. / ACSM (2024), DOI 10.1249/MSS.0000000000003520.
  static const acsmAdiposity2024 = 'acsm_jakicic_2024_adiposity';

  /// Helgerud et al. (2007), DOI 10.1249/mss.0b013e3180304570.
  static const aerobicIntervals2007 = 'helgerud_2007_4x4';

  /// Schumann et al. (2022), DOI 10.1007/s40279-021-01587-7.
  static const concurrentTraining2022 = 'schumann_2022_concurrent';
}

class HeartRateTarget {
  const HeartRateTarget({
    required this.minimumBpm,
    required this.maximumBpm,
    required this.method,
  });

  final int minimumBpm;
  final int maximumBpm;
  final String method;
}

class CardioPrescription {
  const CardioPrescription({
    required this.definition,
    required this.goal,
    required this.structure,
    required this.sessionDuration,
    required this.intensity,
    required this.minimumRpe,
    required this.maximumRpe,
    required this.weeklyTargetModerateEquivalentMinutes,
    required this.completedModerateEquivalentMinutes,
    required this.metrics,
    required this.evidenceIds,
    required this.reason,
    required this.safetyNote,
    this.targetDistanceKm,
    this.targetHeartRate,
    this.workBouts,
    this.workBoutDuration,
    this.recoveryBoutDuration,
  });

  final CardioExerciseDefinition definition;
  final TrainingGoal goal;
  final CardioSessionStructure structure;
  final Duration sessionDuration;
  final CardioIntensity intensity;
  final int minimumRpe;
  final int maximumRpe;
  final int weeklyTargetModerateEquivalentMinutes;
  final int completedModerateEquivalentMinutes;
  final List<CardioMetric> metrics;
  final Set<String> evidenceIds;
  final String reason;
  final String safetyNote;
  final double? targetDistanceKm;
  final HeartRateTarget? targetHeartRate;
  final int? workBouts;
  final Duration? workBoutDuration;
  final Duration? recoveryBoutDuration;

  int get durationSeconds => sessionDuration.inSeconds;
  int get durationMinutes => sessionDuration.inMinutes;
  int get targetRpeMin => minimumRpe;
  int get targetRpeMax => maximumRpe;
  String get intensityLabel => switch (intensity) {
    CardioIntensity.moderate => '중강도',
    CardioIntensity.vigorous => '고강도',
  };
  Set<String> get sourceIds => evidenceIds;
  bool get supportsDistance =>
      definition.metrics.contains(CardioMetric.distance);

  int get remainingModerateEquivalentMinutes {
    final remaining =
        weeklyTargetModerateEquivalentMinutes -
        completedModerateEquivalentMinutes;
    return remaining > 0 ? remaining : 0;
  }

  bool get weeklyMinimumReached => remainingModerateEquivalentMinutes == 0;
}

/// Evidence-bounded cardio prescription for apparently healthy adults.
///
/// The engine intentionally does not predict HRmax from age: prediction error
/// is too large for an individual target. It provides an HR target only when a
/// measured/known maximum is supplied (and resting HR for HRR prescriptions).
/// Moderate continuous work is the safe default. The narrow 4 x 4 protocol is
/// gated to advanced users with explicit vigorous-exercise eligibility and a
/// recent training base because the source RCT studied trained healthy adults.
abstract final class CardioPrescriptionEngine {
  static const int adultWeeklyMinimumMinutes = 150;

  static CardioPrescription? recommend({
    required String exerciseId,
    required TrainingGoal goal,
    required Iterable<CardioSessionRecord> history,
    DateTime? now,
    CardioExperience experience = CardioExperience.beginner,
    bool vigorousExerciseEligible = false,
    int? measuredMaxHeartRateBpm,
    int? restingHeartRateBpm,
  }) {
    final definition = cardioDefinitionForExercise(exerciseId);
    if (definition == null) return null;
    final referenceTime = now ?? DateTime.now();
    final usableHistory = history
        .where((record) => record.validate().isEmpty)
        .toList();
    final completedMinutes = weeklyModerateEquivalentMinutes(
      usableHistory,
      now: referenceTime,
    );
    final intervalEligible =
        goal == TrainingGoal.endurance &&
        experience == CardioExperience.advanced &&
        vigorousExerciseEligible &&
        _recentTrainingBase(usableHistory, referenceTime) >= 6;

    if (intervalEligible) {
      final target = _percentMaxHeartRateTarget(
        measuredMaxHeartRateBpm,
        .90,
        .95,
      );
      return CardioPrescription(
        definition: definition,
        goal: goal,
        structure: CardioSessionStructure.intervals,
        // 10 min warm-up + 4 x 4 min work + 3 x 3 min active recovery +
        // 5 min cool-down = 40 min total.
        sessionDuration: const Duration(minutes: 40),
        intensity: CardioIntensity.vigorous,
        minimumRpe: 7,
        maximumRpe: 9,
        weeklyTargetModerateEquivalentMinutes: adultWeeklyMinimumMinutes,
        completedModerateEquivalentMinutes: completedMinutes,
        metrics: definition.metrics.toList(growable: false),
        evidenceIds: const {
          CardioEvidenceIds.whoPhysicalActivity2020,
          CardioEvidenceIds.acsmExercisePrescription2011,
          CardioEvidenceIds.aerobicIntervals2007,
        },
        reason: '최근 유산소 기반이 있는 숙련자의 체력 향상 목표에 맞춰 4분 고강도와 3분 회복을 4회 반복합니다.',
        safetyNote:
            '고강도 운동이 가능한 상태에서만 사용하고, 통증·흉부 불편·비정상적인 숨참이나 어지럼이 있으면 중단하세요.',
        targetHeartRate: target,
        workBouts: 4,
        workBoutDuration: const Duration(minutes: 4),
        recoveryBoutDuration: const Duration(minutes: 3),
      );
    }

    final sessionMinutes = switch (goal) {
      TrainingGoal.fatLoss => 40,
      TrainingGoal.strength ||
      TrainingGoal.hypertrophy ||
      TrainingGoal.endurance ||
      TrainingGoal.health => 30,
    };
    final evidenceIds = <String>{
      CardioEvidenceIds.whoPhysicalActivity2020,
      CardioEvidenceIds.acsmExercisePrescription2011,
    };
    if (goal == TrainingGoal.fatLoss) {
      evidenceIds.add(CardioEvidenceIds.acsmAdiposity2024);
    }
    if (goal == TrainingGoal.strength || goal == TrainingGoal.hypertrophy) {
      evidenceIds.add(CardioEvidenceIds.concurrentTraining2022);
    }
    final duration = Duration(minutes: sessionMinutes);
    return CardioPrescription(
      definition: definition,
      goal: goal,
      structure: CardioSessionStructure.continuous,
      sessionDuration: duration,
      intensity: CardioIntensity.moderate,
      minimumRpe: 3,
      maximumRpe: 4,
      weeklyTargetModerateEquivalentMinutes: adultWeeklyMinimumMinutes,
      completedModerateEquivalentMinutes: completedMinutes,
      metrics: definition.metrics.toList(growable: false),
      evidenceIds: evidenceIds,
      reason: _continuousReason(goal),
      safetyNote: _continuousSafetyNote(goal),
      targetDistanceKm: _distanceAtRecentMedianSpeed(
        exerciseId: exerciseId,
        history: usableHistory.where(
          (record) => !record.occurredAt.isAfter(referenceTime),
        ),
        duration: duration,
      ),
      targetHeartRate: _heartRateReserveTarget(
        measuredMaxHeartRateBpm,
        restingHeartRateBpm,
        .40,
        .59,
      ),
    );
  }

  /// Vigorous minutes count double when combining the WHO moderate/vigorous
  /// weekly targets (150 moderate or 75 vigorous minutes).
  static int weeklyModerateEquivalentMinutes(
    Iterable<CardioSessionRecord> history, {
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();
    final local = referenceTime.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final weekStart = day.subtract(Duration(days: day.weekday - 1));
    final nextWeek = weekStart.add(const Duration(days: 7));
    var seconds = 0;
    for (final record in history) {
      if (record.validate().isNotEmpty) continue;
      if (record.perceivedExertion case final rpe? when rpe < 3) continue;
      final occurred = record.occurredAt.toLocal();
      if (occurred.isBefore(weekStart) || !occurred.isBefore(nextWeek)) {
        continue;
      }
      if (occurred.isAfter(referenceTime.toLocal())) continue;
      final multiplier = record.intensity == CardioIntensity.vigorous ? 2 : 1;
      seconds += record.duration.inSeconds * multiplier;
    }
    return seconds ~/ Duration.secondsPerMinute;
  }

  static HeartRateTarget? _heartRateReserveTarget(
    int? maximum,
    int? resting,
    double lowerFraction,
    double upperFraction,
  ) {
    if (!_validHeartRates(maximum, resting)) return null;
    final reserve = maximum! - resting!;
    return HeartRateTarget(
      minimumBpm: (resting + reserve * lowerFraction).round(),
      maximumBpm: (resting + reserve * upperFraction).round(),
      method: 'HRR',
    );
  }

  static HeartRateTarget? _percentMaxHeartRateTarget(
    int? maximum,
    double lowerFraction,
    double upperFraction,
  ) {
    if (maximum == null || maximum < 100 || maximum > 250) return null;
    return HeartRateTarget(
      minimumBpm: (maximum * lowerFraction).round(),
      maximumBpm: (maximum * upperFraction).round(),
      method: '%HRmax',
    );
  }

  static bool _validHeartRates(int? maximum, int? resting) =>
      maximum != null &&
      resting != null &&
      maximum >= 100 &&
      maximum <= 250 &&
      resting >= 30 &&
      resting < maximum;

  static int _recentTrainingBase(
    Iterable<CardioSessionRecord> history,
    DateTime now,
  ) {
    final cutoff = now.subtract(const Duration(days: 28));
    return history
        .where(
          (record) =>
              !record.occurredAt.isBefore(cutoff) &&
              !record.occurredAt.isAfter(now) &&
              (record.perceivedExertion == null ||
                  record.perceivedExertion! >= 3) &&
              record.duration >= const Duration(minutes: 20),
        )
        .length;
  }

  static double? _distanceAtRecentMedianSpeed({
    required String exerciseId,
    required Iterable<CardioSessionRecord> history,
    required Duration duration,
  }) {
    final matching =
        history
            .where(
              (record) =>
                  record.exerciseId == exerciseId &&
                  (record.perceivedExertion == null ||
                      record.perceivedExertion! >= 3) &&
                  record.derivedAverageSpeedKph != null &&
                  record.derivedAverageSpeedKph! > 0 &&
                  record.derivedAverageSpeedKph! <= 80,
            )
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (matching.isEmpty) return null;
    final recent =
        matching
            .take(5)
            .map((record) => record.derivedAverageSpeedKph!)
            .toList()
          ..sort();
    final middle = recent.length ~/ 2;
    final median = recent.length.isOdd
        ? recent[middle]
        : (recent[middle - 1] + recent[middle]) / 2;
    final distance = median * duration.inSeconds / Duration.secondsPerHour;
    return (distance * 10).round() / 10;
  }

  static String _continuousReason(TrainingGoal goal) => switch (goal) {
    TrainingGoal.strength => '근력 운동과 병행 가능한 중강도 유산소로 주간 심폐 활동량을 채웁니다.',
    TrainingGoal.hypertrophy => '근비대 운동과 병행 가능한 중강도 유산소로 주간 심폐 활동량을 채웁니다.',
    TrainingGoal.fatLoss =>
      '체중·체지방 관리를 위한 활동량은 최소 주 150분부터 용량-반응 관계가 있어 40분 중강도로 구성했습니다.',
    TrainingGoal.endurance => '고강도 조건이 확인되기 전에는 중강도 지속 운동으로 안전하게 유산소 기반을 만듭니다.',
    TrainingGoal.health => '일반 건강 권고의 주 150분 중강도 목표를 향해 30분 지속 운동으로 구성했습니다.',
  };

  static String _continuousSafetyNote(TrainingGoal goal) {
    const common =
        '처음에는 편안하게 시작해 점진적으로 늘리고, 통증·흉부 불편·비정상적인 숨참이나 어지럼이 있으면 중단하세요.';
    if (goal == TrainingGoal.strength || goal == TrainingGoal.hypertrophy) {
      return '$common 폭발력 향상이 최우선이면 유산소와 근력 세션을 가능하면 3시간 이상 분리하세요.';
    }
    return common;
  }
}
