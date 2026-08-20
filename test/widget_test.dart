import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';

void main() {
  testWidgets('shows role selection on launch', (tester) async {
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    expect(find.text('Setflow'), findsOneWidget);
    expect(find.text('일반 회원'), findsOneWidget);
    expect(find.text('트레이너'), findsOneWidget);
    expect(find.text('헬스장 / 센터장'), findsOneWidget);
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
    expect(find.byTooltip('설정'), findsOneWidget);
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('로그아웃'), 400);
    await tester.pumpAndSettle();
    expect(find.text('로그아웃'), findsOneWidget);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('일반 회원'), findsOneWidget);
  });
}
