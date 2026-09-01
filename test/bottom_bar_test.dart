import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_menu_screen.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme/icons.dart';
import 'package:setflow/widgets/bottom_bar.dart';

IconData _discIcon(WidgetTester tester) => tester
    .widget<SetflowActionNavBar>(find.byType(SetflowActionNavBar))
    .centerIcon;

void main() {
  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(432, 900),
  }) async {
    // The disc must stay genuinely tappable while the sheet is up; a warning
    // here would mean the sheet is swallowing its own close button.
    WidgetController.hitTestWarningShouldBeFatal = true;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
  }

  final disc = find.byKey(const ValueKey('bottom-bar-center-action'));

  testWidgets('bar anchors 홈 first and 마이 last around a 기록 action', (
    tester,
  ) async {
    await launch(tester);

    final bar = tester.widget<SetflowActionNavBar>(
      find.byType(SetflowActionNavBar),
    );
    expect(bar.items.map((item) => item.label).toList(), [
      '홈',
      '함께',
      '커뮤니티',
      '마이',
    ]);
    expect(bar.centerLabel, '기록');
    expect(bar.centerSelected, isFalse);

    // The bar reserves no room for the disc: it is exactly one bar tall, and
    // the disc straddles its top edge. A taller bar means the dead white band
    // above the border is back.
    final barRect = tester.getRect(find.byType(SetflowActionNavBar));
    expect(barRect.height, SetflowActionNavBar.barHeight);
    final discRect = tester.getRect(disc);
    expect(discRect.top, lessThan(barRect.top));
    expect(discRect.bottom, greaterThan(barRect.top));
  });

  testWidgets('first center tap opens 기록, second opens the action sheet', (
    tester,
  ) async {
    await launch(tester);
    expect(find.byType(RecordScreen), findsNothing);

    await tester.tap(disc);
    await tester.pumpAndSettle();

    // 오늘 기록이 비어 있으면 기록의 첫 화면은 캘린더다 — 날짜를 골라 들어간다.
    expect(find.byType(RecordScreen), findsOneWidget);
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(DailyWorkoutScreen), findsNothing);
    expect(find.text('무엇으로 기록할까요?'), findsNothing);
    var bar = tester.widget<SetflowActionNavBar>(
      find.byType(SetflowActionNavBar),
    );
    expect(bar.centerSelected, isTrue);
    expect(bar.selectedIndex, isNull);
    expect(_discIcon(tester), SetflowIcons.record);

    await tester.tap(disc);
    await tester.pumpAndSettle();

    expect(find.text('무엇으로 기록할까요?'), findsOneWidget);
    expect(_discIcon(tester), SetflowIcons.close);

    // Third tap closes it again, like OKX's X state.
    await tester.tap(disc);
    await tester.pumpAndSettle();
    expect(find.text('무엇으로 기록할까요?'), findsNothing);
    expect(_discIcon(tester), SetflowIcons.record);
  });

  testWidgets('sheet sits above the bar and closes on system back', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(disc);
    await tester.pumpAndSettle();
    await tester.tap(disc);
    await tester.pumpAndSettle();

    // Never covers the bar: that is what keeps the close button reachable.
    final sheetBottom = tester.getRect(find.text('무엇으로 기록할까요?')).bottom;
    final barTop = tester.getTopLeft(find.byType(SetflowActionNavBar)).dy;
    expect(sheetBottom, lessThan(barTop + SetflowActionNavBar.barHeight));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('무엇으로 기록할까요?'), findsNothing);
  });

  testWidgets('record sheet routes to routines and the market', (tester) async {
    await launch(tester);
    await tester.tap(disc);
    await tester.pumpAndSettle();
    await tester.tap(disc);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('record-action-market')));
    await tester.pumpAndSettle();
    expect(find.byType(MarketScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(disc);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('record-action-routines')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesScreen), findsOneWidget);
  });

  testWidgets('기록 is today while a workout is in progress, calendar after', (
    tester,
  ) async {
    // 운동 중인 사람은 세트 사이에 폰을 30초만 본다 — 오늘 기록에 운동이
    // 있으면 캘린더를 거치지 않고 바로 오늘 세트 화면이어야 한다.
    await launch(tester);
    final state = AppScope.of(tester.element(find.byType(MemberShell)));
    state.addExercise(state.dateOnly(DateTime.now()), state.exercises.first);
    await tester.pumpAndSettle();

    await tester.tap(disc);
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
    expect(find.byType(CalendarScreen), findsNothing);

    // 지난 날짜가 필요하면 액션 시트의 "지난 날짜 기록"이 캘린더를 연다.
    await tester.tap(disc);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('record-action-past')));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);

    // 탭을 떠났다 돌아오면 한 번의 의도는 지워지고 다시 오늘이다.
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    await tester.tap(disc);
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
  });

  testWidgets('the top-left grid opens the full menu, and stats live there', (
    tester,
  ) async {
    // OKX의 왼쪽 상단 서랍 — 바텀바에 자리가 없는 화면들의 입구다. 숨겨 둔
    // 통계 대시보드가 여기서 다시 열린다.
    await launch(tester);
    await tester.tap(find.byKey(const ValueKey('home-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(MemberMenuScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('menu-stats')));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('마이 hub keeps coaching and routines reachable', (tester) async {
    await launch(tester);

    await tester.tap(find.text('마이'));
    await tester.pumpAndSettle();
    expect(find.byType(MyPageScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mypage-coaching')));
    await tester.pumpAndSettle();
    expect(find.byType(CoachingScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mypage-routines')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesScreen), findsOneWidget);
  });

  testWidgets('the trainer door lives in the full menu, not the header', (
    tester,
  ) async {
    // 헤더 세그먼트는 승인된 프로만 두 개를 보고 회원은 빈 채로 남는
    // 비대칭이었다 — 전환은 전체 메뉴의 한 줄이 됐고, 헤더는 모두에게 같다.
    await launch(tester);

    // Only an approved account has a second portal to switch to at all.
    final state = AppScope.of(tester.element(find.byType(MemberShell)));
    state.businessAccess = const BusinessAccess(
      userId: '00000000-0000-0000-0000-000000000001',
      accountRole: UserRole.member,
      resolvedRole: UserRole.trainer,
      availableRoles: {UserRole.member, UserRole.trainer},
      applicationStatus: BusinessApplicationStatus.approved,
    );
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('portal-segment-trainer')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-app-menu')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('menu-portal-trainer')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('menu-portal-trainer')), findsOneWidget);
  });

  testWidgets('bar fits a small phone without overflow', (tester) async {
    await launch(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    expect(find.byType(SetflowActionNavBar), findsOneWidget);
  });
}
