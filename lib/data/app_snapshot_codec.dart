import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import 'app_repository.dart';

abstract final class AppSnapshotCodec {
  static const schemaVersion = 11;

  static String encode(AppSnapshot snapshot) => jsonEncode(toJson(snapshot));

  /// A single routine, on the wire.
  ///
  /// Handing a routine to a training partner has to produce exactly the shape
  /// the snapshot already stores — a second serializer would drift from this
  /// one the first time a field is added, and the routine that arrived would
  /// quietly lose its set plans.
  static Map<String, dynamic> routineToJson(RoutineData routine) =>
      _routineToJson(routine);

  static RoutineData? routineFromJson(
    Map<String, dynamic> json,
    List<ExerciseTemplate> exerciseCatalog,
  ) => _routineFromJson(json, _templateLookup(exerciseCatalog));

  static Map<String, dynamic> toJson(AppSnapshot snapshot) {
    return {
      'schemaVersion': schemaVersion,
      'preferences': {
        'role': snapshot.role.name,
        'isDarkMode': snapshot.isDarkMode,
        'weightUnit': snapshot.weightUnit,
        'restDefaultSeconds': snapshot.restDefaultSeconds,
        if (snapshot.defaultSetCount != null)
          'defaultSetCount': snapshot.defaultSetCount,
        if (snapshot.defaultRepCount != null)
          'defaultRepCount': snapshot.defaultRepCount,
        if (snapshot.activeTrainingPartyId != null)
          'activeTrainingPartyId': snapshot.activeTrainingPartyId,
        'useRir': snapshot.useRir,
        'autoStartRestTimer': snapshot.autoStartRestTimer,
        'autoRecommendNextExercise': snapshot.autoRecommendNextExercise,
        'restTimerNotifications': snapshot.restTimerNotifications,
        'timerVibration': snapshot.timerVibration,
        'timerSound': snapshot.timerSound,
        'timerCountdownSeconds': snapshot.timerCountdownSeconds,
        'oneRepMaxFormula': snapshot.oneRepMaxFormula.storageKey,
        'pushCoachingFeedback': snapshot.pushCoachingFeedback,
        'communityReactionNotifications':
            snapshot.communityReactionNotifications,
        'pushTogether': snapshot.pushTogether,
        'pushWorkoutReminder': snapshot.pushWorkoutReminder,
        'workoutReminderHour': snapshot.workoutReminderHour,
        'businessNotifications': snapshot.businessNotifications,
      },
      'profile': {
        'nickname': snapshot.nickname,
        'goals': snapshot.goals,
        'heightCm': snapshot.heightCm,
        'weight': snapshot.weight,
        'age': snapshot.age,
        'gender': snapshot.gender,
        'precisionRecommendationPrompted':
            snapshot.precisionRecommendationPrompted,
        'hasSwipedSet': snapshot.hasSwipedSet,
        'hasSeenTogetherGuide': snapshot.hasSeenTogetherGuide,
        'recommendationProfile': snapshot.recommendationProfile?.toJson(),
      },
      'customExercises': snapshot.customExercises
          .map(
            (exercise) => {
              'id': exercise.id,
              'name': exercise.name,
              'muscle': exercise.muscle,
              'measurement': exercise.measurement.name,
            },
          )
          .toList(),
      'sessions': snapshot.sessions.values.map(_sessionToJson).toList(),
      'routines': snapshot.routines.map(_routineToJson).toList(),
      'communityPosts': snapshot.communityPosts.map(_postToJson).toList(),
      'consultations': snapshot.consultations.map(_consultationToJson).toList(),
      'businessDashboards': snapshot.businessDashboards.values
          .map(_businessDashboardToJson)
          .toList(),
    };
  }

  static AppSnapshot? fromJson(
    Map<String, dynamic> json,
    List<ExerciseTemplate> exerciseCatalog,
  ) => decode(jsonEncode(json), exerciseCatalog);

  static AppSnapshot? decode(
    String source,
    List<ExerciseTemplate> exerciseCatalog,
  ) {
    try {
      final root = jsonDecode(source) as Map<String, dynamic>;
      final version = (root['schemaVersion'] as num?)?.toInt();
      if (version == null || version < 1 || version > schemaVersion) {
        return null;
      }
      final preferences = root['preferences'] as Map<String, dynamic>? ?? {};
      final profile = root['profile'] as Map<String, dynamic>? ?? {};
      final customExercises = <ExerciseTemplate>[];
      final knownIds = exerciseCatalog.map((exercise) => exercise.id).toSet();
      const supportedMuscles = {'가슴', '등', '어깨', '하체', '팔', '복근', '유산소'};
      for (final raw in root['customExercises'] as List<dynamic>? ?? const []) {
        if (raw is! Map) continue;
        final value = Map<String, dynamic>.from(raw);
        final id = value['id']?.toString().trim() ?? '';
        final name = value['name']?.toString().trim() ?? '';
        final muscle = value['muscle']?.toString().trim() ?? '';
        if (!id.startsWith('custom_') ||
            id.length > 80 ||
            name.isEmpty ||
            name.length > 50 ||
            !supportedMuscles.contains(muscle) ||
            !knownIds.add(id)) {
          continue;
        }
        final measurement = ExerciseMeasurement.values.firstWhere(
          (candidate) => candidate.name == value['measurement'],
          orElse: () => ExerciseMeasurement.weightReps,
        );
        customExercises.add(
          ExerciseTemplate(
            id: id,
            name: name,
            muscle: muscle,
            icon: exerciseIconForMuscle(muscle),
            measurement: measurement,
          ),
        );
      }
      final templates = _templateLookup([
        ...exerciseCatalog,
        ...customExercises,
      ]);
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
      final posts = <CommunityPost>[];
      for (final raw in root['communityPosts'] as List<dynamic>? ?? const []) {
        final post = _postFromJson(raw as Map<String, dynamic>);
        if (post != null) posts.add(post);
      }
      final consultations = <ConsultationData>[];
      for (final raw in root['consultations'] as List<dynamic>? ?? const []) {
        final consultation = _consultationFromJson(raw as Map<String, dynamic>);
        if (consultation != null) consultations.add(consultation);
      }
      final businessDashboards = <UserRole, BusinessDashboardData>{};
      for (final raw
          in root['businessDashboards'] as List<dynamic>? ?? const []) {
        final dashboard = _businessDashboardFromJson(
          raw as Map<String, dynamic>,
        );
        if (dashboard != null) {
          businessDashboards[dashboard.role] = dashboard;
        }
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
        defaultSetCount: (preferences['defaultSetCount'] as num?)?.toInt(),
        defaultRepCount: (preferences['defaultRepCount'] as num?)?.toInt(),
        activeTrainingPartyId: preferences['activeTrainingPartyId'] as String?,
        nickname: profile['nickname'] as String?,
        useRir: preferences['useRir'] as bool? ?? false,
        autoStartRestTimer: preferences['autoStartRestTimer'] as bool? ?? true,
        autoRecommendNextExercise:
            preferences['autoRecommendNextExercise'] as bool? ?? true,
        restTimerNotifications:
            preferences['restTimerNotifications'] as bool? ?? true,
        timerVibration: preferences['timerVibration'] as bool? ?? true,
        timerSound: preferences['timerSound'] as bool? ?? true,
        timerCountdownSeconds:
            ((preferences['timerCountdownSeconds'] as num?)?.toInt() ?? 30)
                .clamp(0, 120),
        oneRepMaxFormula: oneRepMaxFormulaFromStorage(
          preferences['oneRepMaxFormula'] as String?,
        ),
        pushCoachingFeedback:
            preferences['pushCoachingFeedback'] as bool? ?? true,
        communityReactionNotifications:
            preferences['communityReactionNotifications'] as bool? ?? false,
        pushTogether: preferences['pushTogether'] as bool? ?? true,
        pushWorkoutReminder:
            preferences['pushWorkoutReminder'] as bool? ?? false,
        workoutReminderHour:
            ((preferences['workoutReminderHour'] as num?)?.toInt() ?? 19).clamp(
              AppSnapshot.earliestReminderHour,
              AppSnapshot.latestReminderHour,
            ),
        businessNotifications: {
          for (final entry
              in (preferences['businessNotifications']
                          as Map<String, dynamic>? ??
                      const <String, dynamic>{})
                  .entries)
            if (entry.value is bool) entry.key: entry.value as bool,
        },
        sessions: sessions,
        routines: routines,
        goals: (profile['goals'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        heightCm: (profile['heightCm'] as num?)?.toDouble(),
        weight: (profile['weight'] as num?)?.toDouble(),
        age: (profile['age'] as num?)?.toInt(),
        gender: profile['gender'] as String?,
        precisionRecommendationPrompted:
            profile['precisionRecommendationPrompted'] as bool? ?? false,
        hasSwipedSet: profile['hasSwipedSet'] as bool? ?? false,
        hasSeenTogetherGuide: profile['hasSeenTogetherGuide'] as bool? ?? false,
        recommendationProfile: RecommendationProfile.tryFromJson(
          profile['recommendationProfile'],
        ),
        communityPosts: posts,
        consultations: consultations,
        businessDashboards: businessDashboards,
        customExercises: customExercises,
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
      if (session.startedAt != null)
        'startedAt': session.startedAt!.toIso8601String(),
      if (session.endedAt != null)
        'endedAt': session.endedAt!.toIso8601String(),
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
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? ''),
    );
  }

  static Map<String, dynamic> _workoutExerciseToJson(WorkoutExercise exercise) {
    return {
      'id': exercise.id,
      'templateId': exercise.template.id,
      // A database exercise may not be in the built-in catalog on a cold,
      // offline restart. Keep a small inline fallback so an unknown ID never
      // makes a user's recorded exercise disappear during decode.
      if (exercise.template.sourceName != null || _isUuid(exercise.template.id))
        'template': _exerciseTemplateToJson(
          exercise.template,
          includeSearchMetadata: false,
        ),
      'sets': exercise.sets
          .map(
            (set) => {
              'number': set.number,
              'weight': set.weight,
              'reps': set.reps,
              'completed': set.completed,
              'type': set.type,
              'restSeconds': set.restSeconds,
              'durationSeconds': set.durationSeconds,
              'distanceKm': set.distanceKm,
              'intensityRpe': set.intensityRpe,
              // 적지 않은 세트는 키 자체를 남기지 않는다 — 0(실패 직전)과
              // 구별되어야 한다.
              if (set.rir != null) 'rir': set.rir,
            },
          )
          .toList(),
    };
  }

  static WorkoutExercise? _workoutExerciseFromJson(
    Map<String, dynamic> json,
    Map<String, ExerciseTemplate> templates,
  ) {
    final templateId = json['templateId'] as String?;
    final template = _resolveInlineTemplate(
      templateId,
      json['template'],
      templates,
    );
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
          restSeconds: (set['restSeconds'] as num?)?.toInt() ?? 90,
          durationSeconds: (set['durationSeconds'] as num?)?.toInt() ?? 0,
          distanceKm: (set['distanceKm'] as num?)?.toDouble() ?? 0,
          intensityRpe: (set['intensityRpe'] as num?)?.toDouble() ?? 0,
          rir: (set['rir'] as num?)?.toInt(),
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

  static Map<String, dynamic> _exerciseTemplateToJson(
    ExerciseTemplate exercise, {
    bool includeSearchMetadata = true,
  }) => {
    'id': exercise.id,
    'name': exercise.name,
    'muscle': exercise.muscle,
    'measurement': exercise.measurement.name,
    'nameEnglish': ?exercise.nameEnglish,
    'equipmentKey': ?exercise.equipmentKey,
    'equipmentName': ?exercise.equipmentName,
    if (includeSearchMetadata && exercise.aliases.isNotEmpty)
      'aliases': exercise.aliases,
    if (includeSearchMetadata) 'difficulty': ?exercise.difficulty,
    if (includeSearchMetadata) 'category': ?exercise.category,
    'sourceName': ?exercise.sourceName,
    'sourceId': ?exercise.sourceId,
    'databaseId': ?exercise.databaseId,
  };

  static ExerciseTemplate? _exerciseTemplateFromJson(
    Map<String, dynamic> json,
  ) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final muscle = json['muscle']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty || muscle.isEmpty) return null;
    final measurement = ExerciseMeasurement.values.firstWhere(
      (candidate) => candidate.name == json['measurement'],
      orElse: () => ExerciseMeasurement.weightReps,
    );
    final aliases = json['aliases'] is List
        ? (json['aliases'] as List)
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .take(40)
              .toList(growable: false)
        : const <String>[];
    String? optionalString(String key) {
      final value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }

    return ExerciseTemplate(
      id: id,
      name: name,
      muscle: muscle,
      icon: exerciseIconForMuscle(muscle),
      measurement: measurement,
      nameEnglish: optionalString('nameEnglish'),
      equipmentKey: optionalString('equipmentKey'),
      equipmentName: optionalString('equipmentName'),
      aliases: aliases,
      difficulty: optionalString('difficulty'),
      category: optionalString('category'),
      sourceName: optionalString('sourceName'),
      sourceId: optionalString('sourceId'),
      databaseId: optionalString('databaseId'),
    );
  }

  static Map<String, ExerciseTemplate> _templateLookup(
    Iterable<ExerciseTemplate> catalog,
  ) {
    final lookup = <String, ExerciseTemplate>{};
    for (final exercise in catalog) {
      lookup[exercise.id] = exercise;
      final databaseId = exercise.databaseId;
      if (databaseId != null && databaseId.isNotEmpty) {
        lookup[databaseId] = exercise;
      }
    }
    return lookup;
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static ExerciseTemplate? _resolveInlineTemplate(
    String? templateId,
    Object? rawInline,
    Map<String, ExerciseTemplate> templates,
  ) {
    final existing = templates[templateId];
    final inline = rawInline is Map
        ? _exerciseTemplateFromJson(Map<String, dynamic>.from(rawInline))
        : null;
    final inlineMatches =
        inline != null &&
        (templateId == null || inline.referencesId(templateId));
    final template =
        inlineMatches &&
            (existing == null ||
                (existing.databaseReferenceId == null &&
                    inline.databaseReferenceId != null))
        ? inline
        : existing;
    if (template != null) {
      templates[template.id] = template;
      final databaseId = template.databaseReferenceId;
      if (databaseId != null) templates[databaseId] = template;
    }
    return template;
  }

  static Map<String, dynamic> _routineToJson(RoutineData routine) {
    return {
      'id': routine.id,
      'name': routine.name,
      'description': routine.description,
      'color': routine.color.toARGB32(),
      'exerciseIds': routine.exercises.map((item) => item.id).toList(),
      'exercises': routine.exercises
          .map(
            (exercise) => {
              ..._exerciseTemplateToJson(exercise),
              'sets': routine
                  .setsFor(exercise)
                  .map(
                    (set) => {
                      'number': set.number,
                      'weight': set.weight,
                      'reps': set.reps,
                      'type': set.type,
                      'restSeconds': set.restSeconds,
                      'durationSeconds': set.durationSeconds,
                      'distanceKm': set.distanceKm,
                      'intensityRpe': set.intensityRpe,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'author': routine.author,
      'level': routine.level,
      'accessTier': routine.accessTier.name,
      'sourceMarketRoutineId': routine.sourceMarketRoutineId,
      'sourceCoachingRoutineId': routine.sourceCoachingRoutineId,
      'authorTrainerId': routine.authorTrainerId,
      'authorGymId': routine.authorGymId,
      'authorType': routine.authorType.name,
    };
  }

  static RoutineData? _routineFromJson(
    Map<String, dynamic> json,
    Map<String, ExerciseTemplate> templates,
  ) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || name == null) return null;
    final exercises = <ExerciseTemplate>[];
    final setPlans = <String, List<RoutineSetPlan>>{};
    final inlineExercises = json['exercises'];
    if (inlineExercises is List) {
      for (final raw in inlineExercises) {
        if (raw is! Map) continue;
        final exerciseJson = Map<String, dynamic>.from(raw);
        final exerciseId = exerciseJson['id'] as String?;
        if (exerciseId == null || exerciseId.isEmpty) continue;
        final exercise =
            _resolveInlineTemplate(exerciseId, exerciseJson, templates) ??
            ExerciseTemplate(
              id: exerciseId,
              name: exerciseJson['name'] as String? ?? '운동',
              muscle: exerciseJson['muscle'] as String? ?? '전신',
              icon: Icons.fitness_center_rounded,
            );
        exercises.add(exercise);
        final plans = <RoutineSetPlan>[];
        final rawSets = exerciseJson['sets'];
        if (rawSets is List) {
          for (final rawSet in rawSets) {
            if (rawSet is! Map) continue;
            final setJson = Map<String, dynamic>.from(rawSet);
            plans.add(
              RoutineSetPlan(
                number:
                    (setJson['number'] as num?)?.toInt() ?? plans.length + 1,
                weight: (setJson['weight'] as num?)?.toDouble() ?? 0,
                reps: (setJson['reps'] as num?)?.toInt() ?? 0,
                type: setJson['type'] as String? ?? '일반',
                restSeconds: (setJson['restSeconds'] as num?)?.toInt() ?? 90,
                durationSeconds:
                    (setJson['durationSeconds'] as num?)?.toInt() ?? 0,
                distanceKm: (setJson['distanceKm'] as num?)?.toDouble() ?? 0,
                intensityRpe:
                    (setJson['intensityRpe'] as num?)?.toDouble() ?? 0,
              ),
            );
          }
        }
        if (plans.isNotEmpty) setPlans[exercise.id] = plans;
      }
    }
    if (exercises.isEmpty) {
      exercises.addAll(
        (json['exerciseIds'] as List<dynamic>? ?? const [])
            .map((value) => templates[value as String?])
            .whereType<ExerciseTemplate>(),
      );
    }
    return RoutineData(
      id: id,
      name: name,
      description: json['description'] as String? ?? '',
      color: Color((json['color'] as num?)?.toInt() ?? 0xFF3B82F6),
      exercises: exercises,
      author: json['author'] as String? ?? '나',
      level: json['level'] as String? ?? '중급',
      accessTier:
          RoutineAccessTier.values
              .where((item) => item.name == json['accessTier'])
              .firstOrNull ??
          RoutineAccessTier.free,
      setPlans: setPlans,
      sourceMarketRoutineId: json['sourceMarketRoutineId'] as String?,
      sourceCoachingRoutineId: json['sourceCoachingRoutineId'] as String?,
      authorTrainerId: json['authorTrainerId'] as String?,
      authorGymId: json['authorGymId'] as String?,
      authorType:
          RoutineAuthorType.values
              .where((item) => item.name == json['authorType'])
              .firstOrNull ??
          RoutineAuthorType.system,
    );
  }

  static Map<String, dynamic> _postToJson(CommunityPost post) {
    return {
      'id': post.id,
      'author': post.author,
      'content': post.content,
      'metric': post.metric,
      'createdAt': post.createdAt.toIso8601String(),
      'visualKey': post.visualKey,
      'color': post.color.toARGB32(),
      'likes': post.likes,
      'isLiked': post.isLiked,
      'isMine': post.isMine,
      'imageUrl': post.imageUrl,
      'location': post.location,
      'routineName': post.routineName,
      'activeOverlays': post.activeOverlays,
      'comments': post.comments
          .map(
            (comment) => {
              'id': comment.id,
              'author': comment.author,
              'content': comment.content,
              'createdAt': comment.createdAt.toIso8601String(),
            },
          )
          .toList(),
    };
  }

  static CommunityPost? _postFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final content = json['content'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id == null || content == null || createdAt == null) return null;
    final comments = <PostComment>[];
    for (final raw in json['comments'] as List<dynamic>? ?? const []) {
      final comment = raw as Map<String, dynamic>;
      final commentDate = DateTime.tryParse(
        comment['createdAt'] as String? ?? '',
      );
      final commentId = comment['id'] as String?;
      final commentContent = comment['content'] as String?;
      if (commentDate == null || commentId == null || commentContent == null) {
        continue;
      }
      comments.add(
        PostComment(
          id: commentId,
          author: comment['author'] as String? ?? '회원',
          content: commentContent,
          createdAt: commentDate,
        ),
      );
    }
    return CommunityPost(
      id: id,
      author: json['author'] as String? ?? '회원',
      content: content,
      metric: json['metric'] as String? ?? '',
      createdAt: createdAt,
      visualKey: json['visualKey'] as String? ?? 'workout',
      color: Color((json['color'] as num?)?.toInt() ?? 0xFFFFB20C),
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      isLiked: json['isLiked'] as bool? ?? false,
      isMine: json['isMine'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String?,
      location: json['location'] as String?,
      routineName: json['routineName'] as String?,
      activeOverlays: (json['activeOverlays'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      comments: comments,
    );
  }

  static Map<String, dynamic> _consultationToJson(
    ConsultationData consultation,
  ) {
    return {
      'id': consultation.id,
      'trainerName': consultation.trainerName,
      'specialty': consultation.specialty,
      'goal': consultation.goal,
      'level': consultation.level,
      'question': consultation.question,
      'createdAt': consultation.createdAt.toIso8601String(),
      'status': consultation.status.name,
      'response': consultation.response,
      'rating': consultation.rating,
      'sharedRecommendationProfile': consultation.sharedRecommendationProfile
          ?.toJson(),
      'recommendationProfileShareRevokedAt': consultation
          .recommendationProfileShareRevokedAt
          ?.toUtc()
          .toIso8601String(),
    };
  }

  static ConsultationData? _consultationFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final question = json['question'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id == null || question == null || createdAt == null) return null;
    final statusName = json['status'] as String?;
    final status = ConsultationStatus.values
        .where((item) => item.name == statusName)
        .firstOrNull;
    return ConsultationData(
      id: id,
      trainerName: json['trainerName'] as String? ?? '김코치',
      specialty: json['specialty'] as String? ?? '근력 향상',
      goal: json['goal'] as String? ?? '',
      level: json['level'] as String? ?? '',
      question: question,
      createdAt: createdAt,
      status: status ?? ConsultationStatus.waiting,
      response: json['response'] as String?,
      rating: (json['rating'] as num?)?.toInt(),
      sharedRecommendationProfile: RecommendationProfile.tryFromJson(
        json['sharedRecommendationProfile'],
      ),
      recommendationProfileShareRevokedAt: DateTime.tryParse(
        json['recommendationProfileShareRevokedAt'] as String? ?? '',
      ),
    );
  }

  static Map<String, dynamic> _businessDashboardToJson(
    BusinessDashboardData dashboard,
  ) {
    return {
      'role': dashboard.role.name,
      'facts': dashboard.facts,
      'lastSyncedAt': dashboard.lastSyncedAt.toIso8601String(),
      'tasks': dashboard.tasks
          .map(
            (task) => {
              'id': task.id,
              'title': task.title,
              'subtitle': task.subtitle,
              'action': task.action,
              'kind': task.kind,
            },
          )
          .toList(),
      'notifications': dashboard.notifications
          .map(
            (notification) => {
              'id': notification.id,
              'title': notification.title,
              'subtitle': notification.subtitle,
              'kind': notification.kind,
              'createdAt': notification.createdAt.toIso8601String(),
              'isRead': notification.isRead,
            },
          )
          .toList(),
    };
  }

  static BusinessDashboardData? _businessDashboardFromJson(
    Map<String, dynamic> json,
  ) {
    final roleName = json['role'] as String?;
    final role = UserRole.values
        .where((item) => item.name == roleName)
        .firstOrNull;
    final lastSyncedAt = DateTime.tryParse(
      json['lastSyncedAt'] as String? ?? '',
    );
    if (role == null || lastSyncedAt == null) return null;

    final facts = <String, String>{};
    final rawFacts = json['facts'] as Map<String, dynamic>? ?? const {};
    for (final entry in rawFacts.entries) {
      facts[entry.key] = entry.value.toString();
    }

    final tasks = <BusinessTaskData>[];
    for (final raw in json['tasks'] as List<dynamic>? ?? const []) {
      final task = raw as Map<String, dynamic>;
      final id = task['id'] as String?;
      final title = task['title'] as String?;
      if (id == null || title == null) continue;
      tasks.add(
        BusinessTaskData(
          id: id,
          title: title,
          subtitle: task['subtitle'] as String? ?? '',
          action: task['action'] as String? ?? '확인',
          kind: task['kind'] as String? ?? 'info',
        ),
      );
    }

    final notifications = <BusinessNotificationData>[];
    for (final raw in json['notifications'] as List<dynamic>? ?? const []) {
      final notification = raw as Map<String, dynamic>;
      final id = notification['id'] as String?;
      final title = notification['title'] as String?;
      final createdAt = DateTime.tryParse(
        notification['createdAt'] as String? ?? '',
      );
      if (id == null || title == null || createdAt == null) continue;
      notifications.add(
        BusinessNotificationData(
          id: id,
          title: title,
          subtitle: notification['subtitle'] as String? ?? '',
          kind: notification['kind'] as String? ?? 'info',
          createdAt: createdAt,
          isRead: notification['isRead'] as bool? ?? false,
        ),
      );
    }

    return BusinessDashboardData(
      role: role,
      facts: facts,
      tasks: tasks,
      notifications: notifications,
      lastSyncedAt: lastSyncedAt,
    );
  }
}
