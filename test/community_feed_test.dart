import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/screens/community_screen.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';

CommunityPost _post(
  String id, {
  int likes = 0,
  int day = 1,
  bool photo = true,
  bool own = false,
}) => CommunityPost(
  id: id,
  author: '작성자 $id',
  content: '운동 이야기 $id',
  metric: '오늘 운동',
  createdAt: DateTime(2026, 10, day),
  visualKey: 'strength',
  color: SetflowColors.teal,
  likes: likes,
  isMine: own,
  imageUrl: photo ? 'https://example.com/$id.jpg' : null,
);

Finder _photo(String id) => find.byKey(ValueKey('community-photo-$id'));

typedef _FeedQuery = ({
  CommunityFeedOrder order,
  CommunityFeedMedia media,
  int limit,
  int offset,
});

void main() {
  Future<AppState> pumpFeed(
    WidgetTester tester,
    _FeedRepository repository, {
    Size size = const Size(432, 900),
    double scale = 1,
    bool dark = false,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(communityRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: dark ? SetflowTheme.dark : SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(bottom: 28),
              viewPadding: const EdgeInsets.only(bottom: 28),
            ),
            child: child!,
          ),
          home: const CommunityScreen(),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    return state;
  }

  test(
    'local feed filters before paging and breaks popularity ties by recency',
    () {
      final page = CommunityFeedPage.fromAllPosts(
        [
          _post('text', likes: 1000, photo: false),
          _post('old', likes: 12),
          _post('new', likes: 12, day: 3),
          _post('newest', day: 4),
        ],
        order: CommunityFeedOrder.popular,
        media: CommunityFeedMedia.photos,
        limit: 1,
        offset: 1,
      );
      expect(page.posts.single.id, 'old');
      expect(page.hasMore, isTrue);
      final latest = CommunityFeedPage.fromAllPosts(
        [_post('b', day: 4), _post('a', day: 4)],
        order: CommunityFeedOrder.latest,
        media: CommunityFeedMedia.photos,
        limit: 24,
        offset: 0,
      );
      expect(latest.posts.map((post) => post.id), ['b', 'a']);
      expect(latest.hasMore, isFalse);
      expect(
        CommunityFeedMedia.photos.includes(_post('text', photo: false)),
        isFalse,
      );
    },
  );

  testWidgets('photos fill two large columns with no board captions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _FeedRepository([
      _post('old', likes: 20),
      _post('new', day: 2),
      _post('text', photo: false),
    ]);
    await pumpFeed(tester, repository);
    final left = tester.getRect(_photo('new'));
    final right = tester.getRect(_photo('old'));
    expect(left.left, SetflowSpacing.gutter);
    expect(right.right, 432 - SetflowSpacing.gutter);
    expect(left.top, right.top);
    expect(left.width, greaterThan(190));
    expect(left.height / left.width, closeTo(4 / 3, 0.01));
    expect(find.text('운동 이야기 new'), findsNothing);
    expect(find.text('작성자 new'), findsNothing);
    expect(_photo('text'), findsNothing);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .every((image) => image.fit == BoxFit.cover),
      isTrue,
    );
    expect(
      find.bySemanticsLabel('작성자 new의 사진 게시물, 좋아요 0개, 상세 보기'),
      findsOneWidget,
    );
    expect(repository.calls.single.media, CommunityFeedMedia.photos);
    expect(find.byIcon(SetflowIcons.imageUnavailable), findsWidgets);

    await tester.tap(find.text('인기순'));
    await tester.pumpAndSettle();
    expect(tester.getRect(_photo('old')).left, SetflowSpacing.gutter);
    expect(repository.calls.last.order, CommunityFeedOrder.popular);
    expect(repository.calls.last.offset, 0);
    semantics.dispose();
  });

  testWidgets(
    'text posts stay accessible in a separate screen and open detail',
    (tester) async {
      await pumpFeed(
        tester,
        _FeedRepository([_post('photo'), _post('text', photo: false)]),
      );
      await tester.tap(find.text('사진 없는 글'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('community-text-text')), findsOneWidget);
      expect(find.text('운동 이야기 photo'), findsNothing);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('운동 이야기 text'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityPostDetailScreen), findsOneWidget);
      expect(find.text('운동 이야기 text'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_photo('photo'), findsOneWidget);
    },
  );

  testWidgets(
    'deleting an owned post removes it from the loaded feed on return',
    (tester) async {
      final repository = _FeedRepository([
        _post('mine', own: true),
        _post('other'),
      ]);
      await pumpFeed(tester, repository);
      final requestCount = repository.calls.length;
      await tester.tap(_photo('mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('게시물 메뉴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('글 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(_photo('mine'), findsNothing);
      expect(_photo('other'), findsOneWidget);
      expect(repository.calls, hasLength(requestCount));
    },
  );

  testWidgets('a guest opens a photo and reads its full post', (tester) async {
    await pumpFeed(tester, _FeedRepository([_post('photo')]));
    await tester.tap(_photo('photo'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityPostDetailScreen), findsOneWidget);
    expect(find.text('운동 이야기 photo'), findsOneWidget);
  });

  testWidgets('a guest is asked to sign in only when writing a post', (
    tester,
  ) async {
    final repository = _FeedRepository([_post('photo')]);
    await pumpFeed(tester, repository);
    expect(_photo('photo'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('community-compose')));
    await tester.pumpAndSettle();
    expect(find.textContaining('커뮤니티에 흔적을 남기려면'), findsOneWidget);
    expect(find.byType(SocialPostComposerScreen), findsNothing);
  });

  testWidgets('pull to refresh loads newly shared photos', (tester) async {
    final repository = _FeedRepository([_post('old')]);
    await pumpFeed(tester, repository);
    repository.posts.add(_post('new', day: 2));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(_photo('new'), findsOneWidget);
    expect(repository.calls, hasLength(2));
  });

  testWidgets('cached results disclose their status and can reconnect', (
    tester,
  ) async {
    final repository = _FeedRepository([])
      ..onList = (_) async => CommunityFeedPage(
        posts: [_post('cached')],
        hasMore: false,
        isCached: true,
      );
    await pumpFeed(tester, repository);
    expect(_photo('cached'), findsOneWidget);
    expect(find.text('저장된 게시물을 보여드리고 있어요.'), findsOneWidget);
    repository.onList = (_) async =>
        CommunityFeedPage(posts: [_post('fresh')], hasMore: false);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(_photo('fresh'), findsOneWidget);
    expect(find.text('저장된 게시물을 보여드리고 있어요.'), findsNothing);
  });

  testWidgets('changing account discards an in-flight viewer overlay', (
    tester,
  ) async {
    final previous = Completer<CommunityFeedPage>();
    final repository = _FeedRepository([]);
    repository.onList = (_) => repository.calls.length == 1
        ? previous.future
        : Future.value(
            CommunityFeedPage(posts: [_post('guest')], hasMore: false),
          );
    final state = await pumpFeed(tester, repository, settle: false);
    state.handleExternalAuthSignedOut();
    await tester.pumpAndSettle();
    previous.complete(
      CommunityFeedPage(posts: [_post('previous-member')], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(_photo('guest'), findsOneWidget);
    expect(_photo('previous-member'), findsNothing);
  });

  test(
    'reactions on a paged instance update the home preview and roll back on failure',
    () async {
      final state = AppState(
        communityRepository: _FeedRepository([_post('same')]),
      );
      await state.initialize();
      addTearDown(state.dispose);
      final paged = _post('same');
      final future = state.togglePostLike(paged);
      expect(state.communityPosts.single.likes, 1);
      await expectLater(
        future,
        throwsA(isA<CommunityAuthenticationRequired>()),
      );
      expect(state.communityPosts.single.likes, 0);
      expect(state.communityPosts.single.isLiked, isFalse);
    },
  );

  testWidgets('paging keeps loaded photos and retries the failed next page', (
    tester,
  ) async {
    final repository = _FeedRepository([
      for (var i = 0; i < 26; i++) _post('p$i', day: i + 1),
    ])..failNextPage = true;
    await pumpFeed(tester, repository);
    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
    }
    expect(repository.calls.last.offset, 24);
    expect(repository.calls.where((query) => query.offset == 24), hasLength(1));
    expect(
      tester
          .widget<SliverGrid>(find.byType(SliverGrid))
          .delegate
          .estimatedChildCount,
      24,
    );
    expect(find.text('게시물을 더 불러오지 못했어요.'), findsOneWidget);
    repository.failNextPage = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.offset, 24);
    expect(
      tester
          .widget<SliverGrid>(find.byType(SliverGrid))
          .delegate
          .estimatedChildCount,
      26,
    );
    expect(find.text('게시물을 더 불러오지 못했어요.'), findsNothing);
    await tester.ensureVisible(_photo('p0'));
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    final requests = repository.calls.length;
    await tester.tap(_photo('p0'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SliverGrid>(find.byType(SliverGrid))
          .delegate
          .estimatedChildCount,
      26,
    );
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      closeTo(position, 0.01),
    );
    expect(repository.calls, hasLength(requests));
  });

  test('successful paged reactions reach the separate home instance', () async {
    final repository = _FeedRepository([_post('same')])
      ..likeResult = const CommunityLikeResult(isLiked: true, likesCount: 8)
      ..commentResult = PostComment(
        id: 'reply',
        author: '회원',
        content: '응원해요',
        createdAt: DateTime(2026),
      );
    final state = AppState(communityRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    final paged = _post('same');
    await state.togglePostLike(paged);
    expect(state.communityPosts.single.likes, 8);
    expect(state.communityPosts.single.isLiked, isTrue);
    await state.addPostComment(paged, '응원해요');
    expect(state.communityPosts.single.comments.single.id, 'reply');
    expect(paged.comments.single.id, 'reply');
  });

  test(
    'a reaction finishing after sign-out cannot change the new viewer overlay',
    () async {
      final pending = Completer<CommunityLikeResult>();
      final repository = _FeedRepository([_post('same')])
        ..onLike = (_) => pending.future;
      final state = AppState(communityRepository: repository);
      await state.initialize();
      addTearDown(state.dispose);
      final operation = state.togglePostLike(_post('same'));
      state.handleExternalAuthSignedOut();
      state.communityPosts
        ..clear()
        ..add(_post('same'));
      pending.complete(const CommunityLikeResult(isLiked: true, likesCount: 8));
      await operation;
      expect(state.communityPosts.single.isLiked, isFalse);
      expect(state.communityPosts.single.likes, 0);
    },
  );

  testWidgets('an older request cannot overwrite a new sort selection', (
    tester,
  ) async {
    final latest = Completer<CommunityFeedPage>();
    final popular = Completer<CommunityFeedPage>();
    final repository = _FeedRepository([])
      ..onList = (query) => query.order == CommunityFeedOrder.latest
          ? latest.future
          : popular.future;
    await pumpFeed(tester, repository, settle: false);
    await tester.tap(find.text('인기순'));
    await tester.pump();
    popular.complete(
      CommunityFeedPage(posts: [_post('popular')], hasMore: false),
    );
    await tester.pumpAndSettle();
    latest.complete(
      CommunityFeedPage(posts: [_post('latest')], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(_photo('popular'), findsOneWidget);
    expect(_photo('latest'), findsNothing);
  });

  testWidgets(
    'empty and failed feeds show different states with a working retry',
    (tester) async {
      final repository = _FeedRepository([])..failAll = true;
      await pumpFeed(tester, repository);
      expect(find.text('게시물을 불러오지 못했어요'), findsOneWidget);
      repository.failAll = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('아직 사진이 없어요'), findsOneWidget);
      expect(find.text('사진 없는 글'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'photo and text feeds survive 2x text on a small ${dark ? 'dark' : 'light'} screen',
      (tester) async {
        await pumpFeed(
          tester,
          _FeedRepository([_post('photo'), _post('text', photo: false)]),
          size: const Size(320, 700),
          scale: 2,
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('community-compose')))
              .bottom,
          lessThanOrEqualTo(672),
        );
        await tester.tap(find.text('사진 없는 글'));
        await tester.pumpAndSettle();
        expect(find.text('운동 이야기 text'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _FeedRepository implements CommunityRepository {
  _FeedRepository(this.posts);

  final List<CommunityPost> posts;
  final List<_FeedQuery> calls = [];
  Future<CommunityFeedPage> Function(_FeedQuery)? onList;
  bool failAll = false;
  bool failNextPage = false;
  CommunityLikeResult? likeResult;
  PostComment? commentResult;
  Future<CommunityLikeResult> Function(String)? onLike;

  @override
  Future<CommunityFeedPage> listFeed({
    CommunityFeedOrder order = CommunityFeedOrder.latest,
    CommunityFeedMedia media = CommunityFeedMedia.photos,
    int limit = 24,
    int offset = 0,
  }) async {
    final query = (order: order, media: media, limit: limit, offset: offset);
    calls.add(query);
    if (failAll || (failNextPage && offset > 0)) throw StateError('offline');
    if (onList != null) return onList!(query);
    return CommunityFeedPage.fromAllPosts(
      posts,
      order: order,
      media: media,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<CommunityPostRecord>> fetchPosts({
    int limit = 50,
    int offset = 0,
  }) async => posts
      .skip(offset)
      .take(limit)
      .map((post) => CommunityPostRecord(post: post, authorUserId: 'author'))
      .toList();

  @override
  Future<CommunityPostRecord> createPost(
    CreateCommunityPostInput input,
  ) async => throw const CommunityAuthenticationRequired();

  @override
  Future<CommunityLikeResult> toggleLike(String postId) async {
    if (onLike != null) return onLike!(postId);
    return likeResult ?? (throw const CommunityAuthenticationRequired());
  }

  @override
  Future<void> updatePostContent({
    required String postId,
    required String content,
  }) async =>
      throw UnsupportedError('Post editing is not configured for this test.');

  @override
  Future<void> deletePost(String postId) async {
    posts.removeWhere((post) => post.id == postId);
  }

  @override
  Future<PostComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
  }) async => commentResult ?? (throw const CommunityAuthenticationRequired());
}
