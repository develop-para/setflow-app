import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/welcome_screen.dart';
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
    return state;
  }

  testWidgets('member onboarding validates body profile ranges', (
    tester,
  ) async {
    final state = await pumpScreen(tester, const MemberSetupScreen());

    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);

    await tester.tap(find.text('체중 감량'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 4'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '8');
    await tester.tap(find.text('저장'));
    await tester.pump();
    expect(find.text('나이 값은 14~100 범위로 입력해주세요.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '29');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.text('카카오로 시작하기'), findsOneWidget);

    state.dispose();
  });

  testWidgets('gym onboarding validates and submits verification steps', (
    tester,
  ) async {
    final state = await pumpScreen(
      tester,
      const BusinessSetupScreen(role: UserRole.gym),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '세트플로우짐');
    await tester.enterText(fields.at(1), '123');
    await tester.tap(find.text('다음'));
    await tester.pump();
    expect(find.text('사업자등록번호 숫자 10자리를 입력해주세요.'), findsOneWidget);

    await tester.enterText(fields.at(1), '1234567890');
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('사업자등록증을\n제출해주세요'), findsOneWidget);

    await tester.tap(find.text('사업자등록증'));
    await tester.pump();
    await tester.tap(find.text('서류 제출하기'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('홈택스 사업자 인증'), findsOneWidget);

    await tester.tap(find.text('홈택스 인증하기'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.textContaining('인증 완료!'), findsOneWidget);

    state.dispose();
  });
}
