import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';

void main() {
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

  testWidgets('post detail adds a comment and toggles like', (tester) async {
    final state = AppState();
    await state.initialize();
    final post = state.communityPosts.first;
    final initialLikes = post.likes;
    final initialComments = post.comments.length;
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: CommunityPostDetailScreen(post: post),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('좋아요'));
    await tester.pump();
    expect(post.likes, initialLikes + 1);

    await tester.enterText(find.byType(TextFormField), '다음 기록도 응원합니다.');
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pumpAndSettle();
    expect(post.comments, hasLength(initialComments + 1));
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

    await tester.scrollUntilVisible(
      find.text('코칭 시작'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('코칭 시작'));
    await tester.pumpAndSettle();
    expect(find.text('1:1 코칭을 시작할까요?'), findsOneWidget);

    await tester.tap(find.text('결제하고 시작'));
    await tester.pumpAndSettle();
    expect(consultation.status, ConsultationStatus.coaching);
    expect(find.text('코칭 중'), findsOneWidget);
  });

  test('routine import reports duplicate and free plan limit', () async {
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
      RoutineImportResult.imported,
    );
    expect(
      state.importRoutine(state.marketRoutines[2]),
      RoutineImportResult.limitReached,
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));
    state.dispose();
  });
}
