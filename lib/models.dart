import 'package:flutter/material.dart';

enum UserRole { guest, member, trainer, gym, admin }

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
}

class WorkoutSetEntry {
  WorkoutSetEntry({
    required this.number,
    required this.weight,
    required this.reps,
    this.completed = false,
    this.type = '일반',
  });

  int number;
  double weight;
  int reps;
  bool completed;
  String type;

  double get volume => completed ? weight * reps : 0;

  WorkoutSetEntry copy() => WorkoutSetEntry(
    number: number,
    weight: weight,
    reps: reps,
    completed: false,
    type: type,
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
  });

  final String id;
  final String name;
  final String description;
  final Color color;
  final List<ExerciseTemplate> exercises;
  final String author;
  final String level;
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

enum RoutineImportResult { imported, alreadySaved, limitReached }
