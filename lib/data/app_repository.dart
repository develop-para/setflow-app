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
    this.precisionRecommendationPrompted = false,
    this.hasSwipedSet = false,
    this.defaultSetCount,
    this.defaultRepCount,
    this.activeTrainingPartyId,
    this.recommendationProfile,
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
  final bool precisionRecommendationPrompted;

  /// 세트를 밀어서 기록해 본 적이 있는가. 없으면 그 행에 살짝 미는 힌트를 보여준다.
  final bool hasSwipedSet;

  /// 운동을 추가할 때의 세트 수·횟수 기본값. null이면 추천/처방을 따른다 —
  /// 사용자가 정한 적 없는 값과 "3으로 정했다"를 구분해야 한다.
  final int? defaultSetCount;
  final int? defaultRepCount;
  final String? activeTrainingPartyId;
  final RecommendationProfile? recommendationProfile;
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

/// Account-scoped last-known-good snapshot used to start without a network.
///
/// Unlike the outbox, this cache remains after Supabase acknowledges a write.
/// It must never be shared between user ids.
abstract interface class AccountSnapshotCache {
  Future<AppSnapshot?> loadCached(
    String userId,
    List<ExerciseTemplate> exerciseCatalog,
  );

  Future<void> storeCached(String userId, AppSnapshot snapshot);

  Future<void> clearCached(String userId);
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

  /// The device-local snapshot that belongs to nobody yet — what a guest has
  /// been recording.
  ///
  /// Owner-checked rather than a plain [AppRepository.load]: a snapshot already
  /// claimed by an account must not reappear to the next guest on the device.
  Future<AppSnapshot?> loadUnclaimed(List<ExerciseTemplate> exerciseCatalog);

  /// Writes the guest's snapshot without attributing it to anyone.
  Future<void> saveUnclaimed(AppSnapshot snapshot);

  /// Attributes the unclaimed snapshot to [userId]. False when there is
  /// nothing to claim or it already belongs to someone else.
  Future<bool> claimFor(String userId);
}

/// Repository capability for moving a guest's device-local records into the
/// account that just signed in.
///
/// The app is usable without an account, so by the time someone signs up they
/// may already have weeks of workouts on the device. Those records have no
/// provenance — being the first account to sign in on a shared phone is not
/// evidence of ownership — so adopting them is an explicit, asked-for step
/// rather than something that quietly happens.
abstract interface class GuestDataAdoption {
  /// The guest snapshot, for deciding whether it is worth asking about.
  Future<AppSnapshot?> peekGuestSnapshot(
    List<ExerciseTemplate> exerciseCatalog,
  );

  /// Hands the guest snapshot to [userId]; the next [AppRepository.load] for
  /// that account imports it.
  Future<bool> adoptGuestSnapshot(String userId);
}

/// Optional signal that lets AppState retry a durable outbox after loading.
abstract interface class PendingSaveAwareRepository {
  bool get hasPendingSave;
}

/// Repository capability for local-first persistence with deferred cloud sync.
abstract interface class DeferredSyncAppRepository {
  bool get hasPendingSave;

  Object? get lastSyncError;

  Future<void> syncPending();
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
