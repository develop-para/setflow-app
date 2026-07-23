import 'dart:async';

import 'package:flutter/material.dart';

import 'data/app_repository.dart';
import 'models.dart';

export 'models.dart';

class AppState extends ChangeNotifier {
  AppState({AppRepository? repository})
    : _repository = repository ?? MemoryAppRepository() {
    _seedSessions();
    _seedSocial();
    _seedBusinessDashboards();
  }

  final AppRepository _repository;
  Timer? _persistTimer;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  Object? persistenceError;

  UserRole role = UserRole.guest;
  bool isDarkMode = false;
  String weightUnit = 'kg';
  int restDefaultSeconds = 90;
  int restRemaining = 0;
  Timer? _restTimer;

  final List<ExerciseTemplate> exercises = const [
    ExerciseTemplate(
      id: 'bench',
      name: '바벨 벤치 프레스',
      muscle: '가슴',
      icon: Icons.fitness_center,
    ),
    ExerciseTemplate(
      id: 'incline',
      name: '인클라인 덤벨 프레스',
      muscle: '가슴',
      icon: Icons.sports_gymnastics,
    ),
    ExerciseTemplate(
      id: 'squat',
      name: '스쿼트',
      muscle: '하체',
      icon: Icons.accessibility_new,
    ),
    ExerciseTemplate(
      id: 'legpress',
      name: '레그 프레스',
      muscle: '하체',
      icon: Icons.airline_seat_recline_extra,
    ),
    ExerciseTemplate(
      id: 'latpull',
      name: '렛 풀 다운',
      muscle: '등',
      icon: Icons.vertical_align_bottom,
    ),
    ExerciseTemplate(id: 'row', name: '바벨 로우', muscle: '등', icon: Icons.rowing),
    ExerciseTemplate(
      id: 'ohp',
      name: '오버헤드 프레스',
      muscle: '어깨',
      icon: Icons.upload,
    ),
    ExerciseTemplate(
      id: 'lateral',
      name: '사이드 레터럴 레이즈',
      muscle: '어깨',
      icon: Icons.open_with,
    ),
    ExerciseTemplate(
      id: 'curl',
      name: '덤벨 컬',
      muscle: '팔',
      icon: Icons.fitness_center,
    ),
    ExerciseTemplate(
      id: 'plank',
      name: '플랭크',
      muscle: '복근',
      icon: Icons.timer_outlined,
    ),
    ExerciseTemplate(
      id: 'run',
      name: '트레드밀 러닝',
      muscle: '유산소',
      icon: Icons.directions_run,
    ),
  ];

  final Map<DateTime, WorkoutSession> sessions = {};
  final List<RoutineData> routines = [];
  final List<CommunityPost> communityPosts = [];
  final List<ConsultationData> consultations = [];
  final Map<UserRole, BusinessDashboardData> businessDashboards = {};

  Future<void> initialize() async {
    try {
      final snapshot = await _repository.load(exercises);
      if (snapshot != null) {
        role = snapshot.role;
        isDarkMode = snapshot.isDarkMode;
        weightUnit = snapshot.weightUnit;
        restDefaultSeconds = snapshot.restDefaultSeconds;
        sessions
          ..clear()
          ..addAll(snapshot.sessions);
        routines
          ..clear()
          ..addAll(snapshot.routines);
        if (snapshot.communityPosts.isNotEmpty) {
          communityPosts
            ..clear()
            ..addAll(snapshot.communityPosts);
        }
        if (snapshot.consultations.isNotEmpty) {
          consultations
            ..clear()
            ..addAll(snapshot.consultations);
        }
        if (snapshot.businessDashboards.isNotEmpty) {
          businessDashboards.addAll(snapshot.businessDashboards);
        }
      }
      _initialized = true;
      persistenceError = null;
      if (snapshot == null) _schedulePersist();
    } catch (error) {
      _initialized = true;
      persistenceError = error;
    }
    notifyListeners();
  }

  List<RoutineData> get marketRoutines => [
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
      color: const Color(0xFF8B5CF6),
      exercises: [exercises[4], exercises[5], exercises[8]],
      author: '모션짐 · 사업자 인증',
      level: '중급',
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
  ];

  void chooseRole(UserRole value) {
    role = value;
    _schedulePersist();
    notifyListeners();
  }

  void logout() {
    role = UserRole.guest;
    cancelRestTimer();
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

  DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  WorkoutSession sessionFor(DateTime date) {
    final key = dateOnly(date);
    return sessions.putIfAbsent(
      key,
      () => WorkoutSession(date: key, exercises: []),
    );
  }

  void addExercise(DateTime date, ExerciseTemplate template) {
    final session = sessionFor(date);
    if (session.exercises.any((item) => item.template.id == template.id)) {
      return;
    }
    session.exercises.add(
      WorkoutExercise(
        id: '${template.id}_${DateTime.now().microsecondsSinceEpoch}',
        template: template,
        sets: [
          WorkoutSetEntry(number: 1, weight: 40, reps: 10),
          WorkoutSetEntry(number: 2, weight: 40, reps: 10),
          WorkoutSetEntry(number: 3, weight: 40, reps: 8),
        ],
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  void addSet(WorkoutExercise exercise) {
    final previous = exercise.sets.lastOrNull;
    exercise.sets.add(
      WorkoutSetEntry(
        number: exercise.sets.length + 1,
        weight: previous?.weight ?? 20,
        reps: previous?.reps ?? 10,
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
  }) {
    if (weight != null) set.weight = weight.clamp(0, 999);
    if (reps != null) set.reps = reps.clamp(0, 999);
    if (type != null) set.type = type;
    _schedulePersist();
    notifyListeners();
  }

  void toggleSet(WorkoutSetEntry set) {
    set.completed = !set.completed;
    if (set.completed) startRestTimer(restDefaultSeconds);
    _schedulePersist();
    notifyListeners();
  }

  void copySession(DateTime from, DateTime to) {
    final source = sessions[dateOnly(from)];
    if (source == null) return;
    final target = dateOnly(to);
    sessions[target] = WorkoutSession(
      date: target,
      exercises: source.exercises.map((exercise) => exercise.copy()).toList(),
    );
    _schedulePersist();
    notifyListeners();
  }

  void deleteSession(DateTime date) {
    sessions.remove(dateOnly(date));
    _schedulePersist();
    notifyListeners();
  }

  void applyRoutine(RoutineData routine, DateTime date) {
    for (final exercise in routine.exercises) {
      addExercise(date, exercise);
    }
  }

  RoutineImportResult importRoutine(RoutineData routine) {
    if (routines.any((item) => item.id == routine.id)) {
      return RoutineImportResult.alreadySaved;
    }
    if (routines.length >= 4) return RoutineImportResult.limitReached;
    routines.add(routine);
    _schedulePersist();
    notifyListeners();
    return RoutineImportResult.imported;
  }

  bool createRoutine(String name, String description) {
    if (routines.length >= 4) return false;
    routines.add(
      RoutineData(
        id: 'routine_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        description: description,
        color: const Color(0xFF3B82F6),
        exercises: [exercises[0], exercises[2], exercises[4]],
      ),
    );
    _schedulePersist();
    notifyListeners();
    return true;
  }

  void removeRoutine(RoutineData routine) {
    routines.remove(routine);
    _schedulePersist();
    notifyListeners();
  }

  void addCommunityPost({
    required String content,
    required bool includeWorkout,
    required String visualKey,
  }) {
    communityPosts.insert(
      0,
      CommunityPost(
        id: 'post_${DateTime.now().microsecondsSinceEpoch}',
        author: '운동초보',
        content: content,
        metric: includeWorkout ? '오늘 운동 기록 · 12세트 · 4.2t' : '일상 기록',
        createdAt: DateTime.now(),
        visualKey: visualKey,
        color: const Color(0xFF10CEBD),
        isMine: true,
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  void togglePostLike(CommunityPost post) {
    post.isLiked = !post.isLiked;
    post.likes += post.isLiked ? 1 : -1;
    _schedulePersist();
    notifyListeners();
  }

  void addPostComment(CommunityPost post, String content) {
    post.comments.add(
      PostComment(
        id: 'comment_${DateTime.now().microsecondsSinceEpoch}',
        author: '운동초보',
        content: content,
        createdAt: DateTime.now(),
      ),
    );
    _schedulePersist();
    notifyListeners();
  }

  void addConsultation({
    required String trainerName,
    required String specialty,
    required String goal,
    required String level,
    required String question,
  }) {
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
      ),
    );
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
    return businessDashboards[role] ?? businessDashboards[UserRole.trainer]!;
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

  Future<void> refreshBusinessDashboard(UserRole role) async {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    dashboardFor(role).lastSyncedAt = DateTime.now();
    _schedulePersist();
    notifyListeners();
  }

  void recordBusinessMemberFeedback({
    required UserRole role,
    required String memberName,
    required String feedback,
  }) {
    final facts = dashboardFor(role).facts;
    facts['memberFeedback.$memberName'] = feedback;
    facts['memberFeedbackAt.$memberName'] = DateTime.now().toIso8601String();
    _schedulePersist();
    notifyListeners();
  }

  void assignBusinessMember({
    required String memberName,
    required String trainerName,
  }) {
    final facts = dashboardFor(UserRole.gym).facts;
    facts['memberAssignment.$memberName'] = trainerName;
    facts['memberAssignmentAt.$memberName'] = DateTime.now().toIso8601String();
    _schedulePersist();
    notifyListeners();
  }

  bool isBusinessConsultationAnswered(UserRole role, int consultationIndex) {
    return dashboardFor(
          role,
        ).facts['consultation.$consultationIndex.answered'] ==
        'true';
  }

  void answerBusinessConsultation({
    required UserRole role,
    required int consultationIndex,
    required String answer,
  }) {
    final facts = dashboardFor(role).facts;
    facts['consultation.$consultationIndex.answered'] = 'true';
    facts['consultation.$consultationIndex.answer'] = answer;
    facts['consultation.$consultationIndex.answeredAt'] = DateTime.now()
        .toIso8601String();
    _schedulePersist();
    notifyListeners();
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

  void completeAdminReview({
    required String reviewId,
    required String applicantName,
    required String status,
    String reason = '',
  }) {
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

  Future<void> clearPersistedData() async {
    _persistTimer?.cancel();
    await _repository.clear();
  }

  void retryPersistence() => _schedulePersist();

  void _schedulePersist() {
    if (!_initialized) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        await _repository.save(
          AppSnapshot(
            role: role,
            isDarkMode: isDarkMode,
            weightUnit: weightUnit,
            restDefaultSeconds: restDefaultSeconds,
            sessions: sessions,
            routines: routines,
            communityPosts: communityPosts,
            consultations: consultations,
            businessDashboards: businessDashboards,
          ),
        );
        persistenceError = null;
      } catch (error) {
        persistenceError = error;
        notifyListeners();
      }
    });
  }

  void startRestTimer(int seconds) {
    _restTimer?.cancel();
    restRemaining = seconds;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (restRemaining <= 1) {
        restRemaining = 0;
        timer.cancel();
      } else {
        restRemaining--;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelRestTimer() {
    _restTimer?.cancel();
    restRemaining = 0;
    notifyListeners();
  }

  void _seedSessions() {
    final now = DateTime.now();
    final templates = exercises;
    for (var day = 1; day <= 21; day++) {
      if (day == 1 ||
          day == 2 ||
          day == 3 ||
          day == 4 ||
          day == 5 ||
          day == 6) {
        continue;
      }
      if (day % 4 == 2) continue;
      final date = DateTime(now.year, now.month, day);
      final lower = day % 4 == 0;
      final exercise = WorkoutExercise(
        id: 'seed_$day',
        template: lower ? templates[2] : templates[0],
        sets: List.generate(
          lower ? 4 : 5,
          (index) => WorkoutSetEntry(
            number: index + 1,
            weight: lower ? 80 : 40,
            reps: lower ? 8 : 10,
            completed: day % 5 != 0 || index < 2,
          ),
        ),
      );
      sessions[date] = WorkoutSession(date: date, exercises: [exercise]);
    }
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
          'plan': '엔터프라이즈 플랜',
          'members': '84',
          'revenue': '18.4',
          'trainers': '6',
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

  @override
  void dispose() {
    _restTimer?.cancel();
    _persistTimer?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required super.notifier, required super.child, super.key});

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this context.');
    return scope!.notifier!;
  }
}
