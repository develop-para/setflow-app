import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'app_snapshot_codec.dart';
import 'coaching_workout_repository.dart';
import 'exercise_catalog.dart';

class SupabaseCoachingWorkoutRepository implements CoachingWorkoutRepository {
  SupabaseCoachingWorkoutRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CoachingWorkout> openLessonWorkout(String scheduleId) async =>
      _workout(
        await _client.rpc(
          'open_lesson_workout',
          params: {'schedule_id': scheduleId},
        ),
      );

  @override
  Future<void> setLessonRecordingConsent(
    String scheduleId,
    bool allowed,
  ) async {
    await _client.rpc(
      'set_lesson_recording_consent',
      params: {'schedule_id': scheduleId, 'allowed': allowed},
    );
  }

  @override
  Future<List<CoachingWorkout>> listCoachingWorkouts({
    String? memberUserId,
  }) async {
    final result = await _client.rpc(
      'list_coaching_workouts',
      params: {'member_user_id': ?memberUserId},
    );
    if (result is! List) throw const FormatException('운동 목록 형식이 올바르지 않아요.');
    return result.map(_workout).toList(growable: false);
  }

  @override
  Future<CoachingWorkout> createWorkoutAssignment({
    required String memberUserId,
    required DateTime date,
    required String title,
    required String instruction,
    required WorkoutSession session,
    required String requestId,
  }) async => _workout(
    await _client.rpc(
      'create_workout_assignment',
      params: {
        'member_user_id': memberUserId,
        'date': _date(date),
        'title': title,
        'instruction': instruction,
        'session': AppSnapshotCodec.sessionToJson(session),
        'request_id': requestId,
      },
    ),
  );

  @override
  Future<CoachingWorkout> saveCoachingWorkout({
    required String workoutId,
    required int expectedVersion,
    required WorkoutSession session,
    required String requestId,
  }) async => _workout(
    await _client.rpc(
      'save_coaching_workout',
      params: {
        'workout_id': workoutId,
        'expected_version': expectedVersion,
        'session': AppSnapshotCodec.sessionToJson(session),
        'request_id': requestId,
      },
    ),
  );

  @override
  Future<CoachingWorkout> cancelWorkoutAssignment({
    required String workoutId,
    required int expectedVersion,
    required String requestId,
  }) async => _workout(
    await _client.rpc(
      'cancel_workout_assignment',
      params: {
        'workout_id': workoutId,
        'expected_version': expectedVersion,
        'request_id': requestId,
      },
    ),
  );

  @override
  Future<CoachingReminderPreferences> loadMyCoachingReminder() async =>
      _reminder(await _client.rpc('get_my_coaching_reminder'));

  @override
  Future<CoachingReminderPreferences> setMyCoachingReminder(
    bool enabled,
    int hour,
  ) async => _reminder(
    await _client.rpc(
      'set_my_coaching_reminder',
      params: {'enabled': enabled, 'hour': hour},
    ),
  );

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const FormatException('운동 정보 형식이 올바르지 않아요.');
    return Map<String, dynamic>.from(value);
  }

  static CoachingReminderPreferences _reminder(Object? value) {
    final row = _object(value);
    return CoachingReminderPreferences(
      enabled: row['enabled'] == true,
      hour: (row['hour'] as num).toInt(),
    );
  }

  static CoachingWorkout _workout(Object? value) {
    final row = _object(value);
    final session = AppSnapshotCodec.sessionFromJson(
      _object(row['session']),
      exerciseCatalog,
    );
    if (session == null) throw const FormatException('운동 기록을 읽을 수 없어요.');
    DateTime? time(String key) =>
        row[key] == null ? null : DateTime.parse(row[key] as String);
    return CoachingWorkout(
      id: row['id'] as String,
      kind: switch (row['kind']) {
        'lesson' => CoachingWorkoutKind.lesson,
        'assignment' => CoachingWorkoutKind.assignment,
        _ => throw const FormatException('알 수 없는 운동 유형이에요.'),
      },
      status: switch (row['status']) {
        'assigned' => CoachingWorkoutStatus.assigned,
        'in_progress' => CoachingWorkoutStatus.inProgress,
        'completed' => CoachingWorkoutStatus.completed,
        'cancelled' => CoachingWorkoutStatus.cancelled,
        _ => throw const FormatException('알 수 없는 운동 상태예요.'),
      },
      trainerId: row['trainer_id'] as String,
      memberUserId: row['member_user_id'] as String,
      trainerName: row['trainer_name'] as String? ?? '트레이너',
      memberName: row['member_name'] as String? ?? '회원',
      title: row['title'] as String,
      instruction: row['instruction'] as String? ?? '',
      date: DateTime.parse(row['date'] as String),
      session: session,
      version: (row['version'] as num).toInt(),
      canEdit: row['can_edit'] == true,
      recordingAllowed: row['recording_allowed'] == true,
      scheduleId: row['schedule_id'] as String?,
      startsAt: time('starts_at'),
      endsAt: time('ends_at'),
      editBlockedReason: row['edit_blocked_reason'] as String?,
      updatedAt: time('updated_at'),
      lastEditorName: row['last_editor_name'] as String?,
    );
  }
}
