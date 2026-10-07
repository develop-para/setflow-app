import 'app_snapshot_codec.dart';
import 'coaching_management_repository.dart';
import 'exercise_catalog.dart';

mixin SupabaseCoachingManagement on Object
    implements CoachingManagementRepository {
  Future<dynamic> managementRpc(String name, {Map<String, dynamic>? params});

  static Map<String, dynamic> _object(Object? value) =>
      Map<String, dynamic>.from(value as Map);

  @override
  Future<List<CoachingManagementLink>> listManagementLinks({
    required CoachingManagementRole role,
  }) async {
    final rows = await managementRpc('list_management_links') as List;
    return rows
        .map((value) {
          final row = _object(value);
          return CoachingManagementLink(
            id: row['id'] as String,
            memberName: row['member_name'] as String,
            trainerName: row['trainer_name'] as String,
            status: row['status'] as String,
            viewerRole: row['viewer_role'] as String,
            canRespond: row['can_respond'] == true,
            gymId: row['gym_id'] as String?,
            gymName: row['gym_name'] as String?,
          );
        })
        .where((link) => link.viewerRole == role.name)
        .toList();
  }

  @override
  Future<void> requestManagementLink(String consultationId) async {
    await managementRpc(
      'request_management_link',
      params: {'consultation_id': consultationId},
    );
  }

  @override
  Future<void> respondManagementLink(
    String linkId, {
    required bool accept,
  }) async {
    await managementRpc(
      'respond_management_link',
      params: {'link_id': linkId, 'accept': accept},
    );
  }

  @override
  Future<void> endManagementLink(String linkId) async {
    await managementRpc('end_management_link', params: {'link_id': linkId});
  }

  @override
  Future<void> setManagementGym(String linkId, String? gymId) async {
    await managementRpc(
      'set_management_gym',
      params: {'link_id': linkId, 'gym_id': gymId},
    );
  }

  @override
  Future<void> requestManagementTrainerChange(
    String linkId,
    String trainerId,
  ) async {
    await managementRpc(
      'request_management_trainer_change',
      params: {'link_id': linkId, 'trainer_id': trainerId},
    );
  }

  @override
  Future<ManagedWorkoutPage> listManagedWorkouts(
    String linkId, {
    String? before,
  }) async {
    final result = _object(
      await managementRpc(
        'list_managed_workouts',
        params: {'link_id': linkId, 'before_key': before},
      ),
    );
    return ManagedWorkoutPage(
      nextCursor: result['next_cursor'] as String?,
      workouts: (result['workouts'] as List).map((value) {
        final row = _object(value);
        final session = AppSnapshotCodec.sessionFromJson(
          _object(row['session']),
          exerciseCatalog,
        );
        if (session == null) throw const FormatException('운동 기록을 읽을 수 없어요.');
        return ManagedWorkout(
          key: row['key'] as String,
          revision: row['revision'] as String,
          title: row['title'] as String,
          kind: row['kind'] as String,
          session: session,
          canPropose: row['can_propose'] == true,
          requiresApproval: row['requires_approval'] == true,
        );
      }).toList(),
    );
  }

  @override
  Future<List<WorkoutCorrection>> listWorkoutCorrections({
    required CoachingManagementRole role,
  }) async {
    final rows = await managementRpc('list_workout_corrections') as List;
    return rows
        .map((value) {
          final row = _object(value);
          return WorkoutCorrection(
            id: row['id'] as String,
            memberName: row['member_name'] as String,
            viewerRole: row['viewer_role'] as String,
            recordKey: row['record_key'] as String,
            exerciseId: row['exercise_id'] as String,
            correctionKey: row['correction_key'] as String,
            trainerName: row['trainer_name'] as String,
            workoutTitle: row['workout_title'] as String,
            date: DateTime.parse(row['workout_date'] as String),
            exerciseName: row['exercise_name'] as String,
            setNumber: (row['set_number'] as num).toInt(),
            metric: WorkoutMetric.values.byName(row['metric'] as String),
            before: (row['before_value'] as num?)?.toDouble(),
            after: (row['after_value'] as num).toDouble(),
            reason: row['reason'] as String,
            status: row['status'] as String,
            canRespond: row['can_respond'] == true,
          );
        })
        .where((correction) => correction.viewerRole == role.name)
        .toList();
  }

  @override
  Future<void> proposeWorkoutCorrection({
    required String linkId,
    required ManagedWorkout workout,
    required String exerciseId,
    required int setNumber,
    required WorkoutMetric metric,
    required double value,
    required String reason,
    required String requestId,
  }) async {
    await managementRpc(
      'propose_workout_correction',
      params: {
        'link_id': linkId,
        'record_key': workout.key,
        'expected_revision': workout.revision,
        'exercise_id': exerciseId,
        'set_number': setNumber,
        'metric': metric.name,
        'value': value,
        'reason': reason,
        'request_id': requestId,
      },
    );
  }

  @override
  Future<void> respondWorkoutCorrection(
    String correctionId, {
    required bool accept,
  }) async {
    await managementRpc(
      'respond_workout_correction',
      params: {'correction_id': correctionId, 'accept': accept},
    );
  }
}
