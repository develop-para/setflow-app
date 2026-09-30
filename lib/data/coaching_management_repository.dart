import '../models.dart';

/// 상담과 기록 관리 동의는 별개다. 양쪽이 수락한 연결에만 권한을 준다.
abstract interface class CoachingManagementRepository {
  Future<List<CoachingManagementLink>> listManagementLinks();
  Future<void> requestManagementLink(String consultationId);
  Future<void> respondManagementLink(String linkId, {required bool accept});
  Future<void> endManagementLink(String linkId);
  Future<void> setManagementGym(String linkId, String? gymId);
  Future<void> requestManagementTrainerChange(String linkId, String trainerId);
  Future<ManagedWorkoutPage> listManagedWorkouts(
    String linkId, {
    String? before,
  });
  Future<List<WorkoutCorrection>> listWorkoutCorrections();
  Future<void> proposeWorkoutCorrection({
    required String linkId,
    required ManagedWorkout workout,
    required String exerciseId,
    required int setNumber,
    required WorkoutMetric metric,
    required double value,
    required String reason,
    required String requestId,
  });
  Future<void> respondWorkoutCorrection(
    String correctionId, {
    required bool accept,
  });
}

enum WorkoutMetric {
  weight('무게', 'kg', 0, 999, .5),
  reps('횟수', '회', 1, 1000, 1),
  restSeconds('휴식', '초', 0, 3600, 5),
  durationSeconds('시간', '초', 1, 604800, 1),
  distanceKm('거리', 'km', .01, 999, .01),
  intensityRpe('운동 강도', 'RPE', 1, 10, .5),
  rir('남은 횟수', '회', 0, 10, 1);

  const WorkoutMetric(this.label, this.unit, this.min, this.max, this.step);
  final String label;
  final String unit;
  final double min;
  final double max;
  final double step;

  double read(WorkoutSetEntry set) => switch (this) {
    weight => set.weight,
    reps => set.reps.toDouble(),
    restSeconds => set.restSeconds.toDouble(),
    durationSeconds => set.durationSeconds.toDouble(),
    distanceKm => set.distanceKm,
    intensityRpe => set.intensityRpe,
    rir => (set.rir ?? 0).toDouble(),
  };
}

class CoachingManagementLink {
  const CoachingManagementLink({
    required this.id,
    required this.memberName,
    required this.trainerName,
    required this.status,
    required this.viewerRole,
    required this.canRespond,
    this.gymId,
    this.gymName,
  });
  final String id;
  final String memberName;
  final String trainerName;
  final String status;
  final String viewerRole;
  final bool canRespond;
  final String? gymId;
  final String? gymName;
  bool get isActive => status == 'active';
}

class ManagedWorkout {
  const ManagedWorkout({
    required this.key,
    required this.revision,
    required this.title,
    required this.kind,
    required this.session,
    required this.canPropose,
    required this.requiresApproval,
  });
  final String key;
  final String revision;
  final String title;
  final String kind;
  final WorkoutSession session;
  final bool canPropose;
  final bool requiresApproval;
}

class ManagedWorkoutPage {
  const ManagedWorkoutPage({required this.workouts, this.nextCursor});
  final List<ManagedWorkout> workouts;
  final String? nextCursor;
}

class WorkoutCorrection {
  const WorkoutCorrection({
    required this.id,
    required this.memberName,
    required this.viewerRole,
    required this.recordKey,
    required this.exerciseId,
    required this.correctionKey,
    required this.trainerName,
    required this.workoutTitle,
    required this.date,
    required this.exerciseName,
    required this.setNumber,
    required this.metric,
    required this.before,
    required this.after,
    required this.reason,
    required this.status,
    required this.canRespond,
  });
  final String id;
  final String viewerRole;
  final String recordKey;
  final String exerciseId;
  final String correctionKey;
  final String memberName;
  final String trainerName;
  final String workoutTitle;
  final DateTime date;
  final String exerciseName;
  final int setNumber;
  final WorkoutMetric metric;
  final double? before;
  final double after;
  final String reason;
  final String status;
  final bool canRespond;
}
