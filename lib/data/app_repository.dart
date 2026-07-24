import 'package:flutter/material.dart' show ThemeMode;

import '../models.dart';

class AppSnapshot {
  const AppSnapshot({
    required this.role,
    required this.themeMode,
    required this.weightUnit,
    required this.restDefaultSeconds,
    required this.sessions,
    required this.routines,
    this.communityPosts = const [],
    this.consultations = const [],
    this.businessDashboards = const {},
  });

  final UserRole role;
  final ThemeMode themeMode;
  final String weightUnit;
  final int restDefaultSeconds;
  final Map<DateTime, WorkoutSession> sessions;
  final List<RoutineData> routines;
  final List<CommunityPost> communityPosts;
  final List<ConsultationData> consultations;
  final Map<UserRole, BusinessDashboardData> businessDashboards;
}

abstract interface class AppRepository {
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog);

  Future<void> save(AppSnapshot snapshot);

  Future<void> clear();
}

class MemoryAppRepository implements AppRepository {
  MemoryAppRepository({AppSnapshot? initialSnapshot})
    : _snapshot = initialSnapshot;

  AppSnapshot? _snapshot;

  AppSnapshot? get snapshot => _snapshot;

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    return _snapshot;
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    _snapshot = snapshot;
  }

  @override
  Future<void> clear() async {
    _snapshot = null;
  }
}
