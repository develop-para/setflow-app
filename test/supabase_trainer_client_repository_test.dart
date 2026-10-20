import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/supabase_business_repository.dart';
import 'package:setflow/data/trainer_client_repository.dart';
import 'package:setflow/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseBusinessRepository repository;
  late List<(String, Map<String, dynamic>)> calls;
  late WorkoutSession session;
  late Object? response;
  String? failureCode;

  setUp(() async {
    calls = [];
    failureCode = null;
    session = WorkoutSession(
      date: DateTime(2026, 10, 20),
      exercises: [
        WorkoutExercise(
          id: 'client-bench',
          template: exerciseCatalog.first,
          sets: [
            WorkoutSetEntry(
              number: 1,
              weight: 42.5,
              reps: 8,
              completed: true,
              rir: 2,
            ),
          ],
        ),
      ],
    );
    response = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = SupabaseBusinessRepository(client);
    server.listen((request) async {
      final payload = await utf8.decoder.bind(request).join();
      final args = payload.isEmpty || payload == 'null'
          ? <String, dynamic>{}
          : jsonDecode(payload) as Map<String, dynamic>;
      calls.add((request.uri.pathSegments.last, args));
      request.response.headers.contentType = ContentType.json;
      if (failureCode != null) {
        request.response.statusCode = failureCode == 'PT409' ? 409 : 410;
        request.response.write(
          jsonEncode({
            'code': failureCode,
            'message': 'The server state changed; reload before retrying',
          }),
        );
      } else {
        request.response.write(jsonEncode(response));
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  Map<String, dynamic> clientRow({String id = 'client-id'}) => {
    'id': id,
    'name': '같은 이름',
    'phone': '010-1234-5678',
    'notes': '관리 메모',
    'member_user_id': null,
  };

  Map<String, dynamic> workoutRow({
    TrainerClientWorkoutSource source = TrainerClientWorkoutSource.trainer,
    bool canEdit = true,
  }) => {
    'id': 'workout-id',
    'client_id': 'client-id',
    'session': AppSnapshotCodec.sessionToJson(session),
    'notes': '운동 메모',
    'author_name': '김코치',
    'source': source.name,
    'version': 3,
    'can_edit': canEdit,
  };

  test(
    'independent client identities survive matching contact details',
    () async {
      response = [
        clientRow(id: 'first'),
        {...clientRow(id: 'second'), 'can_connect': false},
      ];
      final clients = await repository.listTrainerClients();
      expect(repository, isA<TrainerClientRepository>());
      expect(clients.map((item) => item.id), ['first', 'second']);
      expect(clients.map((item) => item.name).toSet(), {'같은 이름'});
      expect(clients.first.canConnect, isTrue);
      expect(clients.last.canConnect, isFalse);
      expect(
        clients.singleWhere((item) => item.id == 'first').memberUserId,
        isNull,
      );
      expect(calls.single.$1, 'list_trainer_clients');
    },
  );

  test('client creation and editing use domain RPCs and retry ids', () async {
    response = clientRow();
    final created = await repository.createTrainerClient(
      name: '같은 이름',
      phone: '010-1234-5678',
      notes: '관리 메모',
      requestId: 'create-retry-id',
    );
    expect(created.notes, '관리 메모');
    expect(
      [calls.last.$1, calls.last.$2],
      [
        'create_trainer_client',
        {
          'name': '같은 이름',
          'phone': '010-1234-5678',
          'notes': '관리 메모',
          'request_id': 'create-retry-id',
        },
      ],
    );
    await repository.updateTrainerClient(
      clientId: created.id,
      name: '수정 이름',
      phone: '',
      notes: '수정 메모',
      requestId: 'update-retry-id',
    );
    expect(calls.last.$1, 'update_trainer_client');
    expect(calls.last.$2, {
      'client_id': 'client-id',
      'name': '수정 이름',
      'phone': '',
      'notes': '수정 메모',
      'request_id': 'update-retry-id',
    });
  });

  test('member workout and server edit permission remain distinct', () async {
    response = [
      workoutRow(),
      workoutRow(source: TrainerClientWorkoutSource.member, canEdit: false),
    ];
    final records = await repository.listTrainerClientWorkouts('client-id');
    expect(records.first.canEdit, isTrue);
    expect(records.last.canEdit, isFalse);
    expect(records.last.source, TrainerClientWorkoutSource.member);
    expect(records.last.version, 3);
    expect(calls.single.$2, {'client_id': 'client-id'});
    expect(records.first.session.exercises.single.sets.single.rir, 2);
  });

  test(
    'saving keeps completed sets, inline templates and independent id',
    () async {
      response = workoutRow();
      final saved = await repository.saveTrainerClientWorkout(
        clientId: 'client-id',
        session: session,
        notes: '운동 메모',
        requestId: 'stable-request',
        workoutId: 'independent-workout',
        expectedVersion: 0,
      );
      expect(saved.session.exercises.single.sets.single.completed, isTrue);
      expect(saved.session.exercises.single.sets.single.weight, 42.5);
      expect(calls.single.$1, 'save_trainer_client_workout');
      final args = calls.single.$2;
      expect(args['client_id'], 'client-id');
      expect(args['workout_id'], 'independent-workout');
      expect(args['request_id'], 'stable-request');
      expect(args['expected_version'], 0);
      expect(args['session'], AppSnapshotCodec.sessionToJson(session));
      expect(args.containsKey('user_id'), isFalse);
    },
  );

  test('version conflicts reach the editor as a domain failure', () async {
    failureCode = 'PT409';
    await expectLater(
      repository.saveTrainerClientWorkout(
        clientId: 'client-id',
        session: session,
        notes: '',
        requestId: 'request',
        workoutId: 'workout',
        expectedVersion: 2,
      ),
      throwsA(isA<TrainerClientWorkoutConflict>()),
    );
  });

  test(
    'consumed invitation retries produce a terminal domain failure',
    () async {
      failureCode = 'PT410';
      await expectLater(
        repository.createTrainerClientInvitation(
          clientId: 'client-id',
          expiresAt: DateTime.utc(2026, 10, 21),
          requestId: 'old-request',
        ),
        throwsA(isA<TrainerClientInvitationUnavailable>()),
      );
    },
  );

  test('account linkage requires a token and explicit member action', () async {
    final expires = DateTime.utc(2026, 10, 21);
    response = {
      'client_id': 'client-id',
      'token': 'private-single-use-token',
      'expires_at': expires.toIso8601String(),
    };
    final invite = await repository.createTrainerClientInvitation(
      clientId: 'client-id',
      expiresAt: expires,
      requestId: 'invite-request',
    );
    expect(invite.token, 'private-single-use-token');
    expect(invite.expiresAt, expires);
    expect(calls.last.$2['expires_at'], expires.toIso8601String());
    response = {'accepted': true};
    await repository.acceptTrainerClientInvitation(
      invite.token,
      requestId: 'accept-request',
    );
    expect(
      [calls.last.$1, calls.last.$2],
      [
        'accept_trainer_client_invitation',
        {'token': 'private-single-use-token', 'request_id': 'accept-request'},
      ],
    );
    response = [workoutRow(canEdit: false)];
    expect(
      (await repository.listMyTrainerClientWorkouts()).single.canEdit,
      isFalse,
    );
    expect(calls.last.$1, 'list_my_trainer_client_workouts');
    response = [
      {
        'client_id': 'empty-client',
        'trainer_name': '김코치',
        'client_name': '나',
        'is_sharing': true,
      },
    ];
    final links = await repository.listMyTrainerClientLinks();
    expect(links.single.clientId, 'empty-client');
    expect(links.single.isSharing, isTrue);
    response = {'ended': true};
    await repository.endMyTrainerClientLink(
      links.single.clientId,
      requestId: 'revoke-request',
    );
    expect(
      [calls.last.$1, calls.last.$2],
      [
        'end_my_trainer_client_link',
        {'client_id': 'empty-client', 'request_id': 'revoke-request'},
      ],
    );
  });
}
