import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/supabase_business_repository.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _trainerUserId = '11111111-1111-4111-8111-111111111111';
const _trainerId = '22222222-2222-4222-8222-222222222222';
const _memberUserId = '33333333-3333-4333-8333-333333333333';
const _consultationId = '44444444-4444-4444-8444-444444444444';
const _secondMemberUserId = '55555555-5555-4555-8555-555555555555';
const _secondConsultationId = '66666666-6666-4666-8666-666666666666';
const _connectionId = '77777777-7777-4777-8777-777777777777';
const _secondConnectionId = '88888888-8888-4888-8888-888888888888';

void main() {
  test(
    'server grants override an approved profile and saved account role',
    () async {
      final backend = await _TrainerWorkspaceBackend.start(
        availableRoles: const ['member'],
      );
      addTearDown(backend.close);
      final repository = SupabaseBusinessRepository(backend.client);
      expect((await repository.loadAccess()).availableRoles, {UserRole.member});
      await expectLater(
        repository.loadWorkspace(UserRole.trainer),
        throwsA(isA<BusinessAccessDenied>()),
      );
    },
  );

  test('failed access RPC never falls back to client-computed roles', () async {
    final backend = await _TrainerWorkspaceBackend.start(
      failingResources: const {'get_my_business_access'},
    );
    addTearDown(backend.close);
    await expectLater(
      SupabaseBusinessRepository(backend.client).loadAccess(),
      throwsA(isA<BusinessAccessDenied>()),
    );
  });

  test('access returned for another account is rejected', () async {
    final backend = await _TrainerWorkspaceBackend.start(
      accessUserId: _memberUserId,
    );
    addTearDown(backend.close);
    await expectLater(
      SupabaseBusinessRepository(backend.client).loadAccess(),
      throwsStateError,
    );
  });

  test(
    'dashboard failure preserves successful trainer workspace data',
    () async {
      final backend = await _TrainerWorkspaceBackend.start(
        failingResources: const {'v_trainer_dashboard'},
      );
      addTearDown(backend.close);

      final workspace = await SupabaseBusinessRepository(
        backend.client,
      ).loadWorkspace(UserRole.trainer);

      expect(workspace.dashboardStats.unreadConsultations, 0);
      expect(workspace.dashboardStats.activeMembers, 0);
      expect(workspace.assignments, isEmpty);
      expect(workspace.ownedRoutines, isEmpty);
      expect(workspace.consultations, hasLength(1));
      expect(workspace.consultations.single.id, _consultationId);
      expect(workspace.consultations.single.trainerId, _trainerId);
      expect(workspace.consultations.single.question, '스쿼트 자세를 봐주세요.');
    },
  );

  for (final resource in const [
    'member_assignments',
    'consultations',
    'coaching_routines',
    'list_my_coaching_connections',
    'coaching_session_records',
  ]) {
    test(
      'core trainer workspace failure still propagates: $resource',
      () async {
        final backend = await _TrainerWorkspaceBackend.start(
          failingResources: {resource},
        );
        addTearDown(backend.close);

        await expectLater(
          SupabaseBusinessRepository(
            backend.client,
          ).loadWorkspace(UserRole.trainer),
          throwsA(isA<PostgrestException>()),
        );
      },
    );
  }

  test(
    'one trainer receives consultations and connections for both members',
    () async {
      final backend = await _TrainerWorkspaceBackend.start(
        resourceBodies: {
          'consultations': [
            {
              'id': _consultationId,
              'user_id': _memberUserId,
              'trainer_id': _trainerId,
              'requester_name': '첫 회원',
              'question': '스쿼트 자세 질문',
              'status': 'pending',
              'created_at': '2026-10-01T01:00:00Z',
            },
            {
              'id': _secondConsultationId,
              'user_id': _secondMemberUserId,
              'trainer_id': _trainerId,
              'requester_name': '둘째 회원',
              'question': '벤치 프레스 자세 질문',
              'status': 'replied',
              'created_at': '2026-10-01T02:00:00Z',
            },
          ],
          'list_my_coaching_connections': [
            {
              'id': _connectionId,
              'trainer_id': _trainerId,
              'member_user_id': _memberUserId,
              'member_name': '첫 회원',
              'status': 'active',
              'created_at': '2026-10-01T01:00:00Z',
            },
            {
              'id': _secondConnectionId,
              'trainer_id': _trainerId,
              'member_user_id': _secondMemberUserId,
              'member_name': '둘째 회원',
              'status': 'active',
              'created_at': '2026-10-01T02:00:00Z',
            },
          ],
        },
      );
      addTearDown(backend.close);
      final workspace = await SupabaseBusinessRepository(
        backend.client,
      ).loadWorkspace(UserRole.trainer);
      expect(workspace.consultations.map((c) => c.userId), [
        _memberUserId,
        _secondMemberUserId,
      ]);
      expect(workspace.consultations.map((c) => c.question), [
        '스쿼트 자세 질문',
        '벤치 프레스 자세 질문',
      ]);
      expect(workspace.coachingConnections.map((c) => c.memberUserId), [
        _memberUserId,
        _secondMemberUserId,
      ]);
      expect(workspace.coachingConnections.map((c) => c.memberName), [
        '첫 회원',
        '둘째 회원',
      ]);
    },
  );
}

class _TrainerWorkspaceBackend {
  _TrainerWorkspaceBackend._(this._server, this.client);

  final HttpServer _server;
  final SupabaseClient client;

  static Future<_TrainerWorkspaceBackend> start({
    Set<String> failingResources = const {},
    List<String> availableRoles = const ['member', 'trainer'],
    String accessUserId = _trainerUserId,
    Map<String, Object> resourceBodies = const {},
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final backend = _TrainerWorkspaceBackend._(server, client);
    server.listen(
      (request) => backend._handle(
        request,
        failingResources,
        availableRoles,
        accessUserId,
        resourceBodies,
      ),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': _trainerUserId,
          'email': 'trainer@example.com',
          'app_metadata': const <String, Object?>{},
          'user_metadata': const <String, Object?>{},
          'aud': 'authenticated',
          'created_at': '2026-08-17T00:00:00Z',
        },
      }),
    );
    return backend;
  }

  Future<void> close() async {
    client.dispose();
    await _server.close(force: true);
  }

  Future<void> _handle(
    HttpRequest request,
    Set<String> failingResources,
    List<String> availableRoles,
    String accessUserId,
    Map<String, Object> resourceBodies,
  ) async {
    await request.drain<void>();
    final resource = request.uri.pathSegments.last;
    if (failingResources.contains(resource)) {
      await _writeJson(request.response, {
        'code': '42501',
        'message': 'permission denied for $resource',
        'details': null,
        'hint': null,
      }, statusCode: HttpStatus.forbidden);
      return;
    }

    final fixture = resourceBodies[resource];
    if (fixture != null) {
      await _writeJson(request.response, fixture);
      return;
    }
    final Object body = switch (resource) {
      'get_my_business_access' => {
        'user': {
          'id': accessUserId,
          'email': 'trainer@example.com',
          'role': 'trainer',
        },
        'available_roles': availableRoles,
        'trainer': {
          'id': _trainerId,
          'user_id': _trainerUserId,
          'display_name': '테스트 트레이너',
          'rating_avg': 4.9,
          'post_count': 3,
          'coaching_total': 5,
          'is_public': true,
          'verified_badge': true,
          'status': 'approved',
        },
      },
      'v_trainer_dashboard' => {
        'trainer_id': _trainerId,
        'unread_consults': 1,
        'active_members': 0,
        'pending_settlement': 0,
        'month_settled': 0,
        'overdue_feedbacks': 0,
      },
      'member_assignments' ||
      'coaching_routines' ||
      'list_my_coaching_connections' ||
      'coaching_session_records' => const [],
      'consultations' => [
        {
          'id': _consultationId,
          'user_id': _memberUserId,
          'trainer_id': _trainerId,
          'gym_id': null,
          'routine_id': null,
          'status': 'pending',
          'requester_name': '상담 회원',
          'specialty': '근력',
          'goal': '근비대',
          'level': 'beginner',
          'question': '스쿼트 자세를 봐주세요.',
          'is_read': false,
          'assigned_trainer_id': null,
          'created_at': '2026-08-17T00:00:00Z',
          'member': {
            'id': _memberUserId,
            'nickname': '상담 회원',
            'avatar_url': null,
          },
          'trainer': {'id': _trainerId, 'display_name': '테스트 트레이너'},
          'assigned_trainer': null,
          'gym': null,
          'messages': const [],
        },
      ],
      _ => throw StateError('Unexpected test request: ${request.uri}'),
    };
    await _writeJson(request.response, body);
  }

  Future<void> _writeJson(
    HttpResponse response,
    Object? body, {
    int statusCode = HttpStatus.ok,
  }) async {
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }
}
