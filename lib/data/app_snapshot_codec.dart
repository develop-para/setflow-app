import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import 'app_repository.dart';

abstract final class AppSnapshotCodec {
  // v4: dark athletic rebrand. v5: tri-state theme (system/light/dark) —
  // v4 snapshots keep their explicit choice, pre-v4 land on system.
  static const schemaVersion = 5;

  static ThemeMode _themeModeFromName(String? name) {
    return switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String encode(AppSnapshot snapshot) {
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'preferences': {
        'role': snapshot.role.name,
        'themeMode': snapshot.themeMode.name,
        'weightUnit': snapshot.weightUnit,
        'restDefaultSeconds': snapshot.restDefaultSeconds,
      },
      'sessions': snapshot.sessions.values.map(_sessionToJson).toList(),
      'routines': snapshot.routines.map(_routineToJson).toList(),
      'communityPosts': snapshot.communityPosts.map(_postToJson).toList(),
      'consultations': snapshot.consultations.map(_consultationToJson).toList(),
      'businessDashboards': snapshot.businessDashboards.values
          .map(_businessDashboardToJson)
          .toList(),
    });
  }

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
        // v5+ stores an explicit themeMode; v4 stored a bool (respect it);
        // pre-v4 predates the choice entirely, so fall back to system.
        themeMode: version >= 5
            ? _themeModeFromName(preferences['themeMode'] as String?)
            : version == 4
            ? ((preferences['isDarkMode'] as bool? ?? true)
                  ? ThemeMode.dark
                  : ThemeMode.light)
            : ThemeMode.system,
        weightUnit: preferences['weightUnit'] as String? ?? 'kg',
        restDefaultSeconds:
            (preferences['restDefaultSeconds'] as num?)?.toInt() ?? 90,
        sessions: sessions,
        routines: routines,
        communityPosts: posts,
        consultations: consultations,
        businessDashboards: businessDashboards,
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
