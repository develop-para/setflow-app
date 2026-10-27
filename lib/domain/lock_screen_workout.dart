import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models.dart';

class LockScreenWorkoutStatus {
  const LockScreenWorkoutStatus({
    required this.supported,
    required this.enabled,
    required this.notificationsAllowed,
    this.ownerKey,
    this.workoutDate,
    this.sessionId,
  });

  static const unsupported = LockScreenWorkoutStatus(
    supported: false,
    enabled: false,
    notificationsAllowed: false,
  );

  final bool supported, enabled, notificationsAllowed;
  final String? ownerKey, workoutDate, sessionId;

  factory LockScreenWorkoutStatus.fromJson(Map<String, Object?> json) =>
      LockScreenWorkoutStatus(
        supported: json['supported'] == true,
        enabled: json['enabled'] == true,
        notificationsAllowed: json['notificationsAllowed'] == true,
        ownerKey: json['ownerKey'] as String?,
        workoutDate: json['workoutDate'] as String?,
        sessionId: json['sessionId'] as String?,
      );
}

String lockScreenWorkoutDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The values visibly confirmed by one lock-screen tap. The native journal
/// retains this whole object before advancing, even when Flutter is absent.
class LockScreenWorkoutSet {
  const LockScreenWorkoutSet({
    required this.exerciseEntryId,
    required this.templateId,
    required this.exerciseName,
    required this.setNumber,
    required this.setTotal,
    required this.measurement,
    required this.valuesLabel,
    required this.weight,
    required this.reps,
    required this.durationSeconds,
    required this.distanceKm,
    required this.intensityRpe,
    required this.restSeconds,
    required this.type,
    required this.fingerprint,
    required this.canComplete,
    this.rir,
  });

  factory LockScreenWorkoutSet.fromExercise({
    required String ownerKey,
    required DateTime date,
    required WorkoutExercise exercise,
    required WorkoutSetEntry set,
    required String unit,
  }) {
    final template = exercise.template;
    final measurement = template.isCardio
        ? 'cardio'
        : template.measurement.name;
    final ready = switch (measurement) {
      'repsOnly' => set.reps > 0,
      'duration' || 'cardio' => set.durationSeconds > 0,
      _ => set.weight.isFinite && set.weight > 0 && set.reps > 0,
    };
    String number(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    final valuesLabel = switch (measurement) {
      'repsOnly' => '${set.reps}회',
      'duration' => '${set.durationSeconds}초',
      'cardio' =>
        '${set.durationSeconds ~/ 60}분'
            '${set.distanceKm > 0 ? ' · ${number(set.distanceKm)}km' : ''}'
            '${set.intensityRpe > 0 ? ' · RPE ${number(set.intensityRpe)}' : ''}',
      _ => '${number(set.weight)}$unit × ${set.reps}회',
    };
    final fingerprint = lockScreenSetFingerprint(
      ownerKey: ownerKey,
      workoutDate: lockScreenWorkoutDateKey(date),
      exerciseEntryId: exercise.id,
      templateId: template.id,
      setNumber: set.number,
      measurement: measurement,
      weight: set.weight,
      reps: set.reps,
      durationSeconds: set.durationSeconds,
      distanceKm: set.distanceKm,
      intensityRpe: set.intensityRpe,
      restSeconds: set.restSeconds,
      type: set.type,
      rir: set.rir,
    );
    return LockScreenWorkoutSet(
      exerciseEntryId: exercise.id,
      templateId: template.id,
      exerciseName: template.name,
      setNumber: set.number,
      setTotal: exercise.sets.length,
      measurement: measurement,
      valuesLabel: ready ? valuesLabel : '앱에서 운동 값을 입력해주세요',
      weight: set.weight,
      reps: set.reps,
      durationSeconds: set.durationSeconds,
      distanceKm: set.distanceKm,
      intensityRpe: set.intensityRpe,
      restSeconds: set.restSeconds,
      type: set.type,
      rir: set.rir,
      fingerprint: fingerprint,
      canComplete: ready,
    );
  }

  final String exerciseEntryId, templateId, exerciseName;
  final int setNumber, setTotal, reps, durationSeconds, restSeconds;
  final double weight, distanceKm, intensityRpe;
  final String measurement, valuesLabel, type, fingerprint;
  final bool canComplete;
  final int? rir;

  Map<String, Object?> toJson() => {
    'token': fingerprint,
    'exerciseEntryId': exerciseEntryId,
    'templateId': templateId,
    'exerciseName': exerciseName,
    'setNumber': setNumber,
    'setTotal': setTotal,
    'measurement': measurement,
    'valuesLabel': valuesLabel,
    'weight': weight,
    'reps': reps,
    'durationSeconds': durationSeconds,
    'distanceKm': distanceKm,
    'intensityRpe': intensityRpe,
    'restSeconds': restSeconds,
    'type': type,
    'rir': rir,
    'fingerprint': fingerprint,
    'canComplete': canComplete,
  };
}

/// Completed flags and display labels do not participate: replaying a receipt
/// must still match after completion or a harmless catalog-label refresh.
String lockScreenSetFingerprint({
  required String ownerKey,
  required String workoutDate,
  required String exerciseEntryId,
  required String templateId,
  required int setNumber,
  required String measurement,
  required double weight,
  required int reps,
  required int durationSeconds,
  required double distanceKm,
  required double intensityRpe,
  required int restSeconds,
  required String type,
  int? rir,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          ownerKey,
          workoutDate,
          exerciseEntryId,
          templateId,
          setNumber,
          measurement,
          weight,
          reps,
          durationSeconds,
          distanceKm,
          intensityRpe,
          restSeconds,
          type,
          rir,
        ]),
      ),
    )
    .toString();

class LockScreenWorkoutEvent {
  const LockScreenWorkoutEvent({
    required this.eventId,
    required this.sessionId,
    required this.ownerKey,
    required this.workoutDate,
    required this.publishedAtMillis,
    required this.expiresAtMillis,
    required this.completedAtMillis,
    required this.set,
    this.restEndsAtMillis,
  });

  final String eventId, sessionId, ownerKey, workoutDate;
  final int publishedAtMillis, expiresAtMillis, completedAtMillis;
  final int? restEndsAtMillis;
  final Map<String, Object?> set;

  static LockScreenWorkoutEvent? tryFromJson(Map<String, Object?> json) {
    final rawSet = json['set'];
    if (rawSet is! Map) return null;
    final eventId = json['eventId'];
    final sessionId = json['sessionId'];
    final ownerKey = json['ownerKey'];
    final workoutDate = json['workoutDate'];
    final published = json['publishedAtMillis'];
    final expires = json['expiresAtMillis'];
    final completed = json['completedAtMillis'];
    if (eventId is! String ||
        eventId.isEmpty ||
        eventId.length > 200 ||
        sessionId is! String ||
        sessionId.isEmpty ||
        ownerKey is! String ||
        ownerKey.isEmpty ||
        workoutDate is! String ||
        published is! num ||
        expires is! num ||
        completed is! num) {
      return null;
    }
    return LockScreenWorkoutEvent(
      eventId: eventId,
      sessionId: sessionId,
      ownerKey: ownerKey,
      workoutDate: workoutDate,
      publishedAtMillis: published.toInt(),
      expiresAtMillis: expires.toInt(),
      completedAtMillis: completed.toInt(),
      restEndsAtMillis: (json['restEndsAtMillis'] as num?)?.toInt(),
      set: Map<String, Object?>.from(rawSet),
    );
  }

  DateTime? get validDate {
    final date = DateTime.tryParse(workoutDate);
    if (date == null || lockScreenWorkoutDateKey(date) != workoutDate) {
      return null;
    }
    return DateTime(date.year, date.month, date.day);
  }

  bool hasValidCompletionTime(DateTime now) {
    final date = validDate;
    final completed = DateTime.fromMillisecondsSinceEpoch(completedAtMillis);
    return date != null &&
        publishedAtMillis <= completedAtMillis &&
        completedAtMillis < expiresAtMillis &&
        expiresAtMillis - publishedAtMillis <=
            const Duration(days: 1).inMilliseconds &&
        completedAtMillis <=
            now.add(const Duration(minutes: 5)).millisecondsSinceEpoch &&
        lockScreenWorkoutDateKey(completed) == workoutDate;
  }

  bool matches(LockScreenWorkoutSet current) {
    if (set['token'] != current.fingerprint ||
        set['fingerprint'] != current.fingerprint ||
        set['canComplete'] != true ||
        !current.canComplete) {
      return false;
    }
    final expected = current.toJson();
    for (final key in const [
      'exerciseEntryId',
      'templateId',
      'setNumber',
      'measurement',
      'weight',
      'reps',
      'durationSeconds',
      'distanceKm',
      'intensityRpe',
      'restSeconds',
      'type',
      'rir',
    ]) {
      if (set[key] != expected[key]) return false;
    }
    return true;
  }
}

class LockScreenWorkoutReconciliation {
  const LockScreenWorkoutReconciliation({
    this.applied = 0,
    this.alreadyApplied = 0,
    this.conflicts = 0,
    this.otherOwners = 0,
  });

  final int applied, alreadyApplied, conflicts, otherOwners;
  bool get hasConflicts => conflicts > 0;
}
