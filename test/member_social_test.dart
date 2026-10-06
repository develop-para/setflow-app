import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/services/post_media_picker.dart';
import 'package:setflow/theme.dart';

void main() {
  Future<({AppState state, CommunityPost post})> pumpManagedPost(
    WidgetTester tester,
    _FakeCommunityRepository repository, {
    bool own = true,
    bool signedIn = true,
    double scale = 1,
  }) async {
    if (signedIn) {
      Auth.use(_SignedInAuth());
    } else {
      Auth.reset();
    }
    addTearDown(Auth.reset);
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(communityRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    final post = CommunityPost(
      id: 'managed-post',
      author: '테스터',
      content: '원래 운동 기록',
      metric: '오늘 운동',
      createdAt: DateTime(2026, 10, 5),
      visualKey: 'strength',
      color: SetflowColors.teal,
      isMine: own,
      comments: const [],
    );
    state.communityPosts.add(post);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(bottom: 28),
              viewPadding: const EdgeInsets.only(bottom: 28),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => CommunityPostDetailScreen(post: post),
                  ),
                ),
                child: const Text('글 열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('글 열기'));
    await tester.pumpAndSettle();
    return (state: state, post: post);
  }

  testWidgets('first comment displays and repeated taps submit only once', (
    tester,
  ) async {
    final repository = _FakeCommunityRepository();
    final pending = Completer<PostComment>();
    repository.pendingComment = pending.future;
    final result = await pumpManagedPost(tester, repository);
    await tester.enterText(find.byType(TextFormField), '첫 댓글');
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pump();
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pump();
    expect(repository.commentCalls, 1);
    pending.complete(
      PostComment(
        id: 'first-comment',
        author: '테스터',
        content: '첫 댓글',
        createdAt: DateTime(2026),
      ),
    );
    await tester.pumpAndSettle();
    expect(result.post.comments.single.content, '첫 댓글');
    expect(find.text('게시물을 등록하지 못했어요. 네트워크를 확인한 뒤 다시 시도해주세요.'), findsNothing);
  });

  testWidgets(
    'comment failures preserve the draft and a reply targets the root',
    (tester) async {
      final repository = _FakeCommunityRepository();
      final result = await pumpManagedPost(tester, repository, scale: 2);
      repository.commentError = const CommunityOperationException(
        '댓글을 저장할 권한이 없어요.',
      );
      await tester.enterText(find.byType(TextFormField), '잃으면 안 되는 댓글');
      await tester.tap(find.byTooltip('댓글 등록'));
      await tester.pump();
      expect(result.post.comments, isEmpty);
      expect(find.text('댓글을 저장할 권한이 없어요.'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '잃으면 안 되는 댓글',
      );
      repository.commentError = null;
      await tester.tap(find.byTooltip('댓글 등록'));
      await tester.pumpAndSettle();
      final root = result.post.comments.single;
      await tester.ensureVisible(find.byKey(ValueKey('reply-${root.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('reply-${root.id}')));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '답글이에요');
      await tester.tap(find.byTooltip('댓글 등록'));
      await tester.pumpAndSettle();
      final reply = result.post.comments.last;
      expect(reply.parentCommentId, root.id);
      expect(find.text('답글 취소'), findsNothing);
      await tester.ensureVisible(find.byKey(ValueKey('reply-${reply.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('reply-${reply.id}')));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '답글에 다시 답글');
      await tester.tap(find.byTooltip('댓글 등록'));
      await tester.pumpAndSettle();
      expect(result.post.comments.last.parentCommentId, root.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only the author has post management actions', (tester) async {
    await pumpManagedPost(tester, _FakeCommunityRepository(), own: false);
    expect(find.byTooltip('게시물 메뉴'), findsNothing);
  });

  testWidgets(
    'comments and replies fold without losing the reply draft at large text scale',
    (tester) async {
      final repository = _FakeCommunityRepository();
      final result = await pumpManagedPost(tester, repository, scale: 2);
      await result.state.addPostComment(result.post, '접을 댓글');
      final root = result.post.comments.single;
      await result.state.addPostComment(
        result.post,
        '접을 답글',
        parentCommentId: root.id,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey('reply-${root.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('reply-${root.id}')));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), '작성 중인 답글');
      final toggle = find.byKey(const ValueKey('community-comments-toggle'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pump();

      expect(find.text('댓글 펼치기'), findsOneWidget);
      expect(find.text('댓글 2'), findsOneWidget);
      expect(find.byKey(ValueKey('reply-${root.id}')), findsNothing);
      expect(find.text('접을 댓글'), findsNothing);
      expect(find.text('접을 답글'), findsNothing);
      expect(result.post.comments, hasLength(2));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '작성 중인 답글',
      );
      expect(find.byTooltip('답글 취소'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();
      expect(find.text('접을 댓글'), findsOneWidget);
      expect(find.text('접을 답글'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();
      await tester.tap(find.byTooltip('댓글 등록'));
      await tester.pumpAndSettle();
      expect(result.post.comments.last.content, '작성 중인 답글');
      expect(result.post.comments.last.parentCommentId, root.id);
      expect(find.text('댓글 접기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a guest can fold and unfold an empty comment section', (
    tester,
  ) async {
    await pumpManagedPost(
      tester,
      _FakeCommunityRepository(),
      own: false,
      signedIn: false,
    );
    final toggle = find.byKey(const ValueKey('community-comments-toggle'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('댓글 펼치기'), findsOneWidget);
    expect(find.text('첫 댓글을 남겨보세요'), findsNothing);
    expect(find.byTooltip('댓글 등록'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.text('첫 댓글을 남겨보세요'), findsOneWidget);
    expect(find.textContaining('커뮤니티에 흔적을 남기려면'), findsNothing);
  });

  testWidgets(
    'editing keeps failed input and applies text only after server success',
    (tester) async {
      final repository = _FakeCommunityRepository();
      final result = await pumpManagedPost(tester, repository, scale: 2);
      await tester.tap(find.byTooltip('게시물 메뉴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('글 수정'));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityPostEditScreen), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, '수정한 운동 기록');
      repository.mutationError = const CommunityOperationException(
        '수정 권한을 확인해 주세요.',
      );
      await tester.tap(find.text('저장'));
      await tester.pump();
      expect(result.post.content, '원래 운동 기록');
      expect(find.text('수정한 운동 기록'), findsOneWidget);
      repository.mutationError = null;
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(result.post.content, '수정한 운동 기록');
      expect(repository.updatedContent, '수정한 운동 기록');
      expect(find.byType(CommunityPostEditScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deletion requires confirmation and returns to the feed on success',
    (tester) async {
      final repository = _FakeCommunityRepository();
      final result = await pumpManagedPost(tester, repository);
      Future<void> requestDelete() async {
        await tester.tap(find.byTooltip('게시물 메뉴'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('글 삭제'));
        await tester.pumpAndSettle();
      }

      await requestDelete();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repository.deletedPostId, isNull);
      await requestDelete();
      repository.mutationError = const CommunityOperationException(
        '삭제를 완료하지 못했어요.',
      );
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(result.state.communityPosts, contains(result.post));
      expect(result.post.isDeleted, isFalse);
      repository.mutationError = null;
      await requestDelete();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(repository.deletedPostId, result.post.id);
      expect(result.state.communityPosts, isNot(contains(result.post)));
      expect(result.post.isDeleted, isTrue);
      expect(find.byType(CommunityPostDetailScreen), findsNothing);
    },
  );

  Future<AppState> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(state.dispose);
    return state;
  }

  testWidgets('post composer validates and persists a new post', (
    tester,
  ) async {
    final state = await pumpScreen(tester, const SocialPostComposerScreen());
    final initialCount = state.communityPosts.length;

    await tester.tap(find.text('게시'));
    await tester.pump();
    expect(find.text('사진을 추가하거나 운동 기록을 입력해주세요.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '오늘 스쿼트 기록을 갱신했어요.');
    await tester.tap(find.text('게시'));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.communityPosts, hasLength(initialCount + 1));
    expect(state.communityPosts.first.content, contains('스쿼트'));
    expect(state.communityPosts.first.isMine, isTrue);
  });

  testWidgets('post composer opens both camera and gallery pickers', (
    tester,
  ) async {
    final picker = _FakePostMediaPicker();
    await pumpScreen(tester, SocialPostComposerScreen(mediaPicker: picker));

    await tester.tap(find.text('촬영'));
    await tester.pumpAndSettle();
    expect(picker.sources, [PostMediaSource.camera]);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('사진 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    expect(picker.sources, [PostMediaSource.camera, PostMediaSource.gallery]);
  });

  Future<CommunityPost> pumpPostDetail(WidgetTester tester) async {
    final state = AppState();
    await state.initialize();
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: CommunityPostDetailScreen(post: state.communityPosts.first),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state.communityPosts.first;
  }

  testWidgets('post detail adds a comment and toggles like', (tester) async {
    Auth.use(_SignedInAuth());
    addTearDown(Auth.reset);
    final post = await pumpPostDetail(tester);
    final initialLikes = post.likes;
    final initialComments = post.comments.length;

    await tester.tap(find.byTooltip('좋아요'));
    await tester.pump();
    expect(post.likes, initialLikes + 1);

    await tester.enterText(find.byType(TextFormField), '다음 기록도 응원합니다.');
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pumpAndSettle();
    expect(post.comments, hasLength(initialComments + 1));
  });

  // A guest may read the whole feed, so the gate has to stand at the reaction
  // itself — this is the only thing between "browse freely" and an anonymous
  // like the server would reject anyway.
  testWidgets('post detail asks a guest to sign in before reacting', (
    tester,
  ) async {
    final post = await pumpPostDetail(tester);
    final initialLikes = post.likes;
    final initialComments = post.comments.length;

    await tester.tap(find.byTooltip('좋아요'));
    await tester.pumpAndSettle();
    expect(find.textContaining('커뮤니티에 흔적을 남기려면'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auth-gate-dismiss')));
    await tester.pumpAndSettle();
    expect(post.likes, initialLikes);

    await tester.enterText(find.byType(TextFormField), '저도 응원합니다.');
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pumpAndSettle();
    expect(find.textContaining('커뮤니티에 흔적을 남기려면'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('auth-gate-dismiss')));
    await tester.pumpAndSettle();
    expect(post.comments, hasLength(initialComments));
  });

  test('community post sends selected photo to the shared repository', () async {
    final repository = _FakeCommunityRepository();
    final state = AppState(communityRepository: repository);
    await state.initialize();
    addTearDown(state.dispose);
    final media = CommunityPostMedia(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      fileName: 'workout.png',
      contentType: 'image/png',
    );

    await state.addCommunityPost(
      content: '사진 운동 기록',
      includeWorkout: true,
      visualKey: 'strength',
      media: media,
      activeOverlays: const ['날짜'],
    );

    expect(repository.lastInput?.media, same(media));
    expect(repository.lastInput?.activeOverlays, ['날짜']);
    expect(state.communityPosts.first.imageUrl, contains('workout.png'));
  });

  testWidgets('consultation form validates and creates a waiting request', (
    tester,
  ) async {
    final state = await pumpScreen(tester, const ConsultationCreateScreen());
    final initialCount = state.consultations.length;

    await tester.tap(find.text('상담 신청하기'));
    await tester.pump();
    expect(find.text('운동 목표 내용을 입력해주세요.'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '주 3회 근력 향상');
    await tester.enterText(fields.at(1), '헬스장 등록 3개월 차이며 주 2회 운동합니다.');
    await tester.enterText(fields.at(2), '스쿼트 중량과 반복 횟수를 어떻게 정해야 하나요?');
    await tester.tap(find.text('상담 신청하기'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.consultations, hasLength(initialCount + 1));
    expect(state.consultations.first.status, ConsultationStatus.waiting);
    expect(state.consultations.first.question, contains('스쿼트'));
  });

  testWidgets('expert routine search recovers from an empty result', (
    tester,
  ) async {
    await pumpScreen(tester, const MarketScreen());

    await tester.enterText(find.byType(TextFormField), '존재하지않는루틴');
    await tester.pumpAndSettle();
    expect(find.text('조건에 맞는 루틴이 없어요'), findsOneWidget);

    await tester.tap(find.text('검색 초기화'));
    await tester.pumpAndSettle();
    expect(find.text('초보자 4주 근력 스타트'), findsOneWidget);
  });

  testWidgets('answered consultation transitions into active coaching', (
    tester,
  ) async {
    final state = AppState();
    await state.initialize();
    final consultation = state.consultations.first;
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: ConsultationDetailScreen(consultation: consultation),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final coachingStart = find.byKey(const ValueKey('coaching-start'));
    await tester.scrollUntilVisible(
      coachingStart,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(coachingStart);
    await tester.pumpAndSettle();
    await tester.tap(coachingStart);
    await tester.pumpAndSettle();
    expect(find.text('1:1 코칭을 시작할까요?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coaching-start-confirm')));
    await tester.pumpAndSettle();
    expect(consultation.status, ConsultationStatus.coaching);
    expect(find.byKey(const ValueKey('coaching-rating')), findsOneWidget);
  });

  test('routine import enforces paid access and the free plan limit', () async {
    final state = AppState();
    await state.initialize();

    expect(
      state.importRoutine(state.marketRoutines[0]),
      RoutineImportResult.imported,
    );
    expect(
      state.importRoutine(state.marketRoutines[0]),
      RoutineImportResult.alreadySaved,
    );
    expect(
      state.importRoutine(state.marketRoutines[1]),
      RoutineImportResult.paidPlanRequired,
    );
    expect(
      state.importRoutine(state.marketRoutines[2]),
      RoutineImportResult.imported,
    );
    expect(
      state.importRoutine(
        RoutineData(
          id: 'extra_free',
          name: '추가 무료 루틴',
          description: '무료 플랜 한도 확인',
          color: Colors.blue,
          exercises: [state.exercises.first],
        ),
      ),
      RoutineImportResult.limitReached,
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));
    state.dispose();
  });
}

class _FakePostMediaPicker implements PostMediaPicker {
  final List<PostMediaSource> sources = [];

  @override
  Future<CommunityPostMedia?> pick(PostMediaSource source) async {
    sources.add(source);
    return CommunityPostMedia(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      fileName: 'workout.png',
      contentType: 'image/png',
    );
  }

  @override
  Future<CommunityPostMedia?> recoverLostImage() async => null;
}

class _FakeCommunityRepository implements CommunityRepository {
  CreateCommunityPostInput? lastInput;
  int commentCalls = 0;
  Object? commentError;
  Object? mutationError;
  Future<PostComment>? pendingComment;
  String? updatedContent;
  String? deletedPostId;

  @override
  Future<void> updatePostContent({
    required String postId,
    required String content,
  }) async {
    if (mutationError != null) throw mutationError!;
    updatedContent = content;
  }

  @override
  Future<void> deletePost(String postId) async {
    if (mutationError != null) throw mutationError!;
    deletedPostId = postId;
  }

  @override
  Future<PostComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
  }) async {
    commentCalls++;
    if (commentError != null) throw commentError!;
    if (pendingComment != null) return pendingComment!;
    return PostComment(
      id: 'comment-$commentCalls',
      author: '테스터',
      content: content,
      createdAt: DateTime(2026),
      parentCommentId: parentCommentId,
    );
  }

  @override
  Future<CommunityPostRecord> createPost(CreateCommunityPostInput input) async {
    lastInput = input;
    return CommunityPostRecord(
      post: CommunityPost(
        id: 'shared_post',
        author: '테스터',
        content: input.content,
        metric: input.metric,
        createdAt: DateTime(2026),
        visualKey: input.visualKey,
        color: const Color(0xFF10CEBD),
        imageUrl: 'https://example.com/workout.png',
        isMine: true,
      ),
      authorUserId: 'user',
      imageUrl: 'https://example.com/workout.png',
    );
  }

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
  }) async => const [];

  @override
  Future<CommunityLikeResult> toggleLike(String postId) async =>
      const CommunityLikeResult(isLiked: true, likesCount: 1);
}

class _SignedInAuth implements AuthService {
  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => '테스터';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
