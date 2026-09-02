import 'dart:math' as math;

import 'package:flutter/material.dart';

enum UserRole { guest, member, trainer, gym, admin }

/// 위경도 한 점. 근처 공개방을 찾는 데만 쓴다.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// 두 점 사이 거리(미터). 하버사인 — 서버(`list_nearby_training_parties`)와
  /// 같은 식이라 메모리 백엔드의 목록도 같은 순서로 나온다.
  double distanceTo(GeoPoint other) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(other.lat - lat);
    final dLng = rad(other.lng - lng);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) *
            math.cos(rad(other.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

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

/// 세트 하나를 무엇으로 재는가. 근력은 무게×횟수지만, 맨몸운동은 무게가
/// 없고(푸시업은 횟수만), 플랭크류는 횟수조차 없다(버티는 시간이 기록이다).
/// 가짜 0kg을 타이핑하게 두는 대신 종목이 자기 측정 방식을 선언한다.
/// 추정 1RM을 어느 공식으로 낼지. 둘은 반복수에 따라 갈린다 — Brzycki는
/// 저반복(1~6회)에서, Epley는 고반복에서 더 잘 맞는다고 알려져 있고, 기본값인
/// 평균은 한쪽으로 치우치지 않는 대신 어느 쪽도 아니다. 어느 것이 옳다고
/// 단정할 수 없으므로 고르게 두되, 고르지 않은 사람에게는 평균을 준다.
enum OneRepMaxFormula { average, epley, brzycki }

extension OneRepMaxFormulaLabel on OneRepMaxFormula {
  String get label => switch (this) {
    OneRepMaxFormula.average => 'Epley · Brzycki 평균',
    OneRepMaxFormula.epley => 'Epley',
    OneRepMaxFormula.brzycki => 'Brzycki',
  };

  String get description => switch (this) {
    OneRepMaxFormula.average => '두 공식의 중간값. 반복수 구간을 가리지 않아요.',
    OneRepMaxFormula.epley => '무게 × (1 + 횟수/30). 고반복에서 조금 더 높게 나와요.',
    OneRepMaxFormula.brzycki => '무게 × 36 / (37 − 횟수). 저반복에서 널리 쓰여요.',
  };

  /// 스냅샷에 남기는 값. 이름이 바뀌어도 저장된 것이 안 깨지도록 고정한다.
  String get storageKey => switch (this) {
    OneRepMaxFormula.average => 'average',
    OneRepMaxFormula.epley => 'epley',
    OneRepMaxFormula.brzycki => 'brzycki',
  };
}

OneRepMaxFormula oneRepMaxFormulaFromStorage(String? key) => switch (key) {
  'epley' => OneRepMaxFormula.epley,
  'brzycki' => OneRepMaxFormula.brzycki,
  _ => OneRepMaxFormula.average,
};

enum ExerciseMeasurement {
  /// 무게 × 횟수 — 바벨·덤벨·머신.
  weightReps,

  /// 횟수만 — 푸시업·풀업처럼 몸이 곧 중량인 운동.
  repsOnly,

  /// 시간만 — 플랭크·월싯처럼 버티는 운동.
  duration,
}

class ExerciseTemplate {
  const ExerciseTemplate({
    required this.id,
    required this.name,
    required this.muscle,
    required this.icon,
    this.measurement = ExerciseMeasurement.weightReps,
    this.nameEnglish,
    this.equipmentKey,
    this.equipmentName,
    this.aliases = const [],
    this.difficulty,
    this.category,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.sourceName,
    this.sourceId,
    this.databaseId,
  });

  final String id;
  final String name;
  final String muscle;
  final IconData icon;
  final ExerciseMeasurement measurement;
  final String? nameEnglish;
  final String? equipmentKey;
  final String? equipmentName;
  final List<String> aliases;
  final String? difficulty;
  final String? category;

  /// Stable source muscle keys (for example `chest`, `triceps`). The UI maps
  /// these domain values to Korean labels and to the licensed body atlas; no
  /// package-specific anatomy type leaves the presentation adapter.
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final String? sourceName;
  final String? sourceId;

  /// UUID used by normalized backend routine tables. [id] stays the stable
  /// app/domain ID when a database row maps to an original bundled exercise.
  final String? databaseId;

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
    r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  String? get databaseReferenceId {
    final explicit = databaseId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return _uuidPattern.hasMatch(id) ? id : null;
  }

  bool get isCardio => muscle == '유산소';

  /// 세트 편집에 무게 다이얼이 있는가.
  bool get usesWeight =>
      !isCardio && measurement == ExerciseMeasurement.weightReps;

  bool get isRepsOnly => measurement == ExerciseMeasurement.repsOnly;
  bool get isDurationHold => measurement == ExerciseMeasurement.duration;

  bool referencesId(String? value) =>
      value != null && (id == value || databaseId == value);

  /// Stable equipment facet used by the catalog picker.
  ///
  /// The 80 built-in fallback rows predate the database metadata, so their
  /// facet is inferred conservatively from the visible name. Database rows
  /// always carry [equipmentKey] and do not use this fallback.
  String get resolvedEquipmentKey {
    final explicit = equipmentKey?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final value = name.toLowerCase();
    if (value.contains('덤벨')) return 'dumbbell';
    if (value.contains('바벨')) return 'barbell';
    if (value.contains('이지바') || value.contains('ez')) {
      return 'ez_curl_bar';
    }
    if (value.contains('케이블')) return 'cable';
    if (value.contains('케틀벨')) return 'kettlebell';
    if (value.contains('밴드')) return 'bands';
    if (value.contains('로잉 머신')) return 'rowing_machine';
    if (value.contains('머신') || value.contains('레그 프레스')) {
      return 'machine';
    }
    if (value.contains('트레드밀')) return 'treadmill';
    if (value.contains('자전거')) return 'stationary_bike';
    if (value.contains('스텝밀')) return 'stair_climber';
    if (value.contains('일립티컬')) return 'elliptical';
    if (value.contains('줄넘기')) return 'jump_rope';
    if (value.contains('풀업') || value.contains('친업')) return 'pullup_bar';
    if (value.contains('딥스')) return 'dip_bars';
    if (value.contains('ab 롤') || value.contains('휠')) return 'ab_wheel';
    if (value.contains('맨몸') || measurement != ExerciseMeasurement.weightReps) {
      return 'body_only';
    }
    return 'unspecified';
  }

  String get resolvedEquipmentName {
    final explicit = equipmentName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return switch (resolvedEquipmentKey) {
      'body_only' => '맨몸',
      'bands' => '밴드',
      'barbell' => '바벨',
      'bench' => '벤치',
      'cable' => '케이블',
      'dumbbell' => '덤벨',
      'ez_curl_bar' => '이지바',
      'exercise_ball' => '짐볼',
      'foam_roll' => '폼롤러',
      'kettlebell' => '케틀벨',
      'machine' => '머신',
      'medicine_ball' => '메디신볼',
      'squat_rack' => '스쿼트 랙',
      'pullup_bar' => '풀업 바',
      'dip_bars' => '딥스 바',
      'ab_wheel' => 'AB 휠',
      'jump_rope' => '줄넘기',
      'treadmill' => '트레드밀',
      'stationary_bike' => '실내 자전거',
      'stair_climber' => '스텝밀',
      'rowing_machine' => '로잉 머신',
      'elliptical' => '일립티컬',
      'other' => '기타 기구',
      _ => '기구 미지정',
    };
  }

  String get searchableText => [
    name,
    ?nameEnglish,
    muscle,
    resolvedEquipmentName,
    resolvedEquipmentKey,
    ...aliases,
  ].join(' ').toLowerCase();

  /// Each word may match a different facet, so `가슴 덤벨` finds every
  /// dumbbell chest movement even when those words are not adjacent.
  bool matchesCatalogQuery(String rawQuery) {
    final terms = rawQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    final haystack = searchableText;
    final compactHaystack = haystack.replaceAll(RegExp(r'[\s\-_/().]+'), '');
    return terms.every((term) {
      if (haystack.contains(term)) return true;
      final compactTerm = term.replaceAll(RegExp(r'[\s\-_/().]+'), '');
      return compactTerm.isNotEmpty && compactHaystack.contains(compactTerm);
    });
  }
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
    this.rir,
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

  /// Reps In Reserve — 이 세트 뒤에 몇 회를 더 할 수 있었는지. null은 "적지
  /// 않음"이고 0과 다르다: 0은 실패 직전까지 갔다는 뜻이라 실제 기록이다.
  /// 설정에서 RIR 입력을 켠 사용자만 채운다.
  int? rir;

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
    rir: rir,
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
  WorkoutSession({
    required this.date,
    required this.exercises,
    this.startedAt,
    this.endedAt,
  });

  final DateTime date;
  final List<WorkoutExercise> exercises;

  /// 첫 세트를 완료한 순간과 마지막 세트를 완료한 순간. "몇 시간 몇 분
  /// 운동했나"는 계획이 아니라 이 두 도장 사이의 시간이다. 세트를 되돌려도
  /// [startedAt]은 남는다 — 운동을 시작했다는 사실은 취소되지 않는다.
  DateTime? startedAt;
  DateTime? endedAt;

  Duration? elapsedUntil(DateTime now) {
    final start = startedAt;
    if (start == null) return null;
    final end = isComplete ? (endedAt ?? now) : now;
    final elapsed = end.difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

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
  bool get isComplete => totalSets > 0 && completedSets == totalSets;
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

  /// 대표 아이콘을 고르지 않은 루틴의 색. 부위 면 색(SetflowMuscleFill)과
  /// 겹치지 않아야 한다 — 역매핑이 실패해야 화면이 부위 자동 판정으로 간다.
  static const defaultColor = Color(0xFF3B82F6);

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
    this.consultationMode = '온라인 상담',
    this.consultationLocation,
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
  final String consultationMode;
  final String? consultationLocation;
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
