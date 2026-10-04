import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setflow/data/supabase_routine_catalog_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const userId = '11111111-1111-4111-8111-111111111111';

void main() {
  test(
    'access adapter uses identity-free RPC and rejects malformed or foreign grants',
    () async {
      Object? response;
      final calls = <http.Request>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = SupabaseRoutineCatalogRepository(client);
      expect(await repository.loadMyPersonalCoachingAccess(), isNull);
      expect(calls, isEmpty);
      await client.auth.recoverSession(
        jsonEncode({
          'access_token': 'test-access-token',
          'refresh_token': 'test-refresh-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': userId,
            'email': 'member@example.test',
            'app_metadata': {},
            'user_metadata': {},
            'aud': 'authenticated',
            'created_at': '2026-10-01T00:00:00Z',
          },
        }),
      );
      response = {'user_id': userId, 'expires_at': '2030-01-01T00:00:00Z'};
      final grant = await repository.loadMyPersonalCoachingAccess();
      expect(grant!.isActiveFor(userId, DateTime.utc(2029)), isTrue);
      expect(
        calls.last.url.path,
        '/rest/v1/rpc/get_my_personal_coaching_access',
      );
      expect(jsonDecode(calls.last.body), anyOf(isNull, equals({})));
      expect(grant.isActiveFor(userId, DateTime.utc(2030)), isFalse);
      for (final invalid in [
        null,
        [],
        {'user_id': 'other', 'expires_at': '2030-01-01'},
        {'user_id': userId, 'expires_at': 'broken'},
      ]) {
        response = invalid;
        expect(await repository.loadMyPersonalCoachingAccess(), isNull);
      }
    },
  );

  test(
    'SQL requires an account-owned unexpired subscription and server-owned feature enrollment',
    () {
      final sql = File(
        'supabase/migrations/20261004090000_personal_coaching_access.sql',
      ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      expect(sql, contains('subscription.user_id = (select auth.uid())'));
      expect(sql, contains("subscription.status = 'active'"));
      expect(sql, contains('subscription.current_period_end > now()'));
      expect(sql, contains("plan.audience = 'b2c'"));
      expect(sql, contains('plan.price > 0'));
      expect(sql, contains('join private.personal_coaching_plans feature'));
      expect(
        sql,
        contains(
          'revoke all on table private.personal_coaching_plans from public, anon, authenticated',
        ),
      );
      expect(sql, contains("set search_path = ''"));
      expect(sql, contains('from public, anon;'));
      expect(
        sql,
        isNot(
          contains(
            'grant insert on table private.personal_coaching_plans to authenticated',
          ),
        ),
      );
    },
  );
}
