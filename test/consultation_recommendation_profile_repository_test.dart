import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/supabase_business_repository.dart';
import 'package:setflow/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _memberUserId = '11111111-1111-4111-8111-111111111111';
const _trainerId = '22222222-2222-4222-8222-222222222222';
const _consultationId = '33333333-3333-4333-8333-333333333333';
const _requestId = '44444444-4444-4444-8444-444444444444';
const _sharedAt = '2026-08-21T01:02:03.000Z';

void main() {
  test(
    'createConsultation sends the canonical profile and maps its share',
    () async {
      final profile = RecommendationProfile(
        experienceLevel: TrainingExperienceLevel.intermediate,
        availableEquipment: const {
          TrainingEquipment.dumbbells,
          TrainingEquipment.bodyweight,
          TrainingEquipment.bench,
        },
        painRegions: const {
          TrainingPainRegion.knee,
          TrainingPainRegion.shoulder,
        },
        painLevel: 4,
        restrictedMovements: const {
          TrainingMovementRestriction.squatLunge,
          TrainingMovementRestriction.overheadPress,
        },
        injuryNote: '  오른쪽 무릎은 깊게 굽히면 불편함  ',
        recoveryStatus: TrainingRecoveryStatus.fatigued,
        recoveryRecordedAt: DateTime.parse('2026-08-21T08:30:00+09:00'),
        updatedAt: DateTime.parse('2026-08-21T09:00:00+09:00'),
      );
      final expectedProfileJson = <String, Object?>{
        'schemaVersion': 1,
        'experienceLevel': 'intermediate',
        'availableEquipment': ['bench', 'bodyweight', 'dumbbells'],
        'painRegions': ['knee', 'shoulder'],
        'painLevel': 4,
        'restrictedMovements': ['overheadPress', 'squatLunge'],
        'injuryNote': '오른쪽 무릎은 깊게 굽히면 불편함',
        'recoveryStatus': 'fatigued',
        'recoveryRecordedAt': '2026-08-20T23:30:00.000Z',
        'updatedAt': '2026-08-21T00:00:00.000Z',
      };
      final backend = await _ConsultationBackend.start(
        recommendationProfileShare: {
          'schema_version': 1,
          'profile_snapshot': expectedProfileJson,
          'consented_at': _sharedAt,
          'revoked_at': null,
        },
      );
      addTearDown(backend.close);

      final consultation = await SupabaseBusinessRepository(backend.client)
          .createConsultation(
            CreateConsultationInput(
              requestId: _requestId,
              trainerId: _trainerId,
              specialty: '근력',
              goal: '근비대',
              level: '중급',
              question: '스쿼트 자세를 봐주세요.',
              recommendationProfile: profile,
            ),
          );

      expect(backend.rpcRequests, hasLength(1));
      expect(backend.rpcRequests.single.method, 'POST');
      expect(
        backend.rpcRequests.single.path,
        '/rest/v1/rpc/create_business_consultation',
      );
      expect(backend.rpcRequests.single.body, <String, Object?>{
        'request_id': _requestId,
        'trainer_id': _trainerId,
        'gym_id': null,
        'routine_id': null,
        'specialty': '근력',
        'goal': '근비대',
        'level': '중급',
        'question': '스쿼트 자세를 봐주세요.',
        'recommendation_profile': expectedProfileJson,
      });
      expect(backend.consultationSelects, hasLength(1));
      expect(
        backend.consultationSelects.single.queryParameters['id'],
        'eq.$_consultationId',
      );
      expect(
        backend.consultationSelects.single.queryParameters['select'],
        contains(
          'recommendation_profile_share:'
          'consultation_recommendation_profile_shares',
        ),
      );

      expect(consultation.id, _consultationId);
      expect(
        consultation.sharedRecommendationProfile?.toJson(),
        expectedProfileJson,
      );
      expect(
        consultation.recommendationProfileSharedAt,
        DateTime.parse(_sharedAt),
      );
      expect(consultation.recommendationProfileShareRevokedAt, isNull);
    },
  );

  for (final unsharedResponse in <Object?>[null, const <Object?>[]]) {
    test('createConsultation safely maps an unshared profile response: '
        '${unsharedResponse.runtimeType}', () async {
      final backend = await _ConsultationBackend.start(
        recommendationProfileShare: unsharedResponse,
      );
      addTearDown(backend.close);

      final consultation = await SupabaseBusinessRepository(backend.client)
          .createConsultation(
            const CreateConsultationInput(
              requestId: _requestId,
              trainerId: _trainerId,
              question: '상담을 요청합니다.',
            ),
          );

      expect(backend.rpcRequests.single.body['recommendation_profile'], isNull);
      expect(consultation.sharedRecommendationProfile, isNull);
      expect(consultation.recommendationProfileSharedAt, isNull);
      expect(consultation.recommendationProfileShareRevokedAt, isNull);
    });
  }

  test('revokeRecommendationProfileShare calls the member-only RPC', () async {
    final backend = await _ConsultationBackend.start(
      recommendationProfileShare: null,
    );
    addTearDown(backend.close);

    await SupabaseBusinessRepository(
      backend.client,
    ).revokeRecommendationProfileShare(_consultationId);

    expect(backend.rpcRequests, hasLength(1));
    expect(
      backend.rpcRequests.single.path,
      '/rest/v1/rpc/revoke_consultation_recommendation_profile_share',
    );
    expect(backend.rpcRequests.single.body, {
      'consultation_id': _consultationId,
    });
  });
}

class _ConsultationBackend {
  _ConsultationBackend._(
    this._server,
    this.client,
    this._recommendationProfileShare,
  );

  final HttpServer _server;
  final SupabaseClient client;
  final Object? _recommendationProfileShare;
  final List<_CapturedRequest> rpcRequests = [];
  final List<Uri> consultationSelects = [];

  static Future<_ConsultationBackend> start({
    required Object? recommendationProfileShare,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final backend = _ConsultationBackend._(
      server,
      client,
      recommendationProfileShare,
    );
    server.listen(backend._handle);
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-access-token',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': _memberUserId,
          'email': 'member@example.com',
          'app_metadata': const <String, Object?>{},
          'user_metadata': const <String, Object?>{},
          'aud': 'authenticated',
          'created_at': '2026-08-21T00:00:00Z',
        },
      }),
    );
    return backend;
  }

  Future<void> close() async {
    client.dispose();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/rest/v1/rpc/create_business_consultation') {
      final body = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      rpcRequests.add(
        _CapturedRequest(method: request.method, path: path, body: body),
      );
      await _writeJson(request.response, _consultationId);
      return;
    }
    if (path ==
        '/rest/v1/rpc/revoke_consultation_recommendation_profile_share') {
      final body = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      rpcRequests.add(
        _CapturedRequest(method: request.method, path: path, body: body),
      );
      await _writeJson(request.response, '2026-08-21T04:00:00.000Z');
      return;
    }
    if (path == '/rest/v1/consultations') {
      await request.drain<void>();
      consultationSelects.add(request.uri);
      await _writeJson(request.response, _consultationRow());
      return;
    }
    await request.drain<void>();
    await _writeJson(request.response, {
      'code': 'PGRST404',
      'message': 'Unexpected test request: ${request.method} ${request.uri}',
      'details': null,
      'hint': null,
    }, statusCode: HttpStatus.notFound);
  }

  Map<String, Object?> _consultationRow() => {
    'id': _consultationId,
    'user_id': _memberUserId,
    'trainer_id': _trainerId,
    'gym_id': null,
    'routine_id': null,
    'status': 'pending',
    'requester_name': '상담 회원',
    'specialty': '근력',
    'goal': '근비대',
    'level': 'intermediate',
    'question': '스쿼트 자세를 봐주세요.',
    'is_read': false,
    'assigned_trainer_id': null,
    'created_at': '2026-08-21T00:00:00Z',
    'recommendation_profile_share': _recommendationProfileShare,
    'member': {'id': _memberUserId, 'nickname': '상담 회원', 'avatar_url': null},
    'trainer': {'id': _trainerId, 'display_name': '테스트 트레이너'},
    'assigned_trainer': null,
    'gym': null,
    'messages': const <Object?>[],
  };

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

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, dynamic> body;
}
