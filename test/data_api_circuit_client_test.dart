import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setflow/services/data_api_circuit_client.dart';

void main() {
  test(
    'one Data API 503 blocks duplicate REST calls during cooldown',
    () async {
      var now = DateTime.utc(2026, 8, 30);
      var restCalls = 0;
      var authCalls = 0;
      final client = DataApiCircuitClient(
        now: () => now,
        inner: MockClient((request) async {
          if (request.url.path.startsWith('/rest/v1')) {
            restCalls++;
            return restCalls == 1
                ? http.Response('service unavailable', 503)
                : http.Response('[]', 200);
          }
          authCalls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);

      final first = await client.get(
        Uri.parse('https://example.supabase.co/rest/v1/posts'),
      );
      final duplicate = await client.get(
        Uri.parse('https://example.supabase.co/rest/v1/market_routines'),
      );

      expect(first.statusCode, 503);
      expect(duplicate.statusCode, 503);
      expect(duplicate.body, contains('Using cached data'));
      expect(restCalls, 1);
      expect(client.isOpen, isTrue);

      final auth = await client.get(
        Uri.parse('https://example.supabase.co/auth/v1/user'),
      );
      expect(auth.statusCode, 200);
      expect(authCalls, 1);

      now = now.add(const Duration(seconds: 16));
      final recovered = await client.get(
        Uri.parse('https://example.supabase.co/rest/v1/posts'),
      );
      expect(recovered.statusCode, 200);
      expect(restCalls, 2);
      expect(client.isOpen, isFalse);
    },
  );

  test('a network timeout also opens the Data API circuit', () async {
    var calls = 0;
    final client = DataApiCircuitClient(
      inner: MockClient((request) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('[]', 200, request: request);
      }),
      requestTimeout: const Duration(milliseconds: 1),
    );
    addTearDown(client.close);

    await expectLater(
      client.get(Uri.parse('https://example.supabase.co/rest/v1/posts')),
      throwsA(isA<TimeoutException>()),
    );
    final duplicate = await client.get(
      Uri.parse('https://example.supabase.co/rest/v1/posts'),
    );

    expect(duplicate.statusCode, 503);
    expect(calls, 1);
  });
}
