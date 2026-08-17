import 'package:flutter/material.dart';

enum UserRole { guest, member, trainer, gym, admin }

enum RoutineAccessTier {
  free,
  paid;

  String get label => switch (this) {
    free => '무료',
    paid => '유료',
  };
}

enum RoutineAuthorType { trainer, gym, system }

class ExerciseTemplate {
  const ExerciseTemplate({
    required this.id,
    required this.name,
    required this.muscle,
    required this.icon,
  });

  final String id;
  final String name;
  final String muscle;
  final IconData icon;

  bool get isCardio => muscle == '유산소';
}

class WorkoutSetEntry {
  WorkoutSetEntry({
    required this.number,
    required this.weight,
    required this.reps,
    this.completed = false,
    this.type = '일반',
    this.restSeconds = 90,
    this.durationSeconds = 0,
    this.distanceKm = 0,
    this.intensityRpe = 0,
  });

  int number;
  double weight;
  int reps;
  bool completed;
  String type;
  int restSeconds;
  int durationSeconds;
  double distanceKm;
  double intensityRpe;

  double get volume => completed ? weight * reps : 0;

  WorkoutSetEntry copy() => WorkoutSetEntry(
    number: number,
    weight: weight,
    reps: reps,
    completed: false,
    type: type,
    restSeconds: restSeconds,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    intensityRpe: intensityRpe,
  );
}

String workoutSetTypeLabel(String value) =>
    switch (value.trim().toLowerCase()) {
      'warmup' || '웜업' => '웜업',
      'drop' || '드랍' => '드랍',
      'failure' || '실패' => '실패',
      _ => '일반',
    };

String workoutSetTypeDatabaseValue(String value) =>
    switch (workoutSetTypeLabel(value)) {
      '웜업' => 'warmup',
      '드랍' => 'drop',
      '실패' => 'failure',
      _ => 'normal',
    };

class RoutineSetPlan {
  const RoutineSetPlan({
    required this.number,
    required this.weight,
    required this.reps,
    this.type = '일반',
    this.restSeconds = 90,
    this.durationSeconds = 0,
    this.distanceKm = 0,
    this.intensityRpe = 0,
  });

  final int number;
  final double weight;
  final int reps;
  final String type;
  final int restSeconds;
  final int durationSeconds;
  final double distanceKm;
  final double intensityRpe;

  WorkoutSetEntry toWorkoutSetEntry() => WorkoutSetEntry(
    number: number,
    weight: weight,
    reps: reps,
    type: type,
    restSeconds: restSeconds,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    intensityRpe: intensityRpe,
  );
}

class WorkoutExercise {
  WorkoutExercise({
    required this.id,
    required this.template,
    required this.sets,
  });

  final String id;
  final ExerciseTemplate template;
  final List<WorkoutSetEntry> sets;

  WorkoutExercise copy() => WorkoutExercise(
    id: '${id}_copy_${DateTime.now().microsecondsSinceEpoch}',
    template: template,
    sets: sets.map((set) => set.copy()).toList(),
  );
}

class WorkoutSession {
  WorkoutSession({required this.date, required this.exercises});

  final DateTime date;
  final List<WorkoutExercise> exercises;

  int get totalSets => exercises.fold(0, (sum, item) => sum + item.sets.length);
  int get completedSets => exercises.fold(
    0,
    (sum, item) => sum + item.sets.where((set) => set.completed).length,
  );
  double get volume => exercises.fold(
    0,
    (sum, item) => sum + item.sets.fold(0, (s, set) => s + set.volume),
  );
  int get cardioDurationSeconds => exercises
      .where((exercise) => exercise.template.isCardio)
      .fold(
        0,
        (sum, exercise) =>
            sum +
            exercise.sets
                .where((set) => set.completed)
                .fold(0, (seconds, set) => seconds + set.durationSeconds),
      );
  bool get hasCardio => exercises.any((exercise) => exercise.template.isCardio);
  bool get hasResistance =>
      exercises.any((exercise) => !exercise.template.isCardio);
  double get completion => totalSets == 0 ? 0 : completedSets / totalSets;
}

class RoutineData {
  RoutineData({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.exercises,
    this.author = '나',
    this.level = '중급',
    this.accessTier = RoutineAccessTier.free,
    this.setPlans = const {},
    this.sourceMarketRoutineId,
    this.sourceCoachingRoutineId,
    this.authorTrainerId,
    this.authorGymId,
    this.authorType = RoutineAuthorType.system,
  });

  final String id;
  final String name;
  final String description;
  final Color color;
  final List<ExerciseTemplate> exercises;
  final String author;
  final String level;
  final RoutineAccessTier accessTier;
  final Map<String, List<RoutineSetPlan>> setPlans;
  final String? sourceMarketRoutineId;
  final String? sourceCoachingRoutineId;
  final String? authorTrainerId;
  final String? authorGymId;
  final RoutineAuthorType authorType;

  bool get isPaid => accessTier == RoutineAccessTier.paid;

  List<RoutineSetPlan> setsFor(ExerciseTemplate exercise) =>
      setPlans[exercise.id] ?? const [];
}

class PostComment {
  PostComment({
    required this.id,
    required this.author,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String author;
  final String content;
  final DateTime createdAt;
}

class CommunityPost {
  CommunityPost({
    required this.id,
    required this.author,
    required this.content,
    required this.metric,
    required this.createdAt,
    required this.visualKey,
    required this.color,
    this.likes = 0,
    this.isLiked = false,
    this.isMine = false,
    this.imageUrl,
    this.location,
    this.routineName,
    this.activeOverlays = const [],
    List<PostComment>? comments,
  }) : comments = comments ?? [];

  final String id;
  final String author;
  final String content;
  final String metric;
  final DateTime createdAt;
  final String visualKey;
  final Color color;
  int likes;
  bool isLiked;
  final bool isMine;
  final String? imageUrl;
  final String? location;
  final String? routineName;
  final List<String> activeOverlays;
  final List<PostComment> comments;

  IconData get icon => switch (visualKey) {
    'streak' => Icons.local_fire_department_rounded,
    'tip' => Icons.lightbulb_rounded,
    'strength' => Icons.fitness_center_rounded,
    _ => Icons.emoji_events_rounded,
  };
}

enum ConsultationStatus { waiting, answered, coaching }

class ConsultationData {
  ConsultationData({
    required this.id,
    required this.trainerName,
    required this.specialty,
    required this.goal,
    required this.level,
    required this.question,
    required this.createdAt,
    this.status = ConsultationStatus.waiting,
    this.response,
    this.rating,
  });

  final String id;
  final String trainerName;
  final String specialty;
  final String goal;
  final String level;
  final String question;
  final DateTime createdAt;
  ConsultationStatus status;
  String? response;
  int? rating;
}

class BusinessTaskData {
  BusinessTaskData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.kind,
  });

  final String id;
  final String title;
  final String subtitle;
  final String action;
  final String kind;
}

class BusinessNotificationData {
  BusinessNotificationData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String kind;
  final DateTime createdAt;
  bool isRead;
}

class BusinessDashboardData {
  BusinessDashboardData({
    required this.role,
    required this.facts,
    required this.tasks,
    required this.notifications,
    required this.lastSyncedAt,
  });

  final UserRole role;
  final Map<String, String> facts;
  final List<BusinessTaskData> tasks;
  final List<BusinessNotificationData> notifications;
  DateTime lastSyncedAt;
}

enum RoutineImportResult {
  imported,
  alreadySaved,
  limitReached,
  paidPlanRequired,
}
