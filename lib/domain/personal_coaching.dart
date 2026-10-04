import '../models.dart';

enum CoachingAdjustment { insufficient, maintain, increase, reduce }

class MuscleCoachingTarget {
  const MuscleCoachingTarget({
    required this.muscle,
    required this.weeklySets,
    required this.dailySets,
    required this.trainingDays,
    required this.historyDays,
    required this.adjustment,
    required this.reason,
  });

  final TrainingMuscle muscle;
  final int weeklySets;
  final int dailySets;
  final int trainingDays;
  final int historyDays;
  final CoachingAdjustment adjustment;
  final String reason;
}

/// Reproducible targets, calculated from weeks completed before [weekStart].
/// Entitlements are deliberately absent from personal snapshot data.
class PersonalCoachingPlan {
  PersonalCoachingPlan({
    required this.weekStart,
    required Map<TrainingMuscle, MuscleCoachingTarget> targets,
  }) : targets = Map.unmodifiable(targets);

  static const ruleVersion = 'personal-coaching-v1';
  final DateTime weekStart;
  final Map<TrainingMuscle, MuscleCoachingTarget> targets;

  int weeklyBudget(TrainingMuscle muscle, int fallback) =>
      targets[muscle]?.weeklySets ?? fallback;
  int dailyBudget(TrainingMuscle muscle, int fallback) =>
      targets[muscle]?.dailySets ?? fallback;
  String reasonFor(Iterable<TrainingMuscle> muscles) => targets.values
      .where((target) => muscles.contains(target.muscle))
      .map((target) => target.reason)
      .join(' ');
}
