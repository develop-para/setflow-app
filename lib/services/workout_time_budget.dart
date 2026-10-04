import 'dart:math' as math;

import '../models.dart';

/// 준비·종목 전환 90초, 반복당 4초를 쓰는 시간 추정. 실제 소요시간 보장은 아니다.
abstract final class WorkoutTimeBudget {
  static const transitionSeconds = 90;

  static int workSeconds(ExerciseTemplate template, int reps) =>
      template.isDurationHold ? 60 : math.max(1, reps) * 4;

  static int estimateSessionSeconds(WorkoutSession session) {
    var total = 0;
    var finalRest = 0;
    for (final exercise in session.exercises) {
      if (exercise.id.startsWith('seed_') || exercise.sets.isEmpty) continue;
      total += transitionSeconds;
      for (final set in exercise.sets) {
        final work =
            exercise.template.isCardio || exercise.template.isDurationHold
            ? set.durationSeconds
            : workSeconds(exercise.template, set.reps);
        finalRest = exercise.template.isCardio ? 0 : set.restSeconds;
        total += math.max(0, work) + finalRest;
      }
    }
    return math.max(0, total - finalRest);
  }

  static int committedSeconds(WorkoutSession session, {DateTime? now}) {
    final estimate = estimateSessionSeconds(session);
    if (now == null ||
        session.startedAt == null ||
        session.date.year != now.year ||
        session.date.month != now.month ||
        session.date.day != now.day) {
      return estimate;
    }
    final elapsed = session.elapsedUntil(now)?.inSeconds ?? 0;
    final pending = WorkoutSession(
      date: session.date,
      exercises: [
        for (final exercise in session.exercises)
          WorkoutExercise(
            id: exercise.id,
            template: exercise.template,
            sets: exercise.sets.where((set) => !set.completed).toList(),
          ),
      ],
    );
    return math.max(estimate, elapsed + estimateSessionSeconds(pending));
  }

  static int previousRestSeconds(WorkoutSession session) {
    final exercises = session.exercises.where(
      (exercise) =>
          !exercise.id.startsWith('seed_') && exercise.sets.isNotEmpty,
    );
    if (exercises.isEmpty || exercises.last.template.isCardio) return 0;
    return exercises.last.sets.last.restSeconds;
  }

  static int addedSeconds({
    required WorkoutSession session,
    required ExerciseTemplate template,
    required int sets,
    required int reps,
    required int restSeconds,
  }) =>
      transitionSeconds +
      previousRestSeconds(session) +
      sets * workSeconds(template, reps) +
      math.max(0, sets - 1) * restSeconds;

  static int availableSeconds(WorkoutSession session, {DateTime? now}) =>
      session.timeBudgetMinutes == null
      ? 1 << 30
      : math.max(
          0,
          session.timeBudgetMinutes! * 60 - committedSeconds(session, now: now),
        );

  static int fittingSets({
    required WorkoutSession session,
    required ExerciseTemplate template,
    required int sets,
    required int reps,
    required int restSeconds,
    DateTime? now,
  }) {
    if (session.timeBudgetMinutes == null) return sets;
    final available = availableSeconds(session, now: now);
    for (var count = sets; count > 0; count--) {
      if (addedSeconds(
            session: session,
            template: template,
            sets: count,
            reps: reps,
            restSeconds: restSeconds,
          ) <=
          available) {
        return count;
      }
    }
    return 0;
  }
}
