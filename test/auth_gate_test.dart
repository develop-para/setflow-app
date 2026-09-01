import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/widgets/bottom_bar.dart';

void main() {
  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
  }

  testWidgets('a guest can log a workout without ever being asked to sign in', (
    tester,
  ) async {
    await launch(tester);

    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();

    // The core act is the whole point of the app; it must never hit a wall.
    // 기록의 첫 화면은 캘린더고, 오늘 칸을 누르면 그날 기록이 열린다 — 둘 다
    // 게스트에게 잠기지 않는다.
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
    final now = DateTime.now();
    await tester.tap(
      find.byKey(ValueKey('calendar-tint-${now.year}${now.month}${now.day}')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('record-action-routines')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsNothing);
  });

  testWidgets('posting to the community asks a guest to sign in first', (
    tester,
  ) async {
    await launch(tester);

    // 홈의 커뮤니티 섹션 제목과 겹치므로 바텀바 라벨은 마지막 것이다.
    await tester.tap(find.text('커뮤니티').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-compose')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-gate-sign-up')), findsOneWidget);
    // Declining leaves the composer closed rather than opening a broken form.
    expect(find.byType(SocialPostComposerScreen), findsNothing);

    await tester.tap(find.byKey(const ValueKey('auth-gate-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(SocialPostComposerScreen), findsNothing);
    expect(find.byType(SetflowActionNavBar), findsOneWidget);
  });

  testWidgets('the gate leads into the email screen', (tester) async {
    await launch(tester);

    await tester.tap(find.text('커뮤니티').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('community-compose')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auth-gate-sign-up')));
    await tester.pumpAndSettle();
    expect(find.text('이메일 회원가입'), findsOneWidget);
  });
}
