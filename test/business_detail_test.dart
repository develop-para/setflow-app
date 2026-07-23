import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  Future<AppState> pumpDetail(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(432, 900),
    AppRepository? repository,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(repository: repository);
    await state.initialize();
    state.role = UserRole.trainer;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          darkTheme: SetflowTheme.dark,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    return state;
  }

  testWidgets('member search recovers from an empty result', (tester) async {
    await pumpDetail(tester, const PeoplePage(role: UserRole.trainer));

    await tester.enterText(find.byType(TextFormField).first, '없는회원');
    await tester.pump();
    expect(find.text('검색 결과가 없어요'), findsOneWidget);

    await tester.tap(find.text('검색 초기화'));
    await tester.pump();
    expect(find.text('박민지'), findsOneWidget);
  });

  testWidgets('member feedback validates and reports success', (tester) async {
    final repository = MemoryAppRepository();
    final state = await pumpDetail(
      tester,
      const PeoplePage(role: UserRole.trainer),
      repository: repository,
    );

    await tester.tap(find.text('박민지'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('피드백 보내기'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(
      find.byType(ListView).last,
      const Offset(0, -120),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.tap(find.text('피드백 보내기'));
    await tester.pump();
    expect(find.text('피드백 내용을 입력해주세요.'), findsOneWidget);
    await tester.drag(
      find.byType(ListView).last,
      const Offset(0, -120),
      warnIfMissed: false,
    );
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, '피드백').last,
      '다음 운동에서는 무게보다 정확한 자세에 집중해주세요.',
    );
    await tester.drag(
      find.byType(ListView).last,
      const Offset(0, -120),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.tap(find.text('피드백 보내기'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('박민지님에게 피드백을 보냈어요.'), findsOneWidget);
    expect(
      state.dashboardFor(UserRole.trainer).facts['memberFeedback.박민지'],
      '다음 운동에서는 무게보다 정확한 자세에 집중해주세요.',
    );

    await tester.pump(const Duration(milliseconds: 350));
    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(
      restored.dashboardFor(UserRole.trainer).facts['memberFeedback.박민지'],
      '다음 운동에서는 무게보다 정확한 자세에 집중해주세요.',
    );
  });

  testWidgets('gym member assignment persists through the repository', (
    tester,
  ) async {
    final repository = MemoryAppRepository();
    final state = await pumpDetail(
      tester,
      const PeoplePage(role: UserRole.gym),
      repository: repository,
    );

    await tester.tap(find.text('박민지'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('담당 트레이너 배정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('김코치').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('이코치').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('배정 저장'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      state.dashboardFor(UserRole.gym).facts['memberAssignment.박민지'],
      '이코치',
    );
    expect(find.text('박민지 회원을 이코치 트레이너에게 배정했어요.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(
      restored.dashboardFor(UserRole.gym).facts['memberAssignment.박민지'],
      '이코치',
    );
  });

  testWidgets('routine creation validates and persists through AppState', (
    tester,
  ) async {
    final repository = MemoryAppRepository();
    final state = await pumpDetail(
      tester,
      const RoutineManagerPage(role: UserRole.trainer),
      repository: repository,
    );

    await tester.tap(find.byTooltip('새 루틴 작성'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('루틴 저장'));
    await tester.pump();
    expect(find.text('루틴 이름을 입력해주세요.'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '직장인 근력 루틴');
    await tester.enterText(fields.at(1), '주 3회 전신 근력을 안전하게 높이는 루틴입니다.');
    await tester.tap(find.text('루틴 저장'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.routines.any((item) => item.name == '직장인 근력 루틴'), isTrue);
    expect(find.text('새 루틴을 저장했어요.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));

    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(restored.routines.any((item) => item.name == '직장인 근력 루틴'), isTrue);
  });

  testWidgets('consultation answer validates and updates unread filter', (
    tester,
  ) async {
    final repository = MemoryAppRepository();
    final state = await pumpDetail(
      tester,
      const ConsultationQueuePage(role: UserRole.trainer),
      repository: repository,
    );

    await tester.tap(find.text('이수진'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('답변 보내기'));
    await tester.pump();
    expect(find.text('상담 답변을 입력해주세요.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, '답변 작성'),
      '현재 운동 경력에 맞춰 주 3회 루틴부터 단계적으로 안내해드릴게요.',
    );
    await tester.ensureVisible(find.text('답변 보내기'));
    await tester.pump();
    await tester.tap(find.text('답변 보내기'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('이수진님에게 상담 답변을 보냈어요.'), findsOneWidget);
    expect(state.isBusinessConsultationAnswered(UserRole.trainer, 0), isTrue);

    await tester.tap(find.text('미답변 2'));
    await tester.pump();
    expect(find.text('이수진'), findsNothing);
    expect(find.text('김도윤'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(
      restored.isBusinessConsultationAnswered(UserRole.trainer, 0),
      isTrue,
    );
  });

  testWidgets('trainer management search and performance filters recover', (
    tester,
  ) async {
    await pumpDetail(tester, const TrainerManagementPage());

    await tester.enterText(find.byType(TextFormField), '없는트레이너');
    await tester.pump();
    expect(find.text('조건에 맞는 트레이너가 없어요'), findsOneWidget);

    await tester.tap(find.text('검색·필터 초기화'));
    await tester.pump();
    await tester.tap(find.text('피드백 필요'));
    await tester.pump();
    expect(find.text('이코치'), findsOneWidget);
    expect(find.text('김코치'), findsNothing);
  });

  testWidgets('settlement search and status filter expose empty recovery', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      const SettlementPage(role: UserRole.gym),
      size: const Size(432, 1000),
    );

    await tester.tap(find.text('검토 필요'));
    await tester.pump();
    expect(find.text('환불 보류'), findsOneWidget);
    expect(find.text('단기 코칭'), findsNothing);

    await tester.enterText(find.byType(TextFormField), '없는정산');
    await tester.pump();
    expect(find.text('조건에 맞는 정산 내역이 없어요'), findsOneWidget);
    await tester.tap(find.text('검색·필터 초기화'));
    await tester.pump();
    expect(find.text('단기 코칭'), findsOneWidget);
  });

  testWidgets('admin user restriction validates and persists audit state', (
    tester,
  ) async {
    final repository = MemoryAppRepository();
    final state = await pumpDetail(
      tester,
      const AdminUsersPage(),
      repository: repository,
    );

    await tester.enterText(find.byType(TextFormField).first, '없는회원');
    await tester.pump();
    expect(find.text('조건에 맞는 회원이 없어요'), findsOneWidget);
    await tester.tap(find.text('검색·필터 초기화'));
    await tester.pump();

    await tester.tap(find.byTooltip('회원 관리 메뉴').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('계정 제재'));
    await tester.pumpAndSettle();
    final restrictButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('이용 제한'),
    );
    await tester.tap(restrictButton);
    await tester.pump();
    expect(find.text('제재 사유를 5자 이상 입력해주세요.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).last, '반복적인 운영 정책 위반');
    await tester.tap(restrictButton);
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.isAdminUserBlocked('beginner@setflow.app'), isTrue);
    expect(find.text('운동초보님의 계정을 제한했어요.'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(restored.isAdminUserBlocked('beginner@setflow.app'), isTrue);
  });

  testWidgets('admin review approval and rejection persist with reasons', (
    tester,
  ) async {
    final repository = MemoryAppRepository();
    final state = await pumpDetail(
      tester,
      const AdminReviewPage(),
      repository: repository,
      size: const Size(432, 1000),
    );

    await tester.tap(find.text('승인').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('승인 및 배지 발급'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.adminReviewStatus('review_0'), 'approved');

    await tester.scrollUntilVisible(
      find.text('거절').first,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('거절').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('반려 사유 전송'));
    await tester.pump();
    expect(find.text('반려 사유를 5자 이상 입력해주세요.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '사업자등록증 재제출 필요');
    await tester.tap(find.text('반려 사유 전송'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.adminReviewStatus('review_1'), 'rejected');
    expect(
      state.dashboardFor(UserRole.admin).facts['adminReview.review_1.reason'],
      '사업자등록증 재제출 필요',
    );

    await tester.pump(const Duration(milliseconds: 350));
    final restored = AppState(repository: repository);
    await restored.initialize();
    addTearDown(restored.dispose);
    expect(restored.adminReviewStatus('review_0'), 'approved');
    expect(restored.adminReviewStatus('review_1'), 'rejected');
  });

  const smallPhoneScreens = <String, Widget>{
    'people': PeoplePage(role: UserRole.trainer),
    'routine manager': RoutineManagerPage(role: UserRole.trainer),
    'consultation queue': ConsultationQueuePage(role: UserRole.trainer),
    'settlement': SettlementPage(role: UserRole.trainer),
    'trainer management': TrainerManagementPage(),
    'admin users': AdminUsersPage(),
    'admin review': AdminReviewPage(),
  };
  for (final entry in smallPhoneScreens.entries) {
    testWidgets('${entry.key} fits a 320px-wide phone', (tester) async {
      final screen = entry.value;
      await pumpDetail(tester, screen, size: const Size(320, 568));
      expect(tester.takeException(), isNull, reason: '$screen overflowed');
      expect(tester.getSize(find.byType(Scaffold).first).width, 320);
      final list = tester.widget<ListView>(find.byType(ListView).first);
      final padding = list.padding!.resolve(TextDirection.ltr);
      expect(padding.left, 24, reason: '$screen has inconsistent left inset');
      expect(padding.right, 24, reason: '$screen has inconsistent right inset');
    });
  }
}
