import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/backend_cache.dart';
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/data/supabase_community_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _authorUserId = '11111111-1111-4111-8111-111111111111';
const _postId = '22222222-2222-4222-8222-222222222222';

void main() {
  test('a guest reads the feed without a session', () async {
    final backend = await _CommunityBackend.start();
    addTearDown(backend.close);

    final posts = await SupabaseCommunityRepository(
      backend.client,
    ).fetchPosts();

    expect(posts, hasLength(1));
    final post = posts.single.post;
    expect(post.id, _postId);
    expect(post.content, '오늘 하체 100% 완료');
    expect(post.comments.single.content, '멋져요!');
    // Nothing here belongs to a guest, and asking for it would 401.
    expect(post.isMine, isFalse);
    expect(post.comments.single.author, '응원하는 회원');
    expect(post.isLiked, isFalse);
    expect(backend.requestedResources, isNot(contains('post_likes')));
  });

  test('a signed-in reader still gets their own like overlay', () async {
    final backend = await _CommunityBackend.start(signedInAs: _authorUserId);
    addTearDown(backend.close);

    final posts = await SupabaseCommunityRepository(
      backend.client,
    ).fetchPosts();

    expect(backend.requestedResources, contains('post_likes'));
    expect(posts.single.post.isLiked, isTrue);
    expect(posts.single.post.isMine, isTrue);
  });

  test('the last feed remains available during a Data API outage', () async {
    final backend = await _CommunityBackend.start();
    final cache = _MemoryBackendCache();
    addTearDown(backend.close);
    final repository = SupabaseCommunityRepository(
      backend.client,
      cache: cache,
    );

    final fresh = await repository.fetchPosts();
    backend.failDataApi = true;
    final fallback = await repository.fetchPosts();

    expect(fresh.single.post.content, '오늘 하체 100% 완료');
    expect(fallback.single.post.content, fresh.single.post.content);
    expect(fallback.single.post.comments.single.content, '멋져요!');
    expect(repository.isUsingCachedData, isTrue);
    expect(repository.lastReadError, isNotNull);
  });

  test('app state loads the shared feed while signed out', () async {
    final repository = _RecordingCommunityRepository();
    final state = AppState(communityRepository: repository);
    addTearDown(state.dispose);

    await state.initialize();

    expect(repository.fetchCount, 1);
    expect(state.communityPosts.single.id, _postId);
  });

  test('anon keeps read access to the feed tables', () {
    final sql = File(
      'supabase/migrations/20260821132444_public_community_feed_read.sql',
    ).readAsStringSync();

    expect(sql, contains('grant select on table public.posts to anon;'));
    expect(sql, contains('grant select on table public.comments to anon;'));
    // Writing and "my likes" stay behind an account.
    expect(sql, isNot(contains('insert')));
    expect(sql, isNot(contains('post_likes to anon')));
  });
}

class _RecordingCommunityRepository implements CommunityRepository {
  int fetchCount = 0;

  @override
  Future<List<CommunityPostRecord>> fetchPosts({
    int limit = 50,
    int offset = 0,
  }) async {
    fetchCount++;
    return [
      CommunityPostRecord(
        post: CommunityPost(
          id: _postId,
          author: '오운완 민지',
          content: '오늘 하체 100% 완료',
          metric: '하체 · 12세트',
          createdAt: DateTime(2026, 8, 21),
          visualKey: 'strength',
          color: const Color(0xFF10CEBD),
        ),
        authorUserId: _authorUserId,
      ),
    ];
  }

  @override
  Future<CommunityPostRecord> createPost(
    CreateCommunityPostInput input,
  ) async => throw const CommunityAuthenticationRequired();

  @override
  Future<CommunityLikeResult> toggleLike(String postId) async =>
      throw const CommunityAuthenticationRequired();

  @override
  Future<PostComment> addComment({
    required String postId,
    required String content,
  }) async => throw const CommunityAuthenticationRequired();
}

class _CommunityBackend {
  _CommunityBackend._(this._server, this.client);

  final HttpServer _server;
  final SupabaseClient client;
  final List<String> requestedResources = [];
  bool failDataApi = false;

  static Future<_CommunityBackend> start({String? signedInAs}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
    final backend = _CommunityBackend._(server, client);
    server.listen(backend._handle);
    if (signedInAs != null) {
      await client.auth.recoverSession(
        jsonEncode({
          'access_token': 'test-access-token',
          'refresh_token': 'test-refresh-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': signedInAs,
            'email': 'member@example.com',
            'app_metadata': const <String, Object?>{},
            'user_metadata': const <String, Object?>{},
            'aud': 'authenticated',
            'created_at': '2026-08-21T00:00:00Z',
          },
        }),
      );
    }
    return backend;
  }

  Future<void> close() async {
    client.dispose();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    await request.drain<void>();
    if (failDataApi) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'code': 'PGRST002',
            'message': 'Could not query the database for the schema cache.',
          }),
        );
      await request.response.close();
      return;
    }
    final resource = request.uri.pathSegments.last;
    requestedResources.add(resource);
    final Object body = switch (resource) {
      'posts' => [
        {
          'id': _postId,
          'user_id': _authorUserId,
          'author_name': '오운완 민지',
          'content': '오늘 하체 100% 완료',
          'metric': '하체 · 12세트',
          'visual_key': 'strength',
          'image_url': '$_authorUserId/leg-day.jpg',
          'image_color': '#FF10CEBD',
          'location': null,
          'routine_name': '하체 루틴',
          'active_overlays': const ['날짜'],
          'likes_count': 4,
          'created_at': '2026-08-21T09:00:00Z',
        },
      ],
      'comments' => [
        {
          'id': '33333333-3333-4333-8333-333333333333',
          'post_id': _postId,
          'user_id': '44444444-4444-4444-8444-444444444444',
          'author_name': '응원하는 회원',
          'text': '멋져요!',
          'created_at': '2026-08-21T10:00:00Z',
        },
      ],
      'post_likes' => [
        {'post_id': _postId},
      ],
      _ => throw StateError('Unexpected test request: ${request.uri}'),
    };
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }
}

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
