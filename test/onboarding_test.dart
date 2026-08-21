import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/welcome_screen.dart';
import 'package:setflow/services/auth_service.dart';
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

  testWidgets('welcome screen offers email sign-in and hides dead providers', (
    tester,
  ) async {
    final state = await pumpScreen(tester, const WelcomeScreen());

    // No provider is configured here, so neither the buttons nor the divider
    // that introduces them should be on screen. A button that cannot work is
    // worse than no button.
    expect(find.text('SNS 계정으로 계속'), findsNothing);
    expect(find.byKey(const ValueKey('social-kakao')), findsNothing);
    expect(find.byKey(const ValueKey('social-google')), findsNothing);
    expect(find.byKey(const ValueKey('social-naver')), findsNothing);

    await tester.tap(find.byKey(const Key('welcome-email-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('이메일 로그인'), findsOneWidget);
    expect(find.text('처음이신가요? 이메일 회원가입'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('welcome-email-sign-up')));
    await tester.pumpAndSettle();
    expect(find.text('이메일 회원가입'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
    expect(find.text('가입하면 기록이 계정에 백업돼요.'), findsOneWidget);
    expect(find.text('이미 계정이 있나요? 로그인'), findsOneWidget);

    state.dispose();
  });

  testWidgets('a configured provider brings its button back', (tester) async {
    // Hiding must be driven by configuration, not hard-coded — otherwise
    // enabling Kakao later would silently change nothing.
    addTearDown(Auth.reset);
    Auth.use(_KakaoOnlyAuthService());

    final state = await pumpScreen(tester, const WelcomeScreen());

    expect(find.byKey(const ValueKey('social-kakao')), findsOneWidget);
    expect(find.text('SNS 계정으로 계속'), findsOneWidget);
    // The two that are still off stay off.
    expect(find.byKey(const ValueKey('social-google')), findsNothing);
    expect(find.byKey(const ValueKey('social-naver')), findsNothing);

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

/// Signed out, but with Kakao switched on.
class _KakaoOnlyAuthService implements AuthService {
  @override
  bool isConfigured(SocialLoginProvider provider) =>
      provider == SocialLoginProvider.kakao;

  @override
  AuthUser? get currentUser => null;
  @override
  bool get hasAuthenticatedUser => false;
  @override
  String get currentDisplayName => '회원';
  @override
  Stream<AuthChange> get authChanges => const Stream<AuthChange>.empty();
  @override
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async => const AuthSignUpResult(signedIn: false);
  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}
  @override
  Future<bool> signInWithSocial(SocialLoginProvider provider) async => false;
  @override
  Future<void> sendPasswordReset({required String email}) async {}
  @override
  Future<void> resendConfirmationEmail({required String email}) async {}
  @override
  Future<void> updatePassword({required String newPassword}) async {}
  @override
  Future<bool> verifyPassword(String password) async => false;
  @override
  Future<void> signOut() async {}
  @override
  Future<bool> isVerifiedAdmin() async => false;
  @override
  String messageFor(Object error) => '$error';
}
