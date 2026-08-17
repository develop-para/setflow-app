import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/screens/welcome_screen.dart';
import 'package:setflow/theme.dart';

void main() {
  Future<AppState> pumpLive(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(businessRepository: _LiveRepositoryMarker());
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('live business settings expose disabled server placeholders', (
    tester,
  ) async {
    await pumpLive(
      tester,
      const BusinessSettingsListScreen(role: UserRole.trainer),
    );

    expect(find.text('결제 서버 연동 준비 중'), findsOneWidget);
    expect(find.text('알림 서버 저장 연동 준비 중'), findsOneWidget);
    expect(find.text('서류 업로드 연동 준비 중'), findsOneWidget);
    expect(find.text('계정 탈퇴 서버 처리 연동 준비 중'), findsOneWidget);

    await tester.tap(find.text('알림 설정'));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessSettingsListScreen), findsOneWidget);
  });

  testWidgets('live notification preferences cannot mutate local switches', (
    tester,
  ) async {
    await pumpLive(
      tester,
      const BusinessSettingsNotificationsScreen(role: UserRole.gym),
    );

    expect(find.text('알림 설정을 서버에 저장하는 기능을 준비 중이에요.'), findsOneWidget);
    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switches, isNotEmpty);
    expect(switches.every((tile) => tile.onChanged == null), isTrue);
  });

  testWidgets('live gym onboarding never presents simulated Hometax approval', (
    tester,
  ) async {
    await pumpLive(tester, const BusinessSetupScreen(role: UserRole.gym));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '세트플로우짐');
    await tester.enterText(fields.at(1), '1234567890');
    await tester.pump();
    await tester.ensureVisible(find.text('신청 내용 확인'));
    await tester.tap(find.text('신청 내용 확인'));
    await tester.pumpAndSettle();

    expect(find.text('센터 신청 준비 완료'), findsOneWidget);
    expect(find.text('센터 신청 제출'), findsOneWidget);
    expect(find.text('홈택스 사업자 인증'), findsNothing);
    expect(find.textContaining('인증 완료!'), findsNothing);
  });
}

class _LiveRepositoryMarker implements BusinessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
