import 'package:flutter/material.dart';

enum UserRole { guest, member, trainer, gym, admin }

/// The two product surfaces the header switcher toggles between. A portal is
/// not a page: each one owns its own shell, navigation bar and home, so
/// switching runs a full-screen brand transition instead of a route push.
/// [trainer] hosts every pro role (trainer / gym / admin); [client] hosts the
/// signed-out guest and the member.
enum AppPortal { client, trainer }

enum RoutineAccessTier {
  free,
  paid;

  String get label => switch (this) {
    free => '무료',
    paid => '유료',
  };
}

enum RoutineAuthorType { trainer, gym, system }

enum TrainingExperienceLevel {
  beginner,
  intermediate,
  advanced;

  String get label => switch (this) {
    beginner => '입문 · 1년 미만',
    intermediate => '중급 · 1~3년',
    advanced => '숙련 · 3년 이상',
  };
}

enum TrainingEquipment {
  bodyweight,
  dumbbells,
  barbell,
  bench,
  squatRack,
  cableStation,
  machines,
  pullupBar,
  dipBars,
  abWheel,
  jumpRope,
  treadmill,
  stationaryBike,
  stairClimber,
  rowingMachine,
  elliptical;

  String get label => switch (this) {
    bodyweight => '맨몸 · 운동 공간',
    dumbbells => '덤벨',
    barbell => '바벨 · 원판',
    bench => '벤치 · 벤치프레스대',
    squatRack => '스쿼트 · 파워 랙',
    cableStation => '케이블',
    machines => '일반 웨이트 머신 구역',
    pullupBar => '풀업 바',
    dipBars => '딥스 바',
    abWheel => 'AB 휠',
    jumpRope => '줄넘기',
    treadmill => '트레드밀',
    stationaryBike => '실내 자전거',
    stairClimber => '스텝밀 · 계단 기구',
    rowingMachine => '로잉 머신',
    elliptical => '일립티컬',
  };
}

enum TrainingPainRegion {
  shoulder,
  elbowWrist,
  neckUpperBack,
  lowerBack,
  hip,
  knee,
  ankleFoot,
  other;

  String get label => switch (this) {
    shoulder => '어깨',
    elbowWrist => '팔꿈치 · 손목',
    neckUpperBack => '목 · 등 상부',
    lowerBack => '허리',
    hip => '고관절',
    knee => '무릎',
    ankleFoot => '발목 · 발',
    other => '기타',
  };
}

/// Movements the member has explicitly chosen to avoid.
///
/// These are user-provided constraints, not diagnoses inferred from a painful
/// body region. The recommender only filters against these explicit choices.
enum TrainingMovementRestriction {
  horizontalPress,
  overheadPress,
  shoulderRaise,
  verticalPull,
  rowing,
  squatLunge,
  hipHinge,
  impact,
  trunkFlexionRotation;

  String get label => switch (this) {
    horizontalPress => '가슴 밀기 · 푸시업',
    overheadPress => '머리 위로 밀기',
    shoulderRaise => '어깨 레이즈 · 업라이트 로우',
    verticalPull => '위에서 당기기 · 매달리기',
    rowing => '로우 · 노젓기',
    squatLunge => '스쿼트 · 런지',
    hipHinge => '힙힌지 · 데드리프트',
    impact => '달리기 · 점프 충격',
    trunkFlexionRotation => '몸통 굽힘 · 회전',
  };
}

enum TrainingRecoveryStatus {
  recovered,
  normal,
  fatigued;

  String get label => switch (this) {
    recovered => '충분히 회복됨',
    normal => '보통',
    fatigued => '피로 · 수면 부족',
  };
}

/// Account-scoped answers used to constrain automatic exercise suggestions.
///
/// Recovery is deliberately dated: stale readiness must not keep changing
/// future prescriptions. Injury/pain answers are informational; only
/// [restrictedMovements] are used as hard movement exclusions.
class RecommendationProfile {
  RecommendationProfile({
    required this.experienceLevel,
    required Iterable<TrainingEquipment> availableEquipment,
    required Iterable<TrainingPainRegion> painRegions,
    required this.painLevel,
    required Iterable<TrainingMovementRestriction> restrictedMovements,
    required String injuryNote,
    required this.recoveryStatus,
    required this.recoveryRecordedAt,
    required this.updatedAt,
  }) : availableEquipment = Set.unmodifiable(availableEquipment),
       painRegions = Set.unmodifiable(painRegions),
       restrictedMovements = Set.unmodifiable(restrictedMovements),
       injuryNote = injuryNote.trim() {
    if (this.availableEquipment.isEmpty) {
      throw ArgumentError.value(
        availableEquipment,
        'availableEquipment',
        'At least one equipment option is required.',
      );
    }
    if (painLevel < 0 || painLevel > 10) {
      throw RangeError.range(painLevel, 0, 10, 'painLevel');
    }
    if (this.painRegions.isEmpty && painLevel != 0) {
      throw ArgumentError.value(
        painLevel,
        'painLevel',
        'Pain level must be zero when no pain region is selected.',
      );
    }
    if (this.injuryNote.length > 500) {
      throw ArgumentError.value(
        this.injuryNote,
        'injuryNote',
        'Must not exceed 500 characters.',
      );
    }
  }

  static const schemaVersion = 1;

  final TrainingExperienceLevel experienceLevel;
  final Set<TrainingEquipment> availableEquipment;
  final Set<TrainingPainRegion> painRegions;
  final int painLevel;
  final Set<TrainingMovementRestriction> restrictedMovements;
  final String injuryNote;
  final TrainingRecoveryStatus recoveryStatus;
  final DateTime recoveryRecordedAt;
  final DateTime updatedAt;

  /// Severe self-reported pain is a stop signal for automated suggestions.
  /// The threshold is a conservative product rule, not a diagnosis.
  bool get shouldPauseAutomaticRecommendation => painLevel >= 7;

  bool hasRecoveryFor(DateTime date) {
    final recorded = recoveryRecordedAt.toLocal();
    final target = date.toLocal();
    return recorded.year == target.year &&
        recorded.month == target.month &&
        recorded.day == target.day;
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'experienceLevel': experienceLevel.name,
    'availableEquipment': _sortedEnumNames(availableEquipment),
    'painRegions': _sortedEnumNames(painRegions),
    'painLevel': painLevel,
    'restrictedMovements': _sortedEnumNames(restrictedMovements),
    'injuryNote': injuryNote,
    'recoveryStatus': recoveryStatus.name,
    'recoveryRecordedAt': recoveryRecordedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static RecommendationProfile? tryFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final json = Map<String, dynamic>.from(value);
      if (json['schemaVersion'] is! int ||
          json['schemaVersion'] != schemaVersion) {
        return null;
      }
      final experience = _enumByName(
        TrainingExperienceLevel.values,
        json['experienceLevel'],
      );
      final equipment = _enumSet(
        TrainingEquipment.values,
        json['availableEquipment'],
      );
      final painRegions = _enumSet(
        TrainingPainRegion.values,
        json['painRegions'],
      );
      final restrictions = _enumSet(
        TrainingMovementRestriction.values,
        json['restrictedMovements'],
      );
      final recovery = _enumByName(
        TrainingRecoveryStatus.values,
        json['recoveryStatus'],
      );
      final rawPainLevel = json['painLevel'];
      final painLevel = rawPainLevel is int ? rawPainLevel : null;
      final injuryNote = json['injuryNote'] as String?;
      final recoveryRecordedAt = DateTime.tryParse(
        json['recoveryRecordedAt'] as String? ?? '',
      );
      final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
      if (experience == null ||
          equipment == null ||
          equipment.isEmpty ||
          equipment.length > TrainingEquipment.values.length ||
          painRegions == null ||
          painRegions.length > TrainingPainRegion.values.length ||
          restrictions == null ||
          restrictions.length > TrainingMovementRestriction.values.length ||
          recovery == null ||
          painLevel == null ||
          painLevel < 0 ||
          painLevel > 10 ||
          (painRegions.isEmpty && painLevel != 0) ||
          injuryNote == null ||
          injuryNote.length > 500 ||
          recoveryRecordedAt == null ||
          updatedAt == null) {
        return null;
      }
      return RecommendationProfile(
        experienceLevel: experience,
        availableEquipment: equipment,
        painRegions: painRegions,
        painLevel: painLevel,
        restrictedMovements: restrictions,
        injuryNote: injuryNote,
        recoveryStatus: recovery,
        recoveryRecordedAt: recoveryRecordedAt,
        updatedAt: updatedAt,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static List<String> _sortedEnumNames(Iterable<Enum> values) {
    final names = values.map((value) => value.name).toList()..sort();
    return names;
  }

  static T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static Set<T>? _enumSet<T extends Enum>(Iterable<T> values, Object? raw) {
    if (raw is! List || raw.length > values.length) return null;
    final result = <T>{};
    for (final name in raw) {
      final value = _enumByName(values, name);
      if (value == null || !result.add(value)) return null;
    }
    return result;
  }
}

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

  bool get isCardio => muscle == '유산소';
}

IconData exerciseIconForMuscle(String muscle) => switch (muscle) {
  '가슴' => Icons.fitness_center_rounded,
  '등' => Icons.rowing_rounded,
  '어깨' => Icons.accessibility_new_rounded,
  '하체' => Icons.directions_walk_rounded,
  '팔' => Icons.sports_gymnastics_rounded,
  '복근' => Icons.self_improvement_rounded,
  '유산소' => Icons.directions_run_rounded,
  _ => Icons.fitness_center_rounded,
};

class WorkoutSetEntry {
  WorkoutSetEntry({
    required this.number,
    required this.weight,
    required this.reps,
    this.completed = false,
    this.type = '일반',
    this.restSeconds = 90,
    this.durationSeconds = 0,
    this.distanceKm = 0,
    this.intensityRpe = 0,
  });

  int number;
  double weight;
  int reps;
  bool completed;
  String type;
  int restSeconds;
  int durationSeconds;
  double distanceKm;
  double intensityRpe;

  double get volume => completed ? weight * reps : 0;

  WorkoutSetEntry copy() => WorkoutSetEntry(
    number: number,
    weight: weight,
    reps: reps,
    completed: false,
    type: type,
    restSeconds: restSeconds,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    intensityRpe: intensityRpe,
  );
}

String workoutSetTypeLabel(String value) =>
    switch (value.trim().toLowerCase()) {
      'warmup' || '웜업' => '웜업',
      'drop' || '드랍' => '드랍',
      'failure' || '실패' => '실패',
      _ => '일반',
    };

String workoutSetTypeDatabaseValue(String value) =>
    switch (workoutSetTypeLabel(value)) {
      '웜업' => 'warmup',
      '드랍' => 'drop',
      '실패' => 'failure',
      _ => 'normal',
    };

class RoutineSetPlan {
  const RoutineSetPlan({
    required this.number,
    required this.weight,
    required this.reps,
    this.type = '일반',
    this.restSeconds = 90,
    this.durationSeconds = 0,
    this.distanceKm = 0,
    this.intensityRpe = 0,
  });

  final int number;
  final double weight;
  final int reps;
  final String type;
  final int restSeconds;
  final int durationSeconds;
  final double distanceKm;
  final double intensityRpe;

  WorkoutSetEntry toWorkoutSetEntry() => WorkoutSetEntry(
    number: number,
    weight: weight,
    reps: reps,
    type: type,
    restSeconds: restSeconds,
    durationSeconds: durationSeconds,
    distanceKm: distanceKm,
    intensityRpe: intensityRpe,
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
  int get cardioDurationSeconds => exercises
      .where((exercise) => exercise.template.isCardio)
      .fold(
        0,
        (sum, exercise) =>
            sum +
            exercise.sets
                .where((set) => set.completed)
                .fold(0, (seconds, set) => seconds + set.durationSeconds),
      );
  bool get hasCardio => exercises.any((exercise) => exercise.template.isCardio);
  bool get hasResistance =>
      exercises.any((exercise) => !exercise.template.isCardio);
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
    this.accessTier = RoutineAccessTier.free,
    this.setPlans = const {},
    this.sourceMarketRoutineId,
    this.sourceCoachingRoutineId,
    this.authorTrainerId,
    this.authorGymId,
    this.authorType = RoutineAuthorType.system,
  });

  final String id;
  final String name;
  final String description;
  final Color color;
  final List<ExerciseTemplate> exercises;
  final String author;
  final String level;
  final RoutineAccessTier accessTier;
  final Map<String, List<RoutineSetPlan>> setPlans;
  final String? sourceMarketRoutineId;
  final String? sourceCoachingRoutineId;
  final String? authorTrainerId;
  final String? authorGymId;
  final RoutineAuthorType authorType;

  bool get isPaid => accessTier == RoutineAccessTier.paid;

  List<RoutineSetPlan> setsFor(ExerciseTemplate exercise) =>
      setPlans[exercise.id] ?? const [];
}

class PostComment {
  PostComment({
    required this.id,
    required this.author,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String author;
  final String content;
  final DateTime createdAt;
}

class CommunityPost {
  CommunityPost({
    required this.id,
    required this.author,
    required this.content,
    required this.metric,
    required this.createdAt,
    required this.visualKey,
    required this.color,
    this.likes = 0,
    this.isLiked = false,
    this.isMine = false,
    this.imageUrl,
    this.location,
    this.routineName,
    this.activeOverlays = const [],
    List<PostComment>? comments,
  }) : comments = comments ?? [];

  final String id;
  final String author;
  final String content;
  final String metric;
  final DateTime createdAt;
  final String visualKey;
  final Color color;
  int likes;
  bool isLiked;
  final bool isMine;
  final String? imageUrl;
  final String? location;
  final String? routineName;
  final List<String> activeOverlays;
  final List<PostComment> comments;

  IconData get icon => switch (visualKey) {
    'streak' => Icons.local_fire_department_rounded,
    'tip' => Icons.lightbulb_rounded,
    'strength' => Icons.fitness_center_rounded,
    _ => Icons.emoji_events_rounded,
  };
}

enum ConsultationStatus { waiting, answered, coaching }

class ConsultationData {
  ConsultationData({
    required this.id,
    required this.trainerName,
    required this.specialty,
    required this.goal,
    required this.level,
    required this.question,
    required this.createdAt,
    this.status = ConsultationStatus.waiting,
    this.response,
    this.rating,
    this.sharedRecommendationProfile,
    this.recommendationProfileShareRevokedAt,
  });

  final String id;
  final String trainerName;
  final String specialty;
  final String goal;
  final String level;
  final String question;
  final DateTime createdAt;
  ConsultationStatus status;
  String? response;
  int? rating;
  final RecommendationProfile? sharedRecommendationProfile;
  DateTime? recommendationProfileShareRevokedAt;
}

class BusinessTaskData {
  BusinessTaskData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.kind,
  });

  final String id;
  final String title;
  final String subtitle;
  final String action;
  final String kind;
}

class BusinessNotificationData {
  BusinessNotificationData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.createdAt,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String kind;
  final DateTime createdAt;
  bool isRead;
}

class BusinessDashboardData {
  BusinessDashboardData({
    required this.role,
    required this.facts,
    required this.tasks,
    required this.notifications,
    required this.lastSyncedAt,
  });

  final UserRole role;
  final Map<String, String> facts;
  final List<BusinessTaskData> tasks;
  final List<BusinessNotificationData> notifications;
  DateTime lastSyncedAt;
}

enum RoutineImportResult {
  imported,
  alreadySaved,
  limitReached,
  paidPlanRequired,
}
