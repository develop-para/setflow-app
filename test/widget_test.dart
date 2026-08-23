import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/widgets/bottom_bar.dart';

void main() {
  testWidgets('launches straight into the member home', (tester) async {
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    expect(find.byType(SetflowActionNavBar), findsOneWidget);
    expect(find.text('홈'), findsWidgets);
    expect(find.text('마이'), findsWidgets);
    expect(find.byKey(const Key('welcome-email-sign-in')), findsNothing);
  });

  testWidgets('logout waits for settings route before replacing member shell', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = MemoryAppRepository(
      initialSnapshot: AppSnapshot(
        role: UserRole.member,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        sessions: const {},
        routines: const [],
        goals: const ['근력 향상'],
      ),
    );
    await tester.pumpWidget(SetflowApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    expect(find.byType(MemberShell), findsOneWidget);
    // 설정은 "마이"에 있다. 홈 헤더에 있던 사본은 걷어냈다 — 바텀바가 이미 가는 곳으로
    // 셸 위에 라우트를 하나 더 쌓으면 돌아갈 길이 사라진다.
    await tester.tap(find.text('마이').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('설정'), 300);
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('로그아웃'), 400);
    await tester.pumpAndSettle();
    expect(find.text('로그아웃'), findsOneWidget);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Signing out no longer lands on a role picker — that screen is gone. The
    // shell stays put and the settings route is what has to be torn down.
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(MemberShell), findsOneWidget);
    expect(find.text('로그아웃'), findsNothing);
  });
}
