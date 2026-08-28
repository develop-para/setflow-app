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

  testWidgets('a signed-in visitor is sent straight back, no spinner', (
    tester,
  ) async {
    // "로그인했을 때 화면 버그" — 로그인이 끝난 뒤에도 회원가입 화면이 회색
    // 스피너를 돌리며 동기화를 기다렸다. 로그인됐으면 이 화면은 즉시 닫힌다.
    addTearDown(Auth.reset);
    Auth.use(_SignedInAuthService());
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('open-welcome'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('open-welcome')));
    // 토스트는 3초 뒤 스스로 닫히므로 settle 대신 프레임을 나눠 본다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('로그인됐어요. 기록을 동기화하고 있어요.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byKey(const ValueKey('open-welcome')), findsOneWidget);
    expect(state.role, UserRole.member);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
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

/// 이미 로그인된 사람. 회원가입 화면을 열 일이 없어야 하지만, 열렸다면 곧장 닫힌다.
class _SignedInAuthService extends _KakaoOnlyAuthService {
  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'u-me', email: 'me@example.com', displayName: '나');

  @override
  bool get hasAuthenticatedUser => true;
}
