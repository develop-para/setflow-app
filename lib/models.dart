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
