/// 추천의 영구 제외와 직접 선택한 날짜. 추천을 수락한 횟수는 선호로 세지 않는다.
class RecommendationPreferences {
  const RecommendationPreferences({
    this.excludedExerciseIds = const {},
    this.manualSelectionDays = const {},
    this.personalCoachingEnabled = false,
    this.plannedTrainingDays = 3,
  });

  final Set<String> excludedExerciseIds;
  final Map<String, List<DateTime>> manualSelectionDays;
  final bool personalCoachingEnabled;
  final int plannedTrainingDays;

  RecommendationPreferences withCoaching({bool? enabled, int? trainingDays}) {
    if (trainingDays != null && (trainingDays < 1 || trainingDays > 7)) {
      throw RangeError.range(trainingDays, 1, 7, 'trainingDays');
    }
    return RecommendationPreferences(
      excludedExerciseIds: excludedExerciseIds,
      manualSelectionDays: manualSelectionDays,
      personalCoachingEnabled: enabled ?? personalCoachingEnabled,
      plannedTrainingDays: trainingDays ?? plannedTrainingDays,
    );
  }

  RecommendationPreferences exclude(String id, bool excluded) =>
      RecommendationPreferences(
        excludedExerciseIds: Set.unmodifiable({
          ...excludedExerciseIds.where((item) => item != id),
          if (excluded) id,
        }),
        manualSelectionDays: manualSelectionDays,
        personalCoachingEnabled: personalCoachingEnabled,
        plannedTrainingDays: plannedTrainingDays,
      );

  RecommendationPreferences recordSelection(String id, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final days = <DateTime>{...?manualSelectionDays[id], day}.toList()..sort();
    return RecommendationPreferences(
      excludedExerciseIds: excludedExerciseIds,
      personalCoachingEnabled: personalCoachingEnabled,
      plannedTrainingDays: plannedTrainingDays,
      manualSelectionDays: Map<String, List<DateTime>>.unmodifiable({
        ...manualSelectionDays,
        id: List<DateTime>.unmodifiable(
          days.skip(days.length > 8 ? days.length - 8 : 0),
        ),
      }),
    );
  }

  int preferenceFor(String id, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return (manualSelectionDays[id] ?? const []).where((selected) {
      final age = day.difference(selected).inDays;
      return age >= 0 && age <= 90;
    }).length;
  }

  Map<String, Object?> toJson() => {
    'personalCoachingEnabled': personalCoachingEnabled,
    'plannedTrainingDays': plannedTrainingDays,
    'excludedExerciseIds': excludedExerciseIds.toList()..sort(),
    'manualSelectionDays': {
      for (final entry in manualSelectionDays.entries)
        entry.key: entry.value.map((day) => day.toIso8601String()).toList(),
    },
  };

  static RecommendationPreferences fromJson(Object? value) {
    if (value is! Map) return const RecommendationPreferences();
    final rawDays = value['manualSelectionDays'];
    var result = RecommendationPreferences(
      personalCoachingEnabled: value['personalCoachingEnabled'] == true,
      plannedTrainingDays:
          value['plannedTrainingDays'] is int &&
              (value['plannedTrainingDays'] as int) >= 1 &&
              (value['plannedTrainingDays'] as int) <= 7
          ? value['plannedTrainingDays'] as int
          : 3,
      excludedExerciseIds: Set.unmodifiable(
        value['excludedExerciseIds'] is List
            ? (value['excludedExerciseIds'] as List).whereType<String>()
            : <String>[],
      ),
    );
    if (rawDays is Map) {
      for (final entry in rawDays.entries) {
        if (entry.key is! String || entry.value is! List) continue;
        for (final raw in (entry.value as List).whereType<String>()) {
          final date = DateTime.tryParse(raw);
          if (date != null) result = result.recordSelection(entry.key, date);
        }
      }
    }
    return result;
  }
}
