import 'dart:async';

import 'package:flutter/material.dart';

import 'data/app_repository.dart';
import 'data/community_repository.dart';
import 'data/exercise_catalog.dart';
import 'data/routine_catalog_repository.dart';
import 'models.dart';
import 'services/exercise_recommendation_engine.dart';
import 'services/performance_engine.dart';
import 'services/supabase_auth_service.dart';

export 'models.dart';
export 'services/exercise_recommendation_engine.dart';
export 'services/performance_engine.dart';

class AppState extends ChangeNotifier {
  AppState({
    AppRepository? repository,
    this.routineCatalogRepository,
    this.communityRepository,
  }) : _repository = repository ?? MemoryAppRepository() {
    _seedMarketRoutines();
    _seedStarterRoutines();
    _seedSocial();
    _seedBusinessDashboards();
  }

  final AppRepository _repository;
  final RoutineCatalogRepository? routineCatalogRepository;
  final CommunityRepository? communityRepository;
  Timer? _persistTimer;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  Object? persistenceError;
  Object? cloudSyncError;

  UserRole role = UserRole.guest;
  bool isDarkMode = false;
  String weightUnit = 'kg';
  int restDefaultSeconds = 90;
  List<String> goals = [];
  bool get hasTrainingGoal => goals.isNotEmpty;
  double? heightCm;
  double? weight;
  int? age;
  String? gender;
  int restRemaining = 0;
  Timer? _restTimer;

  final List<ExerciseTemplate> exercises = exerciseCatalog;

  final Map<DateTime, WorkoutSession> sessions = {};
  final List<RoutineData> routines = [];
  final List<RoutineData> _marketRoutines = [];
  final List<CommunityPost> communityPosts = [];
  final List<ConsultationData> consultations = [];
  final Map<UserRole, BusinessDashboardData> businessDashboards = {};

  bool _verifiedAdmin = false;
  bool hasPaidPlan = false;

  bool get isAdmin => _verifiedAdmin;
  List<RoutineData> get marketRoutines => List.unmodifiable(_marketRoutines);

  Future<void> initialize() async {
    try {
      final snapshot = await _repository.load(exercises);
      if (snapshot != null) {
        _applySnapshot(snapshot);
      }
      _initialized = true;
      persistenceError = null;
      if (snapshot == null) _schedulePersist();
      try {
        await _refreshCloudData();
        cloudSyncError = null;
      } catch (error) {
        cloudSyncError = error;
      }
    } catch (error) {
      _initialized = true;
      persistenceError = error;
    }
    notifyListeners();
  }

  void chooseRole(UserRole value) {
    if (value == UserRole.admin && !_verifiedAdmin) return;
    role = value;
    _schedulePersist();
    notifyListeners();
  }

  void logout() {
    _persistTimer?.cancel();
    unawaited(SupabaseAuthService.instance.signOut());
    _resetForSignedOutUser();
    cancelRestTimer();
    notifyListeners();
  }

  Future<void> syncAfterAuthentication() async {
    _persistTimer?.cancel();
    try {
      final snapshot = await _repository.load(exercises);
      if (snapshot != null) _applySnapshot(snapshot);
      await _refreshCloudData();
      persistenceError = null;
      cloudSyncError = null;
      if (snapshot == null) _schedulePersist();
    } catch (error) {
      persistenceError = error;
      rethrow;
    } finally {
      notifyListeners();
    }
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

  ExercisePerformanceSummary? performanceFor(
    ExerciseTemplate template, {
    DateTime? before,
  }) {
    return PerformanceEngine.summarize(
      sessions: sessions.values,
      template: template,
      before: before,
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

  WorkoutRecommendation? recommendationFor(ExerciseTemplate template) {
    return PerformanceEngine.recommend(
      sessions: sessions.values,
      template: template,
      goal: PerformanceEngine.goalFromProfile(goals),
    );
  }

  WorkoutRecommendation? recommendationForDate(DateTime date) {
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
          catalog: exercises,
          session: session,
          completedExercise: lastCompleted,
          goals: goals,
        );
        if (next != null) return _nextExerciseWorkoutRecommendation(next);
      }
    }

    final featured = featuredPerformance;
    return featured == null ? null : recommendationFor(featured.template);
  }

  WorkoutRecommendation? get featuredRecommendation {
    return recommendationForDate(DateTime.now());
  }

  WorkoutRecommendation _plannedExerciseRecommendation(
    WorkoutExercise exercise,
  ) {
    final historical = recommendationFor(exercise.template);
    final pending = exercise.sets.where((set) => !set.completed).toList();
    final first = pending.firstOrNull;
    final weight =
        first?.weight ??
        historical?.weight ??
        ExerciseRecommendationEngine.startingWeightFor(exercise.template);
    final validReps = pending
        .map((set) => set.reps)
        .where((reps) => reps > 0)
        .toList();
    final minReps = validReps.isEmpty
        ? historical?.minReps ?? 8
        : validReps.reduce((a, b) => a < b ? a : b);
    final maxReps = validReps.isEmpty
        ? historical?.maxReps ?? 12
        : validReps.reduce((a, b) => a > b ? a : b);
    final increment = weight <= 0
        ? 0.0
        : weight < 20
        ? 1.0
        : 2.5;
    return WorkoutRecommendation(
      template: exercise.template,
      goal: PerformanceEngine.goalFromProfile(goals),
      weight: weight,
      minReps: minReps,
      maxReps: maxReps,
      sets: exercise.sets.isEmpty
          ? historical?.sets ?? 3
          : exercise.sets.length,
      nextWeight: historical?.nextWeight ?? weight + increment,
      reason: '오늘 계획에서 아직 완료하지 않은 운동',
      restSeconds:
          first?.restSeconds ?? historical?.restSeconds ?? restDefaultSeconds,
    );
  }

  WorkoutRecommendation _nextExerciseWorkoutRecommendation(
    NextExerciseRecommendation next,
  ) {
    final historical = recommendationFor(next.template);
    final weight = historical?.weight ?? next.startingWeight;
    final increment = weight <= 0
        ? 0.0
        : weight < 20
        ? 1.0
        : 2.5;
    return WorkoutRecommendation(
      template: next.template,
      goal: PerformanceEngine.goalFromProfile(goals),
      weight: weight,
      minReps: historical?.minReps ?? next.minReps,
      maxReps: historical?.maxReps ?? next.maxReps,
      sets: historical?.sets ?? next.sets,
      nextWeight: historical?.nextWeight ?? weight + increment,
      reason: next.reason,
      restSeconds: next.restSeconds,
    );
  }

  Set<PerformancePrType> prTypesForCandidate(
    ExerciseTemplate template,
    WorkoutSetEntry candidate,
  ) {
    return PerformanceEngine.prTypesForCandidate(
      sessions: sessions.values,
      templateId: template.id,
      candidate: candidate,
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
          WorkoutSetEntry(
            number: 1,
            weight: 40,
            reps: 10,
            restSeconds: restDefaultSeconds,
          ),
          WorkoutSetEntry(
            number: 2,
            weight: 40,
            reps: 10,
            restSeconds: restDefaultSeconds,
          ),
          WorkoutSetEntry(
            number: 3,
            weight: 40,
            reps: 8,
            restSeconds: restDefaultSeconds,
          ),
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
        restSeconds: previous?.restSeconds ?? restDefaultSeconds,
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
  }) {
    if (weight != null) set.weight = weight.clamp(0, 999);
    if (reps != null) set.reps = reps.clamp(0, 999);
    if (type != null) set.type = type;
    if (restSeconds != null) {
      set.restSeconds = restSeconds.clamp(15, 600);
    }
    _schedulePersist();
    notifyListeners();
  }

  void toggleSet(WorkoutSetEntry set) {
    set.completed = !set.completed;
    if (set.completed) startRestTimer(set.restSeconds);
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
      session.exercises.add(
        WorkoutExercise(
          id: '${template.id}_${DateTime.now().microsecondsSinceEpoch}',
          template: template,
          sets: [
            WorkoutSetEntry(
              number: 1,
              weight: 40,
              reps: 10,
              restSeconds: restDefaultSeconds,
            ),
            WorkoutSetEntry(
              number: 2,
              weight: 40,
              reps: 10,
              restSeconds: restDefaultSeconds,
            ),
            WorkoutSetEntry(
              number: 3,
              weight: 40,
              reps: 8,
              restSeconds: restDefaultSeconds,
            ),
          ],
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
        id:
            '${recommendation.template.id}_'
            '${DateTime.now().microsecondsSinceEpoch}',
        template: recommendation.template,
        sets: [],
      );
      session.exercises.add(exercise);
    }

    final completed = exercise.sets.where((set) => set.completed).toList();
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
    final historyRecommendation = recommendationFor(recommendation.template);
    final weight =
        historyRecommendation?.weight ?? recommendation.startingWeight;
    final reps = historyRecommendation?.minReps ?? recommendation.minReps;
    session.exercises.add(
      WorkoutExercise(
        id:
            '${recommendation.template.id}_recommended_'
            '${DateTime.now().microsecondsSinceEpoch}',
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

  Future<void> _refreshCloudData() async {
    final routineRepository = routineCatalogRepository;
    if (routineRepository != null) {
      final catalog = await routineRepository.listPublished();
      _marketRoutines
        ..clear()
        ..addAll(catalog.map(_routineFromCatalog));
    }

    final auth = SupabaseAuthService.instance;
    if (!auth.hasAuthenticatedUser) return;

    _verifiedAdmin = await auth.isVerifiedAdmin();
    if (_verifiedAdmin) {
      role = UserRole.admin;
    } else if (role == UserRole.admin) {
      role = UserRole.member;
    }

    hasPaidPlan =
        _verifiedAdmin ||
        (routineRepository != null &&
            await routineRepository.hasActivePaidPlan());

    final sharedCommunityRepository = communityRepository;
    if (sharedCommunityRepository != null) {
      final records = await sharedCommunityRepository.fetchPosts();
      communityPosts
        ..clear()
        ..addAll(records.map((record) => record.post));
    }
  }

  RoutineData _routineFromCatalog(RoutineCatalogItem item) {
    final templates = item.exercises
        .map((catalogExercise) {
          return exercises
                  .where((exercise) => exercise.name == catalogExercise.name)
                  .firstOrNull ??
              ExerciseTemplate(
                id: 'catalog_${catalogExercise.id}',
                name: catalogExercise.name,
                muscle: catalogExercise.targetMuscle,
                icon: Icons.fitness_center_rounded,
              );
        })
        .toList(growable: false);
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
    );
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
    );
    notifyListeners();
    return true;
  }

  RoutineImportResult importRoutine(RoutineData routine) {
    if (routines.any((item) => item.id == routine.id)) {
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

  bool createRoutine(String name, String description) {
    if (!hasPaidPlan && !_verifiedAdmin && routines.length >= 4) return false;
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

  bool updateRoutine({
    required RoutineData routine,
    required String name,
    required String description,
    required List<ExerciseTemplate> exercises,
  }) {
    final index = routines.indexWhere((item) => item.id == routine.id);
    if (index < 0 || exercises.isEmpty) return false;
    routines[index] = RoutineData(
      id: routine.id,
      name: name.trim(),
      description: description.trim(),
      color: routine.color,
      exercises: List.of(exercises),
      author: routine.author,
      level: routine.level,
      accessTier: routine.accessTier,
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

  Future<void> addCommunityPost({
    required String content,
    required bool includeWorkout,
    required String visualKey,
    CommunityPostMedia? media,
    List<String> activeOverlays = const [],
  }) async {
    final metric = includeWorkout ? '오늘 운동 기록 · 12세트 · 4.2t' : '일상 기록';
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
        author: SupabaseAuthService.instance.currentDisplayName,
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
            author: SupabaseAuthService.instance.currentDisplayName,
            content: content,
            createdAt: DateTime.now(),
          );
    post.comments.add(comment);
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

  void assignBusinessMember({required String memberName, String? trainerName}) {
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

  void updateBusinessProfile({
    required UserRole role,
    required String displayName,
    required String keyword,
    required String intro,
  }) {
    final facts = dashboardFor(role).facts;
    facts['displayName'] = displayName;
    facts[role == UserRole.gym ? 'location' : 'keyword'] = keyword;
    facts['intro'] = intro;
    _schedulePersist();
    notifyListeners();
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

  bool businessNotificationPreference(
    UserRole role,
    String key, {
    required bool fallback,
  }) {
    final value = dashboardFor(role).facts['notification.$key'];
    return value == null ? fallback : value == 'true';
  }

  void setBusinessNotificationPreference(
    UserRole role,
    String key,
    bool value,
  ) {
    dashboardFor(role).facts['notification.$key'] = '$value';
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
            goals: goals,
            heightCm: heightCm,
            weight: weight,
            age: age,
            gender: gender,
            communityPosts: communityRepository == null
                ? communityPosts
                : const [],
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

  void _applySnapshot(AppSnapshot snapshot) {
    role = snapshot.role;
    isDarkMode = snapshot.isDarkMode;
    weightUnit = snapshot.weightUnit;
    restDefaultSeconds = snapshot.restDefaultSeconds;
    goals = List.of(snapshot.goals);
    heightCm = snapshot.heightCm;
    weight = snapshot.weight;
    age = snapshot.age;
    gender = snapshot.gender;
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
    if (snapshot.consultations.isNotEmpty) {
      consultations
        ..clear()
        ..addAll(snapshot.consultations);
    }
    if (snapshot.businessDashboards.isNotEmpty) {
      businessDashboards.addAll(snapshot.businessDashboards);
    }
  }

  void _resetForSignedOutUser() {
    _verifiedAdmin = false;
    hasPaidPlan = false;
    cloudSyncError = null;
    role = UserRole.guest;
    goals = [];
    heightCm = null;
    weight = null;
    age = null;
    gender = null;
    sessions.clear();
    routines.clear();
    communityPosts.clear();
    consultations.clear();
    businessDashboards.clear();
    _seedStarterRoutines();
    _seedSocial();
    _seedBusinessDashboards();
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
        color: const Color(0xFF8B5CF6),
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
