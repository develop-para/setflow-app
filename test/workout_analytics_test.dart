import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/models.dart';
import 'package:setflow/services/performance_engine.dart';
import 'package:setflow/services/workout_analytics.dart';

const _press = ExerciseTemplate(
  id: 'custom-press',
  name: '내 프레스',
  muscle: '가슴',
  icon: Icons.fitness_center,
);
const _pushup = ExerciseTemplate(
  id: 'pushup',
  name: '푸시업',
  muscle: '가슴',
  icon: Icons.fitness_center,
  measurement: ExerciseMeasurement.repsOnly,
);
const _plank = ExerciseTemplate(
  id: 'plank',
  name: '플랭크',
  muscle: '복근',
  icon: Icons.fitness_center,
  measurement: ExerciseMeasurement.duration,
);
const _run = ExerciseTemplate(
  id: 'run',
  name: '러닝',
  muscle: '유산소',
  icon: Icons.directions_run,
);

WorkoutSetEntry _set({
  double weight = 50,
  int reps = 8,
  int seconds = 0,
  double km = 0,
  double rpe = 0,
  String type = '일반',
  bool completed = true,
}) => WorkoutSetEntry(
  number: 1,
  weight: weight,
  reps: reps,
  durationSeconds: seconds,
  distanceKm: km,
  intensityRpe: rpe,
  type: type,
  completed: completed,
);

WorkoutExercise _exercise(
  ExerciseTemplate template,
  List<WorkoutSetEntry> sets, {
  String? id,
}) => WorkoutExercise(
  id: id ?? 'record-${template.id}',
  template: template,
  sets: sets,
);

WorkoutSession _session(DateTime date, List<WorkoutExercise> exercises) =>
    WorkoutSession(date: date, exercises: exercises);

void main() {
  final today = DateTime(2026, 9, 16);
  WorkoutAnalytics summarize(List<WorkoutSession> sessions) =>
      WorkoutAnalyticsEngine.summarize(sessions: sessions, today: today);

  test(
    'all actual exercise types and custom history appear without a catalog',
    () {
      final data = summarize([
        _session(today, [
          _exercise(_press, [
            _set(reps: 20),
            _set(completed: false, weight: 300),
          ]),
          _exercise(_pushup, [_set(weight: 0, reps: 25)]),
          _exercise(_plank, [_set(weight: 0, reps: 0, seconds: 45)]),
          _exercise(_run, [_set(seconds: 600, km: 2)]),
          _exercise(_press, [_set(weight: 500)], id: 'seed_example'),
        ]),
        _session(today.add(const Duration(days: 1)), [
          _exercise(_press, [_set(weight: 1000)]),
        ]),
      ]);
      expect(data.exercises.map((item) => item.template.id), [
        _press.id,
        _pushup.id,
        _plank.id,
        _run.id,
      ]);
      expect(data.workoutDays, 1);
      expect(data.completedSets, 4);
      expect(data.volume, 1000);
      expect(data.cardioSeconds, 600);
      expect(data.exercises.first.best(ExerciseKpi.estimatedMax), isNull);
      expect(data.exercises.first.best(ExerciseKpi.weight), 50);
      expect(data.exercises.first.totalReps, 20);
    },
  );

  test(
    'periods include their first calendar day and default all includes old workouts',
    () {
      final data = summarize([
        for (final ago in [0, 2, 3, 29, 30, 89, 90, 400])
          _session(today.subtract(Duration(days: ago)), [
            _exercise(_press, [_set()]),
          ]),
      ]);
      expect(data.inPeriod(WorkoutStatsPeriod.all, today).workoutDays, 8);
      expect(data.inPeriod(WorkoutStatsPeriod.week, today).workoutDays, 2);
      expect(data.inPeriod(WorkoutStatsPeriod.month, today).workoutDays, 4);
      expect(data.inPeriod(WorkoutStatsPeriod.quarter, today).workoutDays, 6);
    },
  );

  test('repeat exercise entries merge into one day in chronological order', () {
    final data = summarize([
      _session(today, [
        _exercise(_press, [_set(weight: 70)]),
      ]),
      _session(today.subtract(const Duration(days: 1)), [
        _exercise(_press, [_set(weight: 55)]),
      ]),
      _session(DateTime(2026, 9, 16, 18), [
        _exercise(_press, [_set(weight: 60)]),
        _exercise(_pushup, [_set(weight: 0)]),
      ]),
    ]);
    final press = data.exercises.first;
    expect(press.workoutDays, 2);
    expect(press.completedSets, 3);
    expect(press.days.last.completedSets, 2);
    expect(press.days.last.value(ExerciseKpi.weight), 70);
    expect(press.totalVolume, 1480);
    expect(
      data.workoutDays,
      2,
      reason: 'two exercises on a day are one workout day',
    );
  });

  test(
    '1RM respects the formula and excludes warmups drops high reps and invalid values',
    () {
      final sessions = [
        _session(today, [
          _exercise(_press, [
            _set(weight: 80, reps: 5),
            _set(weight: 200, reps: 2, type: 'warmup'),
            _set(weight: 200, reps: 2, type: '드랍'),
            _set(weight: 200, reps: 12),
            _set(weight: double.nan),
            _set(weight: -20),
          ]),
        ]),
      ];
      for (final formula in OneRepMaxFormula.values) {
        final item = WorkoutAnalyticsEngine.summarize(
          sessions: sessions,
          today: today,
          formula: formula,
        ).exercises.single;
        expect(
          item.best(ExerciseKpi.estimatedMax),
          PerformanceEngine.estimate(80, 5, formula: formula)!.value,
        );
        expect(
          item.best(ExerciseKpi.weight),
          200,
          reason: 'actual weight is not restricted to 1RM eligible sets',
        );
        expect(item.totalVolume.isFinite, isTrue);
      }
    },
  );

  test(
    'cardio pairs pace fields and never adds legacy weight to strength volume',
    () {
      final item = summarize([
        _session(today, [
          _exercise(_run, [
            _set(seconds: 1800, km: 3, rpe: 4),
            _set(seconds: 900, rpe: 6),
            _set(km: 2, rpe: 0),
          ]),
        ]),
      ]).exercises.single;
      expect(item.totalVolume, 0);
      expect(item.totalReps, 0);
      expect(item.durationSeconds, 2700);
      expect(item.distanceKm, 5);
      expect(item.secondsPerKm, 600);
      expect(item.averageRpe, 5);
      expect(item.best(ExerciseKpi.estimatedMax), isNull);
      expect(item.metrics, [ExerciseKpi.duration, ExerciseKpi.distance]);
    },
  );

  test('bodyweight uses repetitions and holds use their longest set', () {
    final data = summarize([
      _session(today, [
        _exercise(_pushup, [_set(reps: 18), _set(reps: 12)]),
        _exercise(_plank, [_set(seconds: 45), _set(seconds: 60)]),
      ]),
    ]);
    expect(data.exercises.first.totalReps, 30);
    expect(data.exercises.first.best(ExerciseKpi.reps), 18);
    expect(data.exercises.first.metrics, [ExerciseKpi.reps]);
    expect(data.exercises.last.durationSeconds, 105);
    expect(data.exercises.last.best(ExerciseKpi.duration), 60);
    expect(data.exercises.last.metrics, [ExerciseKpi.duration]);
    expect(data.volume, 0);
  });

  test(
    'planned exercises and empty periods produce no fake zero performance',
    () {
      final data = summarize([
        _session(today.subtract(const Duration(days: 60)), [
          _exercise(_press, [_set()]),
          _exercise(_run, [_set(completed: false)]),
        ]),
      ]);
      expect(data.exercises, hasLength(1));
      expect(data.inPeriod(WorkoutStatsPeriod.month, today).exercises, isEmpty);
    },
  );
}
