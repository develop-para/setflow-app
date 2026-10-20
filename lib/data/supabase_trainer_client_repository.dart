import '../models.dart';
import 'app_snapshot_codec.dart';
import 'exercise_catalog.dart';
import 'trainer_client_repository.dart';

mixin SupabaseTrainerClients on Object implements TrainerClientRepository {
  Future<dynamic> trainerClientRpc(String name, {Map<String, dynamic>? params});

  static Map<String, dynamic> _object(Object? value) =>
      Map<String, dynamic>.from(value as Map);

  static TrainerManagedClient _client(Object? value) {
    final row = _object(value);
    return TrainerManagedClient(
      id: row['id'] as String,
      name: row['name'] as String,
      phone: row['phone'] as String,
      notes: row['notes'] as String,
      memberUserId: row['member_user_id'] as String?,
      canConnect: row['can_connect'] != false,
    );
  }

  static TrainerClientWorkout _workout(Object? value) {
    final row = _object(value);
    final session = AppSnapshotCodec.sessionFromJson(
      _object(row['session']),
      exerciseCatalog,
    );
    if (session == null) throw const FormatException('회원 운동 기록을 읽을 수 없어요.');
    return TrainerClientWorkout(
      id: row['id'] as String,
      clientId: row['client_id'] as String?,
      session: session,
      notes: row['notes'] as String,
      authorName: row['author_name'] as String,
      source: TrainerClientWorkoutSource.values.byName(row['source'] as String),
      version: (row['version'] as num).toInt(),
      canEdit: row['can_edit'] == true,
    );
  }

  @override
  Future<List<TrainerManagedClient>> listTrainerClients() async =>
      (await trainerClientRpc('list_trainer_clients') as List)
          .map(_client)
          .toList(growable: false);

  @override
  Future<TrainerManagedClient> createTrainerClient({
    required String name,
    required String phone,
    required String notes,
    required String requestId,
  }) async => _client(
    await trainerClientRpc(
      'create_trainer_client',
      params: {
        'name': name,
        'phone': phone,
        'notes': notes,
        'request_id': requestId,
      },
    ),
  );

  @override
  Future<TrainerManagedClient> updateTrainerClient({
    required String clientId,
    required String name,
    required String phone,
    required String notes,
    required String requestId,
  }) async => _client(
    await trainerClientRpc(
      'update_trainer_client',
      params: {
        'client_id': clientId,
        'name': name,
        'phone': phone,
        'notes': notes,
        'request_id': requestId,
      },
    ),
  );

  @override
  Future<List<TrainerClientWorkout>> listTrainerClientWorkouts(
    String clientId,
  ) async =>
      (await trainerClientRpc(
                'list_trainer_client_workouts',
                params: {'client_id': clientId},
              )
              as List)
          .map(_workout)
          .toList(growable: false);

  @override
  Future<TrainerClientWorkout> saveTrainerClientWorkout({
    required String clientId,
    required WorkoutSession session,
    required String notes,
    required String requestId,
    required String workoutId,
    required int expectedVersion,
  }) async => _workout(
    await trainerClientRpc(
      'save_trainer_client_workout',
      params: {
        'client_id': clientId,
        'session': AppSnapshotCodec.sessionToJson(session),
        'notes': notes,
        'request_id': requestId,
        'workout_id': workoutId,
        'expected_version': expectedVersion,
      },
    ),
  );

  @override
  Future<TrainerClientInvitation> createTrainerClientInvitation({
    required String clientId,
    required DateTime expiresAt,
    required String requestId,
  }) async {
    final row = _object(
      await trainerClientRpc(
        'create_trainer_client_invitation',
        params: {
          'client_id': clientId,
          'expires_at': expiresAt.toUtc().toIso8601String(),
          'request_id': requestId,
        },
      ),
    );
    return TrainerClientInvitation(
      clientId: row['client_id'] as String,
      token: row['token'] as String,
      expiresAt: DateTime.parse(row['expires_at'] as String),
    );
  }

  @override
  Future<void> acceptTrainerClientInvitation(
    String token, {
    required String requestId,
  }) async {
    await trainerClientRpc(
      'accept_trainer_client_invitation',
      params: {'token': token, 'request_id': requestId},
    );
  }

  @override
  Future<List<TrainerClientWorkout>> listMyTrainerClientWorkouts() async =>
      (await trainerClientRpc('list_my_trainer_client_workouts') as List)
          .map(_workout)
          .toList(growable: false);

  @override
  Future<List<TrainerClientLink>> listMyTrainerClientLinks() async =>
      (await trainerClientRpc('list_my_trainer_client_links') as List)
          .map((value) {
            final row = _object(value);
            return TrainerClientLink(
              clientId: row['client_id'] as String,
              trainerName: row['trainer_name'] as String,
              clientName: row['client_name'] as String,
              isSharing: row['is_sharing'] == true,
            );
          })
          .toList(growable: false);

  @override
  Future<void> endMyTrainerClientLink(
    String clientId, {
    required String requestId,
  }) async {
    await trainerClientRpc(
      'end_my_trainer_client_link',
      params: {'client_id': clientId, 'request_id': requestId},
    );
  }
}
