import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import 'app_repository.dart';

abstract final class AppSnapshotCodec {
  static const schemaVersion = 1;

  static String encode(AppSnapshot snapshot) {
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'preferences': {
        'role': snapshot.role.name,
        'isDarkMode': snapshot.isDarkMode,
        'weightUnit': snapshot.weightUnit,
        'restDefaultSeconds': snapshot.restDefaultSeconds,
      },
      'sessions': snapshot.sessions.values.map(_sessionToJson).toList(),
      'routines': snapshot.routines.map(_routineToJson).toList(),
    });
  }

  static AppSnapshot? decode(
    String source,
    List<ExerciseTemplate> exerciseCatalog,
  ) {
    try {
      final root = jsonDecode(source) as Map<String, dynamic>;
      if (root['schemaVersion'] != schemaVersion) return null;
      final preferences = root['preferences'] as Map<String, dynamic>? ?? {};
      final templates = {
        for (final exercise in exerciseCatalog) exercise.id: exercise,
      };
      final sessions = <DateTime, WorkoutSession>{};
      for (final raw in root['sessions'] as List<dynamic>? ?? const []) {
        final session = _sessionFromJson(
          raw as Map<String, dynamic>,
          templates,
        );
        if (session != null) sessions[session.date] = session;
      }
      final routines = <RoutineData>[];
      for (final raw in root['routines'] as List<dynamic>? ?? const []) {
        final routine = _routineFromJson(
          raw as Map<String, dynamic>,
          templates,
        );
        if (routine != null) routines.add(routine);
      }
      final roleName = preferences['role'] as String?;
      final role = UserRole.values
          .where((item) => item.name == roleName)
          .firstOrNull;
      return AppSnapshot(
        role: role ?? UserRole.guest,
        isDarkMode: preferences['isDarkMode'] as bool? ?? false,
        weightUnit: preferences['weightUnit'] as String? ?? 'kg',
        restDefaultSeconds:
            (preferences['restDefaultSeconds'] as num?)?.toInt() ?? 90,
        sessions: sessions,
        routines: routines,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static Map<String, dynamic> _sessionToJson(WorkoutSession session) {
    return {
      'date': session.date.toIso8601String(),
      'exercises': session.exercises.map(_workoutExerciseToJson).toList(),
    };
  }

  static WorkoutSession? _sessionFromJson(
    Map<String, dynamic> json,
    Map<String, ExerciseTemplate> templates,
  ) {
    final date = DateTime.tryParse(json['date'] as String? ?? '');
    if (date == null) return null;
    final exercises = <WorkoutExercise>[];
    for (final raw in json['exercises'] as List<dynamic>? ?? const []) {
      final exercise = _workoutExerciseFromJson(
        raw as Map<String, dynamic>,
        templates,
      );
      if (exercise != null) exercises.add(exercise);
    }
    return WorkoutSession(
      date: DateTime(date.year, date.month, date.day),
      exercises: exercises,
    );
  }

  static Map<String, dynamic> _workoutExerciseToJson(WorkoutExercise exercise) {
    return {
      'id': exercise.id,
      'templateId': exercise.template.id,
      'sets': exercise.sets
          .map(
            (set) => {
              'number': set.number,
              'weight': set.weight,
              'reps': set.reps,
              'completed': set.completed,
              'type': set.type,
            },
          )
          .toList(),
    };
  }

  static WorkoutExercise? _workoutExerciseFromJson(
    Map<String, dynamic> json,
    Map<String, ExerciseTemplate> templates,
  ) {
    final template = templates[json['templateId'] as String?];
    if (template == null) return null;
    final sets = <WorkoutSetEntry>[];
    for (final raw in json['sets'] as List<dynamic>? ?? const []) {
      final set = raw as Map<String, dynamic>;
      sets.add(
        WorkoutSetEntry(
          number: (set['number'] as num?)?.toInt() ?? sets.length + 1,
          weight: (set['weight'] as num?)?.toDouble() ?? 0,
          reps: (set['reps'] as num?)?.toInt() ?? 0,
          completed: set['completed'] as bool? ?? false,
          type: set['type'] as String? ?? '일반',
        ),
      );
    }
    return WorkoutExercise(
      id:
          json['id'] as String? ??
          '${template.id}_${DateTime.now().microsecondsSinceEpoch}',
      template: template,
      sets: sets,
    );
  }

  static Map<String, dynamic> _routineToJson(RoutineData routine) {
    return {
      'id': routine.id,
      'name': routine.name,
      'description': routine.description,
      'color': routine.color.toARGB32(),
      'exerciseIds': routine.exercises.map((item) => item.id).toList(),
      'author': routine.author,
      'level': routine.level,
    };
  }

  static RoutineData? _routineFromJson(
    Map<String, dynamic> json,
    Map<String, ExerciseTemplate> templates,
  ) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || name == null) return null;
    final exercises = (json['exerciseIds'] as List<dynamic>? ?? const [])
        .map((value) => templates[value as String?])
        .whereType<ExerciseTemplate>()
        .toList();
    return RoutineData(
      id: id,
      name: name,
      description: json['description'] as String? ?? '',
      color: Color((json['color'] as num?)?.toInt() ?? 0xFF3B82F6),
      exercises: exercises,
      author: json['author'] as String? ?? '나',
      level: json['level'] as String? ?? '중급',
    );
  }
}
