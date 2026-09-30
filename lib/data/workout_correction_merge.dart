import 'dart:convert';

import '../models.dart';

/// Apply only server corrections this device has not acknowledged. Unrelated
/// local sets and metrics survive a snapshot conflict. Once acknowledged, the
/// member can edit that metric normally again.
bool applyUnseenWorkoutCorrections(
  WorkoutSession local,
  WorkoutSession remote,
) {
  var changed = false;
  for (final entry in remote.correctionVersions.entries) {
    if (local.correctionVersions[entry.key] == entry.value) continue;
    final path = jsonDecode(entry.key) as List;
    final exercise = local.exercises.where((e) => e.id == path[0]).firstOrNull;
    final remoteExercise = remote.exercises
        .where((e) => e.id == path[0])
        .firstOrNull;
    final set = exercise?.sets.where((s) => s.number == path[1]).firstOrNull;
    final corrected = remoteExercise?.sets
        .where((s) => s.number == path[1])
        .firstOrNull;
    if (set != null && corrected != null) {
      switch (path[2]) {
        case 'weight':
          set.weight = corrected.weight;
        case 'reps':
          set.reps = corrected.reps;
        case 'restSeconds':
          set.restSeconds = corrected.restSeconds;
        case 'durationSeconds':
          set.durationSeconds = corrected.durationSeconds;
        case 'distanceKm':
          set.distanceKm = corrected.distanceKm;
        case 'intensityRpe':
          set.intensityRpe = corrected.intensityRpe;
        case 'rir':
          set.rir = corrected.rir;
      }
    }
    local.correctionVersions[entry.key] = entry.value;
    changed = true;
  }
  return changed;
}

void applyWorkoutMetricCorrection(
  WorkoutSetEntry set,
  String metric,
  double value,
) {
  switch (metric) {
    case 'weight':
      set.weight = value;
    case 'reps':
      set.reps = value.toInt();
    case 'restSeconds':
      set.restSeconds = value.toInt();
    case 'durationSeconds':
      set.durationSeconds = value.toInt();
    case 'distanceKm':
      set.distanceKm = value;
    case 'intensityRpe':
      set.intensityRpe = value;
    case 'rir':
      set.rir = value.toInt();
  }
}
