import '../models.dart';

enum CoachingWorkoutKind { lesson, assignment }

enum CoachingWorkoutStatus { assigned, inProgress, completed, cancelled }

/// 개인 스냅샷과 독립된 원본. 회원 일지에는 읽기 전용으로 합쳐 표시한다.
class CoachingWorkout {
  const CoachingWorkout({
    required this.id,
    required this.kind,
    required this.status,
    required this.trainerId,
    required this.memberUserId,
    required this.trainerName,
    required this.memberName,
    required this.title,
    required this.instruction,
    required this.date,
    required this.session,
    required this.version,
    required this.canEdit,
    required this.recordingAllowed,
    this.scheduleId,
    this.startsAt,
    this.endsAt,
    this.editBlockedReason,
    this.updatedAt,
    this.lastEditorName,
  });

  final String id;
  final CoachingWorkoutKind kind;
  final CoachingWorkoutStatus status;
  final String trainerId;
  final String memberUserId;
  final String trainerName;
  final String memberName;
  final String title;
  final String instruction;
  final DateTime date;
  final WorkoutSession session;
  final int version;
  final bool canEdit;
  final bool recordingAllowed;
  final String? scheduleId;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? editBlockedReason;
  final DateTime? updatedAt;
  final String? lastEditorName;

  bool get isCancelled => status == CoachingWorkoutStatus.cancelled;
}

class CoachingReminderPreferences {
  const CoachingReminderPreferences({
    required this.enabled,
    required this.hour,
  });
  final bool enabled;

  /// 한국 시각, 6~22시. 회원이 직접 켠 경우에만 하루 한 번 발송한다.
  final int hour;
}

abstract interface class CoachingWorkoutRepository {
  Future<CoachingWorkout> openLessonWorkout(String scheduleId);
  Future<void> setLessonRecordingConsent(String scheduleId, bool allowed);
  Future<List<CoachingWorkout>> listCoachingWorkouts({String? memberUserId});
  Future<CoachingWorkout> createWorkoutAssignment({
    required String memberUserId,
    required DateTime date,
    required String title,
    required String instruction,
    required WorkoutSession session,
    required String requestId,
  });
  Future<CoachingWorkout> saveCoachingWorkout({
    required String workoutId,
    required int expectedVersion,
    required WorkoutSession session,
    required String requestId,
  });
  Future<CoachingWorkout> cancelWorkoutAssignment({
    required String workoutId,
    required int expectedVersion,
    required String requestId,
  });
  Future<CoachingReminderPreferences> loadMyCoachingReminder();
  Future<CoachingReminderPreferences> setMyCoachingReminder(
    bool enabled,
    int hour,
  );
}
