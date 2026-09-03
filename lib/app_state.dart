import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'data/app_repository.dart';
import 'data/business_repository.dart';
import 'data/backend_cache.dart';
import 'data/community_repository.dart';
import 'data/exercise_catalog.dart';
import 'data/exercise_catalog_repository.dart';
import 'data/notification_repository.dart';
import 'data/routine_catalog_repository.dart';
import 'data/together_repository.dart';
import 'domain/cardio.dart';
import 'models.dart';
import 'services/setflow_web.dart';
import 'services/cardio_prescription_engine.dart';
import 'services/exercise_recommendation_engine.dart';
import 'services/performance_engine.dart';
import 'services/push_service.dart';
import 'services/rest_timer_platform.dart';
import 'services/auth_service.dart';

export 'models.dart';
export 'domain/cardio.dart';
export 'services/cardio_prescription_engine.dart';
export 'services/exercise_recommendation_engine.dart';
export 'services/performance_engine.dart';

class MemberProfileDraft {
  MemberProfileDraft({
    required Iterable<String> goals,
    this.heightCm,
    this.weight,
    this.age,
    this.gender,
  }) : goals = List<String>.unmodifiable(
         goals
             .map((goal) => goal.trim())
             .where((goal) => goal.isNotEmpty)
             .toSet(),
       );

  final List<String> goals;
  final double? heightCm;
  final double? weight;
  final int? age;
  final String? gender;
}

/// 휴식 중에 보여 줄 것. 남은 세트와 다음 종목은 세트를 마친 순간에만 알 수 있다.
class RestFocus {
  const RestFocus({
    required this.exerciseName,
    required this.setsLeft,
    this.nextExercise,
  });

  final String exerciseName;

  /// 이 종목에 아직 남은 세트 수.
  final int setsLeft;

  /// 이 종목을 다 했을 때 이어지는 종목. 마지막이면 null.
  final String? nextExercise;
}

class AppState extends ChangeNotifier {
  AppState({
    AppRepository? repository,
    this.businessRepository,
    this.loadBusinessWithoutAuth = false,
    Future<void> Function()? authSignOut,
    this.routineCatalogRepository,
    this.communityRepository,
    this.exerciseCatalogRepository,
    this.togetherRepository,
    this.notificationRepository,
  }) : _repository = repository ?? MemoryAppRepository(),
       _authSignOut = authSignOut ?? Auth.instance.signOut {
    if (routineCatalogRepository == null) {
      _seedMarketRoutines();
    }
    _seedStarterRoutines();
    if (communityRepository == null) {
      _seedSocial();
    }
    if (businessRepository == null) {
      _seedBusinessDashboards();
      _seedDemoCoachingSchedules();
    } else {
      _resetLiveBusinessDashboards();
    }
  }

  final AppRepository _repository;
  final Future<void> Function() _authSignOut;
  final BusinessRepository? businessRepository;
  final bool loadBusinessWithoutAuth;
  final RoutineCatalogRepository? routineCatalogRepository;
  final CommunityRepository? communityRepository;
  final ExerciseCatalogRepository? exerciseCatalogRepository;

  /// 함께 운동(파트너 방). Null이면 화면이 "지금은 쓸 수 없어요"로 내려간다 —
  /// 혼자서는 성립하지 않는 기능이라 로컬 대체본을 두지 않는다.
  final TogetherRepository? togetherRepository;

  /// 알림함. Null이면 화면이 "알림은 로그인하면 볼 수 있어요"로 내려간다 —
  /// 알림은 계정에 붙으므로 로컬 대체본이 없다.
  final NotificationRepository? notificationRepository;
  Timer? _persistTimer;
  Timer? _serverSyncTimer;
  bool _initialized = false;
  bool _disposed = false;
  int _accountEpoch = 0;
  int _businessRequestSequence = 0;
  int _topCoachingTrainerRequestSequence = 0;
  int _memberConsultationRequestSequence = 0;
  int _scheduleRequestSequence = 0;
  int _memberFeedbackRequestSequence = 0;
  int _memberDetailGeneration = 0;
  int _workoutExerciseSequence = 0;
  final Map<String, Future<dynamic>> _businessMutations = {};
  final Map<String, Future<BusinessMemberDetail>> _memberDetailLoads = {};
  final Map<String, BusinessMemberDetail> _businessMemberDetails = {};
  final Map<String, Object> _businessMemberDetailErrors = {};
  final Map<String, String> _businessInviteAcceptRequestIds = {};
  final Map<String, String> _coachingInviteAcceptRequestIds = {};
  final Map<String, String> _sessionFeedbackRequestIds = {};
  final Map<String, String> _membershipEndRequestIds = {};
  final Map<String, String> _personalRoutineSaveRequestIds = {};
  final Map<String, String> _personalRoutineDeleteRequestIds = {};
  final Map<String, String> _coachingScheduleCreateRequestIds = {};
  final Map<String, String> _coachingHealthConsentRequestIds = {};
  final Map<String, String> _consultationAssignRequestIds = {};
  final Map<String, String> _consultationCreateRequestIds = {};
  final Map<String, String> _consultationReplyRequestIds = {};
  final Map<String, String> _stableBusinessRpcRequestIds = {};
  final Map<String, DateTime> _businessInviteCreateExpiresAt = {};
  final Map<String, DateTime> _coachingInviteCreateExpiresAt = {};
  final Set<String> _uncertainRoutineShareLinkRoutineIds = {};
  final Map<String, Map<String, String?>> _personalRoutineBaseExerciseIds = {};
  Future<void>? _signOutInFlight;
  Future<void>? _authenticationSyncInFlight;
  Future<void>? _persistInFlight;
  Future<void>? _accountFlushInFlight;
  AppSnapshot? _queuedSnapshot;
  MemberProfileDraft? _stagedMemberProfileDraft;

  bool get isInitialized => _initialized;
  Object? persistenceError;
  Object? persistenceSyncError;
  Object? cloudSyncError;

  bool get isUsingCachedCloudData =>
      _isUsingCachedData(routineCatalogRepository) ||
      _isUsingCachedData(communityRepository);

  static bool _isUsingCachedData(Object? repository) =>
      repository is CachedBackendReadStatus && repository.isUsingCachedData;

  static Object? _cachedReadError(Object? repository) =>
      repository is CachedBackendReadStatus ? repository.lastReadError : null;

  UserRole role = UserRole.guest;
  bool isDarkMode = false;
  String weightUnit = 'kg';
  int restDefaultSeconds = 90;

  /// 운동을 추가할 때 만들 세트 수·횟수. null이면 정한 적 없음 — 이전 기록
  /// 추천과 목표 처방이 하던 대로 정한다. 값이 있으면 처방보다 앞선다:
  /// 사용자가 직접 정한 것이 프로필에서 유추한 것보다 명시적이다.
  int? defaultSetCount;
  int? defaultRepCount;

  /// 지금 들어가 있는 함께 방. 앱을 껐다 켜도 방으로 돌아가기 위한 기억이고,
  /// 방이 사라졌으면 화면이 지운다.
  String? activeTrainingPartyId;
  String memberNickname = '';
  bool useRir = false;
  bool autoStartRestTimer = true;
  bool autoRecommendNextExercise = true;
  bool restTimerNotifications = true;
  bool timerVibration = true;
  bool timerSound = true;

  /// 카운트다운 알림이 시작되는 남은 시간(초). 0이면 시작음 없이 끝 소리만.
  int timerCountdownSeconds = 30;

  /// 추정 1RM 공식. 화면에 뜨는 e1RM과 e1RM PR 판정이 전부 이걸 따른다.
  OneRepMaxFormula oneRepMaxFormula = OneRepMaxFormula.average;
  bool pushCoachingFeedback = true;
  bool communityReactionNotifications = false;
  bool pushTogether = true;
  bool pushWorkoutReminder = false;
  int workoutReminderHour = 19;

  /// 트레이너·센터 업무 알림 스위치. 서버의 `push_enabled`가 스냅샷에서
  /// 같은 키를 읽는다 — 키가 없으면 켜진 것이다.
  Map<String, bool> businessNotifications = {};

  /// 방금 탭한 푸시. 셸이 이걸 보고 탭을 옮기고, 상세 화면이 필요하면
  /// main.dart가 그 위에 push한다. [PushOpen.serial]로 "이미 처리한 것"을 가른다.
  PushOpen? pendingPushOpen;

  /// 알림함의 내용. 목록 화면과 헤더의 점이 같은 값을 본다 — 두 곳에서 따로
  /// 세면 "빨간 점은 있는데 목록은 비어 있다"가 된다.
  List<AppNotification> notifications = const [];

  /// 안 읽은 알림 수. 목록을 아직 안 받아왔어도 헤더의 점은 떠야 하므로
  /// 목록과 따로 들고 있다.
  int unreadNotificationCount = 0;

  bool notificationsLoading = false;
  Object? notificationsError;
  String get memberDisplayName {
    final nickname = memberNickname.trim();
    return nickname.isEmpty ? Auth.instance.currentDisplayName : nickname;
  }

  List<String> goals = [];
  bool get hasTrainingGoal => PerformanceEngine.goalFromProfile(goals) != null;
  double? heightCm;
  double? weight;
  int? age;
  String? gender;
  bool precisionRecommendationPrompted = false;

  /// 지금 쉬는 이유. 휴식 바가 "무엇을 하다 쉬는지"를 말할 수 있게 한다.
  ///
  /// 타이머만 있으면 남은 시간밖에 못 보여준다. 몇 세트가 남았고 다음이 무엇인지는
  /// 세트를 마친 그 순간에만 알 수 있어서, 그때 찍어 [startRestTimer]에 넘긴다.
  /// 세트 완료가 아닌 휴식(함께 방의 공유 휴식)은 null — 지난 세트 얘기를 남기지 않는다.
  RestFocus? restFocus;

  /// 세트를 밀어서 기록해 본 적이 있는가.
  ///
  /// 미는 조작에는 손잡이가 없어서, 해 보기 전에는 있는 줄도 모른다. 아직 안 해 봤으면
  /// 차례인 행이 스스로 살짝 움직여 보인다. 한 번 하고 나면 다시는 안 한다.
  bool hasSwipedSet = false;
  bool hasSeenTogetherGuide = false;
  RecommendationProfile? recommendationProfile;
  int restRemaining = 0;
  Timer? _restTimer;
  DateTime? _restTimerEndsAt;

  final List<ExerciseTemplate> exercises = List.of(exerciseCatalog);
  final List<ExerciseTemplate> _sharedCatalogExercises = [];
  final List<ExerciseTemplate> customExercises = [];
  bool exerciseCatalogLoading = false;
  Object? exerciseCatalogError;

  final Map<DateTime, WorkoutSession> sessions = {};
  final List<RoutineData> routines = [];
  final List<RoutineData> _marketRoutines = [];
  final List<CommunityPost> communityPosts = [];
  final List<ConsultationData> consultations = [];
  final Map<UserRole, BusinessDashboardData> businessDashboards = {};

  BusinessAccess? businessAccess;
  BusinessWorkspaceData? businessWorkspace;
  List<PublicTrainer> publicTrainers = const [];
  List<TopCoachingTrainer> topCoachingTrainers = const [];
  List<BusinessConsultation> memberConsultations = const [];
  bool memberConsultationsLoading = false;
  Object? memberConsultationsError;
  MemberSharingPreferences? _memberSharingPreferences;
  List<RoutineShareRecord> incomingRoutineShares = const [];
  List<RoutineShareRecord> outgoingRoutineShares = const [];
  List<BusinessInviteRecord> businessInvites = const [];
  List<BusinessCoachingSchedule> coachingSchedules = const [];
  List<BusinessMember> memberMemberships = const [];
  List<ServiceRegion> serviceRegions = const [];
  List<MemberWorkoutLocation> workoutLocations = const [];
  List<MemberSessionFeedback> memberSessionFeedbacks = const [];
  String? pendingRoutineShareToken;
  String? pendingBusinessInviteToken;
  String? pendingCoachingInviteToken;

  /// 초대 링크로 들어온 함께 방 코드. 셸이 함께 탭을 열고, 화면이 그 코드로
  /// 참여한 뒤 지운다(`clearPendingTogetherJoinCode`).
  String? pendingTogetherJoinCode;
  bool businessLoading = false;
  Object? businessError;
  bool coachingSchedulesLoading = false;
  Object? coachingSchedulesError;
  bool memberSessionFeedbackLoading = false;
  Object? memberSessionFeedbackError;
  Object? memberMembershipsError;
  Object? workoutLocationsError;

  MemberWorkoutLocation? get currentWorkoutLocation =>
      workoutLocations.where((item) => item.isActive).firstOrNull;

  bool _verifiedAdmin = false;
  bool hasPaidPlan = false;

  bool get isAdmin => _verifiedAdmin;
  bool get usesLiveBusinessData => businessRepository != null;
  bool get hasPendingBusinessMutation => _businessMutations.isNotEmpty;
  bool isBusinessMutationPending(String key) =>
      _businessMutations.containsKey(key);
  bool isAssigningBusinessMember(String memberId) =>
      isBusinessMutationPending(_assignmentMutationKey(memberId));
  bool isReplyingToBusinessConsultation(String consultationId) =>
      isBusinessMutationPending(_consultationReplyMutationKey(consultationId));
  bool isAssigningBusinessConsultation(String consultationId) =>
      isBusinessMutationPending(_consultationAssignMutationKey(consultationId));
  bool isCreatingBusinessConsultation(String trainerId) =>
      isBusinessMutationPending(_consultationCreateMutationKey(trainerId));
  bool isReviewingBusinessApplication(String applicationId) =>
      isBusinessMutationPending(_applicationReviewMutationKey(applicationId));
  bool isUpdatingBusinessProfile(String profileId) =>
      isBusinessMutationPending(_businessProfileMutationKey(profileId));
  bool get isSubmittingTrainerBusinessApplication =>
      isBusinessMutationPending(_trainerApplicationMutationKey);
  bool get isSubmittingGymBusinessApplication =>
      isBusinessMutationPending(_gymApplicationMutationKey);
  bool get isCreatingBusinessRoutine => _businessMutations.keys.any(
    (key) => key.startsWith(_businessRoutineMutationPrefix),
  );
  bool isSavingBusinessRoutine(String routineId) => _businessMutations.keys.any(
    (key) => key.startsWith('routine:save:$routineId:'),
  );
  bool isSubmittingBusinessRoutine(String routineId) =>
      isBusinessMutationPending('routine:submit:$routineId');
  bool isReviewingBusinessRoutine(String routineId) => _businessMutations.keys
      .any((key) => key.startsWith('routine:review:$routineId:'));
  bool isSharingBusinessRoutine(String routineId) => _businessMutations.keys
      .any((key) => key.startsWith('routine:share:$routineId:'));
  bool get supportsRoutineShareRevocation =>
      businessRepository is RoutineShareRevocationRepository;
  bool isRevokingRoutineShare(String shareId) =>
      isBusinessMutationPending('routine:share-revoke:$shareId');
  bool isRespondingRoutineShare(String shareId) => _businessMutations.keys.any(
    (key) => key.startsWith('routine:respond:$shareId:'),
  );
  bool isSavingPersonalRoutine(String routineId) => _businessMutations.keys.any(
    (key) => key.startsWith('personal-routine:save:$routineId:'),
  );
  bool isDeletingPersonalRoutine(String routineId) =>
      isBusinessMutationPending('personal-routine:delete:$routineId');
  bool isSendingSessionFeedback(String sessionId) =>
      isBusinessMutationPending('feedback:session:$sessionId');
  bool isEndingBusinessMembership(String memberId) =>
      isBusinessMutationPending('membership:end:$memberId');
  bool get isCreatingCoachingSchedule =>
      isBusinessMutationPending('coaching-schedule:create');
  bool isUpdatingCoachingSchedule(String scheduleId) =>
      isBusinessMutationPending('coaching-schedule:update:$scheduleId');
  bool isDeletingCoachingSchedule(String scheduleId) =>
      isBusinessMutationPending('coaching-schedule:delete:$scheduleId');
  bool isSavingCoachingHealthConsent(String scheduleId) =>
      isBusinessMutationPending('coaching-health:consent:$scheduleId');
  bool isCreatingBusinessInvite(BusinessInviteKind kind) =>
      _businessMutations.keys.any(
        (key) =>
            key.startsWith('business-invite:create:${kind.databaseValue}:'),
      );
  bool get isAcceptingBusinessInvite => _businessMutations.keys.any(
    (key) => key.startsWith('business-invite:accept:'),
  );
  bool get isUpdatingMemberSharingPreferences =>
      isBusinessMutationPending('member:sharing-preferences');
  bool isBusinessMemberDetailLoading(String memberId) =>
      _memberDetailLoads.containsKey(memberId);
  BusinessMemberDetail? businessMemberDetail(String memberId) =>
      _businessMemberDetails[memberId];
  Object? businessMemberDetailError(String memberId) =>
      _businessMemberDetailErrors[memberId];
  List<BusinessMember> get businessMembers =>
      businessWorkspace?.members ?? const [];
  List<CoachingConnection> get coachingConnections =>
      businessWorkspace?.coachingConnections ?? const [];
  List<CoachingSessionRecord> get coachingSessionRecords =>
      businessWorkspace?.sessionRecords ?? const [];
  List<GymTrainerRecord> get businessTrainers =>
      businessWorkspace?.trainers ?? const [];
  List<BusinessConsultation> get businessConsultations =>
      businessWorkspace?.consultations ?? const [];
  List<BusinessApplication> get businessApplications =>
      businessWorkspace?.applications ?? const [];
  List<OwnedCoachingRoutine> get ownedBusinessRoutines =>
      businessWorkspace?.ownedRoutines ?? const [];
  MemberSharingPreferences? get memberSharingPreferences =>
      _memberSharingPreferences ?? businessWorkspace?.memberSharingPreferences;
  List<MemberSessionFeedback> memberSessionFeedbackForDate(DateTime value) {
    final target = dateOnly(value);
    return List.unmodifiable(
      memberSessionFeedbacks.where(
        (feedback) => dateOnly(feedback.sessionDate) == target,
      ),
    );
  }

  List<RoutineData> get marketRoutines => List.unmodifiable(_marketRoutines);

  /// 앱이 받는 초대 링크(커스텀 스킴). 보내는 링크는 레포지토리의 `inviteLink`.
  static Uri togetherInviteUri(String code) => togetherSchemeInviteUri(code);

  void captureIncomingUri(Uri uri) {
    final joinCode = switch ((uri.scheme, uri.host)) {
      ('com.teampara.setflow', 'together-join') =>
        uri.pathSegments.firstOrNull ?? uri.queryParameters['code'],
      ('https', final host)
          when host == SetflowWeb.host && uri.path == '/together/join' =>
        uri.queryParameters['code'],
      _ => null,
    };
    if (joinCode != null) {
      final normalized = joinCode.trim().toUpperCase();
      if (normalized.isEmpty) return;
      pendingTogetherJoinCode = normalized;
      notifyListeners();
      return;
    }
    if (uri.scheme == 'com.teampara.setflow' && uri.host == 'routine-share') {
      final token = uri.pathSegments.firstOrNull?.trim();
      if (token == null || token.isEmpty) return;
      pendingRoutineShareToken = token;
      notifyListeners();
      return;
    }
    final businessToken = switch ((uri.scheme, uri.host)) {
      ('com.teampara.setflow', 'business-invite') =>
        uri.pathSegments.firstOrNull?.trim(),
      ('https', 'setflow.app') when uri.path == '/invite/business' =>
        uri.queryParameters['token']?.trim(),
      _ => null,
    };
    if (businessToken != null && businessToken.isNotEmpty) {
      pendingBusinessInviteToken = businessToken;
      notifyListeners();
      return;
    }
    final coachingToken = switch ((uri.scheme, uri.host)) {
      ('com.teampara.setflow', 'coaching-invite') =>
        uri.pathSegments.firstOrNull?.trim(),
      ('https', 'setflow.app') when uri.path == '/invite/coaching' =>
        uri.queryParameters['token']?.trim(),
      _ => null,
    };
    if (coachingToken == null || coachingToken.isEmpty) return;
    pendingCoachingInviteToken = coachingToken;
    notifyListeners();
  }

  void captureRoutineShareUri(Uri uri) => captureIncomingUri(uri);

  void clearPendingRoutineShareToken() {
    if (pendingRoutineShareToken == null) return;
    pendingRoutineShareToken = null;
    notifyListeners();
  }

  void clearPendingTogetherJoinCode() {
    if (pendingTogetherJoinCode == null) return;
    pendingTogetherJoinCode = null;
    notifyListeners();
  }

  void clearPendingBusinessInviteToken() {
    if (pendingBusinessInviteToken == null) return;
    pendingBusinessInviteToken = null;
    notifyListeners();
  }

  void clearPendingCoachingInviteToken() {
    if (pendingCoachingInviteToken == null) return;
    pendingCoachingInviteToken = null;
    notifyListeners();
  }

  Future<void> _loadCachedExerciseCatalog() async {
    final repository = exerciseCatalogRepository;
    if (repository == null) return;
    try {
      final cached = await repository.loadCached();
      if (_disposed || cached.isEmpty) return;
      _replaceSharedExerciseCatalog(cached);
    } catch (_) {
      // The built-in 80-row catalog is always available as an offline floor.
    }
  }

  void _replaceSharedExerciseCatalog(List<ExerciseTemplate> catalog) {
    final byId = <String, ExerciseTemplate>{};
    for (final exercise in catalog) {
      if (exercise.id.trim().isEmpty || exercise.name.trim().isEmpty) continue;
      byId[exercise.id] = exercise;
    }
    _sharedCatalogExercises
      ..clear()
      ..addAll(byId.values);
    _rebuildSelectableExercises();
    _rebindStoredExerciseTemplates();
  }

  void _rebuildSelectableExercises() {
    final byId = <String, ExerciseTemplate>{
      for (final exercise in exerciseCatalog) exercise.id: exercise,
      for (final exercise in _sharedCatalogExercises) exercise.id: exercise,
      for (final exercise in customExercises) exercise.id: exercise,
    };
    exercises
      ..clear()
      ..addAll(byId.values);
  }

  List<ExerciseTemplate> get _curatedRecommendationCatalog {
    final selectableById = {
      for (final exercise in exercises) exercise.id: exercise,
    };
    return [
      for (final fallback in exerciseCatalog)
        selectableById[fallback.id] ?? fallback,
    ];
  }

  void _rebindStoredExerciseTemplates() {
    final lookup = <String, ExerciseTemplate>{};
    for (final exercise in exercises) {
      lookup[exercise.id] = exercise;
      final databaseId = exercise.databaseId;
      if (databaseId != null) lookup[databaseId] = exercise;
    }

    ExerciseTemplate resolved(ExerciseTemplate current) =>
        lookup[current.id] ?? lookup[current.databaseId] ?? current;

    for (final session in sessions.values) {
      for (var index = 0; index < session.exercises.length; index++) {
        final current = session.exercises[index];
        final template = resolved(current.template);
        if (identical(template, current.template)) continue;
        session.exercises[index] = WorkoutExercise(
          id: current.id,
          template: template,
          sets: current.sets,
        );
      }
    }

    for (var routineIndex = 0; routineIndex < routines.length; routineIndex++) {
      final routine = routines[routineIndex];
      var changed = false;
      final reboundExercises = <ExerciseTemplate>[];
      final reboundPlans = Map<String, List<RoutineSetPlan>>.from(
        routine.setPlans,
      );
      final storedBaseIds = _personalRoutineBaseExerciseIds[routine.id];
      final reboundBaseIds = storedBaseIds == null
          ? null
          : Map<String, String?>.from(storedBaseIds);
      for (final current in routine.exercises) {
        final template = resolved(current);
        reboundExercises.add(template);
        if (identical(template, current)) continue;
        changed = true;
        if (template.id != current.id) {
          final plans = reboundPlans.remove(current.id);
          if (plans != null) reboundPlans.putIfAbsent(template.id, () => plans);
          if (reboundBaseIds != null &&
              reboundBaseIds.containsKey(current.id)) {
            final baseId = reboundBaseIds.remove(current.id);
            reboundBaseIds.putIfAbsent(
              template.id,
              () => baseId ?? template.databaseReferenceId,
            );
          }
        }
      }
      if (!changed) continue;
      routines[routineIndex] = RoutineData(
        id: routine.id,
        name: routine.name,
        description: routine.description,
        color: routine.color,
        exercises: reboundExercises,
        author: routine.author,
        level: routine.level,
        accessTier: routine.accessTier,
        setPlans: reboundPlans,
        sourceMarketRoutineId: routine.sourceMarketRoutineId,
        sourceCoachingRoutineId: routine.sourceCoachingRoutineId,
        authorTrainerId: routine.authorTrainerId,
        authorGymId: routine.authorGymId,
        authorType: routine.authorType,
      );
      if (reboundBaseIds != null) {
        _personalRoutineBaseExerciseIds[routine.id] = Map.unmodifiable(
          reboundBaseIds,
        );
      }
    }
  }

  Future<void> refreshExerciseCatalog() async {
    final repository = exerciseCatalogRepository;
    if (_disposed || repository == null || exerciseCatalogLoading) return;
    exerciseCatalogLoading = true;
    exerciseCatalogError = null;
    notifyListeners();
    try {
      final catalog = await repository.refreshCatalog();
      if (_disposed) return;
      _replaceSharedExerciseCatalog(catalog);
      exerciseCatalogError = _cachedReadError(repository);
    } catch (error) {
      if (_disposed) return;
      exerciseCatalogError = error;
    } finally {
      if (!_disposed) {
        exerciseCatalogLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> initialize() async {
    final accountEpoch = _accountEpoch;
    try {
      await _loadCachedExerciseCatalog();
      if (exerciseCatalogRepository != null) {
        // Catalog refresh owns no account data, so begin it before the account
        // snapshot/network path. Snapshot retries must not delay exercise
        // availability on a fresh install.
        unawaited(refreshExerciseCatalog());
      }
      final localFirstRepository = _repository is LocalFirstAppRepository
          ? _repository as LocalFirstAppRepository
          : null;
      var snapshot = localFirstRepository == null
          ? await _repository.load(exercises)
          : await localFirstRepository.loadLocal(exercises);
      if (!_isCurrentAccount(accountEpoch)) {
        _initialized = true;
        return;
      }
      if (snapshot != null) {
        _applySnapshot(snapshot);
      }
      _initialized = true;
      persistenceError = null;
      persistenceSyncError = _repositorySyncError;
      // A missing local cache does not mean the account is empty. Wait for the
      // authoritative read before creating a default snapshot, otherwise a
      // fresh install can race and conflict with an existing cloud account.
      if (localFirstRepository == null &&
          (snapshot == null || _repositoryHasPendingSave)) {
        _schedulePersist();
      }
      // The local account is ready, so the shell must be allowed to render now.
      // Cloud reads can spend tens of seconds in the Supabase client's
      // transient-error retries. If the splash timer already elapsed while the
      // local snapshot was opening, waiting until those reads finish before
      // notifying leaves the launch screen up for the whole retry window.
      if (_isCurrentAccount(accountEpoch)) notifyListeners();

      if (localFirstRepository != null) {
        final localSnapshot = snapshot;
        try {
          snapshot = await _repository.load(exercises);
          if (!_isCurrentAccount(accountEpoch)) return;
          if (snapshot != null) {
            _applySnapshot(snapshot);
          } else if (localSnapshot != null && _repositorySyncError == null) {
            // A successful empty response is authoritative. The device cache
            // may describe data deleted from another device, so remove it from
            // memory instead of showing a resurrected account for this run.
            _resetForSignedOutUser();
          }
          persistenceSyncError = _repositorySyncError;
          if ((snapshot == null && _repositorySyncError == null) ||
              _repositoryHasPendingSave) {
            _schedulePersist();
          }
          notifyListeners();
        } catch (error) {
          if (!_isCurrentAccount(accountEpoch)) return;
          persistenceSyncError = error;
          notifyListeners();
        }
      }

      try {
        await _refreshCloudData(expectedAccountEpoch: accountEpoch);
        if (!_isCurrentAccount(accountEpoch)) return;
        cloudSyncError = null;
      } catch (error) {
        if (!_isCurrentAccount(accountEpoch)) return;
        cloudSyncError = error;
      }
    } catch (error) {
      if (!_isCurrentAccount(accountEpoch)) {
        _initialized = true;
        return;
      }
      _initialized = true;
      persistenceError = error;
    }
    if (_isCurrentAccount(accountEpoch)) notifyListeners();
  }

  /// How long the full-screen brand transition covers a portal switch. Long
  /// enough to read as "another product opening", short enough to not annoy.
  static const portalSwitchDuration = Duration(milliseconds: 720);

  /// True while the portal transition overlay owns the screen.
  bool isPortalSwitching = false;

  AppPortal get portal => switch (role) {
    UserRole.guest || UserRole.member => AppPortal.client,
    UserRole.trainer || UserRole.gym || UserRole.admin => AppPortal.trainer,
  };

  /// Which pro role the trainer portal opens into. Staying on the current pro
  /// role matters: a gym owner who came from settings must not be demoted to
  /// trainer just by toggling back and forth.
  UserRole get portalTrainerRole {
    if (portal == AppPortal.trainer) return role;
    final access = businessAccess;
    if (access != null) {
      if (access.canUse(UserRole.trainer)) return UserRole.trainer;
      if (access.canUse(UserRole.gym)) return UserRole.gym;
    }
    return UserRole.trainer;
  }

  /// Swaps the whole shell behind a brand transition. The pro portal is a
  /// preview surface here, so the local access gate is skipped — the server
  /// still decides what its screens can actually read.
  Future<void> switchPortal(AppPortal target) async {
    if (isPortalSwitching) return;
    final desired = target == AppPortal.client
        ? UserRole.member
        : portalTrainerRole;
    if (portal == target && role == desired) return;
    isPortalSwitching = true;
    notifyListeners();
    final settle = Future<void>.delayed(portalSwitchDuration);
    chooseRole(desired, enforceAccess: false);
    await settle;
    isPortalSwitching = false;
    notifyListeners();
  }

  void chooseRole(UserRole value, {bool enforceAccess = true}) {
    if (value == UserRole.admin && !_verifiedAdmin) return;
    final access = businessAccess;
    if (enforceAccess &&
        businessRepository != null &&
        value != UserRole.member &&
        (access == null || !access.canUse(value))) {
      return;
    }
    final accountEpoch = _accountEpoch;
    final requestToken = ++_businessRequestSequence;
    role = value;
    _schedulePersist();
    final repository = businessRepository;
    if (repository != null &&
        (value == UserRole.trainer ||
            value == UserRole.gym ||
            value == UserRole.admin)) {
      unawaited(
        _loadSelectedBusinessWorkspace(
          repository,
          value,
          accountEpoch: accountEpoch,
          requestToken: requestToken,
        ),
      );
    } else if (repository != null) {
      businessLoading = false;
      businessError = null;
      businessWorkspace = null;
      _resetLiveBusinessDashboards();
    }
    notifyListeners();
  }

  Future<void> _loadSelectedBusinessWorkspace(
    BusinessRepository repository,
    UserRole selectedRole, {
    required int accountEpoch,
    required int requestToken,
  }) async {
    if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
    final preserveExistingWorkspace = businessWorkspace?.role == selectedRole;
    businessLoading = true;
    businessError = null;
    if (!preserveExistingWorkspace) {
      businessWorkspace = null;
      _resetLiveBusinessDashboards();
    }
    notifyListeners();
    try {
      final workspace = await repository.loadWorkspace(selectedRole);
      if (!_isCurrentBusinessRequest(accountEpoch, requestToken) ||
          role != selectedRole) {
        return;
      }
      businessWorkspace = workspace;
      _applyLiveBusinessDashboard(workspace);
    } catch (error) {
      if (!_isCurrentBusinessRequest(accountEpoch, requestToken) ||
          role != selectedRole) {
        return;
      }
      businessError = error;
      if (!preserveExistingWorkspace) {
        businessWorkspace = null;
        _resetLiveBusinessDashboards();
      }
    } finally {
      if (_isCurrentBusinessRequest(accountEpoch, requestToken) &&
          role == selectedRole) {
        businessLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    final persistenceFlush = flushPersistence();
    final syncRepository = _repository is DeferredSyncAppRepository
        ? _repository as DeferredSyncAppRepository
        : null;
    _accountFlushInFlight = persistenceFlush;
    final accountEpoch = ++_accountEpoch;
    _businessRequestSequence++;
    _resetForSignedOutUser();
    cancelRestTimer();
    notifyListeners();

    final previousSignOut = _signOutInFlight;
    late final Future<void> signOut;
    signOut = (() async {
      if (previousSignOut != null) {
        try {
          await previousSignOut;
        } catch (_) {
          // A fresh sign-out attempt still needs to run after a failed one.
        }
      }
      try {
        await persistenceFlush;
      } catch (error) {
        if (_isCurrentAccount(accountEpoch)) persistenceError = error;
      }
      if (syncRepository != null) {
        try {
          await syncRepository.syncPending();
        } catch (_) {
          // The account-scoped local outbox remains available after sign-out.
        }
      }
      // 세션이 죽기 **전에** 떼야 서버에서 지울 수 있다. 남겨 두면 이 기기를
      // 다음에 쓰는 사람에게 남의 알림이 간다. 여기서 하는 이유는 하나 더
      // 있다 — logout() 첫 줄에 두면 화면 초기화가 await 뒤로 밀려,
      // 로그아웃을 누른 뒤에도 한 틱 동안 이전 역할의 셸이 남는다.
      await _releasePushToken();
      await _authSignOut();
    })();
    _signOutInFlight = signOut;
    try {
      await signOut;
    } catch (error) {
      if (_isCurrentAccount(accountEpoch)) cloudSyncError = error;
    } finally {
      if (identical(_signOutInFlight, signOut)) {
        _signOutInFlight = null;
      }
      if (identical(_accountFlushInFlight, persistenceFlush)) {
        _accountFlushInFlight = null;
      }
      if (_isCurrentAccount(accountEpoch)) {
        _persistTimer?.cancel();
        _serverSyncTimer?.cancel();
        _queuedSnapshot = null;
        _resetForSignedOutUser();
        notifyListeners();
      }
    }
  }

  /// Clears every account-scoped value when Supabase reports a remote
  /// sign-out (expired/revoked refresh token, account deletion, or another
  /// client ending the session). This intentionally does not call signOut
  /// again, so it is safe to invoke from the auth-state stream.
  void handleExternalAuthSignedOut() {
    final persistenceFlush = flushPersistence();
    _accountFlushInFlight = persistenceFlush;
    unawaited(
      persistenceFlush
          .catchError((Object error) {
            persistenceError = error;
          })
          .whenComplete(() {
            if (identical(_accountFlushInFlight, persistenceFlush)) {
              _accountFlushInFlight = null;
            }
          }),
    );
    _restTimer?.cancel();
    restRemaining = 0;
    _accountEpoch++;
    _businessRequestSequence++;
    _resetForSignedOutUser();
    notifyListeners();
  }

  void stageMemberProfileForAuthentication(MemberProfileDraft draft) {
    _stagedMemberProfileDraft = draft;
  }

  void clearStagedMemberProfileForAuthentication() {
    _stagedMemberProfileDraft = null;
  }

  StreamSubscription<String>? _pushTokenSubscription;

  /// 이 기기를 계정에 붙인다. 로그인 직후와 앱 시작 시 부른다.
  ///
  /// 실패해도 아무것도 막지 않는다 — 알림을 못 받는 것이지 앱을 못 쓰는 것이
  /// 아니다. 토큰은 재설치·복원·주기적 회전으로 바뀌므로 갱신도 구독한다.
  /// 한 번 등록하고 끝내면 언젠가 조용히 배달이 멈춘다.
  Future<void> syncPushRegistration() async {
    final registry = _repository;
    if (registry is! PushTokenRegistry) return;
    if (!Auth.instance.hasAuthenticatedUser) return;
    final push = Push.instance;
    if (!push.isAvailable) return;

    if (!await push.requestPermission()) return;
    _pushTokenSubscription ??= push.tokenChanges.listen((token) {
      unawaited(_registerPushToken(token));
    });
    final token = await push.currentToken();
    if (token != null) await _registerPushToken(token);
  }

  Future<void> _registerPushToken(String token) async {
    final registry = _repository;
    if (registry is! PushTokenRegistry) return;
    try {
      await (registry as PushTokenRegistry).registerPushToken(
        token: token,
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      );
    } catch (_) {
      // 다음 실행이나 다음 토큰 갱신에 다시 시도된다.
    }
  }

  /// 로그아웃 **전에** 부른다. 세션이 죽은 뒤에는 서버에서 지울 수 없고,
  /// 남겨 두면 이 기기를 다음에 쓰는 사람에게 남의 알림이 간다.
  Future<void> _releasePushToken() async {
    final registry = _repository;
    final push = Push.instance;
    await _pushTokenSubscription?.cancel();
    _pushTokenSubscription = null;
    if (registry is! PushTokenRegistry || !push.isAvailable) return;
    final token = await push.currentToken();
    if (token == null) return;
    try {
      await (registry as PushTokenRegistry).unregisterPushToken(token);
    } catch (_) {
      // 서버에서 못 지웠어도 기기 토큰은 아래에서 버린다.
    }
    await push.deleteToken();
  }

  Future<void> syncAfterAuthentication() {
    final active = _authenticationSyncInFlight;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _syncAfterAuthenticationOnce().whenComplete(() {
      if (identical(_authenticationSyncInFlight, operation)) {
        _authenticationSyncInFlight = null;
      }
    });
    _authenticationSyncInFlight = operation;
    return operation;
  }

  Future<void> _syncAfterAuthenticationOnce() async {
    final profileDraft = _stagedMemberProfileDraft;
    _persistTimer?.cancel();
    _serverSyncTimer?.cancel();
    final pendingSignOut = _signOutInFlight;
    if (pendingSignOut != null) {
      try {
        await pendingSignOut;
      } catch (_) {
        // Continue only if the auth client still reports a signed-in user.
      }
      if (businessRepository != null &&
          !loadBusinessWithoutAuth &&
          !Auth.instance.hasAuthenticatedUser) {
        return;
      }
    }
    final accountFlush = _accountFlushInFlight;
    if (accountFlush != null) {
      try {
        await accountFlush;
      } catch (_) {
        // The account-scoped outbox keeps the previous account mutation.
      }
    } else if (profileDraft == null) {
      try {
        await flushPersistence();
      } catch (_) {
        // A direct A -> B auth switch stages A's snapshot under A's uid. It
        // must never be retried as B, so continue with a clean B load.
      }
    }
    _persistTimer?.cancel();
    _serverSyncTimer?.cancel();
    _queuedSnapshot = null;
    final accountEpoch = ++_accountEpoch;
    _businessRequestSequence++;
    _resetForSignedOutUser();
    notifyListeners();
    var cloudPhase = false;
    try {
      final snapshot = await _repository.load(exercises);
      if (!_isCurrentAccount(accountEpoch)) return;
      if (snapshot != null) _applySnapshot(snapshot);
      final profileChanged =
          profileDraft != null && _mergeMissingMemberProfile(profileDraft);
      if (memberNickname.trim().isEmpty) {
        memberNickname = Auth.instance.currentDisplayName;
      }
      persistenceError = null;
      persistenceSyncError = _repositorySyncError;
      if (profileChanged) {
        _queuedSnapshot = _snapshotForPersistence();
        await flushPersistence();
        if (identical(_stagedMemberProfileDraft, profileDraft)) {
          _stagedMemberProfileDraft = null;
        }
        try {
          await syncPersistenceToServer();
        } catch (_) {
          // The account-scoped outbox is already durable. The lifecycle and
          // periodic retry paths will finish the cloud upload when available.
        }
      } else if (identical(_stagedMemberProfileDraft, profileDraft)) {
        _stagedMemberProfileDraft = null;
      }
      cloudPhase = true;
      await _refreshCloudData(expectedAccountEpoch: accountEpoch);
      if (!_isCurrentAccount(accountEpoch)) return;
      cloudSyncError = null;
      if (snapshot == null || _repositoryHasPendingSave) {
        _schedulePersist();
      }
    } catch (error) {
      if (!_isCurrentAccount(accountEpoch)) return;
      if (cloudPhase) {
        cloudSyncError = error;
      } else {
        persistenceError = error;
        rethrow;
      }
    } finally {
      if (_isCurrentAccount(accountEpoch)) notifyListeners();
    }
  }

  bool _mergeMissingMemberProfile(MemberProfileDraft draft) {
    var changed = false;
    if (goals.isEmpty && draft.goals.isNotEmpty) {
      goals = List<String>.of(draft.goals);
      changed = true;
    }
    if (heightCm == null && draft.heightCm != null) {
      heightCm = draft.heightCm;
      changed = true;
    }
    if (weight == null && draft.weight != null) {
      weight = draft.weight;
      changed = true;
    }
    if (age == null && draft.age != null) {
      age = draft.age;
      changed = true;
    }
    final draftGender = draft.gender?.trim();
    if ((gender == null || gender!.trim().isEmpty) &&
        draftGender != null &&
        draftGender.isNotEmpty) {
      gender = draftGender;
      changed = true;
    }
    return changed;
  }

  void setMemberProfile({
    required Iterable<String> goals,
    double? heightCm,
    double? weight,
    int? age,
    String? gender,
  }) {
    this.goals = List.unmodifiable(goals);
    this.heightCm = heightCm;
    this.weight = weight;
    this.age = age;
    this.gender = gender;
    _schedulePersist();
    notifyListeners();
  }

  /// [exercise]의 지금 상태로 "어디쯤인지"를 계산한다. 마친 세트가 이미 완료로
  /// 표시된 뒤에 불러야 남은 수가 맞는다.
  static RestFocus restFocusFor(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) {
    final remaining = exercise.sets.where((item) => !item.completed).length;
    final index = session.exercises.indexOf(exercise);
    final next = remaining > 0
        ? null
        : session.exercises
              .skip(index + 1)
              .where((item) => item.sets.any((set) => !set.completed))
              .firstOrNull;
    return RestFocus(
      exerciseName: exercise.template.name,
      setsLeft: remaining,
      nextExercise: next?.template.name,
    );
  }

  /// 세트를 밀어서 기록했다. 힌트는 여기서 영구히 꺼진다.
  void markSwipeLearned() {
    if (hasSwipedSet) return;
    hasSwipedSet = true;
    _schedulePersist();
    notifyListeners();
  }

  /// 함께 방의 화면 안내를 봤다(끝까지든 건너뛰기든). 다시는 자동으로 안 뜬다 —
  /// 메뉴의 '사용법'으로만 다시 본다.
  void markTogetherGuideSeen() {
    if (hasSeenTogetherGuide) return;
    hasSeenTogetherGuide = true;
    _schedulePersist();
    notifyListeners();
  }

  void markPrecisionRecommendationPrompted() {
    if (precisionRecommendationPrompted) return;
    precisionRecommendationPrompted = true;
    _schedulePersist();
    notifyListeners();
  }

  void setRecommendationProfile(RecommendationProfile profile) {
    precisionRecommendationPrompted = true;
    recommendationProfile = profile;
    _schedulePersist();
    notifyListeners();
  }

  void clearRecommendationProfile() {
    if (recommendationProfile == null) return;
    recommendationProfile = null;
    // Deleting sensitive answers must not turn the one-time offer back on.
    precisionRecommendationPrompted = true;
    _schedulePersist();
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    _schedulePersist();
    notifyListeners();
  }

  void setWeightUnit(String value) {
    weightUnit = value;
    _schedulePersist();
    notifyListeners();
  }

  void setRestDefaultSeconds(int seconds) {
    restDefaultSeconds = seconds.clamp(30, 600);
    _schedulePersist();
    notifyListeners();
  }

  void setActiveTrainingParty(String? partyId) {
    if (activeTrainingPartyId == partyId) return;
    activeTrainingPartyId = partyId;
    _schedulePersist();
    notifyListeners();
  }

  void setDefaultSetPlan({int? sets, int? reps}) {
    defaultSetCount = sets?.clamp(1, 10);
    defaultRepCount = reps?.clamp(1, 50);
    _schedulePersist();
    notifyListeners();
  }

  bool updateMemberAccountProfile({required String nickname, double? weight}) {
    final normalizedNickname = nickname.trim();
    if (normalizedNickname.length < 2 || normalizedNickname.length > 30) {
      return false;
    }
    if (weight != null && (weight < 20 || weight > 1000)) return false;
    memberNickname = normalizedNickname;
    this.weight = weight;
    _schedulePersist();
    notifyListeners();
    return true;
  }

  void setUseRir(bool value) {
    useRir = value;
    _schedulePersist();
    notifyListeners();
  }

  void setAutoStartRestTimer(bool value) {
    autoStartRestTimer = value;
    _schedulePersist();
    notifyListeners();
  }

  void setAutoRecommendNextExercise(bool value) {
    autoRecommendNextExercise = value;
    _schedulePersist();
    notifyListeners();
  }

  void setRestTimerNotifications(bool value) {
    restTimerNotifications = value;
    _schedulePersist();
    notifyListeners();
  }

  void setTimerVibration(bool value) {
    timerVibration = value;
    _schedulePersist();
    notifyListeners();
  }

  void setTimerSound(bool value) {
    timerSound = value;
    _schedulePersist();
    notifyListeners();
  }

  void setTimerCountdownSeconds(int value) {
    timerCountdownSeconds = value.clamp(0, 120);
    _schedulePersist();
    notifyListeners();
  }

  void setOneRepMaxFormula(OneRepMaxFormula value) {
    if (oneRepMaxFormula == value) return;
    oneRepMaxFormula = value;
    _schedulePersist();
    notifyListeners();
  }

  void setPushCoachingFeedback(bool value) {
    pushCoachingFeedback = value;
    _schedulePersist();
    notifyListeners();
  }

  void setCommunityReactionNotifications(bool value) {
    communityReactionNotifications = value;
    _schedulePersist();
    notifyListeners();
  }

  void setPushTogether(bool value) {
    pushTogether = value;
    _schedulePersist();
    notifyListeners();
  }

  void setPushWorkoutReminder(bool value) {
    pushWorkoutReminder = value;
    _schedulePersist();
    notifyListeners();
  }

  void setWorkoutReminderHour(int hour) {
    workoutReminderHour = hour.clamp(
      AppSnapshot.earliestReminderHour,
      AppSnapshot.latestReminderHour,
    );
    _schedulePersist();
    notifyListeners();
  }

  /// 푸시를 탭했다. 셸과 main.dart가 [pendingPushOpen]을 보고 움직인다.
  void openPush(PushOpen open) {
    pendingPushOpen = open;
    notifyListeners();
  }

  DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _newWorkoutExerciseId(String templateId, {String label = 'entry'}) {
    _workoutExerciseSequence++;
    return '${templateId}_${label}_${DateTime.now().microsecondsSinceEpoch}_'
        '$_workoutExerciseSequence';
  }

  WorkoutSession sessionFor(DateTime date) {
    final key = dateOnly(date);
    return sessions.putIfAbsent(
      key,
      () => WorkoutSession(date: key, exercises: []),
    );
  }

  ExerciseTemplate? createCustomExercise({
    required String name,
    required String muscle,
    ExerciseMeasurement measurement = ExerciseMeasurement.weightReps,
  }) {
    final normalizedName = name.trim();
    final normalizedMuscle = muscle.trim();
    const muscles = {'가슴', '등', '어깨', '하체', '팔', '복근', '유산소', '기타'};
    if (normalizedName.isEmpty ||
        normalizedName.length > 50 ||
        !muscles.contains(normalizedMuscle)) {
      return null;
    }
    final duplicate = exercises.any(
      (exercise) =>
          exercise.name.trim().toLowerCase() == normalizedName.toLowerCase(),
    );
    if (duplicate) return null;
    final exercise = ExerciseTemplate(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: normalizedName,
      muscle: normalizedMuscle,
      icon: exerciseIconForMuscle(normalizedMuscle),
      // 유산소는 자체 구간 UI가 measurement보다 우선한다 — 섞이면 혼란만 남는다.
      measurement: normalizedMuscle == '유산소'
          ? ExerciseMeasurement.weightReps
          : measurement,
    );
    customExercises.add(exercise);
    exercises.add(exercise);
    _schedulePersist();
    notifyListeners();
    return exercise;
  }

  ExercisePerformanceSummary? performanceFor(
    ExerciseTemplate template, {
    DateTime? before,
  }) {
    return PerformanceEngine.summarize(
      sessions: sessions.values,
      template: template,
      before: before,
      formula: oneRepMaxFormula,
    );
  }

  ExercisePerformanceSummary? get featuredPerformance {
    ExercisePerformanceSummary? featured;
    for (final template in exercises) {
      final summary = performanceFor(template);
      if (summary == null) continue;
      if (featured == null ||
          summary.latestSessionBest.date.isAfter(
            featured.latestSessionBest.date,
          )) {
        featured = summary;
      }
    }
    return featured;
  }

  WorkoutRecommendation? recommendationFor(
    ExerciseTemplate template, {
    DateTime? before,
  }) {
    final goal = PerformanceEngine.goalFromProfile(goals);
    if (goal == null) return null;
    final history = before == null
        ? sessions.values
        : sessions.values.where((session) => session.date.isBefore(before));
    if (template.isCardio) {
      final prescription = CardioPrescriptionEngine.recommend(
        exerciseId: template.id,
        goal: goal,
        history: _cardioHistory(before: before),
      );
      return prescription == null
          ? null
          : _cardioWorkoutRecommendation(template, prescription);
    }
    return PerformanceEngine.recommend(
      sessions: history,
      template: template,
      goal: goal,
    );
  }

  WorkoutRecommendation? recommendationForDate(DateTime date) {
    if (!hasTrainingGoal) return null;
    final session = sessions[dateOnly(date)];
    if (session != null && session.exercises.isNotEmpty) {
      WorkoutExercise? pendingExercise;
      for (final exercise in session.exercises) {
        if (exercise.sets.isEmpty ||
            exercise.sets.any((set) => !set.completed)) {
          pendingExercise = exercise;
          break;
        }
      }
      if (pendingExercise != null) {
        return _plannedExerciseRecommendation(pendingExercise);
      }

      WorkoutExercise? lastCompleted;
      for (final exercise in session.exercises.reversed) {
        if (exercise.sets.isNotEmpty &&
            exercise.sets.every((set) => set.completed)) {
          lastCompleted = exercise;
          break;
        }
      }
      if (lastCompleted != null && goals.isNotEmpty) {
        final next = ExerciseRecommendationEngine.recommendNext(
          // Only the curated fallback rows have reviewed recommendation
          // safety traits. Database rows are selectable, but are not silently
          // promoted into automatic coaching until those traits are present.
          catalog: _curatedRecommendationCatalog,
          session: session,
          completedExercise: lastCompleted,
          goals: goals,
          weeklyHistory: sessions.values,
          recommendationProfile: recommendationProfile,
        );
        if (next != null) return _nextExerciseWorkoutRecommendation(next);
      }
    }

    final featured = featuredPerformance;
    final featuredCardio = _featuredCardioExercise;
    if (featured == null) {
      return featuredCardio == null
          ? null
          : recommendationFor(featuredCardio.$1);
    }
    if (featuredCardio != null &&
        featuredCardio.$2.isAfter(featured.latestSessionBest.date)) {
      return recommendationFor(featuredCardio.$1);
    }
    return recommendationFor(featured.template);
  }

  NextExerciseRecommendation? firstExerciseRecommendationForDate(
    DateTime date, {
    Set<String> excludedTemplateIds = const {},
  }) {
    if (!hasTrainingGoal) return null;
    final day = dateOnly(date);
    final session = sessions[day] ?? WorkoutSession(date: day, exercises: []);
    if (session.exercises.isNotEmpty) return null;
    final eligibleHistory = sessions.values
        .where((item) => !item.date.isAfter(day))
        .toList(growable: false);
    return ExerciseRecommendationEngine.recommendFirst(
      catalog: _curatedRecommendationCatalog,
      session: session,
      goals: goals,
      weeklyHistory: eligibleHistory,
      excludedTemplateIds: excludedTemplateIds,
      recommendationProfile: recommendationProfile,
    );
  }

  WorkoutRecommendation? get featuredRecommendation {
    return recommendationForDate(DateTime.now());
  }

  WorkoutRecommendation _plannedExerciseRecommendation(
    WorkoutExercise exercise,
  ) {
    final goal = PerformanceEngine.goalFromProfile(goals)!;
    if (exercise.template.isCardio) {
      final historical = recommendationFor(exercise.template);
      final pending = exercise.sets.where((set) => !set.completed).toList();
      final first = pending.firstOrNull ?? exercise.sets.firstOrNull;
      if (historical != null) {
        return WorkoutRecommendation(
          template: exercise.template,
          goal: goal,
          weight: 0,
          minReps: 0,
          maxReps: 0,
          sets: exercise.sets.isEmpty ? 1 : exercise.sets.length,
          nextWeight: 0,
          reason: '오늘 계획에서 아직 완료하지 않은 유산소 운동',
          restSeconds: 0,
          evidenceIds: historical.evidenceIds,
          evidenceNote: historical.evidenceNote,
          cardioDurationSeconds:
              first?.durationSeconds ?? historical.cardioDurationSeconds,
          cardioDistanceKm: first != null && first.distanceKm > 0
              ? first.distanceKm
              : historical.cardioDistanceKm,
          cardioMinimumRpe: first != null && first.intensityRpe > 0
              ? first.intensityRpe.round()
              : historical.cardioMinimumRpe,
          cardioMaximumRpe: first != null && first.intensityRpe > 0
              ? first.intensityRpe.round()
              : historical.cardioMaximumRpe,
          cardioSupportsDistance: historical.cardioSupportsDistance,
          cardioStructure: historical.cardioStructure,
        );
      }
    }
    final prescription = PerformanceEngine.prescriptionFor(goal);
    final historical = recommendationFor(exercise.template);
    final pending = exercise.sets.where((set) => !set.completed).toList();
    final first = pending.firstOrNull;
    final weight = first?.weight ?? historical?.weight ?? 0;
    final validReps = pending
        .map((set) => set.reps)
        .where((reps) => reps > 0)
        .toList();
    final minReps = validReps.isEmpty
        ? historical?.minReps ?? prescription.minReps
        : validReps.reduce((a, b) => a < b ? a : b);
    final maxReps = validReps.isEmpty
        ? historical?.maxReps ?? prescription.maxReps
        : validReps.reduce((a, b) => a > b ? a : b);
    final increment = weight <= 0
        ? 0.0
        : weight < 20
        ? 1.0
        : 2.5;
    return WorkoutRecommendation(
      template: exercise.template,
      goal: goal,
      weight: weight,
      minReps: minReps,
      maxReps: maxReps,
      sets: exercise.sets.isEmpty
          ? historical?.sets ?? prescription.sets
          : exercise.sets.length,
      nextWeight: historical?.nextWeight ?? weight + increment,
      reason: '오늘 계획에서 아직 완료하지 않은 운동',
      restSeconds:
          first?.restSeconds ??
          historical?.restSeconds ??
          prescription.restSeconds,
      evidenceIds: prescription.evidenceIds,
      evidenceNote: prescription.evidenceNote,
    );
  }

  WorkoutRecommendation _nextExerciseWorkoutRecommendation(
    NextExerciseRecommendation next,
  ) {
    final cardio = next.cardioPrescription;
    if (cardio != null) {
      final materialized = _cardioWorkoutRecommendation(next.template, cardio);
      return WorkoutRecommendation(
        template: materialized.template,
        goal: materialized.goal,
        weight: 0,
        minReps: 0,
        maxReps: 0,
        sets: materialized.sets,
        nextWeight: 0,
        reason: next.reason,
        restSeconds: 0,
        evidenceIds: next.evidenceIds,
        evidenceNote: next.evidenceNote,
        cardioDurationSeconds: materialized.cardioDurationSeconds,
        cardioDistanceKm: materialized.cardioDistanceKm,
        cardioMinimumRpe: materialized.cardioMinimumRpe,
        cardioMaximumRpe: materialized.cardioMaximumRpe,
        cardioSupportsDistance: materialized.cardioSupportsDistance,
        cardioStructure: materialized.cardioStructure,
      );
    }
    final weight = next.startingWeight;
    final increment = weight <= 0
        ? 0.0
        : weight < 20
        ? 1.0
        : 2.5;
    return WorkoutRecommendation(
      template: next.template,
      goal: PerformanceEngine.goalFromProfile(goals)!,
      weight: weight,
      minReps: next.minReps,
      maxReps: next.maxReps,
      sets: next.sets,
      nextWeight: weight + increment,
      reason: next.reason,
      restSeconds: next.restSeconds,
      evidenceIds: next.evidenceIds,
      evidenceNote: next.evidenceNote,
    );
  }

  Iterable<CardioSessionRecord> _cardioHistory({DateTime? before}) sync* {
    for (final session in sessions.values) {
      if (before != null && !session.date.isBefore(before)) continue;
      for (final exercise in session.exercises) {
        if (!exercise.template.isCardio ||
            cardioDefinitionForExercise(exercise.template.id) == null) {
          continue;
        }
        // WHO's moderate/vigorous target must not silently count an unknown
        // intensity or RPE 1–2 light activity as moderate exercise.
        final completed = exercise.sets
            .where(
              (set) =>
                  set.completed &&
                  set.durationSeconds > 0 &&
                  set.intensityRpe >= 3,
            )
            .toList();
        if (completed.isEmpty) continue;
        final durationSeconds = completed.fold<int>(
          0,
          (sum, set) => sum + set.durationSeconds,
        );
        final distances = completed
            .map((set) => set.distanceKm)
            .where((distance) => distance > 0)
            .toList();
        final rpes = completed
            .map((set) => set.intensityRpe)
            .where((rpe) => rpe > 0)
            .toList();
        final averageRpe = rpes.isEmpty
            ? null
            : rpes.reduce((a, b) => a + b) / rpes.length;
        yield CardioSessionRecord(
          id: exercise.id,
          exerciseId: exercise.template.id,
          occurredAt: session.date,
          duration: Duration(seconds: durationSeconds),
          intensity: averageRpe != null && averageRpe >= 7
              ? CardioIntensity.vigorous
              : CardioIntensity.moderate,
          distanceKm: distances.isEmpty
              ? null
              : distances.reduce((a, b) => a + b),
          perceivedExertion: averageRpe,
        );
      }
    }
  }

  (ExerciseTemplate, DateTime)? get _featuredCardioExercise {
    (ExerciseTemplate, DateTime)? latest;
    for (final session in sessions.values) {
      for (final exercise in session.exercises) {
        if (!exercise.template.isCardio ||
            !exercise.sets.any(
              (set) =>
                  set.completed &&
                  set.durationSeconds > 0 &&
                  set.intensityRpe >= 3,
            )) {
          continue;
        }
        if (latest == null || session.date.isAfter(latest.$2)) {
          latest = (exercise.template, session.date);
        }
      }
    }
    return latest;
  }

  WorkoutRecommendation _cardioWorkoutRecommendation(
    ExerciseTemplate template,
    CardioPrescription prescription,
  ) {
    final structure = prescription.structure == CardioSessionStructure.intervals
        ? '${prescription.workBouts ?? 0}×'
              '${prescription.workBoutDuration?.inMinutes ?? 0}분 인터벌'
        : '${prescription.intensityLabel} 지속 운동';
    return WorkoutRecommendation(
      template: template,
      goal: prescription.goal,
      weight: 0,
      minReps: 0,
      maxReps: 0,
      sets: 1,
      nextWeight: 0,
      reason: '${prescription.reason} · $structure',
      restSeconds: 0,
      evidenceIds: prescription.evidenceIds,
      evidenceNote: prescription.safetyNote,
      cardioDurationSeconds: prescription.durationSeconds,
      cardioDistanceKm: prescription.targetDistanceKm,
      cardioMinimumRpe: prescription.minimumRpe,
      cardioMaximumRpe: prescription.maximumRpe,
      cardioSupportsDistance: prescription.supportsDistance,
      cardioStructure: structure,
    );
  }

  /// 지금 설정된 공식으로 낸 추정 1RM. 화면이 공식을 직접 고르지 않도록
  /// 한 곳을 거치게 한다.
  E1rmEstimate? estimateOneRepMax(double weight, int reps) =>
      PerformanceEngine.estimate(weight, reps, formula: oneRepMaxFormula);

  Set<PerformancePrType> prTypesForCandidate(
    ExerciseTemplate template,
    WorkoutSetEntry candidate,
  ) {
    return PerformanceEngine.prTypesForCandidate(
      sessions: sessions.values,
      templateId: template.id,
      candidate: candidate,
      formula: oneRepMaxFormula,
    );
  }

  void addExercise(DateTime date, ExerciseTemplate template) {
    final session = sessionFor(date);
    final cardioRecommendation = template.isCardio
        ? recommendationFor(template, before: dateOnly(date))
        : null;
    final goal = PerformanceEngine.goalFromProfile(goals);
    final resistancePrescription = !template.isCardio && goal != null
        ? PerformanceEngine.prescriptionFor(goal)
        : null;
    final resistanceRecommendation = !template.isCardio
        ? recommendationFor(template, before: dateOnly(date))
        : null;
    final previousPerformance = !template.isCardio
        ? performanceFor(template, before: dateOnly(date))
        : null;
    final suggestedWeight =
        resistanceRecommendation?.weight ??
        previousPerformance?.latestSessionBest.set.weight ??
        0;
    final suggestedReps =
        resistanceRecommendation?.minReps ??
        previousPerformance?.latestSessionBest.set.reps ??
        defaultRepCount ??
        resistancePrescription?.minReps ??
        10;
    session.exercises.add(
      WorkoutExercise(
        id: _newWorkoutExerciseId(template.id),
        template: template,
        sets: template.isCardio
            ? [
                WorkoutSetEntry(
                  number: 1,
                  weight: 0,
                  reps: 0,
                  restSeconds: 0,
                  durationSeconds:
                      cardioRecommendation?.cardioDurationSeconds ?? 1800,
                  distanceKm: cardioRecommendation?.cardioDistanceKm ?? 0,
                  intensityRpe: (cardioRecommendation?.cardioMinimumRpe ?? 3)
                      .toDouble(),
                ),
              ]
            : List.generate(
                resistanceRecommendation?.sets ??
                    defaultSetCount ??
                    resistancePrescription?.sets ??
                    3,
                (index) => WorkoutSetEntry(
                  number: index + 1,
                  weight: template.usesWeight ? suggestedWeight : 0,
                  reps: template.isDurationHold ? 0 : suggestedReps,
                  durationSeconds: template.isDurationHold ? 60 : 0,
                  restSeconds:
                      resistanceRecommendation?.restSeconds ??
                      resistancePrescription?.restSeconds ??
                      restDefaultSeconds,
                ),
              ),
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  void addSet(WorkoutExercise exercise) {
    final previous = exercise.sets.lastOrNull;
    final template = exercise.template;
    exercise.sets.add(
      WorkoutSetEntry(
        number: exercise.sets.length + 1,
        // 몸이 곧 중량인 운동에 가짜 20kg을 남기지 않는다.
        weight: template.isCardio || !template.usesWeight
            ? 0
            : previous?.weight ?? 20,
        reps: template.isCardio || template.isDurationHold
            ? 0
            : previous?.reps ?? 10,
        restSeconds: template.isCardio
            ? 0
            : previous?.restSeconds ?? restDefaultSeconds,
        durationSeconds: template.isCardio
            ? previous?.durationSeconds ?? 600
            : template.isDurationHold
            ? previous?.durationSeconds ?? 60
            : 0,
        distanceKm: exercise.template.isCardio ? previous?.distanceKm ?? 0 : 0,
        intensityRpe: exercise.template.isCardio
            ? previous?.intensityRpe ?? 3
            : 0,
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  void reorderExercise(WorkoutSession session, int oldIndex, int newIndex) {
    final item = session.exercises.removeAt(oldIndex);
    session.exercises.insert(newIndex, item);
    _schedulePersist();
    notifyListeners();
  }

  void removeExercise(WorkoutSession session, WorkoutExercise exercise) {
    session.exercises.remove(exercise);
    _schedulePersist();
    notifyListeners();
  }

  void removeSet(WorkoutExercise exercise, WorkoutSetEntry set) {
    exercise.sets.remove(set);
    for (var index = 0; index < exercise.sets.length; index++) {
      exercise.sets[index].number = index + 1;
    }
    _schedulePersist();
    notifyListeners();
  }

  void updateSet(
    WorkoutSetEntry set, {
    double? weight,
    int? reps,
    String? type,
    int? restSeconds,
    int? durationSeconds,
    double? distanceKm,
    double? intensityRpe,
    int? rir,
    bool clearRir = false,
  }) {
    if (weight != null) set.weight = weight.clamp(0, 999);
    // null을 "안 바꿈"으로 쓰는 다른 인자와 달리 RIR은 null이 값이다 —
    // 지우려면 clearRir로 말해야 한다.
    if (clearRir) {
      set.rir = null;
    } else if (rir != null) {
      set.rir = rir.clamp(0, 10);
    }
    if (reps != null) set.reps = reps.clamp(0, 999);
    if (type != null) set.type = type;
    if (restSeconds != null) {
      set.restSeconds = restSeconds.clamp(15, 600);
    }
    if (durationSeconds != null) {
      set.durationSeconds = durationSeconds.clamp(0, 86400);
    }
    if (distanceKm != null) {
      set.distanceKm = distanceKm.clamp(0, 999.99);
    }
    if (intensityRpe != null) {
      set.intensityRpe = intensityRpe.clamp(0, 10);
    }
    _schedulePersist();
    notifyListeners();
  }

  /// Toggles a set and completes the device-local write before this future
  /// settles. Completion is a commit boundary: unlike ordinary field edits it
  /// must not rely on the debounce timer because the user may leave the page
  /// immediately afterwards.
  Future<void> toggleSet(WorkoutSetEntry set, {bool startRest = true}) async {
    set.completed = !set.completed;
    RestFocus? focus;
    if (set.completed) {
      // 세트는 자기가 속한 세션을 모른다 — 도장을 찍으려면 찾아야 한다.
      for (final session in sessions.values) {
        final exercise = session.exercises
            .where((e) => e.sets.contains(set))
            .firstOrNull;
        if (exercise != null) {
          final now = DateTime.now();
          session.startedAt ??= now;
          session.endedAt = now;
          // 세트 완료가 곧 방 보고다 — 기록 탭 스와이프든 방의 버튼이든,
          // 어디서 완료해도 전광판이 같은 숫자를 본다("기록에서 완료하면
          // 함께에서는 반영이 안 되더라", 실기기 보고).
          _reportSetToParty(session, exercise, set);
          // 타이머를 켜기 전에 계산한다 — 알림의 "다음: 스쿼트" 줄은 시작
          // 인텐트에 실리므로, 뒤늦게 채우면 한 세트 전 얘기가 올라간다.
          focus = restFocusFor(session, exercise);
          break;
        }
      }
    }
    if (set.completed &&
        startRest &&
        autoStartRestTimer &&
        set.restSeconds > 0) {
      startRestTimer(set.restSeconds, focus: focus);
    }
    _schedulePersist();
    notifyListeners();
    await flushPersistence();
  }

  /// 완료된 세트를 진행 중인 함께 방에 알린다. 오늘 세션만 — 전광판은 오늘의
  /// 판이다. 실패는 조용히 버린다: 다음 보고가 누적 볼륨을 다시 실어 나르고,
  /// 세트 사이의 사람에게 보고 실패 팝업은 기록보다 비싸다. 완료 취소는
  /// 서버 카운트를 되돌리지 않는다(알고 가는 한계, docs/plan/09).
  void _reportSetToParty(
    WorkoutSession session,
    WorkoutExercise exercise,
    WorkoutSetEntry set,
  ) {
    final partyId = activeTrainingPartyId;
    final repository = togetherRepository;
    if (partyId == null || repository == null) return;
    if (dateOnly(session.date) != dateOnly(DateTime.now())) return;
    final rest = set.restSeconds > 0 ? set.restSeconds : restDefaultSeconds;
    unawaited(() async {
      try {
        await repository.reportSetDone(
          partyId: partyId,
          restSeconds: rest,
          exerciseName: exercise.template.name,
          setNumber: set.number,
          setTotal: exercise.sets.length,
          // 전광판 볼륨은 완료 반영 후의 오늘 합계다.
          totalVolume: session.volume,
        );
      } catch (_) {
        // 방이 이미 닫혔거나 잠깐 끊겼다 — 전광판은 다음 보고로 따라잡는다.
      }
    }());
  }

  /// What a set held before [adoptActualIntoPendingSets] rewrote it.
  ///
  /// Kept so the toast can hand the change straight back: the app guessed, and
  /// a guess the user cannot undo costs more than it saves.
  static Map<WorkoutSetEntry, Map<String, num>> snapshotPendingSets(
    WorkoutExercise exercise,
    WorkoutSetEntry after,
  ) {
    final index = exercise.sets.indexOf(after);
    if (index < 0) return const {};
    return {
      for (final set in exercise.sets.skip(index + 1))
        if (!set.completed)
          set: {
            'weight': set.weight,
            'reps': set.reps,
            'durationSeconds': set.durationSeconds,
            'distanceKm': set.distanceKm,
            'intensityRpe': set.intensityRpe,
          },
    };
  }

  /// After a set is logged, the sets still ahead of it inherit what actually
  /// happened instead of what was planned.
  ///
  /// Lifting 8 reps when the routine said 10 means the next two sets are far
  /// more likely to be 8 than 10 — without this the same dial trip repeats once
  /// per remaining set. Completed sets are never touched: they are history.
  ///
  /// RIR은 일부러 전파하지 않는다. 무게·횟수는 계획이라 다음 세트에도 그대로
  /// 적용되지만, "몇 회 더 할 수 있었나"는 피로가 쌓이면서 세트마다 달라지는
  /// 관찰값이다. 1세트의 3을 3세트에 복사하면 없던 기록을 지어내는 것이 된다.
  int adoptActualIntoPendingSets(
    WorkoutExercise exercise,
    WorkoutSetEntry from,
  ) {
    final index = exercise.sets.indexOf(from);
    if (index < 0) return 0;
    final cardio = exercise.template.isCardio;
    final hold = !cardio && exercise.template.isDurationHold;
    var changed = 0;
    for (final set in exercise.sets.skip(index + 1)) {
      if (set.completed) continue;
      final differs = cardio
          ? set.durationSeconds != from.durationSeconds ||
                set.distanceKm != from.distanceKm ||
                set.intensityRpe != from.intensityRpe
          : hold
          ? set.durationSeconds != from.durationSeconds
          : set.weight != from.weight || set.reps != from.reps;
      if (!differs) continue;
      if (cardio) {
        set.durationSeconds = from.durationSeconds;
        set.distanceKm = from.distanceKm;
        set.intensityRpe = from.intensityRpe;
      } else if (hold) {
        // 플랭크류는 버틴 시간이 기록의 전부다.
        set.durationSeconds = from.durationSeconds;
      } else {
        set.weight = from.weight;
        set.reps = from.reps;
      }
      changed++;
    }
    if (changed == 0) return 0;
    _schedulePersist();
    notifyListeners();
    return changed;
  }

  /// Puts back exactly what [snapshotPendingSets] captured.
  void restorePendingSets(Map<WorkoutSetEntry, Map<String, num>> snapshot) {
    if (snapshot.isEmpty) return;
    snapshot.forEach((set, values) {
      set.weight = values['weight']!.toDouble();
      set.reps = values['reps']!.toInt();
      set.durationSeconds = values['durationSeconds']!.toInt();
      set.distanceKm = values['distanceKm']!.toDouble();
      set.intensityRpe = values['intensityRpe']!.toDouble();
    });
    _schedulePersist();
    notifyListeners();
  }

  int copySession(DateTime from, DateTime to) {
    final source = sessions[dateOnly(from)];
    if (source == null || source.exercises.isEmpty) return 0;
    final target = dateOnly(to);
    if (target == dateOnly(from)) return 0;

    final targetSession = sessions[target];
    final existingTemplateIds =
        targetSession?.exercises
            .map((exercise) => exercise.template.id)
            .toSet() ??
        <String>{};
    final copiedExercises = source.exercises
        .where(
          (exercise) => !existingTemplateIds.contains(exercise.template.id),
        )
        .map((exercise) => exercise.copy())
        .toList();
    if (copiedExercises.isEmpty) return 0;

    if (targetSession == null) {
      sessions[target] = WorkoutSession(
        date: target,
        exercises: copiedExercises,
      );
    } else {
      targetSession.exercises.addAll(copiedExercises);
    }
    _schedulePersist();
    notifyListeners();
    return copiedExercises.length;
  }

  void deleteSession(DateTime date) {
    sessions.remove(dateOnly(date));
    _schedulePersist();
    notifyListeners();
  }

  int applyRoutine(RoutineData routine, DateTime date) {
    final session = sessionFor(date);
    final existingTemplateIds = session.exercises
        .map((exercise) => exercise.template.id)
        .toSet();
    final additions = routine.exercises
        .where((template) => !existingTemplateIds.contains(template.id))
        .toList();
    if (additions.isEmpty) return 0;

    for (final template in additions) {
      final plannedSets = routine.setsFor(template);
      final cardioRecommendation = template.isCardio
          ? recommendationFor(template)
          : null;
      final goal = PerformanceEngine.goalFromProfile(goals);
      final resistancePrescription = !template.isCardio && goal != null
          ? PerformanceEngine.prescriptionFor(goal)
          : null;
      session.exercises.add(
        WorkoutExercise(
          id: _newWorkoutExerciseId(template.id, label: 'routine'),
          template: template,
          sets: plannedSets.isNotEmpty
              ? plannedSets.map((set) => set.toWorkoutSetEntry()).toList()
              : template.isCardio
              ? [
                  WorkoutSetEntry(
                    number: 1,
                    weight: 0,
                    reps: 0,
                    restSeconds: 0,
                    durationSeconds:
                        cardioRecommendation?.cardioDurationSeconds ?? 1800,
                    distanceKm: cardioRecommendation?.cardioDistanceKm ?? 0,
                    intensityRpe: (cardioRecommendation?.cardioMinimumRpe ?? 3)
                        .toDouble(),
                  ),
                ]
              : List.generate(
                  resistancePrescription?.sets ?? 3,
                  (index) => WorkoutSetEntry(
                    number: index + 1,
                    weight: 0,
                    reps: template.isDurationHold
                        ? 0
                        : resistancePrescription?.minReps ?? 10,
                    durationSeconds: template.isDurationHold ? 60 : 0,
                    restSeconds:
                        resistancePrescription?.restSeconds ??
                        restDefaultSeconds,
                  ),
                ),
        ),
      );
    }
    _schedulePersist();
    notifyListeners();
    return additions.length;
  }

  void applyRecommendation(
    DateTime date,
    WorkoutRecommendation recommendation,
  ) {
    final session = sessionFor(date);
    var exercise = session.exercises
        .where((item) => item.template.id == recommendation.template.id)
        .firstOrNull;
    if (exercise == null) {
      exercise = WorkoutExercise(
        id: _newWorkoutExerciseId(
          recommendation.template.id,
          label: 'recommendation',
        ),
        template: recommendation.template,
        sets: [],
      );
      session.exercises.add(exercise);
    }

    final completed = exercise.sets.where((set) => set.completed).toList();
    if (recommendation.isCardio) {
      exercise.sets
        ..removeWhere((set) => !set.completed)
        ..add(
          WorkoutSetEntry(
            number: completed.length + 1,
            weight: 0,
            reps: 0,
            restSeconds: 0,
            durationSeconds: recommendation.cardioDurationSeconds ?? 1800,
            distanceKm: recommendation.cardioDistanceKm ?? 0,
            intensityRpe: (recommendation.cardioMinimumRpe ?? 3).toDouble(),
          ),
        );
      for (var index = 0; index < exercise.sets.length; index++) {
        exercise.sets[index].number = index + 1;
      }
      _schedulePersist();
      notifyListeners();
      return;
    }
    final plannedCount = (recommendation.sets - completed.length).clamp(
      0,
      recommendation.sets,
    );
    exercise.sets
      ..removeWhere((set) => !set.completed)
      ..addAll(
        List.generate(
          plannedCount,
          (index) => WorkoutSetEntry(
            number: completed.length + index + 1,
            weight: recommendation.weight,
            reps: recommendation.minReps,
            restSeconds: recommendation.restSeconds,
          ),
        ),
      );
    for (var index = 0; index < exercise.sets.length; index++) {
      exercise.sets[index].number = index + 1;
    }
    _schedulePersist();
    notifyListeners();
  }

  bool addRecommendedExercise(
    DateTime date,
    NextExerciseRecommendation recommendation,
  ) {
    final session = sessionFor(date);
    if (session.exercises.any(
      (exercise) => exercise.template.id == recommendation.template.id,
    )) {
      return false;
    }
    if (recommendation.template.isCardio) {
      final cardio = recommendation.cardioPrescription;
      session.exercises.add(
        WorkoutExercise(
          id: _newWorkoutExerciseId(
            recommendation.template.id,
            label: 'recommended',
          ),
          template: recommendation.template,
          sets: [
            WorkoutSetEntry(
              number: 1,
              weight: 0,
              reps: 0,
              restSeconds: 0,
              durationSeconds: cardio?.durationSeconds ?? 1800,
              distanceKm: cardio?.targetDistanceKm ?? 0,
              intensityRpe: (cardio?.minimumRpe ?? 3).toDouble(),
            ),
          ],
        ),
      );
      _schedulePersist();
      notifyListeners();
      return true;
    }
    final weight = recommendation.startingWeight;
    final reps = recommendation.minReps;
    session.exercises.add(
      WorkoutExercise(
        id: _newWorkoutExerciseId(
          recommendation.template.id,
          label: 'recommended',
        ),
        template: recommendation.template,
        sets: List.generate(
          recommendation.sets,
          (index) => WorkoutSetEntry(
            number: index + 1,
            weight: weight,
            reps: reps,
            restSeconds: recommendation.restSeconds,
          ),
        ),
      ),
    );
    _schedulePersist();
    notifyListeners();
    return true;
  }

  Future<void> _refreshCloudData({int? expectedAccountEpoch}) async {
    final accountEpoch = expectedAccountEpoch ?? _accountEpoch;
    if (!_isCurrentAccount(accountEpoch)) return;
    Object? firstError;
    void rememberError(Object error) => firstError ??= error;
    final auth = Auth.instance;
    final canLoadPrivateData =
        auth.hasAuthenticatedUser || loadBusinessWithoutAuth;

    if (canLoadPrivateData) {
      try {
        final verifiedAdmin = auth.hasAuthenticatedUser
            ? await auth.isVerifiedAdmin()
            : false;
        if (!_isCurrentAccount(accountEpoch)) return;
        _verifiedAdmin = verifiedAdmin;
      } catch (error) {
        if (!_isCurrentAccount(accountEpoch)) return;
        _verifiedAdmin = false;
        rememberError(error);
      }

      final liveBusinessRepository = businessRepository;
      if (liveBusinessRepository != null) {
        try {
          await _refreshBusinessData(
            liveBusinessRepository,
            expectedAccountEpoch: accountEpoch,
          );
        } catch (error) {
          if (!_isCurrentAccount(accountEpoch)) return;
          rememberError(error);
        }
      } else if (_verifiedAdmin) {
        role = UserRole.admin;
      } else if (role == UserRole.admin) {
        role = UserRole.member;
      }
      if (!_isCurrentAccount(accountEpoch)) return;
    }

    final routineRepository = routineCatalogRepository;
    if (routineRepository != null) {
      try {
        final catalog = await routineRepository.listPublished();
        if (!_isCurrentAccount(accountEpoch)) return;
        _marketRoutines
          ..clear()
          ..addAll(catalog.map(_routineFromCatalog));
        final cachedError = _cachedReadError(routineRepository);
        if (cachedError != null) rememberError(cachedError);
      } catch (error) {
        if (!_isCurrentAccount(accountEpoch)) return;
        rememberError(error);
      }
    }

    if (canLoadPrivateData) {
      try {
        final paidPlan =
            _verifiedAdmin ||
            (routineRepository != null &&
                await routineRepository.hasActivePaidPlan());
        if (!_isCurrentAccount(accountEpoch)) return;
        hasPaidPlan = paidPlan;
      } catch (error) {
        if (!_isCurrentAccount(accountEpoch)) return;
        rememberError(error);
      }
    }

    // The feed is public reading, so it loads outside the private-data gate —
    // a guest who never signs in must still see what everyone else posted.
    final sharedCommunityRepository = communityRepository;
    if (sharedCommunityRepository != null) {
      try {
        final records = await sharedCommunityRepository.fetchPosts();
        if (!_isCurrentAccount(accountEpoch)) return;
        communityPosts
          ..clear()
          ..addAll(records.map((record) => record.post));
        final cachedError = _cachedReadError(sharedCommunityRepository);
        if (cachedError != null) rememberError(cachedError);
      } catch (error) {
        if (!_isCurrentAccount(accountEpoch)) return;
        rememberError(error);
      }
    }

    // 알림은 계정 것이라 비공개 데이터 게이트 안이다. 목록 전체가 아니라 수만
    // 받아 온다 — 헤더의 점에 필요한 건 그것뿐이고, 목록은 화면을 열 때 받는다.
    //
    // 실패는 여기서 삼킨다(rememberError가 아니다). 알림은 부수적인 표면이라,
    // 못 세었다고 cloudSyncError가 서면 홈 전체가 동기화 오류로 덮인다 —
    // 헤더에 점이 안 붙는 것으로 충분하고, 목록은 화면을 열 때 자기 오류를
    // 자기 자리에서 말한다.
    if (canLoadPrivateData && auth.hasAuthenticatedUser) {
      try {
        await _refreshUnreadNotificationCount(accountEpoch);
      } catch (_) {
        if (!_isCurrentAccount(accountEpoch)) return;
      }
    }

    if (firstError case final Object error) throw error;
  }

  Future<void> _refreshUnreadNotificationCount(int accountEpoch) async {
    final repository = notificationRepository;
    if (repository == null) return;
    final count = await repository.unreadCount();
    if (!_isCurrentAccount(accountEpoch)) return;
    unreadNotificationCount = count;
  }

  /// 헤더의 점만 다시 센다. 앱이 다시 앞으로 나올 때 부른다 — 자리를 비운
  /// 사이 알림이 왔을 수 있고, 그때 점이 안 붙으면 "배지는 있는데 앱은
  /// 모르는" 상태가 그대로 남는다. 목록은 화면을 열 때 받는다.
  Future<void> refreshUnreadNotifications() async {
    if (!Auth.instance.hasAuthenticatedUser) return;
    final accountEpoch = _accountEpoch;
    final before = unreadNotificationCount;
    await _refreshUnreadNotificationCount(accountEpoch);
    if (_isCurrentAccount(accountEpoch) && unreadNotificationCount != before) {
      notifyListeners();
    }
  }

  /// 알림함을 연다. 실패해도 앱의 다른 부분은 건드리지 않는다 — 알림은
  /// 부수적인 표면이라, 못 읽었다고 홈이 오류로 덮이면 안 된다.
  Future<void> refreshNotifications() async {
    final repository = notificationRepository;
    final accountEpoch = _accountEpoch;
    if (repository == null || !Auth.instance.hasAuthenticatedUser) {
      notifications = const [];
      unreadNotificationCount = 0;
      notificationsLoading = false;
      notificationsError = null;
      notifyListeners();
      return;
    }
    notificationsLoading = true;
    notificationsError = null;
    notifyListeners();
    try {
      final items = await repository.listNotifications();
      if (!_isCurrentAccount(accountEpoch)) return;
      notifications = items;
      unreadNotificationCount = items.where((item) => item.isUnread).length;
      notificationsError = null;
    } catch (error) {
      if (!_isCurrentAccount(accountEpoch)) return;
      notificationsError = error;
    } finally {
      if (_isCurrentAccount(accountEpoch)) {
        notificationsLoading = false;
        notifyListeners();
      }
    }
  }

  /// 알림 하나를 읽음으로. 화면이 먼저 바뀌고 서버는 뒤따른다 — 목록을 누른
  /// 순간 이동이 시작되므로 왕복을 기다릴 시간이 없다.
  Future<void> markNotificationRead(String id) async {
    final repository = notificationRepository;
    if (repository == null) return;
    final index = notifications.indexWhere((item) => item.id == id);
    if (index < 0 || !notifications[index].isUnread) return;
    final updated = [...notifications];
    updated[index] = updated[index].copyWith(readAt: DateTime.now());
    notifications = updated;
    unreadNotificationCount = (unreadNotificationCount - 1).clamp(0, 99);
    notifyListeners();
    try {
      await repository.markRead(id);
    } catch (_) {
      // 다음 새로고침이 서버의 진실을 다시 가져온다. 읽음 표시 하나 때문에
      // 이동을 막거나 오류를 띄우지 않는다.
    }
  }

  Future<void> markAllNotificationsRead() async {
    final repository = notificationRepository;
    if (repository == null || notifications.every((item) => !item.isUnread)) {
      return;
    }
    final now = DateTime.now();
    notifications = [
      for (final item in notifications)
        item.isUnread ? item.copyWith(readAt: now) : item,
    ];
    unreadNotificationCount = 0;
    notifyListeners();
    try {
      await repository.markAllRead();
    } catch (_) {
      // 위와 같다 — 다음 새로고침이 바로잡는다.
    }
  }

  Future<void> refreshCloudData() async {
    final accountEpoch = _accountEpoch;
    try {
      await _refreshCloudData(expectedAccountEpoch: accountEpoch);
      if (!_isCurrentAccount(accountEpoch)) return;
      cloudSyncError = null;
    } catch (error) {
      if (!_isCurrentAccount(accountEpoch)) return;
      cloudSyncError = error;
    } finally {
      if (_isCurrentAccount(accountEpoch)) notifyListeners();
    }
  }

  Future<void> _refreshBusinessData(
    BusinessRepository repository, {
    int? expectedAccountEpoch,
  }) async {
    final accountEpoch = expectedAccountEpoch ?? _accountEpoch;
    final requestToken = ++_businessRequestSequence;
    final memberConsultationRequestToken = ++_memberConsultationRequestSequence;
    if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
    businessLoading = true;
    businessError = null;
    memberConsultationsLoading = true;
    memberConsultationsError = null;
    _clearBusinessMemberDetailCache();
    notifyListeners();
    Object? auxiliaryError;
    void rememberAuxiliaryError(Object error) => auxiliaryError ??= error;
    try {
      final access = await repository.loadAccess();
      if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
      final resolvedRole = _resolveRefreshedBusinessRole(access);

      BusinessWorkspaceData? refreshedWorkspace;
      if (_isBusinessWorkspaceRole(resolvedRole)) {
        refreshedWorkspace = await repository.loadWorkspace(resolvedRole);
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
      }

      businessAccess = access;
      role = resolvedRole;
      businessWorkspace = refreshedWorkspace;
      if (refreshedWorkspace != null) {
        _applyLiveBusinessDashboard(refreshedWorkspace);
      }

      try {
        final refreshedPublicTrainers = List<PublicTrainer>.unmodifiable(
          await repository.listPublicTrainers(),
        );
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        publicTrainers = refreshedPublicTrainers;
      } catch (error) {
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        rememberAuxiliaryError(error);
      }

      try {
        final refreshedMemberConsultations =
            List<BusinessConsultation>.unmodifiable(
              await repository.listMyConsultations(),
            );
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        if (memberConsultationRequestToken ==
            _memberConsultationRequestSequence) {
          memberConsultations = refreshedMemberConsultations;
          memberConsultationsError = null;
          _syncMemberConsultationsFromCloud();
        }
      } catch (error) {
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        if (memberConsultationRequestToken ==
            _memberConsultationRequestSequence) {
          memberConsultationsError = error;
          rememberAuxiliaryError(error);
        }
      } finally {
        if (_isCurrentBusinessRequest(accountEpoch, requestToken) &&
            memberConsultationRequestToken ==
                _memberConsultationRequestSequence) {
          memberConsultationsLoading = false;
        }
      }

      try {
        final refreshedPreferences = await repository
            .loadMySharingPreferences();
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        _memberSharingPreferences = refreshedPreferences;
      } catch (error) {
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        rememberAuxiliaryError(error);
      }

      try {
        final today = DateTime.now();
        final refreshedSchedules = _sortedCoachingSchedules(
          (await repository.listCoachingSchedules(
            from: DateTime(today.year, today.month - 1),
            to: DateTime(today.year, today.month + 7, 0),
          )).map(_enrichCoachingScheduleNames),
        );
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        coachingSchedules = refreshedSchedules;
        coachingSchedulesError = null;
      } catch (error) {
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        coachingSchedulesError = error;
        rememberAuxiliaryError(error);
      }

      try {
        final refreshedShares = List<RoutineShareRecord>.unmodifiable(
          await repository.listIncomingRoutineShares(),
        );
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        incomingRoutineShares = refreshedShares;
      } catch (error) {
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        rememberAuxiliaryError(error);
      }

      try {
        final personalRoutines = await repository.listPersonalRoutines();
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        _mergePersonalRoutines(personalRoutines);
      } catch (error) {
        if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        rememberAuxiliaryError(error);
      }

      if (resolvedRole == UserRole.member &&
          repository is MemberSessionFeedbackRepository) {
        try {
          await _refreshMemberSessionFeedback(
            repository as MemberSessionFeedbackRepository,
            expectedAccountEpoch: accountEpoch,
          );
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        } catch (_) {
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          // The feedback card owns this auxiliary error and retry path. Core
          // member data remains usable when the feed is temporarily offline.
        }
      } else {
        memberSessionFeedbacks = const [];
        memberSessionFeedbackError = null;
      }

      if (resolvedRole == UserRole.member &&
          repository is BusinessMembershipRepository) {
        try {
          final memberships = await (repository as BusinessMembershipRepository)
              .listMyBusinessMemberships();
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          memberMemberships = List.unmodifiable(
            memberships.where((item) => item.isActive),
          );
          memberMembershipsError = null;
        } catch (error) {
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          memberMembershipsError = error;
        }
      } else {
        memberMemberships = const [];
        memberMembershipsError = null;
      }

      if (repository is WorkoutLocationRepository) {
        final locationRepository = repository as WorkoutLocationRepository;
        try {
          serviceRegions = List.unmodifiable(
            await locationRepository.listServiceRegions(),
          );
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
        } catch (error) {
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          rememberAuxiliaryError(error);
        }
        if (resolvedRole == UserRole.member) {
          try {
            workoutLocations = List.unmodifiable(
              await locationRepository.listMyWorkoutLocations(),
            );
            if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
            workoutLocationsError = null;
          } catch (error) {
            if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
            workoutLocationsError = error;
          }
        } else {
          workoutLocations = const [];
          workoutLocationsError = null;
        }
      } else {
        serviceRegions = const [];
        workoutLocations = const [];
        workoutLocationsError = null;
      }

      if (resolvedRole == UserRole.trainer || resolvedRole == UserRole.gym) {
        try {
          final refreshedOutgoingShares = List<RoutineShareRecord>.unmodifiable(
            await repository.listOutgoingRoutineShares(),
          );
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          outgoingRoutineShares = refreshedOutgoingShares;
        } catch (error) {
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          rememberAuxiliaryError(error);
        }
      } else {
        outgoingRoutineShares = const [];
      }

      final refreshedProfile = refreshedWorkspace?.profile;
      if (resolvedRole == UserRole.gym &&
          refreshedProfile is GymBusinessProfile) {
        try {
          final refreshedInvites = List<BusinessInviteRecord>.unmodifiable(
            await repository.listBusinessInvites(refreshedProfile.id),
          );
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          businessInvites = refreshedInvites;
        } catch (error) {
          if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
          rememberAuxiliaryError(error);
        }
      } else {
        businessInvites = const [];
      }

      if (auxiliaryError case final Object error) {
        businessError = error;
        throw error;
      }
    } catch (error) {
      if (!_isCurrentBusinessRequest(accountEpoch, requestToken)) return;
      if (memberConsultationsLoading &&
          memberConsultationRequestToken ==
              _memberConsultationRequestSequence) {
        memberConsultationsError = error;
      }
      businessError = error;
      rethrow;
    } finally {
      if (_isCurrentBusinessRequest(accountEpoch, requestToken)) {
        if (memberConsultationRequestToken ==
            _memberConsultationRequestSequence) {
          memberConsultationsLoading = false;
        }
        businessLoading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentAccount(int accountEpoch) =>
      !_disposed && accountEpoch == _accountEpoch;

  bool _isCurrentBusinessRequest(int accountEpoch, int requestToken) =>
      _isCurrentAccount(accountEpoch) &&
      requestToken == _businessRequestSequence;

  bool _isCurrentMemberFeedbackRequest(int accountEpoch, int requestToken) =>
      _isCurrentAccount(accountEpoch) &&
      requestToken == _memberFeedbackRequestSequence;

  Future<void> refreshMemberSessionFeedback({
    DateTime? from,
    DateTime? to,
  }) async {
    final repository = businessRepository;
    if (repository is! MemberSessionFeedbackRepository) return;
    await _refreshMemberSessionFeedback(
      repository as MemberSessionFeedbackRepository,
      from: from,
      to: to,
    );
  }

  Future<void> _refreshMemberSessionFeedback(
    MemberSessionFeedbackRepository repository, {
    int? expectedAccountEpoch,
    DateTime? from,
    DateTime? to,
  }) async {
    final accountEpoch = expectedAccountEpoch ?? _accountEpoch;
    final requestToken = ++_memberFeedbackRequestSequence;
    if (!_isCurrentMemberFeedbackRequest(accountEpoch, requestToken)) return;
    memberSessionFeedbackLoading = true;
    memberSessionFeedbackError = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final records = await repository.listMySessionFeedback(
        from: from ?? DateTime(now.year, now.month, now.day - 365),
        to: to ?? DateTime(now.year, now.month, now.day),
      );
      if (!_isCurrentMemberFeedbackRequest(accountEpoch, requestToken)) return;
      final sorted = records.toList(growable: false)
        ..sort((left, right) {
          final bySession = right.sessionDate.compareTo(left.sessionDate);
          return bySession != 0
              ? bySession
              : right.createdAt.compareTo(left.createdAt);
        });
      memberSessionFeedbacks = List.unmodifiable(sorted);
    } catch (error) {
      if (!_isCurrentMemberFeedbackRequest(accountEpoch, requestToken)) return;
      memberSessionFeedbackError = error;
      rethrow;
    } finally {
      if (_isCurrentMemberFeedbackRequest(accountEpoch, requestToken)) {
        memberSessionFeedbackLoading = false;
        notifyListeners();
      }
    }
  }

  static bool _isBusinessWorkspaceRole(UserRole value) =>
      value == UserRole.trainer ||
      value == UserRole.gym ||
      value == UserRole.admin;

  UserRole _resolveRefreshedBusinessRole(BusinessAccess access) {
    final selectedRole = role;
    if (selectedRole == UserRole.member) return UserRole.member;
    if (selectedRole == UserRole.admin && _verifiedAdmin) {
      return UserRole.admin;
    }
    if (selectedRole != UserRole.admin && access.canUse(selectedRole)) {
      return selectedRole;
    }
    if (_verifiedAdmin) return UserRole.admin;
    if (access.resolvedRole != UserRole.admin &&
        (access.resolvedRole == UserRole.member ||
            access.canUse(access.resolvedRole))) {
      return access.resolvedRole;
    }
    for (final fallback in const [
      UserRole.trainer,
      UserRole.gym,
      UserRole.member,
    ]) {
      if (fallback == UserRole.member || access.canUse(fallback)) {
        return fallback;
      }
    }
    return UserRole.member;
  }

  Future<T> _runBusinessMutation<T>(
    String key,
    Future<T> Function(int accountEpoch) action,
  ) {
    final pending = _businessMutations[key];
    if (pending != null) return pending as Future<T>;

    final accountEpoch = _accountEpoch;
    late final Future<T> guarded;
    guarded = Future<T>.sync(() => action(accountEpoch)).whenComplete(() {
      if (!identical(_businessMutations[key], guarded)) return;
      _businessMutations.remove(key);
      if (_isCurrentAccount(accountEpoch)) notifyListeners();
    });
    _businessMutations[key] = guarded;
    if (_isCurrentAccount(accountEpoch)) notifyListeners();
    return guarded;
  }

  static const _trainerApplicationMutationKey = 'business-application:trainer';
  static const _gymApplicationMutationKey = 'business-application:gym';
  static const _businessRoutineMutationPrefix = 'business-routine:create:';

  static String _assignmentMutationKey(String memberId) =>
      'business-member:assign:$memberId';

  static String _consultationCreateMutationKey(String trainerId) =>
      'business-consultation:create:$trainerId';

  static String _consultationReplyMutationKey(String consultationId) =>
      'business-consultation:reply:$consultationId';

  static String _consultationAssignMutationKey(String consultationId) =>
      'business-consultation:assign:$consultationId';

  static String _applicationReviewMutationKey(String applicationId) =>
      'business-application:review:$applicationId';

  static String _businessProfileMutationKey(String profileId) =>
      'business-profile:update:$profileId';

  static String _businessRoutineMutationKey(UserRole ownerRole, String title) =>
      '$_businessRoutineMutationPrefix${ownerRole.name}:${title.trim().toLowerCase()}';

  static String _businessRpcRequestKey(
    String operation,
    Map<String, Object?> payload,
  ) => '$operation\u0000${jsonEncode(payload)}';

  String _stableBusinessRpcRequestId(String requestKey) =>
      _stableBusinessRpcRequestIds.putIfAbsent(requestKey, _newUuidV4);

  void _completeBusinessRpcRequest(
    String requestKey, {
    required int expectedAccountEpoch,
  }) {
    if (!_isCurrentAccount(expectedAccountEpoch)) return;
    _stableBusinessRpcRequestIds.remove(requestKey);
  }

  void _syncMemberConsultationsFromCloud() {
    consultations
      ..clear()
      ..addAll(
        memberConsultations.map((record) {
          final responseMessages =
              record.messages
                  .where(
                    (message) =>
                        message.sender == BusinessMessageSender.trainer ||
                        message.sender == BusinessMessageSender.gym,
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                          .compareTo(
                            b.createdAt ??
                                DateTime.fromMillisecondsSinceEpoch(0),
                          ),
                );
          final response = responseMessages.lastOrNull?.text;
          return ConsultationData(
            id: record.id,
            trainerName: record.trainerName ?? record.gymName ?? '담당 전문가',
            specialty: record.specialty ?? '맞춤 운동 상담',
            goal: record.goal ?? '',
            level: record.level ?? '',
            question: record.question ?? '',
            createdAt: record.createdAt ?? DateTime.now(),
            consultationMode: record.mode.label,
            consultationLocation: switch (record.matchingSource) {
              ConsultationMatchingSource.region =>
                serviceRegions
                        .where(
                          (region) => region.code == record.requestedRegionCode,
                        )
                        .firstOrNull
                        ?.name ??
                    record.requestedRegionCode,
              ConsultationMatchingSource.gym => record.gymName,
              ConsultationMatchingSource.direct => record.gymName,
            },
            status: switch (record.status) {
              BusinessConsultationStatus.answered ||
              BusinessConsultationStatus.replied => ConsultationStatus.answered,
              BusinessConsultationStatus.pending ||
              BusinessConsultationStatus.assigned ||
              BusinessConsultationStatus.unknown => ConsultationStatus.waiting,
            },
            response: response,
            sharedRecommendationProfile: record.sharedRecommendationProfile,
            recommendationProfileShareRevokedAt:
                record.recommendationProfileShareRevokedAt,
          );
        }),
      );
  }

  void _resetLiveBusinessDashboards() {
    businessDashboards
      ..clear()
      ..addAll({
        for (final workspaceRole in const [
          UserRole.trainer,
          UserRole.gym,
          UserRole.admin,
        ])
          workspaceRole: BusinessDashboardData(
            role: workspaceRole,
            facts: {},
            tasks: [],
            notifications: [],
            lastSyncedAt: DateTime.now(),
          ),
      });
  }

  void _applyLiveBusinessDashboard(BusinessWorkspaceData workspace) {
    final metrics = workspace.dashboardStats;
    final tasks = <BusinessTaskData>[];
    final notifications = <BusinessNotificationData>[];
    final facts = <String, String>{};

    switch (workspace.profile) {
      case final TrainerBusinessProfile trainer:
        facts.addAll({
          'displayName': trainer.displayName,
          'revenue': '${_formatInteger(metrics.pendingSettlement)}원',
          'revenueChange': '서버 정산 데이터 기준',
          'members': '${metrics.activeMembers}',
          'memberCapacity': '명',
          'feedbackPending': '${metrics.overdueFeedbacks}',
          'routineViews':
              '${workspace.ownedRoutines.fold<int>(0, (sum, item) => sum + item.cumulativeUsers)}',
          'routineViewsChange': '누적 사용',
          'consultationConversion': '${metrics.unreadConsultations}건',
          'consultationConversionChange': '미답변 상담',
          'routineImports': '${workspace.ownedRoutines.length}개',
          'routineImportsChange': '등록 루틴',
          'keyword': trainer.keyword ?? '',
          'intro': trainer.intro ?? '',
          'acceptsOnlineConsultation': '${trainer.acceptsOnlineConsultation}',
          'acceptsOfflineConsultation': '${trainer.acceptsOfflineConsultation}',
          'primaryActivityRegion':
              trainer.serviceAreas
                  .where((area) => area.isPrimary)
                  .firstOrNull
                  ?.regionName ??
              '',
        });
      case final GymBusinessProfile gym:
        facts.addAll({
          'displayName': gym.name,
          'businessVerified': '${gym.status == BusinessProfileStatus.verified}',
          'businessNumber': gym.businessNumber ?? '',
          'planId': gym.planTier ?? 'basic',
          'plan': gym.planTier ?? '기본 플랜',
          'location': gym.address ?? '',
          'intro': gym.description ?? '',
          'members': '${workspace.members.length}',
          'revenue': (metrics.totalRevenue / 1000000).toStringAsFixed(1),
          'trainers': '${workspace.trainers.length}',
          'consultations': '${metrics.unreadConsultations}',
        });
        for (
          var index = 0;
          index < workspace.trainers.length && index < 3;
          index++
        ) {
          final trainer = workspace.trainers[index];
          facts['trainer${index + 1}Name'] = trainer.displayName ?? '이름 미등록';
          facts['trainer${index + 1}Detail'] =
              '회원 ${trainer.memberCount}명 · 평점 ${trainer.averageRating.toStringAsFixed(1)}';
        }
        for (final member in workspace.members) {
          final assignment = workspace.assignments
              .where((item) => item.active && item.memberId == member.id)
              .firstOrNull;
          if (assignment?.trainerName case final String trainerName) {
            facts['memberAssignment.${member.id}'] = trainerName;
          }
        }
      case null:
        break;
    }

    if (metrics.overdueFeedbacks > 0) {
      tasks.add(
        BusinessTaskData(
          id: 'feedback_due',
          title: '피드백 확인이 필요해요',
          subtitle: '${metrics.overdueFeedbacks}건의 피드백이 지연되고 있어요.',
          action: '확인',
          kind: 'urgent',
        ),
      );
    }
    if (metrics.unreadConsultations > 0) {
      tasks.add(
        BusinessTaskData(
          id: 'new_consultation',
          title: '새 상담이 도착했어요',
          subtitle: '미답변 상담 ${metrics.unreadConsultations}건',
          action: '답변',
          kind: 'consultation',
        ),
      );
      notifications.add(
        BusinessNotificationData(
          id: 'consultations_unread',
          title: '새 상담이 도착했어요',
          subtitle: '미답변 상담 ${metrics.unreadConsultations}건을 확인해주세요.',
          kind: 'consultation',
          createdAt: DateTime.now(),
        ),
      );
    }
    if (workspace.role == UserRole.gym) {
      final assignedIds = workspace.assignments
          .where((assignment) => assignment.active)
          .map((assignment) => assignment.memberId)
          .toSet();
      final unassigned = workspace.members
          .where((member) => !assignedIds.contains(member.id))
          .length;
      if (unassigned > 0) {
        tasks.add(
          BusinessTaskData(
            id: 'gym_member_assignment',
            title: '신규 회원 배정이 필요해요',
            subtitle: '담당자가 없는 회원 $unassigned명',
            action: '배정',
            kind: 'member',
          ),
        );
      }
    }
    if (workspace.role == UserRole.admin) {
      final pending = workspace.applications
          .where(
            (application) =>
                application.status == BusinessApplicationStatus.pending,
          )
          .length;
      facts['reviews'] = '$pending';
      if (pending > 0) {
        tasks.add(
          BusinessTaskData(
            id: 'admin_business_reviews',
            title: '사업자 심사 대기 $pending건',
            subtitle: '실제 제출된 신청서를 확인해주세요.',
            action: '검토',
            kind: 'review',
          ),
        );
      }
    }

    businessDashboards[workspace.role] = BusinessDashboardData(
      role: workspace.role,
      facts: facts,
      tasks: tasks,
      notifications: notifications,
      lastSyncedAt: DateTime.now(),
    );
  }

  static String _formatInteger(double value) {
    final digits = value.round().toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  RoutineData _routineFromCatalog(RoutineCatalogItem item) {
    final templates = <ExerciseTemplate>[];
    final setPlans = <String, List<RoutineSetPlan>>{};
    for (final catalogExercise in item.exercises) {
      final template =
          exercises
              .where(
                (exercise) =>
                    exercise.referencesId(catalogExercise.baseExerciseId) ||
                    exercise.name == catalogExercise.name,
              )
              .firstOrNull ??
          ExerciseTemplate(
            id:
                catalogExercise.baseExerciseId ??
                'catalog_${catalogExercise.id}',
            name: catalogExercise.name,
            muscle: catalogExercise.targetMuscle,
            icon: Icons.fitness_center_rounded,
          );
      templates.add(template);
      if (catalogExercise.sets.isNotEmpty) {
        setPlans[template.id] = catalogExercise.sets
            .map(
              (set) => RoutineSetPlan(
                number: set.setNumber,
                weight: set.targetWeight ?? 0,
                reps: set.targetReps ?? 0,
                type: workoutSetTypeLabel(set.type),
                restSeconds: set.restSeconds,
                durationSeconds: set.durationSeconds ?? 0,
                distanceKm: (set.distanceMeters ?? 0) / 1000,
                intensityRpe: set.intensityRpe ?? 0,
              ),
            )
            .toList(growable: false);
      }
    }
    return RoutineData(
      id: item.id,
      name: item.title,
      description: item.description,
      color: Color(_colorValue(item.colorHex)),
      exercises: templates,
      author: item.authorName,
      level: item.difficulty,
      accessTier: item.accessTier == RoutineCatalogAccessTier.paid
          ? RoutineAccessTier.paid
          : RoutineAccessTier.free,
      setPlans: setPlans,
      sourceMarketRoutineId: item.id,
      sourceCoachingRoutineId: item.coachingRoutineId,
      authorTrainerId: item.authorTrainerId,
      authorGymId: item.authorGymId,
      authorType: item.authorType,
    );
  }

  RoutineData _routineFromPersonalRecord(PersonalRoutineRecord record) {
    final templates = <ExerciseTemplate>[];
    final setPlans = <String, List<RoutineSetPlan>>{};
    final baseExerciseIds = <String, String?>{};
    for (final item in record.exercises) {
      final template =
          exercises
              .where(
                (exercise) =>
                    exercise.referencesId(item.baseExerciseId) ||
                    exercise.name == item.name,
              )
              .firstOrNull ??
          ExerciseTemplate(
            id: item.baseExerciseId ?? item.id,
            name: item.name,
            muscle: item.targetMuscle,
            icon: Icons.fitness_center_rounded,
          );
      templates.add(template);
      baseExerciseIds[template.id] = item.baseExerciseId;
      if (item.sets.isNotEmpty) {
        setPlans[template.id] = item.sets
            .map(
              (set) => RoutineSetPlan(
                number: set.setNumber,
                weight: set.targetWeight ?? 0,
                reps: set.targetReps ?? 0,
                type: workoutSetTypeLabel(set.type),
                restSeconds: set.restSeconds,
                durationSeconds: set.durationSeconds ?? 0,
                distanceKm: (set.distanceMeters ?? 0) / 1000,
                intensityRpe: set.intensityRpe ?? 0,
              ),
            )
            .toList(growable: false);
      }
    }
    _personalRoutineBaseExerciseIds[record.id] = Map.unmodifiable(
      baseExerciseIds,
    );
    return RoutineData(
      id: record.id,
      name: record.name,
      description: record.description ?? '',
      color: Color(_colorValue(record.color)),
      exercises: templates,
      author: record.sourceCoachingRoutineId == null ? '나' : '전문가 공유',
      setPlans: setPlans,
      sourceMarketRoutineId: record.marketRoutineId,
      sourceCoachingRoutineId: record.sourceCoachingRoutineId,
    );
  }

  void _mergePersonalRoutines(List<PersonalRoutineRecord> records) {
    final serverRoutineIds = records.map((record) => record.id).toSet();
    routines.removeWhere(
      (routine) =>
          _isUuid(routine.id) && !serverRoutineIds.contains(routine.id),
    );
    _personalRoutineBaseExerciseIds.removeWhere(
      (routineId, _) => !serverRoutineIds.contains(routineId),
    );
    for (final record in records) {
      final routine = _routineFromPersonalRecord(record);
      final index = routines.indexWhere((item) => item.id == routine.id);
      if (index < 0) {
        routines.add(routine);
      } else {
        routines[index] = routine;
      }
    }
    _schedulePersist();
  }

  static int _colorValue(String? value) {
    var normalized = value?.trim().replaceFirst('#', '') ?? '';
    if (normalized.length == 6) normalized = 'FF$normalized';
    return int.tryParse(normalized, radix: 16) ?? 0xFF10CEBD;
  }

  Future<bool> updateMarketRoutineAccess(
    RoutineData routine,
    RoutineAccessTier accessTier,
  ) async {
    final repository = routineCatalogRepository;
    if (!_verifiedAdmin || repository == null) return false;
    await repository.updateAccessTier(
      routine.id,
      accessTier == RoutineAccessTier.paid
          ? RoutineCatalogAccessTier.paid
          : RoutineCatalogAccessTier.free,
    );
    final index = _marketRoutines.indexWhere((item) => item.id == routine.id);
    if (index < 0) return false;
    _marketRoutines[index] = RoutineData(
      id: routine.id,
      name: routine.name,
      description: routine.description,
      color: routine.color,
      exercises: routine.exercises,
      author: routine.author,
      level: routine.level,
      accessTier: accessTier,
      setPlans: routine.setPlans,
      sourceMarketRoutineId: routine.sourceMarketRoutineId,
      sourceCoachingRoutineId: routine.sourceCoachingRoutineId,
      authorTrainerId: routine.authorTrainerId,
      authorGymId: routine.authorGymId,
      authorType: routine.authorType,
    );
    notifyListeners();
    return true;
  }

  RoutineImportResult importRoutine(RoutineData routine) {
    if (routines.any(
      (item) =>
          item.id == routine.id ||
          (routine.sourceMarketRoutineId != null &&
              item.sourceMarketRoutineId == routine.sourceMarketRoutineId),
    )) {
      return RoutineImportResult.alreadySaved;
    }
    if (routine.isPaid && !hasPaidPlan && !_verifiedAdmin) {
      return RoutineImportResult.paidPlanRequired;
    }
    if (!hasPaidPlan && !_verifiedAdmin && routines.length >= 4) {
      return RoutineImportResult.limitReached;
    }
    routines.add(routine);
    _schedulePersist();
    notifyListeners();
    return RoutineImportResult.imported;
  }

  Future<RoutineImportResult> importMarketRoutine(RoutineData routine) async {
    final eligibility = _routineImportEligibility(routine);
    if (eligibility != RoutineImportResult.imported) return eligibility;
    final repository = businessRepository;
    final marketRoutineId = routine.sourceMarketRoutineId ?? routine.id;
    if (repository == null) return importRoutine(routine);
    final requestKey = _businessRpcRequestKey('import_market_routine', {
      'marketRoutineId': marketRoutineId.trim(),
    });
    final requestId = _stableBusinessRpcRequestId(requestKey);

    return _runBusinessMutation<RoutineImportResult>(
      'routine:market-import:$marketRoutineId',
      (accountEpoch) async {
        final record = await repository.importMarketRoutine(
          marketRoutineId,
          requestId: requestId,
        );
        if (!_isCurrentAccount(accountEpoch)) {
          return RoutineImportResult.imported;
        }
        final imported = _routineFromPersonalRecord(record);
        final index = routines.indexWhere((item) => item.id == imported.id);
        if (index < 0) {
          routines.add(imported);
        } else {
          routines[index] = imported;
        }
        _schedulePersist();
        notifyListeners();
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return RoutineImportResult.imported;
      },
    );
  }

  RoutineImportResult _routineImportEligibility(RoutineData routine) {
    if (routines.any(
      (item) =>
          item.id == routine.id ||
          (routine.sourceMarketRoutineId != null &&
              item.sourceMarketRoutineId == routine.sourceMarketRoutineId),
    )) {
      return RoutineImportResult.alreadySaved;
    }
    if (routine.isPaid && !hasPaidPlan && !_verifiedAdmin) {
      return RoutineImportResult.paidPlanRequired;
    }
    if (!hasPaidPlan && !_verifiedAdmin && routines.length >= 4) {
      return RoutineImportResult.limitReached;
    }
    return RoutineImportResult.imported;
  }

  bool createRoutine(String name, String description, {Color? color}) {
    if (!hasPaidPlan && !_verifiedAdmin && routines.length >= 4) return false;
    routines.add(
      RoutineData(
        id: 'routine_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        description: description,
        color: color ?? const Color(0xFF3B82F6),
        exercises: [exercises[0], exercises[2], exercises[4]],
      ),
    );
    _schedulePersist();
    notifyListeners();
    return true;
  }

  /// Creates a member-owned routine through the normalized Supabase tables.
  /// Demo/Memory repositories keep the original synchronous local path.
  Future<bool> createPersonalRoutine(
    String name,
    String description, {
    Color? color,
  }) async {
    final normalizedName = name.trim();
    final normalizedDescription = description.trim();
    if (normalizedName.isEmpty ||
        (!hasPaidPlan && !_verifiedAdmin && routines.length >= 4)) {
      return false;
    }
    final repository = businessRepository;
    if (repository == null) {
      return createRoutine(normalizedName, normalizedDescription, color: color);
    }

    final payloadKey = _businessRpcRequestKey('create_personal_routine', {
      'name': normalizedName,
      'description': normalizedDescription,
    });
    final routineIdKey = '$payloadKey\u0000routine-id';
    final requestIdKey = '$payloadKey\u0000request-id';
    final routineId = _stableBusinessRpcRequestId(routineIdKey);
    final requestId = _stableBusinessRpcRequestId(requestIdKey);
    final selectedExercises = [exercises[0], exercises[2], exercises[4]];
    final routine = RoutineData(
      id: routineId,
      name: normalizedName,
      description: normalizedDescription,
      // 대표 아이콘 선택이 부위 색으로 들어온다(routine_icon_picker 참고).
      color: color ?? const Color(0xFF3B82F6),
      exercises: selectedExercises,
      setPlans: {
        for (final exercise in selectedExercises)
          exercise.id: _defaultPersonalRoutineSetPlans(exercise),
      },
    );

    return _runBusinessMutation<bool>('personal-routine:create:$requestId', (
      accountEpoch,
    ) async {
      final record = await repository.savePersonalRoutine(
        _personalRoutineSaveInput(routine, requestId: requestId),
      );
      _completeBusinessRpcRequest(
        routineIdKey,
        expectedAccountEpoch: accountEpoch,
      );
      _completeBusinessRpcRequest(
        requestIdKey,
        expectedAccountEpoch: accountEpoch,
      );
      if (!_isCurrentAccount(accountEpoch)) return true;
      final savedRoutine = _routineFromPersonalRecord(record);
      routines.removeWhere((item) => item.id == savedRoutine.id);
      routines.add(savedRoutine);
      _schedulePersist();
      notifyListeners();
      return true;
    });
  }

  Future<bool> updateRoutine({
    required RoutineData routine,
    required String name,
    required String description,
    required List<ExerciseTemplate> exercises,
    Color? color,
  }) async {
    final index = routines.indexWhere((item) => item.id == routine.id);
    final normalizedName = name.trim();
    if (index < 0 || normalizedName.isEmpty || exercises.isEmpty) return false;
    final updatedRoutine = RoutineData(
      id: routine.id,
      name: normalizedName,
      description: description.trim(),
      // 편집기의 대표 아이콘 선택이 부위 색으로 들어온다 — 개인 루틴 서버
      // 레코드의 color로 왕복하므로 기기 간에 보존된다.
      color: color ?? routine.color,
      exercises: List.of(exercises),
      author: routine.author,
      level: routine.level,
      accessTier: routine.accessTier,
      setPlans: {
        for (final exercise in exercises)
          exercise.id:
              routine.setPlans[exercise.id] ??
              _defaultPersonalRoutineSetPlans(exercise),
      },
      sourceMarketRoutineId: routine.sourceMarketRoutineId,
      sourceCoachingRoutineId: routine.sourceCoachingRoutineId,
      authorTrainerId: routine.authorTrainerId,
      authorGymId: routine.authorGymId,
      authorType: routine.authorType,
    );

    final repository = businessRepository;
    if (repository == null || !_isUuid(routine.id)) {
      routines[index] = updatedRoutine;
      _schedulePersist();
      notifyListeners();
      return true;
    }

    final fingerprint = _personalRoutineFingerprint(updatedRoutine);
    final requestKey = '${routine.id}\u0000$fingerprint';
    final requestId = _personalRoutineSaveRequestIds.putIfAbsent(
      requestKey,
      _newUuidV4,
    );
    return _runBusinessMutation<bool>(
      'personal-routine:save:${routine.id}:$fingerprint',
      (accountEpoch) async {
        final savedRecord = await repository.savePersonalRoutine(
          _personalRoutineSaveInput(updatedRoutine, requestId: requestId),
        );
        _personalRoutineSaveRequestIds.remove(requestKey);
        if (!_isCurrentAccount(accountEpoch)) return true;
        final savedRoutine = _routineFromPersonalRecord(savedRecord);
        final currentIndex = routines.indexWhere(
          (item) => item.id == savedRoutine.id,
        );
        if (currentIndex < 0) {
          routines.add(savedRoutine);
        } else {
          routines[currentIndex] = savedRoutine;
        }
        _schedulePersist();
        notifyListeners();
        return true;
      },
    );
  }

  Future<bool> removeRoutine(RoutineData routine) async {
    final repository = businessRepository;
    if (repository == null || !_isUuid(routine.id)) {
      final removed = routines.remove(routine);
      if (!removed) return false;
      _personalRoutineBaseExerciseIds.remove(routine.id);
      _schedulePersist();
      notifyListeners();
      return true;
    }

    final requestId = _personalRoutineDeleteRequestIds.putIfAbsent(
      routine.id,
      _newUuidV4,
    );
    return _runBusinessMutation<bool>('personal-routine:delete:${routine.id}', (
      accountEpoch,
    ) async {
      await repository.deletePersonalRoutine(routine.id, requestId: requestId);
      _personalRoutineDeleteRequestIds.remove(routine.id);
      if (!_isCurrentAccount(accountEpoch)) return true;
      routines.removeWhere((item) => item.id == routine.id);
      _personalRoutineBaseExerciseIds.remove(routine.id);
      _schedulePersist();
      notifyListeners();
      return true;
    });
  }

  List<RoutineSetPlan> _defaultPersonalRoutineSetPlans(
    ExerciseTemplate exercise,
  ) => exercise.isCardio
      ? const [
          RoutineSetPlan(
            number: 1,
            weight: 0,
            reps: 0,
            restSeconds: 0,
            durationSeconds: 1800,
            intensityRpe: 3,
          ),
        ]
      : [
          RoutineSetPlan(
            number: 1,
            weight: 40,
            reps: 10,
            restSeconds: restDefaultSeconds,
          ),
          RoutineSetPlan(
            number: 2,
            weight: 40,
            reps: 10,
            restSeconds: restDefaultSeconds,
          ),
          RoutineSetPlan(
            number: 3,
            weight: 40,
            reps: 8,
            restSeconds: restDefaultSeconds,
          ),
        ];

  SavePersonalRoutineInput _personalRoutineSaveInput(
    RoutineData routine, {
    required String requestId,
  }) {
    final storedBaseIds = _personalRoutineBaseExerciseIds[routine.id];
    return SavePersonalRoutineInput(
      routineId: routine.id,
      name: routine.name,
      description: routine.description,
      color: _routineColorHex(routine.color),
      requestId: requestId,
      exercises: routine.exercises
          .map((exercise) {
            final baseExerciseId =
                storedBaseIds?[exercise.id] ?? exercise.databaseReferenceId;
            final plans = [...routine.setsFor(exercise)]
              ..sort((left, right) => left.number.compareTo(right.number));
            return CreateOwnedRoutineExerciseInput(
              baseExerciseId: baseExerciseId,
              name: exercise.name,
              targetMuscle: exercise.muscle,
              sets: plans
                  .map(
                    (set) => CreateOwnedRoutineSetInput(
                      setNumber: set.number,
                      type: workoutSetTypeDatabaseValue(set.type),
                      targetWeight: set.weight,
                      targetReps: set.reps,
                      restSeconds: set.restSeconds,
                      durationSeconds: set.durationSeconds > 0
                          ? set.durationSeconds
                          : null,
                      distanceMeters: set.distanceKm > 0
                          ? set.distanceKm * 1000
                          : null,
                      intensityRpe: set.intensityRpe > 0
                          ? set.intensityRpe
                          : null,
                    ),
                  )
                  .toList(growable: false),
            );
          })
          .toList(growable: false),
    );
  }

  String _personalRoutineFingerprint(RoutineData routine) {
    final parts = <Object?>[
      routine.name,
      routine.description,
      _routineColorHex(routine.color),
    ];
    final storedBaseIds = _personalRoutineBaseExerciseIds[routine.id];
    for (final exercise in routine.exercises) {
      parts
        ..add(exercise.id)
        ..add(exercise.name)
        ..add(exercise.muscle)
        ..add(storedBaseIds?[exercise.id] ?? exercise.databaseReferenceId);
      for (final set in routine.setsFor(exercise)) {
        parts
          ..add(set.number)
          ..add(set.weight)
          ..add(set.reps)
          ..add(workoutSetTypeDatabaseValue(set.type))
          ..add(set.restSeconds)
          ..add(set.durationSeconds)
          ..add(set.distanceKm)
          ..add(set.intensityRpe);
      }
    }
    return parts.join('\u001f').hashCode.toUnsigned(32).toRadixString(16);
  }

  String get todayWorkoutMetric {
    final session = sessions[dateOnly(DateTime.now())];
    if (session == null) return '오늘 운동 기록';
    final resistanceSets = session.exercises
        .where((exercise) => !exercise.template.isCardio)
        .fold<int>(
          0,
          (sum, exercise) =>
              sum + exercise.sets.where((set) => set.completed).length,
        );
    final parts = <String>[];
    if (resistanceSets > 0) parts.add('$resistanceSets세트');
    if (session.volume > 0) {
      final volume = session.volume >= 1000
          ? '${(session.volume / 1000).toStringAsFixed(1)}k'
          : session.volume.toStringAsFixed(0);
      parts.add('$volume $weightUnit·회');
    }
    if (session.cardioDurationSeconds > 0) {
      parts.add('${(session.cardioDurationSeconds / 60).round()}분 유산소');
    }
    return parts.isEmpty ? '오늘 운동 기록' : parts.join(' · ');
  }

  Future<void> addCommunityPost({
    required String content,
    required bool includeWorkout,
    required String visualKey,
    CommunityPostMedia? media,
    List<String> activeOverlays = const [],
  }) async {
    final metric = includeWorkout ? todayWorkoutMetric : '일상 기록';
    final repository = communityRepository;
    if (repository != null) {
      final record = await repository.createPost(
        CreateCommunityPostInput(
          content: content,
          metric: metric,
          visualKey: visualKey,
          media: media,
          activeOverlays: activeOverlays,
          routineName: includeWorkout ? '오늘 운동' : null,
        ),
      );
      communityPosts.removeWhere((post) => post.id == record.post.id);
      communityPosts.insert(0, record.post);
      notifyListeners();
      return;
    }
    communityPosts.insert(
      0,
      CommunityPost(
        id: 'post_${DateTime.now().microsecondsSinceEpoch}',
        author: memberDisplayName,
        content: content,
        metric: metric,
        createdAt: DateTime.now(),
        visualKey: visualKey,
        color: const Color(0xFF10CEBD),
        isMine: true,
        activeOverlays: activeOverlays,
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  Future<void> togglePostLike(CommunityPost post) async {
    final previousLiked = post.isLiked;
    final previousLikes = post.likes;
    post.isLiked = !post.isLiked;
    post.likes += post.isLiked ? 1 : -1;
    notifyListeners();
    final repository = communityRepository;
    if (repository == null) {
      _schedulePersist();
      return;
    }
    try {
      final result = await repository.toggleLike(post.id);
      post.isLiked = result.isLiked;
      post.likes = result.likesCount;
      notifyListeners();
    } catch (_) {
      post.isLiked = previousLiked;
      post.likes = previousLikes;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> addPostComment(CommunityPost post, String content) async {
    final repository = communityRepository;
    final comment = repository != null
        ? await repository.addComment(postId: post.id, content: content)
        : PostComment(
            id: 'comment_${DateTime.now().microsecondsSinceEpoch}',
            author: memberDisplayName,
            content: content,
            createdAt: DateTime.now(),
          );
    post.comments.add(comment);
    _schedulePersist();
    notifyListeners();
  }

  Future<PublicTrainerSearchPage> searchPublicTrainers({
    String query = '',
    String? cursor,
    int pageSize = 20,
  }) async {
    final normalizedQuery = normalizePublicTrainerSearchQuery(query);
    final normalizedPageSize = validatePublicTrainerSearchPageSize(pageSize);
    final repository = businessRepository;
    if (repository case final PublicTrainerSearchRepository searchRepository) {
      final accountEpoch = _accountEpoch;
      final page = await searchRepository.searchPublicTrainers(
        query: normalizedQuery,
        cursor: cursor,
        pageSize: normalizedPageSize,
      );
      if (_accountEpoch == accountEpoch && page.items.isNotEmpty) {
        final merged = <String, PublicTrainer>{
          for (final trainer in publicTrainers) trainer.profile.id: trainer,
          for (final trainer in page.items) trainer.profile.id: trainer,
        };
        publicTrainers = List.unmodifiable(merged.values);
        notifyListeners();
      }
      return page;
    }

    // Compatibility path for demo repositories and older test doubles. Live
    // Supabase traffic always uses PublicTrainerSearchRepository above.
    if (cursor != null) {
      return const PublicTrainerSearchPage(items: []);
    }
    final needle = normalizedQuery.toLowerCase();
    final filtered = publicTrainers
        .where((trainer) {
          if (needle.isEmpty) return true;
          return <String?>[
            trainer.profile.displayName,
            trainer.profile.centerName,
            trainer.profile.keyword,
            ...trainer.specialties,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(needle),
          );
        })
        .toList(growable: false);
    filtered.sort((left, right) {
      if (needle.isNotEmpty) {
        int matchRank(PublicTrainer trainer) {
          final name = trainer.profile.displayName.toLowerCase();
          if (name == needle) return 0;
          if (name.startsWith(needle)) return 1;
          return 2;
        }

        final byMatch = matchRank(left).compareTo(matchRank(right));
        if (byMatch != 0) return byMatch;
      }
      final byRating = right.profile.rating.compareTo(left.profile.rating);
      if (byRating != 0) return byRating;
      final byName = left.profile.displayName.compareTo(
        right.profile.displayName,
      );
      return byName != 0 ? byName : left.profile.id.compareTo(right.profile.id);
    });
    return PublicTrainerSearchPage(
      items: List.unmodifiable(filtered.take(normalizedPageSize)),
    );
  }

  Future<List<TopCoachingTrainer>> loadTopCoachingTrainers({
    int limit = 3,
  }) async {
    final normalizedLimit = validateTopCoachingTrainerLimit(limit);
    final requestToken = ++_topCoachingTrainerRequestSequence;
    final repository = businessRepository;
    if (repository case final TopCoachingTrainerRepository topRepository) {
      final accountEpoch = _accountEpoch;
      final result = List<TopCoachingTrainer>.unmodifiable(
        await topRepository.listTopCoachingTrainers(limit: normalizedLimit),
      );
      if (result.length > normalizedLimit) {
        throw const FormatException(
          'Top coaching trainer repository returned too many rows.',
        );
      }
      if (_accountEpoch != accountEpoch ||
          requestToken != _topCoachingTrainerRequestSequence) {
        return topCoachingTrainers;
      }
      topCoachingTrainers = result;
      publicTrainers = List.unmodifiable(
        {
          for (final trainer in publicTrainers) trainer.profile.id: trainer,
          for (final item in result) item.trainer.profile.id: item.trainer,
        }.values,
      );
      notifyListeners();
      return result;
    }

    // Demo/legacy repositories do not have an active-coaching aggregate. Keep
    // them usable with the closest existing count while live Supabase traffic
    // always follows the server-owned capability above.
    final fallback = [...publicTrainers]
      ..sort((left, right) {
        final byCount = right.profile.coachingTotal.compareTo(
          left.profile.coachingTotal,
        );
        if (byCount != 0) return byCount;
        final byRating = right.profile.rating.compareTo(left.profile.rating);
        if (byRating != 0) return byRating;
        return left.profile.id.compareTo(right.profile.id);
      });
    topCoachingTrainers = List.unmodifiable(
      fallback
          .take(normalizedLimit)
          .map(
            (trainer) => TopCoachingTrainer(
              trainer: trainer,
              activeCoachingCount: trainer.profile.coachingTotal < 0
                  ? 0
                  : trainer.profile.coachingTotal,
            ),
          ),
    );
    notifyListeners();
    return topCoachingTrainers;
  }

  Future<void> addConsultation({
    String? trainerId,
    String? gymId,
    String? routineId,
    required String trainerName,
    required String specialty,
    required String goal,
    required String level,
    required String question,
    ConsultationMode mode = ConsultationMode.online,
    String? regionCode,
    RecommendationProfile? sharedRecommendationProfile,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      consultations.insert(
        0,
        ConsultationData(
          id: 'consult_${DateTime.now().microsecondsSinceEpoch}',
          trainerName: trainerName,
          specialty: specialty,
          goal: goal,
          level: level,
          question: question,
          createdAt: DateTime.now(),
          consultationMode: mode.label,
          consultationLocation: regionCode == null
              ? null
              : serviceRegions
                        .where((region) => region.code == regionCode)
                        .firstOrNull
                        ?.name ??
                    regionCode,
          sharedRecommendationProfile: sharedRecommendationProfile,
        ),
      );
      _schedulePersist();
      notifyListeners();
      return;
    }

    if (trainerId != null && gymId != null) {
      throw ArgumentError('트레이너와 센터 상담 대상을 동시에 지정할 수 없습니다.');
    }
    String? resolvedTrainerId = trainerId;
    if (mode == ConsultationMode.online &&
        resolvedTrainerId == null &&
        gymId == null) {
      final matchingTrainers = publicTrainers
          .where((trainer) => trainer.profile.displayName == trainerName)
          .take(2)
          .toList(growable: false);
      if (matchingTrainers.length > 1) {
        throw StateError('동명이인 트레이너가 있어 ID로 선택해야 합니다.');
      }
      resolvedTrainerId = matchingTrainers.firstOrNull?.profile.id;
    }
    if (mode == ConsultationMode.online &&
        resolvedTrainerId == null &&
        gymId == null) {
      throw StateError('선택한 트레이너 정보를 찾을 수 없습니다.');
    }
    if (mode == ConsultationMode.offline &&
        gymId == null &&
        (regionCode?.trim().isEmpty ?? true)) {
      throw StateError('오프라인 상담 지역 또는 헬스장을 선택해주세요.');
    }
    final targetId = resolvedTrainerId ?? gymId ?? 'region:${regionCode!}';
    final requestKey = _businessRpcRequestKey('create_consultation', {
      'trainerId': resolvedTrainerId,
      'gymId': gymId,
      'mode': mode.databaseValue,
      'regionCode': regionCode?.trim(),
      'routineId': routineId,
      'specialty': specialty.trim(),
      'goal': goal.trim(),
      'level': level.trim(),
      'question': question.trim(),
      'recommendationProfile': sharedRecommendationProfile?.toJson(),
    });
    final requestId = _consultationCreateRequestIds.putIfAbsent(
      requestKey,
      _newUuidV4,
    );
    await _runBusinessMutation<void>(_consultationCreateMutationKey(targetId), (
      accountEpoch,
    ) async {
      await repository.createConsultation(
        CreateConsultationInput(
          requestId: requestId,
          mode: mode,
          trainerId: resolvedTrainerId,
          gymId: gymId,
          regionCode: regionCode,
          routineId: routineId,
          specialty: specialty,
          goal: goal,
          level: level,
          question: question,
          recommendationProfile: sharedRecommendationProfile,
        ),
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      await refreshMemberConsultations();
      if (!_isCurrentAccount(accountEpoch)) return;
      _consultationCreateRequestIds.remove(requestKey);
      notifyListeners();
    });
  }

  Future<void> revokeConsultationRecommendationProfileShare(
    String consultationId,
  ) async {
    final repository = businessRepository;
    if (repository != null &&
        repository is ConsultationRecommendationProfileShareRepository) {
      final shareRepository =
          repository as ConsultationRecommendationProfileShareRepository;
      await shareRepository.revokeRecommendationProfileShare(consultationId);
      await refreshMemberConsultations();
      return;
    }
    final consultation = consultations
        .where((item) => item.id == consultationId)
        .firstOrNull;
    if (consultation == null ||
        consultation.sharedRecommendationProfile == null) {
      throw StateError('공유된 정밀 추천 정보를 찾을 수 없습니다.');
    }
    consultation.recommendationProfileShareRevokedAt ??= DateTime.now();
    _schedulePersist();
    notifyListeners();
  }

  void startCoaching(ConsultationData consultation) {
    consultation.status = ConsultationStatus.coaching;
    _schedulePersist();
    notifyListeners();
  }

  void rateConsultation(ConsultationData consultation, int rating) {
    consultation.rating = rating.clamp(1, 5);
    _schedulePersist();
    notifyListeners();
  }

  BusinessDashboardData dashboardFor(UserRole role) {
    return businessDashboards[role] ??
        businessDashboards[UserRole.trainer] ??
        BusinessDashboardData(
          role: role,
          facts: {},
          tasks: [],
          notifications: [],
          lastSyncedAt: DateTime.now(),
        );
  }

  int unreadBusinessNotifications(UserRole role) {
    return dashboardFor(
      role,
    ).notifications.where((notification) => !notification.isRead).length;
  }

  void dismissBusinessNotification(UserRole role, String notificationId) {
    dashboardFor(
      role,
    ).notifications.removeWhere((item) => item.id == notificationId);
    _schedulePersist();
    notifyListeners();
  }

  void markAllBusinessNotificationsRead(UserRole role) {
    for (final notification in dashboardFor(role).notifications) {
      notification.isRead = true;
    }
    _schedulePersist();
    notifyListeners();
  }

  /// Reloads just the account's business access (roles, application status).
  ///
  /// The pro gate needs this right after a sign-in: the shell may not have
  /// pulled business data yet, and reporting "not applied" to an approved
  /// trainer would be a lie the user cannot argue with.
  Future<void> refreshBusinessAccess() async {
    final repository = businessRepository;
    if (repository == null) return;
    final accountEpoch = _accountEpoch;
    try {
      final access = await repository.loadAccess();
      if (!_isCurrentAccount(accountEpoch)) return;
      businessAccess = access;
      notifyListeners();
    } catch (error) {
      if (!_isCurrentAccount(accountEpoch)) return;
      businessError = error;
      notifyListeners();
    }
  }

  Future<void> refreshBusinessDashboard(UserRole role) async {
    final repository = businessRepository;
    if (repository != null) {
      try {
        await _refreshBusinessData(repository);
        cloudSyncError = null;
      } catch (error) {
        cloudSyncError = error;
        rethrow;
      } finally {
        notifyListeners();
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 550));
    dashboardFor(role).lastSyncedAt = DateTime.now();
    _schedulePersist();
    notifyListeners();
  }

  Future<void> refreshMemberConsultations() async {
    final repository = businessRepository;
    if (repository == null) {
      await refreshBusinessDashboard(role);
      return;
    }
    final accountEpoch = _accountEpoch;
    final requestToken = ++_memberConsultationRequestSequence;
    memberConsultationsLoading = true;
    memberConsultationsError = null;
    notifyListeners();
    try {
      final refreshed = List<BusinessConsultation>.unmodifiable(
        await repository.listMyConsultations(),
      );
      if (!_isCurrentAccount(accountEpoch) ||
          requestToken != _memberConsultationRequestSequence) {
        return;
      }
      memberConsultations = refreshed;
      memberConsultationsError = null;
      _syncMemberConsultationsFromCloud();
    } catch (error) {
      if (!_isCurrentAccount(accountEpoch) ||
          requestToken != _memberConsultationRequestSequence) {
        return;
      }
      memberConsultationsError = error;
      rethrow;
    } finally {
      if (_isCurrentAccount(accountEpoch) &&
          requestToken == _memberConsultationRequestSequence) {
        memberConsultationsLoading = false;
        notifyListeners();
      }
    }
  }

  void recordBusinessMemberFeedback({
    required UserRole role,
    required String memberName,
    required String feedback,
  }) {
    if (businessRepository != null) return;
    final facts = dashboardFor(role).facts;
    facts['memberFeedback.$memberName'] = feedback;
    facts['memberFeedbackAt.$memberName'] = DateTime.now().toIso8601String();
    _schedulePersist();
    notifyListeners();
  }

  Future<void> assignBusinessMember({
    required String memberName,
    String? trainerName,
  }) async {
    if (businessRepository != null) {
      final matchingMembers = businessMembers
          .where((item) => item.name == memberName)
          .take(2)
          .toList(growable: false);
      if (matchingMembers.isEmpty) throw StateError('회원을 찾을 수 없습니다.');
      if (matchingMembers.length > 1) {
        throw StateError('동명이인 회원이 있어 ID로 선택해야 합니다.');
      }
      final member = matchingMembers.single;
      String? trainerId;
      if (trainerName != null) {
        final matchingTrainers = businessTrainers
            .where((item) => item.displayName == trainerName)
            .take(2)
            .toList(growable: false);
        if (matchingTrainers.isEmpty) {
          throw StateError('트레이너를 찾을 수 없습니다.');
        }
        if (matchingTrainers.length > 1) {
          throw StateError('동명이인 트레이너가 있어 ID로 선택해야 합니다.');
        }
        trainerId = matchingTrainers.single.trainerId;
        if (trainerId == null) throw StateError('트레이너 ID가 없습니다.');
      }
      await assignBusinessMemberById(
        gymId: member.gymId,
        memberId: member.id,
        trainerId: trainerId,
      );
      return;
    }
    final facts = dashboardFor(UserRole.gym).facts;
    if (trainerName == null) {
      facts.remove('memberAssignment.$memberName');
    } else {
      facts['memberAssignment.$memberName'] = trainerName;
    }
    facts['memberAssignmentAt.$memberName'] = DateTime.now().toIso8601String();
    _schedulePersist();
    notifyListeners();
  }

  Future<void> assignBusinessMemberById({
    required String gymId,
    required String memberId,
    String? trainerId,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    await _runBusinessMutation<void>(_assignmentMutationKey(memberId), (
      accountEpoch,
    ) async {
      await repository.assignMember(
        AssignMemberInput(
          gymId: gymId,
          memberId: memberId,
          trainerId: trainerId,
        ),
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      await _refreshBusinessData(
        repository,
        expectedAccountEpoch: accountEpoch,
      );
    });
  }

  Future<BusinessMember> endBusinessMembership(String memberId) async {
    final repository = businessRepository;
    if (repository is! BusinessMembershipRepository) {
      throw StateError('센터 관계 종료 서버가 연결되지 않았습니다.');
    }
    final requestId = _membershipEndRequestIds.putIfAbsent(
      memberId,
      _newUuidV4,
    );
    return _runBusinessMutation<BusinessMember>('membership:end:$memberId', (
      accountEpoch,
    ) async {
      final ended = await (repository as BusinessMembershipRepository)
          .endBusinessMembership(
            EndBusinessMembershipInput(
              memberId: memberId,
              requestId: requestId,
            ),
          );
      if (!_isCurrentAccount(accountEpoch)) return ended;
      _businessMemberDetails.remove(memberId);
      _businessMemberDetailErrors.remove(memberId);
      memberMemberships = memberMemberships
          .where((item) => item.id != memberId)
          .toList(growable: false);
      await _refreshBusinessData(
        repository as BusinessRepository,
        expectedAccountEpoch: accountEpoch,
      );
      if (_isCurrentAccount(accountEpoch)) {
        _membershipEndRequestIds.remove(memberId);
      }
      return ended;
    });
  }

  Future<BusinessMemberDetail> loadBusinessMemberDetail(
    String memberId, {
    bool force = false,
    DateTime? from,
    DateTime? to,
  }) {
    final repository = businessRepository;
    if (repository == null) {
      return Future<BusinessMemberDetail>.error(
        StateError('실데이터 저장소가 연결되지 않았습니다.'),
      );
    }
    if (force) {
      _memberDetailGeneration++;
      _businessMemberDetails.remove(memberId);
      _businessMemberDetailErrors.remove(memberId);
    }
    if (!force) {
      final cached = _businessMemberDetails[memberId];
      if (cached != null) return Future.value(cached);
      final inFlight = _memberDetailLoads[memberId];
      if (inFlight != null) return inFlight;
    }

    final accountEpoch = _accountEpoch;
    final detailGeneration = _memberDetailGeneration;
    final request = repository
        .loadMemberDetail(memberId, from: from, to: to)
        .then((detail) {
          if (!_isCurrentAccount(accountEpoch) ||
              detailGeneration != _memberDetailGeneration) {
            throw StateError('계정 또는 공유 권한이 변경되어 회원 상세 요청을 취소했습니다.');
          }
          if (detail.memberId != memberId) {
            throw StateError('요청한 회원과 다른 상세 데이터가 반환되었습니다.');
          }
          _businessMemberDetails[memberId] = detail;
          _businessMemberDetailErrors.remove(memberId);
          return detail;
        })
        .catchError((Object error) {
          if (_isCurrentAccount(accountEpoch) &&
              detailGeneration == _memberDetailGeneration) {
            _businessMemberDetailErrors[memberId] = error;
          }
          throw error;
        })
        .whenComplete(() {
          if (_isCurrentAccount(accountEpoch) &&
              detailGeneration == _memberDetailGeneration) {
            _memberDetailLoads.remove(memberId);
            notifyListeners();
          }
        });
    _memberDetailLoads[memberId] = request;
    _businessMemberDetailErrors.remove(memberId);
    notifyListeners();
    return request;
  }

  void _clearBusinessMemberDetailCache() {
    _memberDetailGeneration++;
    _memberDetailLoads.clear();
    _businessMemberDetails.clear();
    _businessMemberDetailErrors.clear();
  }

  Future<BusinessSessionFeedback> sendBusinessSessionFeedback({
    required String memberId,
    required String sessionId,
    required String text,
    String? requestId,
  }) async {
    final message = text.trim();
    if (message.isEmpty) throw ArgumentError('피드백 내용을 입력해주세요.');
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    final requestKey = '$sessionId\u0000$message';
    final stableRequestId =
        requestId ??
        _sessionFeedbackRequestIds.putIfAbsent(requestKey, _newUuidV4);
    return _runBusinessMutation<BusinessSessionFeedback>(
      'feedback:session:$sessionId',
      (accountEpoch) async {
        final feedback = await repository.sendSessionFeedback(
          SendSessionFeedbackInput(
            sessionId: sessionId,
            text: message,
            requestId: stableRequestId,
          ),
        );
        _sessionFeedbackRequestIds.remove(requestKey);
        if (_isCurrentAccount(accountEpoch)) {
          try {
            await loadBusinessMemberDetail(memberId, force: true);
          } catch (error) {
            if (_isCurrentAccount(accountEpoch)) {
              _businessMemberDetailErrors[memberId] = error;
            }
          }
        }
        return feedback;
      },
    );
  }

  Future<void> updateMemberSharingPreferences({
    required bool shareBodyData,
    required bool shareWorkoutRecords,
    required bool marketing,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    await _runBusinessMutation<void>('member:sharing-preferences', (
      accountEpoch,
    ) async {
      await repository.updateMySharingPreferences(
        MemberSharingPreferences(
          shareBodyData: shareBodyData,
          shareWorkoutRecords: shareWorkoutRecords,
          marketing: marketing,
        ),
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      await _refreshBusinessData(
        repository,
        expectedAccountEpoch: accountEpoch,
      );
    });
  }

  Future<void> refreshCoachingSchedules({DateTime? from, DateTime? to}) async {
    final repository = businessRepository;
    if (repository == null) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      notifyListeners();
      return;
    }
    final accountEpoch = _accountEpoch;
    final requestToken = ++_scheduleRequestSequence;
    coachingSchedulesLoading = true;
    coachingSchedulesError = null;
    notifyListeners();
    try {
      final schedules = await repository.listCoachingSchedules(
        from: from,
        to: to,
      );
      if (!_isCurrentAccount(accountEpoch) ||
          requestToken != _scheduleRequestSequence) {
        return;
      }
      coachingSchedules = _sortedCoachingSchedules(
        schedules.map(_enrichCoachingScheduleNames),
      );
    } catch (error) {
      if (_isCurrentAccount(accountEpoch) &&
          requestToken == _scheduleRequestSequence) {
        coachingSchedulesError = error;
      }
      rethrow;
    } finally {
      if (_isCurrentAccount(accountEpoch) &&
          requestToken == _scheduleRequestSequence) {
        coachingSchedulesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<BusinessCoachingSchedule> createCoachingSchedule({
    required String title,
    required DateTime date,
    required int startMinutes,
    required int endMinutes,
    String? memberId,
    String? connectionId,
    String? gymId,
  }) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) throw ArgumentError('일정 제목을 입력해주세요.');
    if (endMinutes <= startMinutes) {
      throw ArgumentError('종료 시간은 시작 시간보다 늦어야 합니다.');
    }
    final repository = businessRepository;
    if (repository == null) {
      final schedule = BusinessCoachingSchedule(
        id: 'demo-schedule-${DateTime.now().microsecondsSinceEpoch}',
        trainerId: 'demo-trainer',
        memberUserId: memberId == null && connectionId == null
            ? null
            : 'demo-member-user',
        gymId: gymId,
        title: normalizedTitle,
        date: DateTime(date.year, date.month, date.day),
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        trainerName: '김코치',
        memberName: memberId == null && connectionId == null ? null : '박민지',
        createdAt: DateTime.now(),
      );
      coachingSchedules = _sortedCoachingSchedules([
        ...coachingSchedules,
        schedule,
      ]);
      notifyListeners();
      return Future.value(schedule);
    }
    final profile = businessWorkspace?.profile;
    if (role != UserRole.trainer || profile is! TrainerBusinessProfile) {
      throw StateError('승인된 트레이너만 일정을 만들 수 있습니다.');
    }

    BusinessMember? member;
    CoachingConnection? connection;
    if (memberId != null && connectionId != null) {
      throw ArgumentError('센터 회원과 개인 연결 회원을 동시에 선택할 수 없습니다.');
    }
    if (memberId != null) {
      member = businessMembers.where((item) => item.id == memberId).firstOrNull;
      if (member == null || member.userId == null) {
        throw StateError('연결된 회원 계정만 일정에 지정할 수 있습니다.');
      }
      final isAssigned = businessWorkspace?.assignments.any(
        (assignment) =>
            assignment.active &&
            assignment.memberId == member!.id &&
            assignment.trainerId == profile.id &&
            assignment.gymId == member.gymId,
      );
      if (isAssigned != true) {
        throw StateError('현재 트레이너에게 배정된 회원이 아닙니다.');
      }
    }
    if (connectionId != null) {
      connection = coachingConnections
          .where(
            (item) =>
                item.id == connectionId &&
                item.trainerId == profile.id &&
                item.isActive,
          )
          .firstOrNull;
      if (connection == null) {
        throw StateError('활성 상태인 개인 코칭 회원이 아닙니다.');
      }
    }
    final resolvedMemberUserId = member?.userId ?? connection?.memberUserId;
    final resolvedGymId = gymId ?? member?.gymId;

    final requestKey = [
      profile.id,
      resolvedMemberUserId ?? '',
      resolvedGymId ?? '',
      DateTime(date.year, date.month, date.day).toIso8601String(),
      startMinutes,
      endMinutes,
      normalizedTitle,
    ].join('|');
    final requestId = _coachingScheduleCreateRequestIds.putIfAbsent(
      requestKey,
      _newUuidV4,
    );

    return _runBusinessMutation<BusinessCoachingSchedule>(
      'coaching-schedule:create',
      (accountEpoch) async {
        final created = await repository.createCoachingSchedule(
          CreateCoachingScheduleInput(
            requestId: requestId,
            trainerId: profile.id,
            memberUserId: resolvedMemberUserId,
            gymId: resolvedGymId,
            title: normalizedTitle,
            date: date,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
          ),
        );
        if (created.trainerId != profile.id ||
            created.memberUserId != resolvedMemberUserId ||
            created.gymId != resolvedGymId) {
          throw StateError('요청한 관계와 다른 일정이 반환되었습니다.');
        }
        final enriched = _enrichCoachingScheduleNames(created);
        if (_isCurrentAccount(accountEpoch)) {
          _coachingScheduleCreateRequestIds.remove(requestKey);
          coachingSchedules = _sortedCoachingSchedules([
            ...coachingSchedules.where((item) => item.id != enriched.id),
            enriched,
          ]);
          notifyListeners();
        }
        return enriched;
      },
    );
  }

  Future<BusinessCoachingSchedule> setCoachingScheduleCompleted(
    String scheduleId, {
    required bool completed,
  }) {
    final schedule = coachingSchedules
        .where((item) => item.id == scheduleId)
        .firstOrNull;
    if (schedule == null) throw StateError('일정을 찾을 수 없습니다.');
    final repository = businessRepository;
    if (repository == null) {
      final updated = _copyCoachingSchedule(
        schedule,
        completedAt: completed ? DateTime.now() : null,
        clearCompletedAt: !completed,
      );
      coachingSchedules = _replaceCoachingSchedule(updated);
      notifyListeners();
      return Future.value(updated);
    }
    final profile = businessWorkspace?.profile;
    if (role != UserRole.trainer ||
        profile is! TrainerBusinessProfile ||
        profile.id != schedule.trainerId) {
      throw StateError('일정을 만든 트레이너만 완료 상태를 변경할 수 있습니다.');
    }
    return _runBusinessMutation<BusinessCoachingSchedule>(
      'coaching-schedule:update:$scheduleId',
      (accountEpoch) async {
        final updated = await repository.setCoachingScheduleCompleted(
          schedule.id,
          trainerId: profile.id,
          completed: completed,
        );
        if (updated.id != schedule.id || updated.trainerId != profile.id) {
          throw StateError('요청한 일정과 다른 데이터가 반환되었습니다.');
        }
        if (_isCurrentAccount(accountEpoch)) {
          coachingSchedules = _replaceCoachingSchedule(updated);
          notifyListeners();
        }
        return updated;
      },
    );
  }

  Future<void> deleteCoachingSchedule(String scheduleId) async {
    final schedule = coachingSchedules
        .where((item) => item.id == scheduleId)
        .firstOrNull;
    if (schedule == null) throw StateError('일정을 찾을 수 없습니다.');
    final repository = businessRepository;
    if (repository == null) {
      coachingSchedules = List.unmodifiable(
        coachingSchedules.where((item) => item.id != scheduleId),
      );
      notifyListeners();
      return;
    }
    final profile = businessWorkspace?.profile;
    if (role != UserRole.trainer ||
        profile is! TrainerBusinessProfile ||
        profile.id != schedule.trainerId) {
      throw StateError('일정을 만든 트레이너만 삭제할 수 있습니다.');
    }
    await _runBusinessMutation<void>('coaching-schedule:delete:$scheduleId', (
      accountEpoch,
    ) async {
      await repository.deleteCoachingSchedule(
        schedule.id,
        trainerId: profile.id,
      );
      if (_isCurrentAccount(accountEpoch)) {
        coachingSchedules = List.unmodifiable(
          coachingSchedules.where((item) => item.id != scheduleId),
        );
        notifyListeners();
      }
    });
  }

  Future<CoachingHealthConsent> updateCoachingHealthConsent({
    required String scheduleId,
    required bool shareWithTrainer,
    required bool shareWithGym,
  }) async {
    final schedule = coachingSchedules
        .where((item) => item.id == scheduleId)
        .firstOrNull;
    if (schedule == null ||
        schedule.memberUserId == null ||
        schedule.gymId == null) {
      throw StateError('회원과 실제 수업 헬스장이 지정된 일정이 필요합니다.');
    }
    if (schedule.isCompleted) {
      throw StateError('완료된 수업의 건강정보 동의는 변경할 수 없습니다.');
    }

    final currentUserId = businessAccess?.userId;
    if (role != UserRole.member ||
        currentUserId == null ||
        currentUserId != schedule.memberUserId) {
      throw StateError('해당 수업의 회원만 건강정보 제공 여부를 선택할 수 있습니다.');
    }

    final repository = businessRepository;
    if (repository == null) {
      final now = DateTime.now();
      final previous = schedule.healthConsent;
      final consent = CoachingHealthConsent(
        scheduleId: schedule.id,
        memberUserId: schedule.memberUserId!,
        trainerId: schedule.trainerId,
        gymId: schedule.gymId!,
        shareWithTrainer: shareWithTrainer,
        shareWithGym: shareWithGym,
        trainerConsentedAt: shareWithTrainer
            ? previous?.trainerConsentedAt ?? now
            : previous?.trainerConsentedAt,
        trainerRevokedAt:
            !shareWithTrainer && (previous?.shareWithTrainer ?? false)
            ? now
            : previous?.trainerRevokedAt,
        gymConsentedAt: shareWithGym
            ? previous?.gymConsentedAt ?? now
            : previous?.gymConsentedAt,
        gymRevokedAt: !shareWithGym && (previous?.shareWithGym ?? false)
            ? now
            : previous?.gymRevokedAt,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
      );
      coachingSchedules = _replaceCoachingSchedule(
        _copyCoachingSchedule(schedule, healthConsent: consent),
      );
      notifyListeners();
      return consent;
    }
    if (repository is! CoachingHealthConsentRepository) {
      throw StateError('수업별 건강정보 동의 기능이 연결되지 않았습니다.');
    }

    // The health overview reads the current account snapshot. Flush the
    // member's latest survey and body profile before opening access.
    await syncPersistenceToServer();
    final requestKey = '$scheduleId|$shareWithTrainer|$shareWithGym';
    final requestId = _coachingHealthConsentRequestIds.putIfAbsent(
      requestKey,
      _newUuidV4,
    );
    return _runBusinessMutation<CoachingHealthConsent>(
      'coaching-health:consent:$scheduleId',
      (accountEpoch) async {
        final consent = await (repository as CoachingHealthConsentRepository)
            .setCoachingHealthConsent(
              scheduleId: scheduleId,
              shareWithTrainer: shareWithTrainer,
              shareWithGym: shareWithGym,
              requestId: requestId,
            );
        if (consent.scheduleId != schedule.id ||
            consent.memberUserId != schedule.memberUserId ||
            consent.trainerId != schedule.trainerId ||
            consent.gymId != schedule.gymId) {
          throw StateError('요청한 수업과 다른 건강정보 동의가 반환되었습니다.');
        }
        if (_isCurrentAccount(accountEpoch)) {
          _coachingHealthConsentRequestIds.remove(requestKey);
          coachingSchedules = _replaceCoachingSchedule(
            _copyCoachingSchedule(schedule, healthConsent: consent),
          );
          notifyListeners();
        }
        return consent;
      },
    );
  }

  Future<CoachingHealthOverview> loadCoachingHealthOverview(
    String scheduleId,
  ) async {
    final schedule = coachingSchedules
        .where((item) => item.id == scheduleId)
        .firstOrNull;
    if (schedule == null) throw StateError('일정을 찾을 수 없습니다.');
    if (schedule.isCompleted && role != UserRole.member) {
      throw StateError('수업이 종료되어 건강정보 접근이 만료되었습니다.');
    }
    final repository = businessRepository;
    if (repository is! CoachingHealthConsentRepository) {
      throw StateError('수업별 건강정보 열람 기능이 연결되지 않았습니다.');
    }
    final overview = await (repository as CoachingHealthConsentRepository)
        .getCoachingHealthOverview(scheduleId);
    if (overview.scheduleId != schedule.id ||
        overview.memberUserId != schedule.memberUserId ||
        overview.trainerId != schedule.trainerId ||
        overview.gymId != schedule.gymId) {
      throw StateError('요청한 수업과 다른 건강정보가 반환되었습니다.');
    }
    return overview;
  }

  Future<BusinessInviteCreation> createGymBusinessInvite({
    required BusinessInviteKind kind,
    String? memberId,
    String? recipientName,
    String? recipientPhone,
    String? roleTitle,
    Duration validFor = const Duration(days: 7),
  }) {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    final profile = businessWorkspace?.profile;
    if (profile is! GymBusinessProfile || role != UserRole.gym) {
      throw StateError('승인된 센터 계정에서만 초대를 만들 수 있습니다.');
    }
    final normalizedMemberId = _normalizedBusinessRequestText(memberId);
    final normalizedRecipientName = _normalizedBusinessRequestText(
      recipientName,
    );
    final normalizedRecipientPhone = _normalizedBusinessRequestText(
      recipientPhone,
    );
    final normalizedRoleTitle = _normalizedBusinessRequestText(roleTitle);
    final expiryRequestKey =
        _businessRpcRequestKey('create_business_invite:expiry', {
          'gymId': profile.id,
          'kind': kind.databaseValue,
          'memberId': normalizedMemberId,
          'recipientName': normalizedRecipientName,
          'recipientPhone': normalizedRecipientPhone,
          'roleTitle': normalizedRoleTitle,
          'validForMicroseconds': validFor.inMicroseconds,
        });
    final requestId = _stableBusinessRpcRequestId(expiryRequestKey);
    final mutationKey =
        'business-invite:create:${kind.databaseValue}:$requestId';
    return _runBusinessMutation<BusinessInviteCreation>(mutationKey, (
      accountEpoch,
    ) async {
      final expiresAt = _businessInviteCreateExpiresAt.putIfAbsent(
        expiryRequestKey,
        () => DateTime.now().toUtc().add(validFor),
      );
      final result = await repository.createBusinessInvite(
        CreateBusinessInviteInput(
          gymId: profile.id,
          kind: kind,
          expiresAt: expiresAt,
          requestId: requestId,
          memberId: normalizedMemberId,
          recipientName: normalizedRecipientName,
          recipientPhone: normalizedRecipientPhone,
          roleTitle: normalizedRoleTitle,
        ),
      );
      if (_isCurrentAccount(accountEpoch)) {
        businessInvites = List.unmodifiable([
          result.invite,
          ...businessInvites.where((item) => item.id != result.invite.id),
        ]);
        notifyListeners();
      }
      _completeBusinessRpcRequest(
        expiryRequestKey,
        expectedAccountEpoch: accountEpoch,
      );
      if (_isCurrentAccount(accountEpoch)) {
        _businessInviteCreateExpiresAt.remove(expiryRequestKey);
      }
      return result;
    });
  }

  Future<BusinessInviteAcceptance> acceptBusinessInviteToken([String? token]) {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    final normalizedToken = (token ?? pendingBusinessInviteToken)?.trim();
    if (normalizedToken == null || normalizedToken.isEmpty) {
      throw ArgumentError('초대 토큰이 없습니다.');
    }
    final requestId = _businessInviteAcceptRequestIds.putIfAbsent(
      normalizedToken,
      _newUuidV4,
    );
    return _runBusinessMutation<BusinessInviteAcceptance>(
      'business-invite:accept:$normalizedToken',
      (accountEpoch) async {
        final result = await repository.acceptBusinessInvite(
          normalizedToken,
          requestId: requestId,
        );
        if (!_isCurrentAccount(accountEpoch)) return result;
        pendingBusinessInviteToken = null;
        _businessInviteAcceptRequestIds.remove(normalizedToken);
        try {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        } catch (error) {
          if (_isCurrentAccount(accountEpoch)) businessError = error;
        }
        return result;
      },
    );
  }

  Future<CoachingConnectionInviteCreation> createCoachingConnectionInvite({
    String? recipientName,
    Duration validFor = const Duration(days: 7),
  }) {
    final repository = businessRepository;
    if (repository is! MobileCoachingRepository) {
      throw StateError('이 앱 버전에서는 개인 회원 연결을 지원하지 않습니다.');
    }
    final mobileRepository = repository as MobileCoachingRepository;
    final profile = businessWorkspace?.profile;
    if (role != UserRole.trainer || profile is! TrainerBusinessProfile) {
      throw StateError('승인된 트레이너만 회원 연결 초대를 만들 수 있습니다.');
    }
    final normalizedName = _normalizedBusinessRequestText(recipientName);
    final requestKey =
        _businessRpcRequestKey('create_coaching_connection_invite', {
          'trainerId': profile.id,
          'recipientName': normalizedName,
          'validForMicroseconds': validFor.inMicroseconds,
        });
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<CoachingConnectionInviteCreation>(
      'coaching-invite:create:$requestId',
      (accountEpoch) async {
        final expiresAt = _coachingInviteCreateExpiresAt.putIfAbsent(
          requestKey,
          () => DateTime.now().toUtc().add(validFor),
        );
        final result = await mobileRepository.createCoachingConnectionInvite(
          requestId: requestId,
          expiresAt: expiresAt,
          recipientName: normalizedName,
        );
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        if (_isCurrentAccount(accountEpoch)) {
          _coachingInviteCreateExpiresAt.remove(requestKey);
        }
        return result;
      },
    );
  }

  Future<CoachingConnectionAcceptance> acceptCoachingConnectionInviteToken([
    String? token,
  ]) {
    final repository = businessRepository;
    if (repository is! MobileCoachingRepository) {
      throw StateError('이 앱 버전에서는 개인 회원 연결을 지원하지 않습니다.');
    }
    final mobileRepository = repository as MobileCoachingRepository;
    final normalizedToken = (token ?? pendingCoachingInviteToken)?.trim();
    if (normalizedToken == null || normalizedToken.isEmpty) {
      throw ArgumentError('초대 토큰이 없습니다.');
    }
    final requestId = _coachingInviteAcceptRequestIds.putIfAbsent(
      normalizedToken,
      _newUuidV4,
    );
    return _runBusinessMutation<CoachingConnectionAcceptance>(
      'coaching-invite:accept:$normalizedToken',
      (accountEpoch) async {
        final result = await mobileRepository.acceptCoachingConnectionInvite(
          normalizedToken,
          requestId: requestId,
        );
        if (!_isCurrentAccount(accountEpoch)) return result;
        pendingCoachingInviteToken = null;
        _coachingInviteAcceptRequestIds.remove(normalizedToken);
        try {
          await _refreshBusinessData(
            businessRepository!,
            expectedAccountEpoch: accountEpoch,
          );
        } catch (error) {
          if (_isCurrentAccount(accountEpoch)) businessError = error;
        }
        return result;
      },
    );
  }

  Future<CoachingSessionRecord> publishCoachingSessionRecord({
    required String scheduleId,
    required String sessionSummary,
    String? routineId,
    String? routineSummary,
    String? consultationSummary,
  }) {
    final repository = businessRepository;
    if (repository is! MobileCoachingRepository) {
      throw StateError('수업 공유 기록 저장을 지원하지 않습니다.');
    }
    final mobileRepository = repository as MobileCoachingRepository;
    final normalizedSummary = sessionSummary.trim();
    if (normalizedSummary.isEmpty) {
      throw ArgumentError('수업 내용을 입력해주세요.');
    }
    final requestKey =
        _businessRpcRequestKey('publish_coaching_session_record', {
          'scheduleId': scheduleId,
          'routineId': routineId,
          'sessionSummary': normalizedSummary,
          'routineSummary': routineSummary?.trim(),
          'consultationSummary': consultationSummary?.trim(),
        });
    return _runBusinessMutation<CoachingSessionRecord>(
      'coaching-session:publish:$scheduleId',
      (accountEpoch) async {
        final record = await mobileRepository.publishCoachingSessionRecord(
          PublishCoachingSessionRecordInput(
            requestId: _stableBusinessRpcRequestId(requestKey),
            scheduleId: scheduleId,
            routineId: _normalizedBusinessRequestText(routineId),
            sessionSummary: normalizedSummary,
            routineSummary: _normalizedBusinessRequestText(routineSummary),
            consultationSummary: _normalizedBusinessRequestText(
              consultationSummary,
            ),
          ),
        );
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            businessRepository!,
            expectedAccountEpoch: accountEpoch,
          );
          await refreshCoachingSchedules();
        }
        return record;
      },
    );
  }

  Future<BusinessInviteRecord> revokeBusinessInvite(String inviteId) {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    final normalizedInviteId = inviteId.trim();
    final requestKey = _businessRpcRequestKey('revoke_business_invite', {
      'inviteId': normalizedInviteId,
    });
    return _runBusinessMutation<BusinessInviteRecord>(
      'business-invite:revoke:$inviteId',
      (accountEpoch) async {
        final requestId = _stableBusinessRpcRequestId(requestKey);
        final result = await repository.revokeBusinessInvite(
          normalizedInviteId,
          requestId: requestId,
        );
        if (_isCurrentAccount(accountEpoch)) {
          businessInvites = List.unmodifiable(
            businessInvites
                .map((item) => item.id == result.id ? result : item)
                .toList(growable: false),
          );
          notifyListeners();
        }
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return result;
      },
    );
  }

  void markBusinessNotificationRead(UserRole role, String notificationId) {
    for (final notification in dashboardFor(role).notifications) {
      if (notification.id == notificationId) {
        notification.isRead = true;
        break;
      }
    }
    _schedulePersist();
    notifyListeners();
  }

  void completeGymOnboarding({
    required String displayName,
    required String businessNumber,
  }) {
    final facts = dashboardFor(UserRole.gym).facts;
    facts['displayName'] = displayName;
    facts['businessNumber'] = businessNumber;
    facts['businessVerified'] = 'true';
    facts.putIfAbsent('planId', () => 'basic');
    facts.putIfAbsent('plan', () => 'Basic');
    _schedulePersist();
    notifyListeners();
  }

  Future<void> updateBusinessProfile({
    required UserRole role,
    required String displayName,
    required String keyword,
    required String intro,
    bool? acceptsOnlineConsultation,
    bool? acceptsOfflineConsultation,
    String? primaryActivityRegionCode,
  }) async {
    final repository = businessRepository;
    final profile = businessWorkspace?.profile;
    if (repository != null && profile != null) {
      final input = switch (profile) {
        TrainerBusinessProfile() => UpdateBusinessProfileInput.trainer(
          profileId: profile.id,
          displayName: displayName,
          keyword: keyword,
          intro: intro,
        ),
        GymBusinessProfile() => UpdateBusinessProfileInput.gym(
          profileId: profile.id,
          name: displayName,
          address: keyword,
          description: intro,
        ),
      };
      await _runBusinessMutation<void>(
        _businessProfileMutationKey(profile.id),
        (accountEpoch) async {
          if (profile is TrainerBusinessProfile &&
              acceptsOnlineConsultation != null &&
              acceptsOfflineConsultation != null) {
            if (repository is! TrainerConsultationSettingsRepository) {
              throw StateError('트레이너 상담 설정을 저장할 수 없습니다.');
            }
            await (repository as TrainerConsultationSettingsRepository)
                .updateTrainerConsultationSettings(
                  TrainerConsultationSettingsInput(
                    acceptsOnline: acceptsOnlineConsultation,
                    acceptsOffline: acceptsOfflineConsultation,
                    regionCodes: primaryActivityRegionCode == null
                        ? const []
                        : [primaryActivityRegionCode],
                  ),
                );
          }
          await repository.updateProfile(input);
          if (!_isCurrentAccount(accountEpoch)) return;
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        },
      );
      return;
    }
    final facts = dashboardFor(role).facts;
    facts['displayName'] = displayName;
    facts[role == UserRole.gym ? 'location' : 'keyword'] = keyword;
    facts['intro'] = intro;
    if (role == UserRole.trainer) {
      if (acceptsOnlineConsultation != null) {
        facts['acceptsOnlineConsultation'] = '$acceptsOnlineConsultation';
      }
      if (acceptsOfflineConsultation != null) {
        facts['acceptsOfflineConsultation'] = '$acceptsOfflineConsultation';
      }
      final selectedRegion = serviceRegions
          .where((item) => item.code == primaryActivityRegionCode)
          .firstOrNull;
      facts['primaryActivityRegion'] = selectedRegion?.name ?? '';
    }
    _schedulePersist();
    notifyListeners();
  }

  Future<List<GymDirectoryEntry>> loadVerifiedGyms() async {
    final repository = businessRepository;
    if (repository is! WorkoutLocationRepository) return const [];
    return List.unmodifiable(
      await (repository as WorkoutLocationRepository).listVerifiedGyms(),
    );
  }

  Future<void> refreshWorkoutLocations() async {
    final repository = businessRepository;
    if (repository is! WorkoutLocationRepository) return;
    try {
      serviceRegions = List.unmodifiable(
        await (repository as WorkoutLocationRepository).listServiceRegions(),
      );
      workoutLocations = List.unmodifiable(
        await (repository as WorkoutLocationRepository)
            .listMyWorkoutLocations(),
      );
      workoutLocationsError = null;
      notifyListeners();
    } catch (error) {
      workoutLocationsError = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveWorkoutLocation(String gymId) async {
    final repository = businessRepository;
    if (repository is! WorkoutLocationRepository) {
      throw StateError('운동 장소 저장을 지원하지 않습니다.');
    }
    await _runBusinessMutation<void>('workout-location:save:$gymId', (
      accountEpoch,
    ) async {
      await (repository as WorkoutLocationRepository).saveWorkoutLocation(
        gymId,
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      workoutLocations = List.unmodifiable(
        await (repository as WorkoutLocationRepository)
            .listMyWorkoutLocations(),
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      workoutLocationsError = null;
      notifyListeners();
    });
  }

  Future<void> selectWorkoutLocation(String locationId) async {
    final repository = businessRepository;
    if (repository is! WorkoutLocationRepository) {
      throw StateError('운동 장소 선택을 지원하지 않습니다.');
    }
    await _runBusinessMutation<void>('workout-location:select:$locationId', (
      accountEpoch,
    ) async {
      await (repository as WorkoutLocationRepository).selectWorkoutLocation(
        locationId,
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      workoutLocations = List.unmodifiable(
        await (repository as WorkoutLocationRepository)
            .listMyWorkoutLocations(),
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      workoutLocationsError = null;
      notifyListeners();
    });
  }

  Future<void> removeWorkoutLocation(String locationId) async {
    final repository = businessRepository;
    if (repository is! WorkoutLocationRepository) {
      throw StateError('운동 장소 삭제를 지원하지 않습니다.');
    }
    await _runBusinessMutation<void>('workout-location:remove:$locationId', (
      accountEpoch,
    ) async {
      await (repository as WorkoutLocationRepository).removeWorkoutLocation(
        locationId,
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      workoutLocations = List.unmodifiable(
        await (repository as WorkoutLocationRepository)
            .listMyWorkoutLocations(),
      );
      if (!_isCurrentAccount(accountEpoch)) return;
      workoutLocationsError = null;
      notifyListeners();
    });
  }

  void setBusinessPlan({
    required UserRole role,
    required String planId,
    required String planName,
  }) {
    final facts = dashboardFor(role).facts;
    facts['planId'] = planId;
    facts['plan'] = planName;
    _schedulePersist();
    notifyListeners();
  }

  /// 업무 알림 스위치. 역할에 상관없이 계정에 하나다 — 한 계정은 한 역할로
  /// 일하고, 스냅샷의 `preferences.businessNotifications`가 서버와 공유하는
  /// 진실이다(예전엔 데모 대시보드의 facts에만 있어 라이브에서 저장되지 않았다).
  bool businessNotificationPreference(
    UserRole role,
    String key, {
    required bool fallback,
  }) {
    return businessNotifications[key] ?? fallback;
  }

  void setBusinessNotificationPreference(
    UserRole role,
    String key,
    bool value,
  ) {
    businessNotifications = {...businessNotifications, key: value};
    _schedulePersist();
    notifyListeners();
  }

  bool isBusinessConsultationAnswered(UserRole role, int consultationIndex) {
    if (businessRepository != null) {
      if (consultationIndex < 0 ||
          consultationIndex >= businessConsultations.length) {
        return false;
      }
      final consultation = businessConsultations[consultationIndex];
      return consultation.status == BusinessConsultationStatus.answered ||
          consultation.status == BusinessConsultationStatus.replied ||
          consultation.messages.any(
            (message) =>
                message.sender == BusinessMessageSender.trainer ||
                message.sender == BusinessMessageSender.gym,
          );
    }
    return dashboardFor(
          role,
        ).facts['consultation.$consultationIndex.answered'] ==
        'true';
  }

  Future<void> answerBusinessConsultation({
    required UserRole role,
    required int consultationIndex,
    required String answer,
  }) async {
    if (businessRepository != null) {
      if (consultationIndex < 0 ||
          consultationIndex >= businessConsultations.length) {
        throw RangeError.index(
          consultationIndex,
          businessConsultations,
          'consultationIndex',
        );
      }
      await answerBusinessConsultationById(
        role: role,
        consultationId: businessConsultations[consultationIndex].id,
        answer: answer,
      );
      return;
    }
    final facts = dashboardFor(role).facts;
    facts['consultation.$consultationIndex.answered'] = 'true';
    facts['consultation.$consultationIndex.answer'] = answer;
    facts['consultation.$consultationIndex.answeredAt'] = DateTime.now()
        .toIso8601String();
    _schedulePersist();
    notifyListeners();
  }

  Future<void> answerBusinessConsultationById({
    required UserRole role,
    required String consultationId,
    required String answer,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    final requestKey = _businessRpcRequestKey('reply_consultation', {
      'consultationId': consultationId,
      'answer': answer.trim(),
    });
    final requestId = _consultationReplyRequestIds.putIfAbsent(
      requestKey,
      _newUuidV4,
    );
    await _runBusinessMutation<void>(
      _consultationReplyMutationKey(consultationId),
      (accountEpoch) async {
        await repository.replyConsultation(
          ReplyConsultationInput(
            requestId: requestId,
            consultationId: consultationId,
            message: answer,
          ),
        );
        if (!_isCurrentAccount(accountEpoch)) return;
        await _refreshBusinessData(
          repository,
          expectedAccountEpoch: accountEpoch,
        );
        if (_isCurrentAccount(accountEpoch)) {
          _consultationReplyRequestIds.remove(requestKey);
        }
      },
    );
  }

  Future<BusinessConsultation> assignBusinessConsultation({
    required String consultationId,
    required String trainerId,
  }) {
    final repository = businessRepository;
    final profile = businessWorkspace?.profile;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    if (role != UserRole.gym ||
        profile is! GymBusinessProfile ||
        profile.status != BusinessProfileStatus.verified) {
      throw StateError('인증된 센터 계정만 상담을 배정할 수 있습니다.');
    }
    final consultation = businessConsultations
        .where((item) => item.id == consultationId)
        .firstOrNull;
    if (consultation == null || consultation.gymId != profile.id) {
      throw StateError('이 센터에 접수된 상담만 배정할 수 있습니다.');
    }
    final trainer = businessTrainers
        .where(
          (item) =>
              item.gymId == profile.id &&
              item.trainerId == trainerId &&
              item.status == 'active',
        )
        .firstOrNull;
    if (trainer == null) {
      throw StateError('현재 센터에서 활동 중인 트레이너를 선택해주세요.');
    }
    final requestKey = '$consultationId|$trainerId';
    final requestId = _consultationAssignRequestIds.putIfAbsent(
      requestKey,
      _newUuidV4,
    );
    return _runBusinessMutation<BusinessConsultation>(
      _consultationAssignMutationKey(consultationId),
      (accountEpoch) async {
        final assigned = await repository.assignConsultation(
          AssignConsultationInput(
            requestId: requestId,
            consultationId: consultationId,
            gymId: profile.id,
            trainerId: trainerId,
          ),
        );
        if (assigned.id != consultationId ||
            assigned.gymId != profile.id ||
            assigned.assignedTrainerId != trainerId) {
          throw StateError('요청한 상담과 다른 배정 결과가 반환되었습니다.');
        }
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
          if (_isCurrentAccount(accountEpoch)) {
            _consultationAssignRequestIds.remove(requestKey);
          }
        }
        return assigned;
      },
    );
  }

  bool isAdminUserBlocked(String email, {bool fallback = false}) {
    final value = dashboardFor(
      UserRole.admin,
    ).facts['adminUser.$email.blocked'];
    return value == null ? fallback : value == 'true';
  }

  void setAdminUserBlocked({
    required String email,
    required bool blocked,
    required String reason,
  }) {
    final facts = dashboardFor(UserRole.admin).facts;
    facts['adminUser.$email.blocked'] = '$blocked';
    facts['adminUser.$email.reason'] = reason;
    facts['adminUser.$email.updatedAt'] = DateTime.now().toIso8601String();
    facts['audit.latest'] = blocked ? '$email 계정 이용 제한' : '$email 계정 제한 해제';
    _schedulePersist();
    notifyListeners();
  }

  String adminReviewStatus(String reviewId) {
    return dashboardFor(UserRole.admin).facts['adminReview.$reviewId.status'] ??
        'pending';
  }

  Future<void> completeAdminReview({
    required String reviewId,
    required String applicantName,
    required String status,
    String reason = '',
  }) async {
    final repository = businessRepository;
    if (repository != null) {
      final application = businessApplications
          .where((item) => item.id == reviewId)
          .firstOrNull;
      if (application == null) {
        throw StateError('심사 신청서를 찾을 수 없습니다.');
      }
      await _runBusinessMutation<void>(
        _applicationReviewMutationKey(application.id),
        (accountEpoch) async {
          await repository.reviewApplication(
            ReviewBusinessApplicationInput(
              kind: application.kind,
              applicationId: application.id,
              approve: status == 'approved',
              rejectReason: reason.isEmpty ? null : reason,
            ),
          );
          if (!_isCurrentAccount(accountEpoch)) return;
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        },
      );
      return;
    }
    final facts = dashboardFor(UserRole.admin).facts;
    facts['adminReview.$reviewId.status'] = status;
    facts['adminReview.$reviewId.reason'] = reason;
    facts['adminReview.$reviewId.updatedAt'] = DateTime.now().toIso8601String();
    facts['audit.latest'] = status == 'approved'
        ? '$applicantName 인증 승인'
        : '$applicantName 인증 반려';
    _schedulePersist();
    notifyListeners();
  }

  Future<BusinessApplication> submitTrainerBusinessApplication({
    required String displayName,
    required String credentialNumber,
    required List<TrainerApplicationDocumentInput> documents,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    return _runBusinessMutation<BusinessApplication>(
      _trainerApplicationMutationKey,
      (accountEpoch) async {
        final application = await repository.submitTrainerApplication(
          TrainerApplicationInput(
            displayName: displayName,
            credentialNumber: credentialNumber,
            documents: documents,
          ),
        );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        }
        return application;
      },
    );
  }

  Future<BusinessApplication> submitGymBusinessApplication({
    required String gymName,
    required String businessNumber,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    return _runBusinessMutation<BusinessApplication>(
      _gymApplicationMutationKey,
      (accountEpoch) async {
        final application = await repository.submitGymApplication(
          GymApplicationInput(
            gymName: gymName,
            ownerName: Auth.instance.currentDisplayName,
            businessNumber: businessNumber,
          ),
        );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        }
        return application;
      },
    );
  }

  Future<OwnedCoachingRoutine> createBusinessRoutine({
    required UserRole ownerRole,
    required String title,
    required String description,
    required List<ExerciseTemplate> routineExercises,
    required int setCount,
    required int targetReps,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    if (setCount < 1 || setCount > 10) {
      throw ArgumentError.value(setCount, 'setCount', '1~10이어야 합니다.');
    }
    if (targetReps < 1 || targetReps > 100) {
      throw ArgumentError.value(targetReps, 'targetReps', '1~100이어야 합니다.');
    }
    if (routineExercises.isEmpty) {
      throw ArgumentError.value(
        routineExercises,
        'routineExercises',
        '운동을 한 개 이상 선택해야 합니다.',
      );
    }
    final exerciseInputs = routineExercises
        .map(
          (exercise) => CreateOwnedRoutineExerciseInput(
            baseExerciseId: exercise.databaseReferenceId,
            name: exercise.name,
            targetMuscle: exercise.muscle,
            sets: List.generate(
              setCount,
              (index) => CreateOwnedRoutineSetInput(
                setNumber: index + 1,
                targetReps: targetReps,
                restSeconds: restDefaultSeconds,
              ),
              growable: false,
            ),
          ),
        )
        .toList(growable: false);
    final requestKey = _businessRpcRequestKey(
      'save_coaching_routine',
      _ownedRoutineRequestPayload(
        ownerRole: ownerRole,
        title: title,
        intro: description,
        difficulty: BusinessRoutineDifficulty.intermediate,
        exercises: exerciseInputs,
      ),
    );
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<OwnedCoachingRoutine>(
      '${_businessRoutineMutationKey(ownerRole, title)}:$requestId',
      (accountEpoch) async {
        final record = await repository.createOwnedRoutine(
          CreateOwnedRoutineInput(
            ownerRole: ownerRole,
            title: title,
            intro: description,
            difficulty: BusinessRoutineDifficulty.intermediate,
            exercises: exerciseInputs,
            requestId: requestId,
          ),
        );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        }
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return record;
      },
    );
  }

  Future<OwnedCoachingRoutine> saveBusinessRoutineDraft({
    required UserRole ownerRole,
    required String title,
    required String description,
    required BusinessRoutineDifficulty difficulty,
    required List<CreateOwnedRoutineExerciseInput> routineExercises,
    OwnedCoachingRoutine? existing,
    double? price,
  }) async {
    final repository = businessRepository;
    if (repository == null) {
      throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    }
    if (routineExercises.isEmpty) {
      throw ArgumentError.value(
        routineExercises,
        'routineExercises',
        '운동을 한 개 이상 선택해야 합니다.',
      );
    }
    final mutationId = existing?.id ?? title.trim();
    final requestKey = _businessRpcRequestKey(
      'save_coaching_routine',
      _ownedRoutineRequestPayload(
        routineId: existing?.id,
        ownerRole: ownerRole,
        title: title,
        intro: description,
        price: price,
        difficulty: difficulty,
        exercises: routineExercises,
      ),
    );
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<OwnedCoachingRoutine>(
      'routine:save:$mutationId:$requestId',
      (accountEpoch) async {
        final record = existing == null
            ? await repository.createOwnedRoutine(
                CreateOwnedRoutineInput(
                  ownerRole: ownerRole,
                  title: title,
                  intro: description,
                  price: price,
                  difficulty: difficulty,
                  exercises: routineExercises,
                  requestId: requestId,
                ),
              )
            : await repository.updateOwnedRoutine(
                UpdateOwnedRoutineInput(
                  routineId: existing.id,
                  ownerRole: ownerRole,
                  title: title,
                  intro: description,
                  price: price,
                  difficulty: difficulty,
                  exercises: routineExercises,
                  requestId: requestId,
                ),
              );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        }
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return record;
      },
    );
  }

  Future<OwnedCoachingRoutine> submitBusinessRoutineForReview(
    String routineId,
  ) async {
    final repository = businessRepository;
    if (repository == null) throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    final normalizedRoutineId = routineId.trim();
    final requestKey = _businessRpcRequestKey(
      'submit_coaching_routine_review',
      {'routineId': normalizedRoutineId},
    );
    return _runBusinessMutation<OwnedCoachingRoutine>(
      'routine:submit:$routineId',
      (accountEpoch) async {
        final requestId = _stableBusinessRpcRequestId(requestKey);
        final record = await repository.submitOwnedRoutineForReview(
          normalizedRoutineId,
          requestId: requestId,
        );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        }
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return record;
      },
    );
  }

  Future<OwnedCoachingRoutine> reviewBusinessRoutine({
    required String routineId,
    required bool approve,
    String? rejectReason,
    RoutineAccessTier accessTier = RoutineAccessTier.free,
  }) async {
    final repository = businessRepository;
    if (repository == null) throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    final normalizedRoutineId = routineId.trim();
    final normalizedReason = approve
        ? null
        : _normalizedBusinessRequestText(rejectReason);
    final requestKey = _businessRpcRequestKey('review_coaching_routine', {
      'routineId': normalizedRoutineId,
      'decision': approve ? 'approve' : 'reject',
      'reason': normalizedReason,
      'accessTier': accessTier.name,
    });
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<OwnedCoachingRoutine>(
      'routine:review:$routineId:$requestId',
      (accountEpoch) async {
        final record = await repository.reviewOwnedRoutine(
          ReviewOwnedRoutineInput(
            routineId: normalizedRoutineId,
            approve: approve,
            rejectReason: normalizedReason,
            accessTier: accessTier,
            requestId: requestId,
          ),
        );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
          await _refreshPublishedRoutineCatalog(accountEpoch);
        }
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return record;
      },
    );
  }

  Future<List<RoutineShareRecord>> shareBusinessRoutine({
    required String routineId,
    required List<String> memberIds,
    String? message,
    DateTime? expiresAt,
  }) async {
    final repository = businessRepository;
    if (repository == null) throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    final normalizedRoutineId = routineId.trim();
    final normalizedMemberIds =
        memberIds
            .map((memberId) => memberId.trim())
            .where((memberId) => memberId.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final normalizedMessage = _normalizedBusinessRequestText(message);
    final normalizedExpiresAt = expiresAt?.toUtc();
    final requestKey = _businessRpcRequestKey('share_coaching_routine', {
      'routineId': normalizedRoutineId,
      'memberIds': normalizedMemberIds,
      'message': normalizedMessage,
      'expiresAt': normalizedExpiresAt?.toIso8601String(),
    });
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<List<RoutineShareRecord>>(
      'routine:share:$routineId:$requestId',
      (accountEpoch) async {
        final records = await repository.shareOwnedRoutine(
          ShareOwnedRoutineInput(
            routineId: normalizedRoutineId,
            memberIds: normalizedMemberIds,
            message: normalizedMessage,
            expiresAt: normalizedExpiresAt,
            requestId: requestId,
          ),
        );
        if (_isCurrentAccount(accountEpoch)) {
          await _refreshBusinessData(
            repository,
            expectedAccountEpoch: accountEpoch,
          );
        }
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return records;
      },
    );
  }

  Future<RoutineShareRecord> revokeBusinessRoutineShare(String shareId) {
    final repository = businessRepository;
    final revocationRepository = repository is RoutineShareRevocationRepository
        ? repository as RoutineShareRevocationRepository
        : null;
    if (revocationRepository == null) {
      throw StateError('루틴 공유 취소 서버가 연결되지 않았습니다.');
    }
    final normalizedShareId = shareId.trim();
    final current = outgoingRoutineShares
        .where((share) => share.id == normalizedShareId)
        .firstOrNull;
    if (current == null ||
        current.kind != RoutineShareKind.direct ||
        current.status != RoutineShareStatus.pending) {
      throw StateError('수락 대기 중인 회원 공유만 취소할 수 있습니다.');
    }
    final requestKey = _businessRpcRequestKey('revoke_routine_share', {
      'shareId': normalizedShareId,
    });
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<RoutineShareRecord>(
      'routine:share-revoke:$normalizedShareId',
      (accountEpoch) async {
        final revoked = await revocationRepository.revokeRoutineShare(
          normalizedShareId,
          requestId: requestId,
        );
        if (revoked.id != normalizedShareId ||
            revoked.status != RoutineShareStatus.revoked) {
          throw StateError('서버가 다른 루틴 공유 상태를 반환했습니다.');
        }
        if (_isCurrentAccount(accountEpoch)) {
          outgoingRoutineShares = List.unmodifiable(
            outgoingRoutineShares
                .map((share) => share.id == revoked.id ? revoked : share)
                .toList(growable: false),
          );
          notifyListeners();
          try {
            await _refreshBusinessData(
              businessRepository!,
              expectedAccountEpoch: accountEpoch,
            );
          } catch (error) {
            // The revoke already committed. Keep the verified returned state
            // and surface only the follow-up refresh problem.
            if (_isCurrentAccount(accountEpoch)) businessError = error;
          }
        }
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return revoked;
      },
    );
  }

  Future<RoutineShareLink> createBusinessRoutineShareLink(
    String routineId, {
    DateTime? expiresAt,
    bool confirmCreateNewAfterUncertainResult = false,
  }) async {
    final repository = businessRepository;
    if (repository == null) throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    final normalizedRoutineId = routineId.trim();
    if (_uncertainRoutineShareLinkRoutineIds.contains(normalizedRoutineId)) {
      if (!confirmCreateNewAfterUncertainResult) {
        throw const RoutineShareLinkResultUncertainException();
      }
      _uncertainRoutineShareLinkRoutineIds.remove(normalizedRoutineId);
    }
    final normalizedExpiresAt = expiresAt?.toUtc();
    final requestKey = _businessRpcRequestKey('create_routine_share_link', {
      'routineId': normalizedRoutineId,
      'expiresAt': normalizedExpiresAt?.toIso8601String(),
    });
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<RoutineShareLink>(
      'routine:link:$routineId:$requestId',
      (accountEpoch) async {
        late final RoutineShareLink link;
        try {
          link = await repository.createRoutineShareLink(
            normalizedRoutineId,
            expiresAt: normalizedExpiresAt,
            requestId: requestId,
          );
        } on RoutineShareLinkResultUncertainException {
          if (_isCurrentAccount(accountEpoch)) {
            // The server deliberately never stores a raw bearer token. Reusing
            // this request ID could only create another unrecoverable link.
            _stableBusinessRpcRequestIds.remove(requestKey);
            _uncertainRoutineShareLinkRoutineIds.add(normalizedRoutineId);
          }
          rethrow;
        }

        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        if (_isCurrentAccount(accountEpoch)) {
          _uncertainRoutineShareLinkRoutineIds.remove(normalizedRoutineId);
        }
        if (_isCurrentAccount(accountEpoch)) {
          try {
            await _refreshBusinessData(
              repository,
              expectedAccountEpoch: accountEpoch,
            );
          } catch (error) {
            if (_isCurrentAccount(accountEpoch)) businessError = error;
          }
        }
        return link;
      },
    );
  }

  Future<PersonalRoutineRecord?> respondToRoutineShare(
    String shareId, {
    required bool accept,
    DateTime? applyDate,
  }) async {
    final repository = businessRepository;
    if (repository == null) throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    final normalizedShareId = shareId.trim();
    final requestKey = _businessRpcRequestKey('respond_routine_share', {
      'shareId': normalizedShareId,
      'decision': accept ? 'accept' : 'decline',
    });
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<PersonalRoutineRecord?>(
      'routine:respond:$shareId:$requestId',
      (accountEpoch) async {
        final record = await repository.respondRoutineShare(
          normalizedShareId,
          accept: accept,
          requestId: requestId,
        );
        if (accept && record == null) {
          throw StateError('루틴 공유가 만료되었거나 더 이상 수락할 수 없습니다.');
        }
        if (!_isCurrentAccount(accountEpoch)) return record;
        if (record != null) {
          final routine = _routineFromPersonalRecord(record);
          final index = routines.indexWhere((item) => item.id == routine.id);
          if (index < 0) {
            routines.add(routine);
          } else {
            routines[index] = routine;
          }
          if (applyDate != null) applyRoutine(routine, applyDate);
          _schedulePersist();
        }
        await _refreshBusinessData(
          repository,
          expectedAccountEpoch: accountEpoch,
        );
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return record;
      },
    );
  }

  Future<PersonalRoutineRecord> acceptRoutineShareToken(
    String token, {
    DateTime? applyDate,
  }) async {
    final repository = businessRepository;
    if (repository == null) throw StateError('실데이터 저장소가 연결되지 않았습니다.');
    final normalized = _routineShareTokenFromInput(token);
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', '비어 있습니다.');
    }
    final requestKey = _businessRpcRequestKey('accept_routine_share_token', {
      'token': normalized,
    });
    final requestId = _stableBusinessRpcRequestId(requestKey);
    return _runBusinessMutation<PersonalRoutineRecord>(
      'routine:token:$requestId',
      (accountEpoch) async {
        final record = await repository.acceptRoutineShareToken(
          normalized,
          requestId: requestId,
        );
        if (!_isCurrentAccount(accountEpoch)) return record;
        final routine = _routineFromPersonalRecord(record);
        final index = routines.indexWhere((item) => item.id == routine.id);
        if (index < 0) {
          routines.add(routine);
        } else {
          routines[index] = routine;
        }
        if (applyDate != null) applyRoutine(routine, applyDate);
        pendingRoutineShareToken = null;
        _schedulePersist();
        await _refreshBusinessData(
          repository,
          expectedAccountEpoch: accountEpoch,
        );
        _completeBusinessRpcRequest(
          requestKey,
          expectedAccountEpoch: accountEpoch,
        );
        return record;
      },
    );
  }

  static String _routineShareTokenFromInput(String input) {
    final normalized = input.trim();
    final uri = Uri.tryParse(normalized);
    if (uri != null &&
        uri.scheme == 'com.teampara.setflow' &&
        uri.host == 'routine-share' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first.trim();
    }
    return normalized;
  }

  Future<void> _refreshPublishedRoutineCatalog(int accountEpoch) async {
    final repository = routineCatalogRepository;
    if (repository == null) return;
    final catalog = await repository.listPublished();
    if (!_isCurrentAccount(accountEpoch)) return;
    _marketRoutines
      ..clear()
      ..addAll(catalog.map(_routineFromCatalog));
    final cachedError = _cachedReadError(repository);
    if (cachedError != null) cloudSyncError = cachedError;
    notifyListeners();
  }

  Future<void> clearPersistedData() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    _serverSyncTimer?.cancel();
    _serverSyncTimer = null;
    _queuedSnapshot = null;
    final inFlight = _persistInFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Clearing is an explicit user action and supersedes a failed save.
      }
    }
    await _repository.clear();
  }

  void retryPersistence() {
    if (!_initialized) return;
    _queuedSnapshot = _snapshotForPersistence();
    _schedulePersistTimer();
  }

  bool get hasPendingPersistenceSync =>
      _repository is DeferredSyncAppRepository &&
      (_repository as DeferredSyncAppRepository).hasPendingSave;

  Object? get _repositorySyncError => _repository is DeferredSyncAppRepository
      ? (_repository as DeferredSyncAppRepository).lastSyncError
      : null;

  /// Flushes the newest snapshot to device storage, then asks the deferred
  /// repository to synchronize its durable outbox with Supabase.
  Future<void> syncPersistenceToServer() async {
    await flushPersistence();
    final repository = _repository;
    if (repository is! DeferredSyncAppRepository) return;
    final syncRepository = repository as DeferredSyncAppRepository;
    try {
      await syncRepository.syncPending();
      persistenceSyncError = null;
    } catch (error) {
      persistenceSyncError = error;
      if (!_disposed) notifyListeners();
      rethrow;
    }
    if (!_disposed) notifyListeners();
  }

  /// 탈퇴는 서버가 있어야 성립한다 — 게스트에게는 지울 계정이 없다.
  bool get supportsAccountDeletion => _repository is AccountDeletion;

  /// 지금 걸려 있는 탈퇴 요청. 유예 중이면 화면이 남은 날짜와 취소를 보여준다.
  AccountDeletionRequest? pendingAccountDeletion;

  Future<AccountDeletionRequest?> refreshPendingAccountDeletion() async {
    final repository = _repository;
    if (repository is! AccountDeletion) return null;
    pendingAccountDeletion = await (repository as AccountDeletion)
        .pendingAccountDeletion();
    if (!_disposed) notifyListeners();
    return pendingAccountDeletion;
  }

  Future<AccountDeletionRequest> requestAccountDeletion({
    String? reason,
  }) async {
    final repository = _repository;
    if (repository is! AccountDeletion) {
      throw StateError('이 계정에는 탈퇴할 서버 기록이 없습니다.');
    }
    final request = await (repository as AccountDeletion)
        .requestAccountDeletion(reason: reason);
    pendingAccountDeletion = request;
    if (!_disposed) notifyListeners();
    return request;
  }

  Future<bool> cancelAccountDeletion() async {
    final repository = _repository;
    if (repository is! AccountDeletion) return false;
    final cancelled = await (repository as AccountDeletion)
        .cancelAccountDeletion();
    if (cancelled) pendingAccountDeletion = null;
    if (!_disposed) notifyListeners();
    return cancelled;
  }

  bool get _repositoryHasPendingSave =>
      _repository is PendingSaveAwareRepository &&
      (_repository as PendingSaveAwareRepository).hasPendingSave;

  void _schedulePersist() {
    if (!_initialized) return;
    _queuedSnapshot = _snapshotForPersistence();
    _schedulePersistTimer();
  }

  void _schedulePersistTimer() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(
        flushPersistence()
            .then((_) => _scheduleServerSync())
            .catchError((_) {}),
      );
    });
  }

  /// 로컬 저장이 끝나는 즉시 서버 업로드를 예약한다. 예전엔 5분 주기 타이머와
  /// 앱 백그라운드 전환만 업로드를 트리거해서, 방금 기록한 세트가 최대 5분간
  /// "서버 동기화 대기 중"으로 남았다 — 사용자에겐 서버가 죽은 것으로 보인다.
  /// 1초 디바운스는 세트 연속 기록을 업로드 한 번으로 접는다. 실패해도 여기서
  /// 재시도하지 않는다: 아웃박스는 이미 내구적이고, 다음 기록·5분 주기·
  /// 라이프사이클 경로가 재시도를 맡는다.
  void _scheduleServerSync() {
    if (!hasPendingPersistenceSync) return;
    _serverSyncTimer?.cancel();
    _serverSyncTimer = Timer(const Duration(seconds: 1), () {
      unawaited(syncPersistenceToServer().catchError((_) {}));
    });
  }

  /// Persists every snapshot already queued at the time this future settles.
  /// Saves are serialized and, for Supabase accounts, complete after the
  /// account-scoped Hive cache/outbox is durable. Network sync is independent.
  Future<void> flushPersistence() {
    _persistTimer?.cancel();
    _persistTimer = null;

    final active = _persistInFlight;
    if (active != null) {
      return active.then((_) {
        if (_queuedSnapshot != null) return flushPersistence();
      });
    }

    final snapshot = _queuedSnapshot;
    if (snapshot == null) return Future<void>.value();
    _queuedSnapshot = null;

    late final Future<void> operation;
    operation = _repository
        .save(snapshot)
        .then((_) {
          persistenceError = null;
        })
        .catchError((Object error) {
          persistenceError = error;
          // Preserve the failed payload unless a newer mutation is already queued.
          _queuedSnapshot ??= snapshot;
          if (!_disposed) notifyListeners();
          throw error;
        })
        .whenComplete(() {
          if (identical(_persistInFlight, operation)) _persistInFlight = null;
        });
    _persistInFlight = operation;
    return operation.then((_) {
      if (_queuedSnapshot != null) return flushPersistence();
    });
  }

  AppSnapshot _snapshotForPersistence() => AppSnapshot(
    role: role,
    isDarkMode: isDarkMode,
    weightUnit: weightUnit,
    restDefaultSeconds: restDefaultSeconds,
    defaultSetCount: defaultSetCount,
    defaultRepCount: defaultRepCount,
    activeTrainingPartyId: activeTrainingPartyId,
    nickname: memberNickname.trim().isEmpty ? null : memberNickname.trim(),
    useRir: useRir,
    autoStartRestTimer: autoStartRestTimer,
    autoRecommendNextExercise: autoRecommendNextExercise,
    restTimerNotifications: restTimerNotifications,
    timerVibration: timerVibration,
    timerSound: timerSound,
    timerCountdownSeconds: timerCountdownSeconds,
    oneRepMaxFormula: oneRepMaxFormula,
    pushCoachingFeedback: pushCoachingFeedback,
    communityReactionNotifications: communityReactionNotifications,
    pushTogether: pushTogether,
    pushWorkoutReminder: pushWorkoutReminder,
    workoutReminderHour: workoutReminderHour,
    businessNotifications: Map<String, bool>.unmodifiable(
      businessNotifications,
    ),
    sessions: Map<DateTime, WorkoutSession>.unmodifiable(sessions),
    routines: List<RoutineData>.unmodifiable(routines),
    goals: List<String>.unmodifiable(goals),
    heightCm: heightCm,
    weight: weight,
    age: age,
    gender: gender,
    precisionRecommendationPrompted: precisionRecommendationPrompted,
    hasSwipedSet: hasSwipedSet,
    hasSeenTogetherGuide: hasSeenTogetherGuide,
    recommendationProfile: recommendationProfile,
    communityPosts: communityRepository == null
        ? List<CommunityPost>.unmodifiable(communityPosts)
        : const [],
    consultations: businessRepository == null
        ? List<ConsultationData>.unmodifiable(consultations)
        : const [],
    businessDashboards: businessRepository == null
        ? Map<UserRole, BusinessDashboardData>.unmodifiable(businessDashboards)
        : const {},
    customExercises: List<ExerciseTemplate>.unmodifiable(customExercises),
  );

  /// 휴식을 새로 시작한다. [focus]는 "무엇을 하다 쉬는지" — 세트 완료가 아닌
  /// 시작(함께 방의 공유 휴식)은 비워서 지난 세트 얘기가 바에 남지 않게 한다.
  /// 이미 가는 휴식을 늘리는 건 [extendRestTimer]다.
  void startRestTimer(int seconds, {RestFocus? focus}) {
    restFocus = focus;
    _runRestTimer(seconds);
  }

  /// 가던 휴식에 [seconds]초를 더한다. 어디쯤인지는 그대로다.
  void extendRestTimer([int seconds = 30]) {
    _runRestTimer(restRemaining + seconds);
  }

  void _runRestTimer(int seconds) {
    _restTimer?.cancel();
    final safeSeconds = seconds.clamp(1, 3600);
    _restTimerEndsAt = DateTime.now().add(Duration(seconds: safeSeconds));
    restRemaining = safeSeconds;
    unawaited(
      RestTimerPlatform.start(
        seconds: safeSeconds,
        showCompletionNotification: restTimerNotifications,
        vibrate: timerVibration,
        sound: timerSound,
        countdownSeconds: timerCountdownSeconds,
        detail: restTimerDetail,
      ),
    );
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _refreshRestRemaining();
      notifyListeners();
    });
    notifyListeners();
  }

  /// 알림 창에 적을 "지금 어디쯤인지". 휴식 바([GlobalRestTimerOverlay])가
  /// 답하는 것과 같은 질문이다. 방금 마친 세트를 모르면 null이고 네이티브가
  /// 기본 문구를 쓴다.
  String? get restTimerDetail {
    final focus = restFocus;
    if (focus == null) return null;
    if (focus.setsLeft > 0) {
      return '${focus.exerciseName} · 남은 세트 ${focus.setsLeft}';
    }
    final next = focus.nextExercise;
    return next == null ? '${focus.exerciseName} 끝 · 마지막 종목이에요' : '다음: $next';
  }

  void _refreshRestRemaining() {
    final endsAt = _restTimerEndsAt;
    if (endsAt == null) {
      restRemaining = 0;
      _restTimer?.cancel();
      return;
    }
    final milliseconds = endsAt.difference(DateTime.now()).inMilliseconds;
    if (milliseconds <= 0) {
      restRemaining = 0;
      _restTimerEndsAt = null;
      _restTimer?.cancel();
      return;
    }
    restRemaining = (milliseconds / 1000).ceil();
  }

  Future<void> syncRestTimerFromPlatform() async {
    // 앱을 보고 있다면 "휴식이 끝났어요" 알림은 할 일을 마쳤다. 안 걷으면
    // 탭할 때까지 알림창에 남아 런처 배지를 붙들고 있는다.
    unawaited(RestTimerPlatform.clearCompletionNotification());
    final status = await RestTimerPlatform.status();
    if (_disposed || status == null) return;
    _restTimer?.cancel();
    if (status.remainingSeconds <= 0) {
      restRemaining = 0;
      _restTimerEndsAt = null;
      notifyListeners();
      return;
    }
    _restTimerEndsAt = status.endsAtMillis == null
        ? DateTime.now().add(Duration(seconds: status.remainingSeconds))
        : DateTime.fromMillisecondsSinceEpoch(status.endsAtMillis!);
    _refreshRestRemaining();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshRestRemaining();
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelRestTimer() {
    _restTimer?.cancel();
    _restTimerEndsAt = null;
    restRemaining = 0;
    unawaited(RestTimerPlatform.cancel());
    notifyListeners();
  }

  void _applySnapshot(AppSnapshot snapshot) {
    role = businessRepository == null ? snapshot.role : UserRole.guest;
    isDarkMode = snapshot.isDarkMode;
    weightUnit = snapshot.weightUnit;
    restDefaultSeconds = snapshot.restDefaultSeconds;
    defaultSetCount = snapshot.defaultSetCount;
    defaultRepCount = snapshot.defaultRepCount;
    activeTrainingPartyId = snapshot.activeTrainingPartyId;
    memberNickname = snapshot.nickname?.trim() ?? '';
    useRir = snapshot.useRir;
    autoStartRestTimer = snapshot.autoStartRestTimer;
    autoRecommendNextExercise = snapshot.autoRecommendNextExercise;
    restTimerNotifications = snapshot.restTimerNotifications;
    timerVibration = snapshot.timerVibration;
    timerSound = snapshot.timerSound;
    timerCountdownSeconds = snapshot.timerCountdownSeconds.clamp(0, 120);
    oneRepMaxFormula = snapshot.oneRepMaxFormula;
    pushCoachingFeedback = snapshot.pushCoachingFeedback;
    communityReactionNotifications = snapshot.communityReactionNotifications;
    pushTogether = snapshot.pushTogether;
    pushWorkoutReminder = snapshot.pushWorkoutReminder;
    workoutReminderHour = snapshot.workoutReminderHour.clamp(
      AppSnapshot.earliestReminderHour,
      AppSnapshot.latestReminderHour,
    );
    businessNotifications = Map.of(snapshot.businessNotifications);
    goals = List.of(snapshot.goals);
    heightCm = snapshot.heightCm;
    weight = snapshot.weight;
    age = snapshot.age;
    gender = snapshot.gender;
    precisionRecommendationPrompted =
        snapshot.precisionRecommendationPrompted ||
        snapshot.recommendationProfile != null;
    hasSwipedSet = snapshot.hasSwipedSet;
    hasSeenTogetherGuide = snapshot.hasSeenTogetherGuide;
    recommendationProfile = snapshot.recommendationProfile;
    customExercises
      ..clear()
      ..addAll(snapshot.customExercises);
    _rebuildSelectableExercises();
    sessions.clear();
    for (final entry in snapshot.sessions.entries) {
      final userExercises = entry.value.exercises
          .where((exercise) => !exercise.id.startsWith('seed_'))
          .toList();
      if (userExercises.isEmpty) continue;
      sessions[entry.key] = WorkoutSession(
        date: entry.value.date,
        exercises: userExercises,
      );
    }
    routines
      ..clear()
      ..addAll(snapshot.routines);
    if (communityRepository == null && snapshot.communityPosts.isNotEmpty) {
      communityPosts
        ..clear()
        ..addAll(snapshot.communityPosts);
    }
    if (businessRepository == null && snapshot.consultations.isNotEmpty) {
      consultations
        ..clear()
        ..addAll(snapshot.consultations);
    }
    if (businessRepository == null && snapshot.businessDashboards.isNotEmpty) {
      businessDashboards.addAll(snapshot.businessDashboards);
    }
  }

  void _resetForSignedOutUser() {
    _verifiedAdmin = false;
    hasPaidPlan = false;
    cloudSyncError = null;
    persistenceSyncError = null;
    role = UserRole.guest;
    isDarkMode = false;
    weightUnit = 'kg';
    restDefaultSeconds = 90;
    defaultSetCount = null;
    defaultRepCount = null;
    activeTrainingPartyId = null;
    memberNickname = '';
    useRir = false;
    autoStartRestTimer = true;
    autoRecommendNextExercise = true;
    restTimerNotifications = true;
    timerVibration = true;
    timerSound = true;
    timerCountdownSeconds = 30;
    oneRepMaxFormula = OneRepMaxFormula.average;
    pushCoachingFeedback = true;
    communityReactionNotifications = false;
    pushTogether = true;
    pushWorkoutReminder = false;
    workoutReminderHour = 19;
    businessNotifications = {};
    goals = [];
    heightCm = null;
    weight = null;
    age = null;
    gender = null;
    precisionRecommendationPrompted = false;
    hasSwipedSet = false;
    hasSeenTogetherGuide = false;
    recommendationProfile = null;
    customExercises.clear();
    _rebuildSelectableExercises();
    sessions.clear();
    routines.clear();
    communityPosts.clear();
    consultations.clear();
    businessDashboards.clear();
    notifications = const [];
    unreadNotificationCount = 0;
    notificationsLoading = false;
    notificationsError = null;
    _seedStarterRoutines();
    if (communityRepository == null) {
      _seedSocial();
    }
    businessAccess = null;
    businessWorkspace = null;
    publicTrainers = const [];
    topCoachingTrainers = const [];
    memberConsultations = const [];
    memberConsultationsLoading = false;
    memberConsultationsError = null;
    _memberSharingPreferences = null;
    memberSessionFeedbacks = const [];
    memberMemberships = const [];
    serviceRegions = const [];
    workoutLocations = const [];
    incomingRoutineShares = const [];
    outgoingRoutineShares = const [];
    businessInvites = const [];
    coachingSchedules = const [];
    _memberDetailLoads.clear();
    _businessMemberDetails.clear();
    _businessMemberDetailErrors.clear();
    businessLoading = false;
    businessError = null;
    coachingSchedulesLoading = false;
    coachingSchedulesError = null;
    memberSessionFeedbackLoading = false;
    memberSessionFeedbackError = null;
    memberMembershipsError = null;
    workoutLocationsError = null;
    _memberFeedbackRequestSequence++;
    _memberConsultationRequestSequence++;
    _businessMutations.clear();
    _businessInviteAcceptRequestIds.clear();
    _coachingInviteAcceptRequestIds.clear();
    _sessionFeedbackRequestIds.clear();
    _membershipEndRequestIds.clear();
    _personalRoutineSaveRequestIds.clear();
    _personalRoutineDeleteRequestIds.clear();
    _coachingScheduleCreateRequestIds.clear();
    _coachingHealthConsentRequestIds.clear();
    _consultationAssignRequestIds.clear();
    _consultationCreateRequestIds.clear();
    _consultationReplyRequestIds.clear();
    _stableBusinessRpcRequestIds.clear();
    _businessInviteCreateExpiresAt.clear();
    _coachingInviteCreateExpiresAt.clear();
    _uncertainRoutineShareLinkRoutineIds.clear();
    _personalRoutineBaseExerciseIds.clear();
    if (businessRepository == null) {
      _seedBusinessDashboards();
      _seedDemoCoachingSchedules();
    } else {
      _resetLiveBusinessDashboards();
    }
  }

  void _seedMarketRoutines() {
    _marketRoutines.addAll([
      RoutineData(
        id: 'market_1',
        name: '초보자 4주 근력 스타트',
        description: '무리 없이 기초 근력을 만드는 주 3회 프로그램',
        color: const Color(0xFF10CEBD),
        exercises: [exercises[0], exercises[2], exercises[4]],
        author: '김코치 · 인증 트레이너',
        level: '초급',
      ),
      RoutineData(
        id: 'market_2',
        name: '등 라인 집중 루틴',
        description: '당기는 힘과 선명한 등 라인을 함께 만드는 루틴',
        color: const Color(0xFF71717A),
        exercises: [exercises[4], exercises[5], exercises[8]],
        author: '모션짐 · 사업자 인증',
        level: '중급',
        accessTier: RoutineAccessTier.paid,
      ),
      RoutineData(
        id: 'market_3',
        name: '퇴근 후 35분 전신',
        description: '짧은 시간 안에 전신 볼륨을 채우는 고효율 구성',
        color: const Color(0xFFFFB20C),
        exercises: [exercises[2], exercises[0], exercises[6]],
        author: '박트레이너 · 인증 트레이너',
        level: '중급',
      ),
    ]);
  }

  void _seedStarterRoutines() {
    final templates = exercises;
    routines.addAll([
      RoutineData(
        id: 'mine_1',
        name: '월요일 상체',
        description: '가슴과 등을 균형 있게 채우는 45분 루틴',
        color: const Color(0xFF10CEBD),
        exercises: [templates[0], templates[4], templates[6]],
      ),
      RoutineData(
        id: 'mine_2',
        name: '하체 집중',
        description: '스쿼트 중심의 하체 근력 루틴',
        color: const Color(0xFFFFB20C),
        exercises: [templates[2], templates[3]],
      ),
    ]);
  }

  void _seedSocial() {
    final now = DateTime.now();
    communityPosts.addAll([
      CommunityPost(
        id: 'post_1',
        author: '오운완 민지',
        content: '오늘 하체 루틴 100% 완료! 지난주보다 스쿼트 5kg 올렸어요.',
        metric: '하체 · 12세트 · 4.2t',
        createdAt: now.subtract(const Duration(minutes: 10)),
        visualKey: 'strength',
        color: const Color(0xFFFFB20C),
        likes: 24,
        comments: [
          PostComment(
            id: 'comment_1',
            author: '꾸준한 준호',
            content: '기록 갱신 축하해요. 다음 운동도 응원할게요!',
            createdAt: now.subtract(const Duration(minutes: 5)),
          ),
        ],
      ),
      CommunityPost(
        id: 'post_2',
        author: '꾸준한 준호',
        content: '30일 연속 운동 달성. 짧게라도 기록하니 습관이 되네요.',
        metric: '전신 · 8세트 · 2.8t',
        createdAt: now.subtract(const Duration(hours: 1)),
        visualKey: 'streak',
        color: const Color(0xFF10CEBD),
        likes: 128,
        isLiked: true,
      ),
      CommunityPost(
        id: 'post_3',
        author: '세트플로우 코치',
        content: '이번 주는 무게보다 정확한 가동범위에 집중해보세요.',
        metric: '코칭 팁',
        createdAt: now.subtract(const Duration(hours: 3)),
        visualKey: 'tip',
        color: const Color(0xFF3B82F6),
        likes: 56,
      ),
    ]);
    consultations.add(
      ConsultationData(
        id: 'consult_1',
        trainerName: '김코치',
        specialty: '초보자 근력 향상',
        goal: '주 3회 근력 운동을 꾸준히 진행하고 싶어요.',
        level: '헬스장 등록 1개월 차이며 기본 동작을 배우는 중입니다.',
        question: '무릎이 불편한 날에도 하체 운동을 안전하게 진행할 수 있을까요?',
        createdAt: now.subtract(const Duration(days: 1)),
        status: ConsultationStatus.answered,
        response:
            '가능합니다. 통증이 없는 범위에서 스쿼트 깊이와 중량을 낮추고, 둔근 중심 동작으로 구성해드릴게요. 운동 중 날카로운 통증이 있으면 즉시 중단해주세요.',
      ),
    );
  }

  void _seedBusinessDashboards() {
    final now = DateTime.now();
    businessDashboards.addAll({
      UserRole.trainer: BusinessDashboardData(
        role: UserRole.trainer,
        facts: {
          'displayName': '김코치',
          'revenue': '2,480,000원',
          'revenueChange': '지난달보다 12.4% 증가',
          'members': '12',
          'memberCapacity': '/ 50명',
          'feedbackPending': '3',
          'routineViews': '1,284',
          'routineViewsChange': '+18%',
          'consultationConversion': '8.6%',
          'consultationConversionChange': '+2.1%',
          'routineImports': '94회',
          'routineImportsChange': '+12회',
        },
        tasks: [
          BusinessTaskData(
            id: 'trainer_feedback_due',
            title: '72시간 피드백 마감 임박',
            subtitle: '박민지 회원 · 4시간 남음',
            action: '피드백',
            kind: 'urgent',
          ),
          BusinessTaskData(
            id: 'trainer_new_consultation',
            title: '새 상담이 도착했어요',
            subtitle: '근육 증가 상담 외 1건',
            action: '확인',
            kind: 'consultation',
          ),
        ],
        notifications: [
          BusinessNotificationData(
            id: 'trainer_consultation',
            title: '새 상담이 도착했어요',
            subtitle: '방금 전 · 상담 내용을 확인해주세요.',
            kind: 'consultation',
            createdAt: now.subtract(const Duration(minutes: 2)),
          ),
          BusinessNotificationData(
            id: 'trainer_feedback',
            title: '피드백 마감이 가까워요',
            subtitle: '12분 전 · 남은 시간 4시간',
            kind: 'timer',
            createdAt: now.subtract(const Duration(minutes: 12)),
          ),
          BusinessNotificationData(
            id: 'trainer_settlement',
            title: '정산 예정 금액이 확정됐어요',
            subtitle: '오늘 · 정산 내역에서 확인할 수 있어요.',
            kind: 'settlement',
            createdAt: now.subtract(const Duration(hours: 2)),
          ),
        ],
        lastSyncedAt: now,
      ),
      UserRole.gym: BusinessDashboardData(
        role: UserRole.gym,
        facts: {
          'displayName': '모션짐 강남점',
          'businessVerified': 'true',
          'businessNumber': '1234567890',
          'planId': 'enterprise',
          'plan': '엔터프라이즈 플랜',
          'location': '서울 강남구 테헤란로 123',
          'intro': '운동에 집중할 수 있는 코칭 중심 피트니스 센터입니다.',
          'members': '4',
          'revenue': '18.4',
          'trainers': '4',
          'consultations': '9',
          'trainer1Name': '김코치',
          'trainer1Detail': '회원 18명 · 피드백 98%',
          'trainer2Name': '박트레이너',
          'trainer2Detail': '회원 15명 · 피드백 94%',
          'trainer3Name': '이코치',
          'trainer3Detail': '회원 12명 · 피드백 78%',
        },
        tasks: [
          BusinessTaskData(
            id: 'gym_member_assignment',
            title: '신규 회원 배정이 필요해요',
            subtitle: '상담 완료 회원 3명',
            action: '배정',
            kind: 'member',
          ),
          BusinessTaskData(
            id: 'gym_feedback_rate',
            title: '피드백 이행률 확인',
            subtitle: '이행률 80% 미만 트레이너 1명',
            action: '보기',
            kind: 'warning',
          ),
        ],
        notifications: [
          BusinessNotificationData(
            id: 'gym_assignment',
            title: '회원 배정 대기 3건',
            subtitle: '방금 전 · 담당 트레이너를 지정해주세요.',
            kind: 'member',
            createdAt: now.subtract(const Duration(minutes: 3)),
          ),
          BusinessNotificationData(
            id: 'gym_feedback',
            title: '피드백 이행률을 확인해주세요',
            subtitle: '20분 전 · 기준 미달 트레이너 1명',
            kind: 'warning',
            createdAt: now.subtract(const Duration(minutes: 20)),
          ),
        ],
        lastSyncedAt: now,
      ),
      UserRole.admin: BusinessDashboardData(
        role: UserRole.admin,
        facts: {
          'users': '8,420',
          'coaching': '284',
          'reviews': '14',
          'reports': '6',
          'redSla': '82',
          'orangeSla': '94',
          'reviewSla': '97',
          'apiStatus': '정상',
          'ocrStatus': '정상',
          'settlementStatus': '대기 2건',
        },
        tasks: [
          BusinessTaskData(
            id: 'admin_urgent_reports',
            title: '긴급 신고 2건',
            subtitle: 'SLA 1시간 내 처리가 필요해요.',
            action: '처리',
            kind: 'urgent',
          ),
          BusinessTaskData(
            id: 'admin_business_reviews',
            title: '사업자 심사 대기 14건',
            subtitle: '트레이너 9건 · 센터 5건',
            action: '검토',
            kind: 'review',
          ),
        ],
        notifications: [
          BusinessNotificationData(
            id: 'admin_report',
            title: 'Red 신고가 접수됐어요',
            subtitle: '1분 전 · SLA 1시간 내 처리가 필요해요.',
            kind: 'urgent',
            createdAt: now.subtract(const Duration(minutes: 1)),
          ),
          BusinessNotificationData(
            id: 'admin_review',
            title: '사업자 심사 대기가 증가했어요',
            subtitle: '15분 전 · 현재 14건 대기 중',
            kind: 'review',
            createdAt: now.subtract(const Duration(minutes: 15)),
          ),
        ],
        lastSyncedAt: now,
      ),
    });
  }

  void _seedDemoCoachingSchedules() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    coachingSchedules = [
      BusinessCoachingSchedule(
        id: 'demo-schedule-1',
        trainerId: 'demo-trainer',
        memberUserId: 'demo-member-1',
        title: '운동 기록 피드백',
        date: today,
        startMinutes: 10 * 60,
        endMinutes: 10 * 60 + 50,
        trainerName: '김코치',
        memberName: '박민지',
        createdAt: now,
      ),
      BusinessCoachingSchedule(
        id: 'demo-schedule-2',
        trainerId: 'demo-trainer',
        memberUserId: 'demo-member-2',
        title: '4주차 상담',
        date: today,
        startMinutes: 13 * 60 + 30,
        endMinutes: 14 * 60 + 20,
        trainerName: '김코치',
        memberName: '이준호',
        createdAt: now,
      ),
      BusinessCoachingSchedule(
        id: 'demo-schedule-3',
        trainerId: 'demo-trainer',
        memberUserId: 'demo-member-3',
        title: '루틴 수정',
        date: today,
        startMinutes: 17 * 60,
        endMinutes: 17 * 60 + 50,
        trainerName: '김코치',
        memberName: '정민아',
        createdAt: now,
      ),
    ];
  }

  List<BusinessCoachingSchedule> _replaceCoachingSchedule(
    BusinessCoachingSchedule updated,
  ) => _sortedCoachingSchedules([
    ...coachingSchedules.where((item) => item.id != updated.id),
    updated,
  ]);

  BusinessCoachingSchedule _enrichCoachingScheduleNames(
    BusinessCoachingSchedule schedule,
  ) {
    final member = schedule.memberUserId == null
        ? null
        : businessMembers
              .where((item) => item.userId == schedule.memberUserId)
              .firstOrNull;
    final connection = schedule.memberUserId == null
        ? null
        : coachingConnections
              .where((item) => item.memberUserId == schedule.memberUserId)
              .firstOrNull;
    final profile = businessWorkspace?.profile;
    final trainerName = switch (profile) {
      TrainerBusinessProfile(:final id, :final displayName)
          when id == schedule.trainerId =>
        displayName,
      _ =>
        businessTrainers
            .where((item) => item.trainerId == schedule.trainerId)
            .map((item) => item.displayName)
            .whereType<String>()
            .firstOrNull,
    };
    final gymName = switch (profile) {
      GymBusinessProfile(:final id, :final name) when id == schedule.gymId =>
        name,
      _ => null,
    };
    return BusinessCoachingSchedule(
      id: schedule.id,
      trainerId: schedule.trainerId,
      memberUserId: schedule.memberUserId,
      gymId: schedule.gymId,
      title: schedule.title,
      date: schedule.date,
      startMinutes: schedule.startMinutes,
      endMinutes: schedule.endMinutes,
      trainerName: trainerName ?? schedule.trainerName,
      memberName: member?.name ?? connection?.memberName ?? schedule.memberName,
      gymName: gymName ?? schedule.gymName,
      createdAt: schedule.createdAt,
      completedAt: schedule.completedAt,
      healthConsent: schedule.healthConsent,
    );
  }

  @override
  void dispose() {
    final persistenceFlush = flushPersistence();
    unawaited(persistenceFlush.catchError((_) {}));
    _disposed = true;
    _accountEpoch++;
    _businessRequestSequence++;
    _topCoachingTrainerRequestSequence++;
    _memberConsultationRequestSequence++;
    _scheduleRequestSequence++;
    _businessMutations.clear();
    _restTimer?.cancel();
    _serverSyncTimer?.cancel();
    super.dispose();
  }
}

List<BusinessCoachingSchedule> _sortedCoachingSchedules(
  Iterable<BusinessCoachingSchedule> schedules,
) {
  final sorted = schedules.toList(growable: false)
    ..sort((left, right) {
      final byDate = left.date.compareTo(right.date);
      if (byDate != 0) return byDate;
      final byTime = left.startMinutes.compareTo(right.startMinutes);
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });
  return List.unmodifiable(sorted);
}

BusinessCoachingSchedule _copyCoachingSchedule(
  BusinessCoachingSchedule source, {
  DateTime? completedAt,
  bool clearCompletedAt = false,
  CoachingHealthConsent? healthConsent,
}) => BusinessCoachingSchedule(
  id: source.id,
  trainerId: source.trainerId,
  memberUserId: source.memberUserId,
  gymId: source.gymId,
  title: source.title,
  date: source.date,
  startMinutes: source.startMinutes,
  endMinutes: source.endMinutes,
  trainerName: source.trainerName,
  memberName: source.memberName,
  gymName: source.gymName,
  createdAt: source.createdAt,
  completedAt: clearCompletedAt ? null : completedAt ?? source.completedAt,
  healthConsent: healthConsent ?? source.healthConsent,
);

bool _isUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value.trim());

String? _normalizedBusinessRequestText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Map<String, Object?> _ownedRoutineRequestPayload({
  String? routineId,
  required UserRole ownerRole,
  required String title,
  required BusinessRoutineDifficulty difficulty,
  required List<CreateOwnedRoutineExerciseInput> exercises,
  String? intro,
  double? price,
}) => <String, Object?>{
  'routineId': _normalizedBusinessRequestText(routineId),
  'ownerRole': ownerRole.name,
  'title': title.trim(),
  'intro': _normalizedBusinessRequestText(intro),
  'difficulty': difficulty.databaseValue,
  'price': price ?? 0,
  'exercises': _ownedRoutineExercisesRequestPayload(exercises),
};

List<Map<String, Object?>> _ownedRoutineExercisesRequestPayload(
  List<CreateOwnedRoutineExerciseInput> exercises,
) => List.generate(exercises.length, (exerciseIndex) {
  final exercise = exercises[exerciseIndex];
  final sets = [...exercise.sets]
    ..sort((left, right) => left.setNumber.compareTo(right.setNumber));
  return <String, Object?>{
    'baseExerciseId': _normalizedBusinessRequestText(exercise.baseExerciseId),
    'name': exercise.name.trim(),
    'targetMuscle': exercise.targetMuscle.trim(),
    'sets': sets
        .map(
          (set) => <String, Object?>{
            'type': workoutSetTypeDatabaseValue(set.type),
            'targetWeight': set.targetWeight,
            'targetReps': set.targetReps,
            'restSeconds': set.restSeconds,
            'durationSeconds': set.durationSeconds,
            'distanceMeters': set.distanceMeters,
            'intensityRpe': set.intensityRpe,
          },
        )
        .toList(growable: false),
  };
});

String _routineColorHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required super.notifier, required super.child, super.key});

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this context.');
    return scope!.notifier!;
  }
}
