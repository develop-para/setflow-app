import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:setflow/data/backend_cache.dart';
import 'package:setflow/data/supabase_routine_catalog_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'the published routine catalog falls back to its last response',
    () async {
      var failDataApi = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: MockClient((request) async {
          if (failDataApi) {
            return http.Response(
              jsonEncode({
                'code': 'PGRST002',
                'message': 'Could not query the database for the schema cache.',
              }),
              503,
              headers: const {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            jsonEncode([_routineRow]),
            200,
            headers: const {'content-type': 'application/json'},
            request: request,
          );
        }),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      addTearDown(client.dispose);
      final repository = SupabaseRoutineCatalogRepository(
        client,
        cache: _MemoryBackendCache(),
      );

      final fresh = await repository.listPublished();
      failDataApi = true;
      final fallback = await repository.listPublished();

      expect(fresh.single.title, '전신 기초 루틴');
      expect(fallback.single.title, fresh.single.title);
      expect(fallback.single.exercises.single.name, '스쿼트');
      expect(repository.isUsingCachedData, isTrue);
      expect(repository.lastReadError, isNotNull);
    },
  );
}

const _routineRow = <String, Object?>{
  'id': '11111111-1111-4111-8111-111111111111',
  'coaching_routine_id': '22222222-2222-4222-8222-222222222222',
  'title': '전신 기초 루틴',
  'description': '전신을 고르게 운동해요.',
  'author_name': 'Setflow',
  'trainer_id': null,
  'gym_id': null,
  'difficulty': 'beginner',
  'access_tier': 'free',
  'color_hex': null,
  'catalog_key': 'full-body-basic',
  'tags': <String>['전신', '초급'],
  'duration_min': 30,
  'created_at': '2026-08-30T00:00:00Z',
  'coaching_routine': <String, Object?>{
    'id': '22222222-2222-4222-8222-222222222222',
    'status': 'approved',
    'exercises': <Map<String, Object?>>[
      <String, Object?>{
        'id': '33333333-3333-4333-8333-333333333333',
        'base_exercise_id': null,
        'name': '스쿼트',
        'target_muscle': '하체',
        'order_index': 0,
        'sets': <Map<String, Object?>>[
          <String, Object?>{
            'id': '44444444-4444-4444-8444-444444444444',
            'set_no': 1,
            'type': 'normal',
            'target_weight': 20,
            'target_reps': 10,
            'rest_seconds': 90,
            'duration_sec': null,
            'distance_m': null,
            'intensity_rpe': 6,
          },
        ],
      },
    ],
  },
};

class _MemoryBackendCache implements BackendDocumentCache {
  final Map<String, Map<String, dynamic>> _documents = {};

  @override
  Future<Map<String, dynamic>?> loadDocument(String key) async =>
      _documents[key];

  @override
  Future<void> storeDocument(String key, Map<String, dynamic> document) async {
    _documents[key] = document;
  }
}
