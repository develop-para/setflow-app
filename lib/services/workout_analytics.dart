import 'dart:math' as math;

import '../models.dart';
import 'performance_engine.dart';

enum WorkoutStatsPeriod {
  all('전체 기간'),
  week('이번 주'),
  month('30일'),
  quarter('90일');

  const WorkoutStatsPeriod(this.label);
  final String label;

  DateTime? start(DateTime today) => switch (this) {
    all => null,
    week => DateTime(today.year, today.month, today.day - today.weekday + 1),
    month => DateTime(today.year, today.month, today.day - 29),
    quarter => DateTime(today.year, today.month, today.day - 89),
  };
}

enum ExerciseKpi {
  weight('최고 중량'),
  estimatedMax('추정 1RM'),
  volume('근력 볼륨'),
  reps('최고 반복'),
  duration('운동 시간'),
  distance('이동 거리');

  const ExerciseKpi(this.label);
  final String label;
}

/// A day's actual completed sets, including warmups. Estimates alone use
/// normal sets of 1–10 reps, matching the app's performance policy.
class ExerciseDayStats {
  ExerciseDayStats({
    required this.date,
    required this.template,
    required List<WorkoutSetEntry> sets,
    required this.formula,
  }) : sets = List.unmodifiable(sets);

  final DateTime date;
  final ExerciseTemplate template;
  final List<WorkoutSetEntry> sets;
  final OneRepMaxFormula formula;

  int get completedSets => sets.length;
  int get reps => template.isCardio || template.isDurationHold
      ? 0
      : sets.fold(0, (sum, set) => sum + math.max(0, set.reps));
  double get volume => !template.usesWeight
      ? 0
      : sets.fold(
          0,
          (sum, set) => sum + _positive(set.weight) * math.max(0, set.reps),
        );
  int get durationSeconds => !template.isCardio && !template.isDurationHold
      ? 0
      : sets.fold(0, (sum, set) => sum + math.max(0, set.durationSeconds));
  double get distanceKm => !template.isCardio
      ? 0
      : sets.fold(0, (sum, set) => sum + _positive(set.distanceKm));

  double? value(ExerciseKpi metric) => switch (metric) {
    ExerciseKpi.weight =>
      template.usesWeight
          ? _maximum(sets.map((set) => _positive(set.weight)))
          : null,
    ExerciseKpi.estimatedMax =>
      !template.usesWeight
          ? null
          : _maximum(
              sets
                  .where(
                    (set) =>
                        workoutSetTypeLabel(set.type) == '일반' &&
                        set.reps >= 1 &&
                        set.reps <= 10 &&
                        set.weight.isFinite &&
                        set.weight > 0,
                  )
                  .map(
                    (set) => PerformanceEngine.estimate(
                      set.weight,
                      set.reps,
                      formula: formula,
                    )!.value,
                  ),
            ),
    ExerciseKpi.volume => template.usesWeight ? volume : null,
    ExerciseKpi.reps =>
      !template.isCardio && !template.isDurationHold
          ? _maximum(sets.map((set) => math.max(0, set.reps).toDouble()))
          : null,
    ExerciseKpi.duration =>
      template.isCardio
          ? durationSeconds.toDouble()
          : template.isDurationHold
          ? _maximum(
              sets.map((set) => math.max(0, set.durationSeconds).toDouble()),
            )
          : null,
    ExerciseKpi.distance => template.isCardio ? distanceKm : null,
  };
}

class ExerciseKpiSummary {
  ExerciseKpiSummary({
    required this.template,
    required List<ExerciseDayStats> days,
  }) : days = List.unmodifiable(days);

  final ExerciseTemplate template;

  /// Chronological, with repeat appearances of a template on a day merged.
  final List<ExerciseDayStats> days;

  int get workoutDays => days.length;
  DateTime get lastDate => days.last.date;
  int get completedSets => days.fold(0, (sum, day) => sum + day.completedSets);
  int get totalReps => days.fold(0, (sum, day) => sum + day.reps);
  double get totalVolume => days.fold(0, (sum, day) => sum + day.volume);
  int get durationSeconds =>
      days.fold(0, (sum, day) => sum + day.durationSeconds);
  double get distanceKm => days.fold(0, (sum, day) => sum + day.distanceKm);

  double? best(ExerciseKpi metric) =>
      _maximum(days.map((day) => day.value(metric)).whereType<double>());

  double? get averageRpe {
    if (!template.isCardio) return null;
    final values = days
        .expand((day) => day.sets)
        .map((set) => set.intensityRpe)
        .where((value) => value.isFinite && value >= 1 && value <= 10)
        .toList();
    return values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  /// Pair time and distance from the same segments; missing distance must not
  /// make the user's pace appear slower.
  double? get secondsPerKm {
    if (!template.isCardio) return null;
    final paired = days
        .expand((day) => day.sets)
        .where(
          (set) =>
              set.durationSeconds > 0 &&
              set.distanceKm.isFinite &&
              set.distanceKm > 0,
        );
    final km = paired.fold<double>(0, (sum, set) => sum + set.distanceKm);
    if (km == 0) return null;
    return paired.fold<int>(0, (sum, set) => sum + set.durationSeconds) / km;
  }

  List<ExerciseKpi> get metrics => template.isCardio
      ? [ExerciseKpi.duration, if (distanceKm > 0) ExerciseKpi.distance]
      : template.isDurationHold
      ? [ExerciseKpi.duration]
      : [
          if (template.usesWeight) ...[
            ExerciseKpi.weight,
            if (best(ExerciseKpi.estimatedMax) != null)
              ExerciseKpi.estimatedMax,
            ExerciseKpi.volume,
          ],
          ExerciseKpi.reps,
        ];
}

class WorkoutAnalytics {
  WorkoutAnalytics(List<ExerciseKpiSummary> exercises)
    : exercises = List.unmodifiable(exercises);

  final List<ExerciseKpiSummary> exercises;
  int get workoutDays => exercises
      .expand((item) => item.days)
      .map((day) => day.date)
      .toSet()
      .length;
  int get completedSets =>
      exercises.fold(0, (sum, item) => sum + item.completedSets);
  double get volume => exercises.fold(0, (sum, item) => sum + item.totalVolume);
  int get cardioSeconds => exercises
      .where((item) => item.template.isCardio)
      .fold(0, (sum, item) => sum + item.durationSeconds);

  WorkoutAnalytics inPeriod(WorkoutStatsPeriod period, DateTime today) {
    final start = period.start(today);
    if (start == null) return this;
    return WorkoutAnalytics([
      for (final item in exercises)
        if (item.days.any((day) => !day.date.isBefore(start)))
          ExerciseKpiSummary(
            template: item.template,
            days: item.days.where((day) => !day.date.isBefore(start)).toList(),
          ),
    ]);
  }
}

abstract final class WorkoutAnalyticsEngine {
  /// Read recorded templates, not the current catalog: archived/custom
  /// exercises and high-rep/bodyweight/cardio records must remain discoverable.
  static WorkoutAnalytics summarize({
    required Iterable<WorkoutSession> sessions,
    required DateTime today,
    OneRepMaxFormula formula = OneRepMaxFormula.average,
  }) {
    final end = DateTime(today.year, today.month, today.day);
    final templates = <String, ExerciseTemplate>{};
    final grouped = <String, Map<DateTime, List<WorkoutSetEntry>>>{};
    final ordered = sessions.toList()..sort((a, b) => a.date.compareTo(b.date));
    for (final session in ordered) {
      final day = DateTime(
        session.date.year,
        session.date.month,
        session.date.day,
      );
      if (day.isAfter(end)) continue;
      for (final exercise in session.exercises) {
        if (exercise.id.startsWith('seed_')) continue;
        final completed = exercise.sets.where((set) => set.completed).toList();
        if (completed.isEmpty) continue;
        final id = exercise.template.id;
        templates[id] = exercise.template;
        grouped
            .putIfAbsent(id, () => {})
            .putIfAbsent(day, () => [])
            .addAll(completed);
      }
    }
    return WorkoutAnalytics([
      for (final entry in grouped.entries)
        ExerciseKpiSummary(
          template: templates[entry.key]!,
          days: [
            for (final day in entry.value.entries)
              ExerciseDayStats(
                date: day.key,
                template: templates[entry.key]!,
                sets: day.value,
                formula: formula,
              ),
          ],
        ),
    ]);
  }
}

double _positive(double value) => value.isFinite && value > 0 ? value : 0;
double? _maximum(Iterable<double> values) =>
    values.isEmpty ? null : values.reduce(math.max);
