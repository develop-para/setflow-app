import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/screens/community_screen.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  for (final width in [320.0, 432.0, 800.0]) {
    testWidgets('photo grid keeps three or more square columns at $width', (
      tester,
    ) async {
      await _mount(tester, _posts(), size: Size(width, 900));
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(
        delegate.crossAxisCount,
        width < 800 ? 3 : greaterThanOrEqualTo(4),
      );
      final first = tester.getRect(_photo('0'));
      final third = tester.getRect(_photo('2'));
      expect(first.top, third.top);
      expect(first.width, closeTo(first.height, .01));
      expect(first.left, SetflowSpacing.gutter);
      expect(third.left, greaterThan(first.right));
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images, isNotEmpty);
      expect(images.every((image) => image.fit == BoxFit.contain), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('each photo uses its saved workout and local posting time', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final first = _post('first', metric: '12세트 · 4.2k kg·회');
    final second = _post('second', metric: '32분 유산소');
    final state = await _mount(tester, [first, second]);
    expect(state.todayWorkoutMetric, '오늘 운동 기록');
    expect(_workoutText(tester, 'first'), first.metric);
    expect(_workoutText(tester, 'second'), second.metric);
    final dateText = tester
        .widget<Text>(find.byKey(const ValueKey('community-photo-date-first')))
        .data!;
    final localTime = first.createdAt.toLocal();
    expect(dateText, contains('게시'));
    expect(dateText, contains(DateFormat('MM.dd').format(localTime)));
    expect(dateText, contains(DateFormat('HH:mm').format(localTime)));
    final label = tester.getSemantics(_photo('first')).label;
    expect(label, contains(first.author));
    expect(label, contains(first.metric));
    expect(label, contains('게시'));
    expect(label, contains('상세 보기'));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('missing and generic workout summaries never invent a record', (
    tester,
  ) async {
    await _mount(tester, [
      _post('daily', metric: '일상 기록'),
      _post('empty', metric: '  '),
      _post('generic', metric: '오늘 운동 기록'),
    ]);
    expect(_workoutText(tester, 'daily'), '운동 기록 미첨부');
    expect(_workoutText(tester, 'empty'), '운동 기록 미첨부');
    expect(_workoutText(tester, 'generic'), '첨부된 운동 수치 없음');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'long saved summaries stay accessible with 2x text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final semantics = tester.ensureSemantics();
        const metric = '근력 24세트 · 12.5k kg·회 · 120분 유산소 · 아주 긴 운동 기록';
        await _mount(
          tester,
          [_post('long', metric: metric), ..._posts()],
          size: const Size(320, 700),
          scale: 2,
          dark: dark,
        );
        expect(_workoutText(tester, 'long'), metric);
        expect(tester.getSemantics(_photo('long')).label, contains(metric));
        final summary = find.byKey(
          const ValueKey('community-photo-workout-long'),
        );
        final scaler = MediaQuery.textScalerOf(tester.element(summary));
        expect(scaler.scale(11), inInclusiveRange(11, 12.100001));
        expect(tester.takeException(), isNull);
        await tester.tap(_photo('long'));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityPostDetailScreen), findsOneWidget);
        expect(find.text(metric), findsOneWidget);
        expect(
          MediaQuery.textScalerOf(
            tester.element(find.byType(CommunityPostDetailScreen)),
          ).scale(11),
          22,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}

Finder _photo(String id) => find.byKey(ValueKey('community-photo-$id'));

String? _workoutText(WidgetTester tester, String id) => tester
    .widget<Text>(find.byKey(ValueKey('community-photo-workout-$id')))
    .data
    ?.replaceAll('\n', ' · ');

CommunityPost _post(
  String id, {
  String metric = '8세트 · 1.2k kg·회',
  DateTime? createdAt,
}) => CommunityPost(
  id: id,
  author: '작성자 $id',
  content: '운동을 꾸준히 기록하고 있어요.',
  metric: metric,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 24, 9, 32),
  visualKey: 'strength',
  color: SetflowColors.teal,
  imageUrl: 'https://example.com/photo-$id.jpg',
);

List<CommunityPost> _posts() => [
  for (var index = 0; index < 12; index++)
    _post('$index', createdAt: DateTime.utc(2026, 10, 24, 9, 32 - index)),
];

Future<AppState> _mount(
  WidgetTester tester,
  List<CommunityPost> posts, {
  Size size = const Size(432, 900),
  double scale = 1,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(communityRepository: _PhotoRepository(posts));
  await state.initialize();
  addTearDown(state.dispose);
  await tester.pump(const Duration(milliseconds: 300));
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
  await tester.pumpAndSettle();
  return state;
}

class _PhotoRepository implements CommunityRepository {
  _PhotoRepository(this.posts);

  final List<CommunityPost> posts;

  @override
  Future<CommunityFeedPage> listFeed({
    CommunityFeedOrder order = CommunityFeedOrder.latest,
    CommunityFeedMedia media = CommunityFeedMedia.photos,
    int limit = 24,
    int offset = 0,
  }) async => CommunityFeedPage.fromAllPosts(
    posts,
    order: order,
    media: media,
    limit: limit,
    offset: offset,
  );

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
  Future<CommunityLikeResult> toggleLike(String postId) async =>
      throw const CommunityAuthenticationRequired();

  @override
  Future<void> updatePostContent({
    required String postId,
    required String content,
  }) async =>
      throw UnsupportedError('Editing is outside this photo grid test.');

  @override
  Future<void> deletePost(String postId) async =>
      throw UnsupportedError('Deleting is outside this photo grid test.');

  @override
  Future<PostComment> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
  }) async => throw const CommunityAuthenticationRequired();
}
