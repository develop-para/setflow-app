import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/main.dart';
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
      '통계',
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
    expect(find.byType(DailyWorkoutScreen), findsNothing);

    await tester.tap(disc);
    await tester.pumpAndSettle();

    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
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

  testWidgets('the portal switch belongs to 홈 and follows nobody to 기록', (
    tester,
  ) async {
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
    expect(
      find.byKey(const ValueKey('portal-segment-trainer')),
      findsOneWidget,
    );

    // 기록 needs its whole height, and a 일반인/트레이너 toggle floating over the
    // set you are logging is noise rather than navigation.
    await tester.tap(disc);
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('portal-segment-trainer')), findsNothing);

    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('portal-segment-trainer')),
      findsOneWidget,
    );
  });

  testWidgets('bar fits a small phone without overflow', (tester) async {
    await launch(tester, size: const Size(320, 568));
    expect(tester.takeException(), isNull);
    expect(find.byType(SetflowActionNavBar), findsOneWidget);
  });
}
