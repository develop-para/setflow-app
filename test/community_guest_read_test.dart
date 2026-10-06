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
  test(
    'a first server comment updates an empty feed post without throwing',
    () async {
      final backend = await _CommunityBackend.start(signedInAs: _authorUserId);
      backend.commentRows = [];
      addTearDown(backend.close);
      final repository = SupabaseCommunityRepository(backend.client);
      final state = AppState(communityRepository: repository);
      addTearDown(state.dispose);
      await state.initialize();
      final post = state.communityPosts.single;
      expect(post.comments, isEmpty);

      await state.addPostComment(post, '첫 댓글이에요.');

      expect(post.comments.single.content, '첫 댓글이에요.');
      expect(backend.commentWrites, hasLength(1));
      expect(
        backend.commentWrites.single,
        isNot(contains('parent_comment_id')),
      );
      expect(
        (await repository.fetchPosts()).single.post.comments.single.content,
        '첫 댓글이에요.',
      );
    },
  );

  test(
    'replies retain their parent through server reads and cached reads',
    () async {
      final backend = await _CommunityBackend.start(signedInAs: _authorUserId);
      addTearDown(backend.close);
      final repository = SupabaseCommunityRepository(
        backend.client,
        cache: _MemoryBackendCache(),
      );
      final root = (await repository.fetchPosts()).single.post.comments.single;
      final reply = await repository.addComment(
        postId: _postId,
        content: '함께 응원해요.',
        parentCommentId: root.id,
      );
      expect(reply.parentCommentId, root.id);
      expect(backend.commentWrites.single['parent_comment_id'], root.id);
      final fresh = await repository.fetchPosts();
      expect(fresh.single.post.comments.last.parentCommentId, root.id);
      backend.failDataApi = true;
      final cached = await repository.fetchPosts();
      expect(cached.single.post.comments.last.parentCommentId, root.id);
    },
  );

  test(
    'comment authorization and schema failures cross the port as domain errors',
    () async {
      final backend = await _CommunityBackend.start(signedInAs: _authorUserId);
      addTearDown(backend.close);
      final repository = SupabaseCommunityRepository(backend.client);
      for (final entry in {
        '42501': '권한',
        'PGRST204': '서버 업데이트',
        '23503': '삭제',
      }.entries) {
        backend.writeErrorCode = entry.key;
        await expectLater(
          repository.addComment(postId: _postId, content: '응원합니다.'),
          throwsA(
            isA<CommunityOperationException>().having(
              (error) => error.message,
              'message',
              contains(entry.value),
            ),
          ),
        );
      }
    },
  );

  test(
    'post mutations restrict requests to the current author and detect empty results',
    () async {
      final backend = await _CommunityBackend.start(signedInAs: _authorUserId);
      addTearDown(backend.close);
      final repository = SupabaseCommunityRepository(backend.client);
      await repository.updatePostContent(postId: _postId, content: '수정된 운동 기록');
      expect(
        backend.postWrites.single.uri.queryParameters['user_id'],
        'eq.$_authorUserId',
      );
      expect(backend.postWrites.single.body['content'], '수정된 운동 기록');
      await repository.deletePost(_postId);
      expect(backend.postWrites.last.method, 'DELETE');
      expect(
        backend.postWrites.last.uri.queryParameters['user_id'],
        'eq.$_authorUserId',
      );
      backend.emptyMutationResult = true;
      await expectLater(
        repository.updatePostContent(postId: _postId, content: '거부될 수정'),
        throwsA(isA<CommunityOperationException>()),
      );
      await expectLater(
        repository.deletePost(_postId),
        throwsA(isA<CommunityOperationException>()),
      );
    },
  );

  test(
    'successful post writes invalidate old cached pages even for a new adapter',
    () async {
      final backend = await _CommunityBackend.start(signedInAs: _authorUserId);
      addTearDown(backend.close);
      final cache = _MemoryBackendCache();
      final repository = SupabaseCommunityRepository(
        backend.client,
        cache: cache,
      );
      await repository.fetchPosts();
      await repository.deletePost(_postId);
      backend.failDataApi = true;
      final reopened = SupabaseCommunityRepository(
        backend.client,
        cache: cache,
      );
      await expectLater(
        reopened.fetchPosts(),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test(
    'post deletion cleans up only its own media and tolerates cleanup failure',
    () async {
      final backend = await _CommunityBackend.start(signedInAs: _authorUserId);
      addTearDown(backend.close);
      final repository = SupabaseCommunityRepository(backend.client);
      backend.deletedImagePath = '$_authorUserId/workout.jpg';
      await repository.deletePost(_postId);
      expect(backend.removedImagePaths, ['$_authorUserId/workout.jpg']);
      backend.deletedImagePath = 'another-user/workout.jpg';
      await repository.deletePost(_postId);
      expect(backend.removedImagePaths, hasLength(1));
      backend.deletedImagePath = '$_authorUserId/other.jpg';
      backend.failStorageDelete = true;
      await repository.deletePost(_postId);
      expect(backend.removedImagePaths.last, '$_authorUserId/other.jpg');
    },
  );

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

  test('photo popularity is queried globally before pagination', () async {
    final backend = await _CommunityBackend.start();
    addTearDown(backend.close);
    backend.postRows = [
      for (var i = 0; i < 60; i++)
        {
          'id': 'post-$i',
          'user_id': _authorUserId,
          'author_name': '회원',
          'content': '기록 $i',
          'image_url': i == 59 ? null : '$_authorUserId/$i.jpg',
          'likes_count': i == 0 ? 500 : i,
          'created_at': DateTime(
            2026,
            1,
            1,
          ).add(Duration(days: i)).toIso8601String(),
        },
    ];
    final page = await SupabaseCommunityRepository(
      backend.client,
    ).listFeed(order: CommunityFeedOrder.popular, limit: 2);
    expect(page.posts.map((post) => post.id), ['post-0', 'post-58']);
    expect(page.hasMore, isTrue);
    final query = backend.postRequests.single.queryParametersAll;
    expect(query['order'], [
      'likes_count.desc.nullslast,created_at.desc.nullslast,id.desc.nullslast',
    ]);
    expect(query['image_url'], containsAll(['not.is.null', 'neq.']));
    expect(query['limit'], ['2']);
    expect(backend.requestedResources, isNot(contains('post_likes')));
  });

  test(
    'text feed includes null and empty media and has deterministic newest ordering',
    () async {
      final backend = await _CommunityBackend.start();
      addTearDown(backend.close);
      backend.postRows = [
        for (final entry in {'a': null, 'b': '', 'c': 'photo.jpg'}.entries)
          {
            'id': entry.key,
            'user_id': _authorUserId,
            'image_url': entry.value,
            'created_at': '2026-10-04T10:00:00Z',
            'likes_count': 0,
          },
      ];
      final page = await SupabaseCommunityRepository(
        backend.client,
      ).listFeed(media: CommunityFeedMedia.textOnly);
      expect(page.posts.map((post) => post.id), ['b', 'a']);
      expect(
        backend.postRequests.single.queryParameters['or'],
        '(image_url.is.null,image_url.eq.)',
      );
      expect(
        backend.postRequests.single.queryParameters['order'],
        'created_at.desc.nullslast,id.desc.nullslast',
      );
    },
  );

  test('offline cache keeps sort, media, size, and offset separate', () async {
    final backend = await _CommunityBackend.start();
    addTearDown(backend.close);
    final repository = SupabaseCommunityRepository(
      backend.client,
      cache: _MemoryBackendCache(),
    );
    final fresh = await repository.listFeed(
      order: CommunityFeedOrder.popular,
      limit: 1,
    );
    backend.failDataApi = true;
    final cached = await repository.listFeed(
      order: CommunityFeedOrder.popular,
      limit: 1,
    );
    expect(cached.posts.single.id, fresh.posts.single.id);
    expect(cached.isCached, isTrue);
    await Future.wait(
      [
        repository.listFeed(order: CommunityFeedOrder.latest, limit: 1),
        repository.listFeed(
          order: CommunityFeedOrder.popular,
          media: CommunityFeedMedia.textOnly,
          limit: 1,
        ),
        repository.listFeed(order: CommunityFeedOrder.popular, limit: 2),
        repository.listFeed(
          order: CommunityFeedOrder.popular,
          limit: 1,
          offset: 1,
        ),
      ].map(
        (future) => expectLater(future, throwsA(isA<PostgrestException>())),
      ),
    );
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

  test('a member cached like overlay is never used for a guest', () async {
    final member = await _CommunityBackend.start(signedInAs: _authorUserId);
    final guest = await _CommunityBackend.start();
    addTearDown(member.close);
    addTearDown(guest.close);
    final cache = _MemoryBackendCache();
    final memberRepository = SupabaseCommunityRepository(
      member.client,
      cache: cache,
    );
    final guestRepository = SupabaseCommunityRepository(
      guest.client,
      cache: cache,
    );
    expect((await memberRepository.listFeed()).posts.single.isLiked, isTrue);
    guest.failDataApi = true;
    await expectLater(
      guestRepository.listFeed(),
      throwsA(isA<PostgrestException>()),
    );
    guest.failDataApi = false;
    expect((await guestRepository.listFeed()).posts.single.isLiked, isFalse);
    member.failDataApi = true;
    final cached = await memberRepository.listFeed();
    expect(cached.isCached, isTrue);
    expect(cached.posts.single.isLiked, isTrue);
  });
}

class _RecordingCommunityRepository implements CommunityRepository {
  int fetchCount = 0;

  @override
  Future<CommunityFeedPage> listFeed({
    CommunityFeedOrder order = CommunityFeedOrder.latest,
    CommunityFeedMedia media = CommunityFeedMedia.photos,
    int limit = 24,
    int offset = 0,
  }) async => CommunityFeedPage.fromAllPosts(
    (await fetchPosts()).map((record) => record.post),
    order: order,
    media: media,
    limit: limit,
    offset: offset,
  );

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
  Future<void> updatePostContent({
    required String postId,
    required String content,
  }) async =>
      throw UnsupportedError('Post editing is not configured for this test.');

  @override
  Future<void> deletePost(String postId) async =>
      throw UnsupportedError('Post deletion is not configured for this test.');

  @override
  Future<PostComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
  }) async => throw const CommunityAuthenticationRequired();
}

class _CommunityBackend {
  _CommunityBackend._(this._server, this.client);

  final HttpServer _server;
  final SupabaseClient client;
  final List<String> requestedResources = [];
  final List<Uri> postRequests = [];
  List<Map<String, Object?>>? postRows;
  List<Map<String, Object?>>? commentRows;
  final List<Map<String, dynamic>> commentWrites = [];
  final List<({String method, Uri uri, Map<String, dynamic> body})> postWrites =
      [];
  String? writeErrorCode;
  bool emptyMutationResult = false;
  String? deletedImagePath;
  final List<String> removedImagePaths = [];
  bool failStorageDelete = false;
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
    final payload = await utf8.decoder.bind(request).join();
    final input = payload.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(payload) as Map);
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
    if (resource == 'post-images' && request.method == 'DELETE') {
      removedImagePaths.addAll((input['prefixes'] as List).cast<String>());
      request.response
        ..statusCode = failStorageDelete ? HttpStatus.forbidden : HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(failStorageDelete ? {'message': 'Storage refusal'} : []),
        );
      await request.response.close();
      return;
    }
    if (request.method != 'GET' && writeErrorCode != null) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({'code': writeErrorCode, 'message': 'Test write refusal'}),
        );
      await request.response.close();
      return;
    }
    Object body = switch (resource) {
      'posts' => _queryPosts(request.uri, [
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
      ]),
      'comments' =>
        commentRows ??
            [
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
      'users' => {'nickname': '회원'},
      _ => throw StateError('Unexpected test request: ${request.uri}'),
    };
    if (resource == 'comments' && request.method == 'POST') {
      commentWrites.add(input);
      final row = <String, Object?>{
        ...input,
        'id': 'new-comment-${commentWrites.length}',
        'created_at': '2026-10-05T00:00:00Z',
      };
      commentRows = [...(body as List).cast<Map<String, Object?>>(), row];
      body = row;
    }
    if (resource == 'posts' &&
        (request.method == 'PATCH' || request.method == 'DELETE')) {
      postWrites.add((method: request.method, uri: request.uri, body: input));
      body = emptyMutationResult
          ? <Object>[]
          : [
              {'id': _postId, 'image_url': deletedImagePath},
            ];
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  List<Map<String, Object?>> _queryPosts(
    Uri uri,
    List<Map<String, Object?>> defaults,
  ) {
    postRequests.add(uri);
    var rows = List<Map<String, Object?>>.from(postRows ?? defaults);
    final filters = uri.queryParametersAll['image_url'] ?? const [];
    if (filters.contains('not.is.null')) {
      rows = rows.where((row) => row['image_url'] != null).toList();
    }
    if (filters.contains('neq.')) {
      rows = rows.where((row) => row['image_url'] != '').toList();
    }
    if (uri.queryParameters['or'] == '(image_url.is.null,image_url.eq.)') {
      rows = rows
          .where((row) => row['image_url'] == null || row['image_url'] == '')
          .toList();
    }
    final orders = (uri.queryParameters['order'] ?? '').split(',');
    rows.sort((a, b) {
      for (final order in orders) {
        final field = order.split('.').first;
        final valueA = a[field], valueB = b[field];
        final diff = valueA is int && valueB is int
            ? valueB.compareTo(valueA)
            : '$valueB'.compareTo('$valueA');
        if (diff != 0) return diff;
      }
      return 0;
    });
    return rows
        .skip(int.parse(uri.queryParameters['offset'] ?? '0'))
        .take(int.parse(uri.queryParameters['limit'] ?? '50'))
        .toList();
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
