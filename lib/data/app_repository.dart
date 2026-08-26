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
    this.timerSound = true,
    this.timerCountdownSeconds = 30,
    this.oneRepMaxFormula = OneRepMaxFormula.average,
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

  /// 휴식 카운트다운 소리. [timerCountdownSeconds]초 남은 순간 알림음이 울리고
  /// 마지막 3초는 초마다 짧게 삑, 0초에 끝 소리가 난다. 0이면 시작음 없이
  /// 마지막 3초와 끝 소리만 남는다.
  final bool timerSound;
  final int timerCountdownSeconds;

  /// 추정 1RM을 내는 공식. 고른 적 없으면 두 공식의 평균.
  final OneRepMaxFormula oneRepMaxFormula;
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

/// 지금 걸려 있는 탈퇴 요청. 유예 중이면 [purgeAfter]까지 되돌릴 수 있다.
class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.requestedAt,
    required this.purgeAfter,
    this.reason,
  });

  final DateTime requestedAt;
  final DateTime purgeAfter;
  final String? reason;

  int daysLeft(DateTime now) {
    final remaining = purgeAfter.difference(now).inHours;
    return remaining <= 0 ? 0 : (remaining / 24).ceil();
  }
}

/// 회원 탈퇴. 스토어가 요구하는 "앱 안에서 계정을 지울 수 있는 경로"이고,
/// 곧바로 지우는 대신 유예를 두기 때문에 취소와 조회가 함께 있어야 한다.
///
/// 화면은 테이블도 RPC 이름도 모른다 — 요청·취소·조회 셋만 안다.
abstract interface class AccountDeletion {
  /// 탈퇴를 요청하고 유예 기간을 돌려준다.
  Future<AccountDeletionRequest> requestAccountDeletion({String? reason});

  /// 유예 중인 요청을 되돌린다. 걸린 요청이 없으면 false.
  Future<bool> cancelAccountDeletion();

  /// 지금 걸려 있는 요청. 없으면 null.
  Future<AccountDeletionRequest?> pendingAccountDeletion();
}

/// 이 기기로 알림을 받겠다고 서버에 알리는 경로.
///
/// 토큰이 어디에 저장되는지, 어떤 RPC 이름인지는 어댑터만 안다. AppState는
/// "이 기기를 등록해 / 지워"만 말한다.
abstract interface class PushTokenRegistry {
  /// 지금 로그인한 계정에 이 기기의 토큰을 붙인다. 같은 토큰이 다른 계정에
  /// 붙어 있었다면 이쪽으로 옮겨 온다 — 기기의 현재 사용자가 진실이다.
  Future<void> registerPushToken({
    required String token,
    required String platform,
  });

  /// 이 기기의 토큰을 뗀다. 로그아웃할 때 부른다.
  Future<void> unregisterPushToken(String token);
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
