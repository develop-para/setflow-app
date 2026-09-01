import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  late DateTime sessionDate;
  late List<MemberSessionFeedback> feedbacks;

  setUp(() {
    final now = DateTime.now();
    sessionDate = DateTime(now.year, now.month, now.day);
    feedbacks = [
      MemberSessionFeedback(
        id: '10000000-0000-4000-8000-000000000001',
        sessionId: '20000000-0000-4000-8000-000000000001',
        sessionDate: sessionDate,
        trainerUserId: '30000000-0000-4000-8000-000000000001',
        authorName: '김코치',
        text: '자세가 안정적이었어요. 다음 세션도 같은 템포로 진행하세요.',
        createdAt: sessionDate.add(const Duration(hours: 12)),
      ),
      MemberSessionFeedback(
        id: '10000000-0000-4000-8000-000000000002',
        sessionId: '20000000-0000-4000-8000-000000000001',
        sessionDate: sessionDate,
        authorName: '센터 코치',
        text: '마지막 세트는 휴식 시간을 30초 더 확보해도 좋아요.',
        createdAt: sessionDate.add(const Duration(hours: 10)),
      ),
    ];
  });

  test(
    'member feedback refresh is date scoped and clears on sign-out',
    () async {
      final repository = _FeedbackRepository(feedbacks);
      final state = AppState(
        businessRepository: repository,
        authSignOut: () async {},
      );
      addTearDown(state.dispose);

      await state.refreshMemberSessionFeedback(
        from: sessionDate.subtract(const Duration(days: 7)),
        to: sessionDate.add(const Duration(days: 7)),
      );

      expect(repository.calls, 1);
      expect(state.memberSessionFeedbackForDate(sessionDate), feedbacks);
      expect(
        state.memberSessionFeedbackForDate(
          sessionDate.subtract(const Duration(days: 1)),
        ),
        isEmpty,
      );

      state.handleExternalAuthSignedOut();
      expect(state.memberSessionFeedbacks, isEmpty);
      expect(state.memberSessionFeedbackError, isNull);
    },
  );

  testWidgets('daily workout shows latest feedback and opens the full feed', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    state.role = UserRole.member;
    state.memberSessionFeedbacks = feedbacks;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: sessionDate),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('member-session-feedback-card')),
      findsOneWidget,
    );
    expect(find.text('김코치'), findsOneWidget);
    expect(find.textContaining('자세가 안정적이었어요'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('member-session-feedback-card')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('센터 코치 · ${sessionDate.month}월 ${sessionDate.day}일 10:00'),
      findsOneWidget,
    );
    expect(find.textContaining('마지막 세트는 휴식 시간을'), findsOneWidget);
  });

  testWidgets('calendar marks dates that have coach feedback', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    state.role = UserRole.member;
    state.memberSessionFeedbacks = feedbacks;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const MemberShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 캘린더는 이제 기록 탭의 첫 화면이다(오늘 기록이 비어 있을 때).
    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ValueKey(
          'calendar-feedback-${sessionDate.year}-${sessionDate.month}-'
          '${sessionDate.day}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('코치 피드백 2개')), findsOneWidget);
  });
}

class _FeedbackRepository
    implements BusinessRepository, MemberSessionFeedbackRepository {
  _FeedbackRepository(this.feedbacks);

  final List<MemberSessionFeedback> feedbacks;
  int calls = 0;

  @override
  Future<List<MemberSessionFeedback>> listMySessionFeedback({
    DateTime? from,
    DateTime? to,
  }) async {
    calls++;
    return feedbacks;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
