import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/data/supabase_business_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _consultationId = '11111111-1111-4111-8111-111111111111';

void main() {
  test('verified self connection denial becomes a domain failure', () async {
    final repository = _failingRepository(
      code: '42501',
      details: 'management_self_connection',
    );
    await expectLater(
      repository.requestManagementLink(_consultationId),
      throwsA(
        isA<CoachingManagementFailure>().having(
          (error) => error.reason,
          'reason',
          CoachingManagementFailureReason.selfConnection,
        ),
      ),
    );
  });

  for (final details in <Object?>[
    null,
    'permission denied',
    {'reason': 'management_self_connection'},
  ]) {
    test(
      'ordinary permission denial does not expose a self hint: $details',
      () async {
        final repository = _failingRepository(
          code: '42501',
          details: details,
          message: 'management_self_connection',
        );
        await expectLater(
          repository.requestManagementLink(_consultationId),
          throwsA(
            isA<CoachingManagementFailure>().having(
              (error) => error.reason,
              'reason',
              CoachingManagementFailureReason.accessDenied,
            ),
          ),
        );
      },
    );
  }

  for (final code in ['PGRST202', 'PGRST002', 'P0001']) {
    test(
      'non-permission failures keep their original fallback: $code',
      () async {
        final repository = _failingRepository(
          code: code,
          details: 'management_self_connection',
          status: code == 'PGRST002' ? 503 : 400,
        );
        await expectLater(
          repository.requestManagementLink(_consultationId),
          throwsA(
            isA<PostgrestException>()
                .having((error) => error.code, 'code', code)
                .having(
                  (error) => error.details,
                  'details',
                  'management_self_connection',
                ),
          ),
        );
      },
    );
  }

  test(
    'other management operations keep their original permission error',
    () async {
      final repository = _failingRepository(
        code: '42501',
        details: 'management_self_connection',
        rpc: 'respond_management_link',
        params: {'link_id': 'link', 'accept': true},
      );
      await expectLater(
        repository.respondManagementLink('link', accept: true),
        throwsA(
          isA<PostgrestException>().having(
            (error) => error.code,
            'code',
            '42501',
          ),
        ),
      );
    },
  );

  test(
    'offline failure stays retryable through the existing fallback',
    () async {
      final offline = const SocketException('offline');
      final client = _client(MockClient((request) async => throw offline));
      await expectLater(
        SupabaseBusinessRepository(
          client,
        ).requestManagementLink(_consultationId),
        throwsA(same(offline)),
      );
    },
  );

  test(
    'successful request still sends only the consultation identifier',
    () async {
      var calls = 0;
      final client = _client(
        MockClient((request) async {
          calls++;
          _expectRequest(request);
          return http.Response('', 204, request: request);
        }),
      );
      await SupabaseBusinessRepository(
        client,
      ).requestManagementLink(_consultationId);
      expect(calls, 1);
    },
  );
}

SupabaseBusinessRepository _failingRepository({
  required String code,
  Object? details,
  String message = 'server rejected request',
  int status = 403,
  String rpc = 'request_management_link',
  Map<String, Object?> params = const {'consultation_id': _consultationId},
}) => SupabaseBusinessRepository(
  _client(
    MockClient((request) async {
      _expectRequest(request, rpc: rpc, params: params);
      return http.Response(
        jsonEncode({'code': code, 'message': message, 'details': details}),
        status,
        headers: const {'content-type': 'application/json'},
        request: request,
      );
    }),
  ),
);

SupabaseClient _client(MockClient httpClient) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: httpClient,
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  addTearDown(client.dispose);
  return client;
}

void _expectRequest(
  http.Request request, {
  String rpc = 'request_management_link',
  Map<String, Object?> params = const {'consultation_id': _consultationId},
}) {
  expect(request.method, 'POST');
  expect(request.url.path, '/rest/v1/rpc/$rpc');
  expect(jsonDecode(request.body), params);
}
