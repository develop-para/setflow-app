import '../models.dart';

class AppSnapshot {
  const AppSnapshot({
    required this.role,
    required this.isDarkMode,
    required this.weightUnit,
    required this.restDefaultSeconds,
    required this.sessions,
    required this.routines,
    this.nickname,
    this.useRir = false,
    this.autoStartRestTimer = true,
    this.autoRecommendNextExercise = true,
    this.restTimerNotifications = true,
    this.timerVibration = true,
    this.pushCoachingFeedback = true,
    this.communityReactionNotifications = false,
    this.goals = const [],
    this.heightCm,
    this.weight,
    this.age,
    this.gender,
    this.communityPosts = const [],
    this.consultations = const [],
    this.businessDashboards = const {},
    this.customExercises = const [],
  });

  final UserRole role;
  final bool isDarkMode;
  final String weightUnit;
  final int restDefaultSeconds;
  final String? nickname;
  final bool useRir;
  final bool autoStartRestTimer;
  final bool autoRecommendNextExercise;
  final bool restTimerNotifications;
  final bool timerVibration;
  final bool pushCoachingFeedback;
  final bool communityReactionNotifications;
  final Map<DateTime, WorkoutSession> sessions;
  final List<RoutineData> routines;
  final List<String> goals;
  final double? heightCm;
  final double? weight;
  final int? age;
  final String? gender;
  final List<CommunityPost> communityPosts;
  final List<ConsultationData> consultations;
  final Map<UserRole, BusinessDashboardData> businessDashboards;
  final List<ExerciseTemplate> customExercises;
}

/// A locally durable write that has not yet been acknowledged by Supabase.
///
/// [expectedServerUpdatedAt] is the optimistic-lock version that was current
/// when the mutation was queued. Keeping it with the payload prevents an old
/// device from silently overwriting a newer server snapshot after reconnect.
class PendingAppSnapshot {
  const PendingAppSnapshot({
    required this.snapshot,
    required this.queuedAt,
    this.expectedServerUpdatedAt,
  });

  final AppSnapshot snapshot;
  final DateTime queuedAt;
  final DateTime? expectedServerUpdatedAt;
}

/// Account-scoped local outbox used before attempting a network write.
abstract interface class AccountSnapshotOutbox {
  Future<PendingAppSnapshot?> loadPending(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  );

  Future<void> stagePending(String userId, PendingAppSnapshot pending);

  Future<void> clearPending(String userId);
}

/// Explicitly claimed source for the one-time pre-authentication Hive import.
///
/// An unclaimed legacy snapshot must never be inferred to belong to whichever
/// account happens to sign in first.
abstract interface class ClaimedLegacySnapshotSource {
  Future<AppSnapshot?> loadClaimed(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  );

  Future<void> clearClaimed(String userId);
}

/// Optional signal that lets AppState retry a durable outbox after loading.
abstract interface class PendingSaveAwareRepository {
  bool get hasPendingSave;
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
