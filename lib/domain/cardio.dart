/// Cardio is recorded as elapsed work and modality-specific output, never as
/// resistance-training weight x repetitions. The persistence/UI layers can use
/// [CardioExerciseDefinition.metrics] to render only meaningful fields.
enum CardioMetric {
  duration,
  distance,
  pace,
  speed,
  incline,
  resistance,
  power,
  heartRate,
  perceivedExertion,
  cadence,
  strokeRate,
  elevationGain,
  floors,
  jumpCount,
}

extension CardioMetricLabel on CardioMetric {
  String get label => switch (this) {
    CardioMetric.duration => '시간',
    CardioMetric.distance => '거리',
    CardioMetric.pace => '페이스',
    CardioMetric.speed => '속도',
    CardioMetric.incline => '경사',
    CardioMetric.resistance => '저항',
    CardioMetric.power => '파워',
    CardioMetric.heartRate => '심박수',
    CardioMetric.perceivedExertion => '운동자각도',
    CardioMetric.cadence => '케이던스',
    CardioMetric.strokeRate => '스트로크',
    CardioMetric.elevationGain => '상승고도',
    CardioMetric.floors => '층수',
    CardioMetric.jumpCount => '점프 수',
  };
}

enum CardioModality {
  treadmillRunning,
  outdoorRunning,
  briskWalking,
  stationaryCycling,
  outdoorCycling,
  stairClimber,
  rowingErgometer,
  elliptical,
  jumpRope,
}

enum CardioIntensity { moderate, vigorous }

enum CardioSessionStructure { continuous, intervals }

enum CardioExperience { beginner, regular, advanced }

class CardioExerciseDefinition {
  const CardioExerciseDefinition({
    required this.exerciseId,
    required this.modality,
    required this.primaryMetrics,
    required this.optionalMetrics,
  });

  final String exerciseId;
  final CardioModality modality;
  final List<CardioMetric> primaryMetrics;
  final List<CardioMetric> optionalMetrics;

  Set<CardioMetric> get metrics => {...primaryMetrics, ...optionalMetrics};
}

/// Setflow catalog ids plus forward-compatible outdoor ids.
const cardioExerciseDefinitions = <String, CardioExerciseDefinition>{
  'run': CardioExerciseDefinition(
    exerciseId: 'run',
    modality: CardioModality.treadmillRunning,
    primaryMetrics: [
      CardioMetric.duration,
      CardioMetric.distance,
      CardioMetric.pace,
    ],
    optionalMetrics: [
      CardioMetric.speed,
      CardioMetric.incline,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'outdoor_run': CardioExerciseDefinition(
    exerciseId: 'outdoor_run',
    modality: CardioModality.outdoorRunning,
    primaryMetrics: [
      CardioMetric.duration,
      CardioMetric.distance,
      CardioMetric.pace,
    ],
    optionalMetrics: [
      CardioMetric.speed,
      CardioMetric.elevationGain,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'brisk_walk': CardioExerciseDefinition(
    exerciseId: 'brisk_walk',
    modality: CardioModality.briskWalking,
    primaryMetrics: [
      CardioMetric.duration,
      CardioMetric.distance,
      CardioMetric.pace,
    ],
    optionalMetrics: [
      CardioMetric.speed,
      CardioMetric.incline,
      CardioMetric.elevationGain,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'stationary_bike': CardioExerciseDefinition(
    exerciseId: 'stationary_bike',
    modality: CardioModality.stationaryCycling,
    primaryMetrics: [CardioMetric.duration],
    optionalMetrics: [
      CardioMetric.distance,
      CardioMetric.speed,
      CardioMetric.resistance,
      CardioMetric.power,
      CardioMetric.cadence,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'outdoor_bike': CardioExerciseDefinition(
    exerciseId: 'outdoor_bike',
    modality: CardioModality.outdoorCycling,
    primaryMetrics: [CardioMetric.duration, CardioMetric.distance],
    optionalMetrics: [
      CardioMetric.speed,
      CardioMetric.elevationGain,
      CardioMetric.power,
      CardioMetric.cadence,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'stair_climber': CardioExerciseDefinition(
    exerciseId: 'stair_climber',
    modality: CardioModality.stairClimber,
    primaryMetrics: [CardioMetric.duration, CardioMetric.floors],
    optionalMetrics: [
      CardioMetric.elevationGain,
      CardioMetric.speed,
      CardioMetric.resistance,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'rowing_machine': CardioExerciseDefinition(
    exerciseId: 'rowing_machine',
    modality: CardioModality.rowingErgometer,
    primaryMetrics: [
      CardioMetric.duration,
      CardioMetric.distance,
      CardioMetric.pace,
    ],
    optionalMetrics: [
      CardioMetric.power,
      CardioMetric.resistance,
      CardioMetric.strokeRate,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'elliptical': CardioExerciseDefinition(
    exerciseId: 'elliptical',
    modality: CardioModality.elliptical,
    primaryMetrics: [CardioMetric.duration],
    optionalMetrics: [
      CardioMetric.distance,
      CardioMetric.speed,
      CardioMetric.incline,
      CardioMetric.resistance,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
  'jump_rope': CardioExerciseDefinition(
    exerciseId: 'jump_rope',
    modality: CardioModality.jumpRope,
    primaryMetrics: [CardioMetric.duration, CardioMetric.jumpCount],
    optionalMetrics: [
      CardioMetric.cadence,
      CardioMetric.heartRate,
      CardioMetric.perceivedExertion,
    ],
  ),
};

CardioExerciseDefinition? cardioDefinitionForExercise(String exerciseId) =>
    cardioExerciseDefinitions[exerciseId];

bool isCardioExerciseId(String exerciseId) =>
    cardioExerciseDefinitions.containsKey(exerciseId);

/// Persistence-friendly cardio record. Machine-specific values are optional
/// because not every device exposes distance, watts, resistance, or heart rate.
class CardioSessionRecord {
  const CardioSessionRecord({
    required this.id,
    required this.exerciseId,
    required this.occurredAt,
    required this.duration,
    required this.intensity,
    this.distanceKm,
    this.averageSpeedKph,
    this.inclinePercent,
    this.resistanceLevel,
    this.averagePowerWatts,
    this.averageHeartRateBpm,
    this.maxHeartRateBpm,
    this.perceivedExertion,
    this.cadenceRpm,
    this.strokeRateSpm,
    this.elevationGainMeters,
    this.floors,
    this.jumpCount,
  });

  final String id;
  final String exerciseId;
  final DateTime occurredAt;
  final Duration duration;
  final CardioIntensity intensity;
  final double? distanceKm;
  final double? averageSpeedKph;
  final double? inclinePercent;
  final double? resistanceLevel;
  final double? averagePowerWatts;
  final int? averageHeartRateBpm;
  final int? maxHeartRateBpm;
  final double? perceivedExertion;
  final double? cadenceRpm;
  final double? strokeRateSpm;
  final double? elevationGainMeters;
  final int? floors;
  final int? jumpCount;

  double? get derivedAverageSpeedKph {
    if (averageSpeedKph case final speed? when speed > 0) return speed;
    if (distanceKm case final distance?
        when distance > 0 && duration.inSeconds > 0) {
      return distance / (duration.inSeconds / Duration.secondsPerHour);
    }
    return null;
  }

  /// Running/walking pace in seconds per kilometre.
  double? get paceSecondsPerKm {
    if (distanceKm case final distance?
        when distance > 0 && duration.inSeconds > 0) {
      return duration.inSeconds / distance;
    }
    return null;
  }

  /// Standard rowing split in seconds per 500 metres.
  double? get rowingPaceSecondsPer500m {
    if (distanceKm case final distance?
        when distance > 0 && duration.inSeconds > 0) {
      return duration.inSeconds / (distance * 2);
    }
    return null;
  }

  List<String> validate() {
    final issues = <String>[];
    if (id.trim().isEmpty) issues.add('id');
    if (!isCardioExerciseId(exerciseId)) issues.add('exerciseId');
    if (duration.inSeconds <= 0 || duration > const Duration(hours: 24)) {
      issues.add('duration');
    }
    _positiveOrNull(distanceKm, 'distanceKm', issues);
    _positiveOrNull(averageSpeedKph, 'averageSpeedKph', issues);
    if (inclinePercent != null &&
        (inclinePercent! < -10 || inclinePercent! > 50)) {
      issues.add('inclinePercent');
    }
    _nonNegativeOrNull(resistanceLevel, 'resistanceLevel', issues);
    _positiveOrNull(averagePowerWatts, 'averagePowerWatts', issues);
    if (averageHeartRateBpm != null &&
        (averageHeartRateBpm! < 30 || averageHeartRateBpm! > 250)) {
      issues.add('averageHeartRateBpm');
    }
    if (maxHeartRateBpm != null &&
        (maxHeartRateBpm! < 30 || maxHeartRateBpm! > 250)) {
      issues.add('maxHeartRateBpm');
    }
    if (averageHeartRateBpm != null &&
        maxHeartRateBpm != null &&
        averageHeartRateBpm! > maxHeartRateBpm!) {
      issues.add('heartRateOrder');
    }
    if (perceivedExertion != null &&
        (perceivedExertion! < 0 || perceivedExertion! > 10)) {
      issues.add('perceivedExertion');
    }
    _positiveOrNull(cadenceRpm, 'cadenceRpm', issues);
    _positiveOrNull(strokeRateSpm, 'strokeRateSpm', issues);
    _nonNegativeOrNull(elevationGainMeters, 'elevationGainMeters', issues);
    if (floors != null && floors! < 0) issues.add('floors');
    if (jumpCount != null && jumpCount! < 0) issues.add('jumpCount');
    return issues;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'exerciseId': exerciseId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'intensity': intensity.name,
    'distanceKm': distanceKm,
    'averageSpeedKph': averageSpeedKph,
    'inclinePercent': inclinePercent,
    'resistanceLevel': resistanceLevel,
    'averagePowerWatts': averagePowerWatts,
    'averageHeartRateBpm': averageHeartRateBpm,
    'maxHeartRateBpm': maxHeartRateBpm,
    'perceivedExertion': perceivedExertion,
    'cadenceRpm': cadenceRpm,
    'strokeRateSpm': strokeRateSpm,
    'elevationGainMeters': elevationGainMeters,
    'floors': floors,
    'jumpCount': jumpCount,
  };

  static void _positiveOrNull(
    double? value,
    String field,
    List<String> issues,
  ) {
    if (value != null && (!value.isFinite || value <= 0)) issues.add(field);
  }

  static void _nonNegativeOrNull(
    double? value,
    String field,
    List<String> issues,
  ) {
    if (value != null && (!value.isFinite || value < 0)) issues.add(field);
  }
}
