import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/screens/email_auth_screen.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/password_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

/// Records what the UI asked the backend to do, and lets a test decide how the
/// backend answers. The point of the [AuthService] port is that this is
/// possible at all — none of these flows need Supabase to be exercised.
class _RecordingAuthService implements AuthService {
  _RecordingAuthService({
    this.signUpSignsIn = true,
    this.currentPassword = 'correct-horse',
    this.email = 'me@example.com',
    this.failWith,
  });

  final bool signUpSignsIn;
  final String currentPassword;
  final String? email;

  /// Thrown by the next network-ish call, to exercise the error paths.
  final Object? failWith;

  final calls = <String>[];
  String? lastResetEmail;
  String? lastNewPassword;

  @override
  AuthUser? get currentUser =>
      email == null ? null : AuthUser(id: 'u1', email: email, displayName: '나');

  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => '나';

  @override
  Stream<AuthChange> get authChanges => const Stream<AuthChange>.empty();

  @override
  bool isConfigured(SocialLoginProvider provider) => false;

  @override
  Future<AuthSignUpResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) async {
    calls.add('signUp');
    return AuthSignUpResult(signedIn: signUpSignsIn);
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async => calls.add('signIn');

  @override
  Future<bool> signInWithSocial(SocialLoginProvider provider) async => false;

  @override
  Future<void> sendPasswordReset({required String email}) async {
    calls.add('sendPasswordReset');
    lastResetEmail = email;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> resendConfirmationEmail({required String email}) async {
    calls.add('resendConfirmationEmail');
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> updatePassword({required String newPassword}) async {
    calls.add('updatePassword');
    lastNewPassword = newPassword;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<bool> verifyPassword(String password) async {
    calls.add('verifyPassword');
    return password == currentPassword;
  }

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  String messageFor(Object error) =>
      error is AuthFailure ? error.message : '문제가 발생했어요.';
}

void main() {
  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(432, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: SetflowTheme.light, home: screen),
    );
    await tester.pumpAndSettle();
  }

  _RecordingAuthService bind(_RecordingAuthService service) {
    Auth.use(service);
    addTearDown(Auth.reset);
    return service;
  }

  group('password policy', () {
    test('one rule serves signup, reset and change', () {
      expect(AuthPasswordPolicy.validate('short'), isNotNull);
      expect(AuthPasswordPolicy.validate('        '), isNotNull);
      expect(AuthPasswordPolicy.validate('longenough'), isNull);
    });
  });

  group('forgotten password', () {
    testWidgets('sign-in offers a way out and carries the typed email over', (
      tester,
    ) async {
      bind(_RecordingAuthService());
      await show(
        tester,
        const EmailAuthScreen(initialMode: EmailAuthMode.signIn),
      );

      await tester.enterText(
        find.byType(TextFormField).first,
        'forgot@example.com',
      );
      await tester.tap(find.byKey(const ValueKey('auth-forgot-password')));
      await tester.pumpAndSettle();

      expect(find.byType(PasswordResetRequestScreen), findsOneWidget);
      // Retyping an address you just typed is friction, not security.
      expect(find.text('forgot@example.com'), findsOneWidget);
    });

    testWidgets('sign-up mode does not offer it', (tester) async {
      bind(_RecordingAuthService());
      await show(
        tester,
        const EmailAuthScreen(initialMode: EmailAuthMode.signUp),
      );

      expect(find.byKey(const ValueKey('auth-forgot-password')), findsNothing);
    });

    testWidgets('sending never reveals whether the account exists', (
      tester,
    ) async {
      final auth = bind(_RecordingAuthService());
      await show(tester, const PasswordResetRequestScreen());

      await tester.enterText(find.byType(TextFormField), 'nobody@example.com');
      await tester.tap(find.byKey(const ValueKey('reset-send')));
      await tester.pumpAndSettle();

      expect(auth.calls, contains('sendPasswordReset'));
      expect(auth.lastResetEmail, 'nobody@example.com');
      expect(find.byKey(const ValueKey('reset-sent')), findsOneWidget);
      expect(find.textContaining('가입된 계정이 있다면'), findsOneWidget);
    });

    testWidgets('a malformed address never reaches the backend', (
      tester,
    ) async {
      final auth = bind(_RecordingAuthService());
      await show(tester, const PasswordResetRequestScreen());

      await tester.enterText(find.byType(TextFormField), 'not-an-email');
      await tester.tap(find.byKey(const ValueKey('reset-send')));
      await tester.pumpAndSettle();

      expect(auth.calls, isEmpty);
      expect(find.text('올바른 이메일 주소를 입력해주세요.'), findsOneWidget);
    });
  });

  group('unconfirmed signup', () {
    testWidgets('offers a resend and then holds it on a cooldown', (
      tester,
    ) async {
      final auth = bind(_RecordingAuthService(signUpSignsIn: false));
      await show(
        tester,
        const EmailAuthScreen(initialMode: EmailAuthMode.signUp),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '테스터');
      await tester.enterText(fields.at(1), 'new@example.com');
      await tester.enterText(fields.at(2), 'longenough');
      await tester.enterText(fields.at(3), 'longenough');
      await tester.tap(find.text('회원가입'));
      await tester.pumpAndSettle();

      // A mail that never arrives must not be a dead end: the account exists,
      // so signing up again fails and signing in fails too.
      final resend = find.byKey(const ValueKey('auth-resend-confirmation'));
      expect(find.byKey(const ValueKey('auth-confirm-email')), findsOneWidget);
      expect(resend, findsOneWidget);

      // The cooldown starts immediately, because the first mail just went out.
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(find.textContaining('60초'), findsOneWidget);

      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);

      await tester.tap(resend);
      await tester.pumpAndSettle();
      expect(auth.calls, contains('resendConfirmationEmail'));

      // Leave no repeating timer behind for the next test.
      await tester.pump(const Duration(seconds: 60));
    });
  });

  group('changing a password while signed in', () {
    testWidgets('a wrong current password never reaches updatePassword', (
      tester,
    ) async {
      final auth = bind(_RecordingAuthService(currentPassword: 'the-real-one'));
      await show(
        tester,
        const NewPasswordScreen(requiresCurrentPassword: true),
      );

      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'guessing',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-password')),
        'brand-new-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'brand-new-password',
      );
      await tester.tap(find.byKey(const ValueKey('new-password-save')));
      await tester.pumpAndSettle();

      expect(auth.calls, contains('verifyPassword'));
      expect(
        auth.calls,
        isNot(contains('updatePassword')),
        reason: 'an unlocked phone must not be enough to take over the account',
      );
      expect(find.text('현재 비밀번호가 맞지 않아요.'), findsOneWidget);
    });

    testWidgets('the right one goes through and reports back', (tester) async {
      final auth = bind(_RecordingAuthService(currentPassword: 'the-real-one'));
      await show(
        tester,
        const NewPasswordScreen(requiresCurrentPassword: true),
      );

      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'the-real-one',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-password')),
        'brand-new-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'brand-new-password',
      );
      await tester.tap(find.byKey(const ValueKey('new-password-save')));
      await tester.pumpAndSettle();

      expect(auth.calls, contains('updatePassword'));
      expect(auth.lastNewPassword, 'brand-new-password');
    });

    testWidgets('mismatched confirmation is caught before the network', (
      tester,
    ) async {
      final auth = bind(_RecordingAuthService(currentPassword: 'the-real-one'));
      await show(
        tester,
        const NewPasswordScreen(requiresCurrentPassword: true),
      );

      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'the-real-one',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-password')),
        'brand-new-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'brand-new-passwor',
      );
      await tester.tap(find.byKey(const ValueKey('new-password-save')));
      await tester.pumpAndSettle();

      expect(auth.calls, isEmpty);
      expect(find.text('비밀번호가 일치하지 않아요.'), findsOneWidget);
    });
  });

  group('who is offered a password change', () {
    Future<void> showHub(WidgetTester tester, AppState state) async {
      await tester.binding.setSurfaceSize(const Size(432, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const MyPageScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an email account gets the entry', (tester) async {
      bind(_RecordingAuthService(email: 'me@example.com'));
      final state = AppState(repository: MemoryAppRepository());
      addTearDown(state.dispose);
      await showHub(tester, state);

      expect(
        find.byKey(const ValueKey('mypage-change-password')),
        findsOneWidget,
      );
    });

    testWidgets('a social-only account does not', (tester) async {
      // Nothing to change here — the password lives at the provider, so the
      // form could only ever fail.
      bind(_RecordingAuthService(email: null));
      final state = AppState(repository: MemoryAppRepository());
      addTearDown(state.dispose);
      await showHub(tester, state);

      expect(
        find.byKey(const ValueKey('mypage-change-password')),
        findsNothing,
      );
    });
  });

  group('backend refusals reach the user', () {
    testWidgets('a rate-limited reset is reported, not swallowed', (
      tester,
    ) async {
      bind(
        _RecordingAuthService(
          failWith: const AuthFailure('요청이 많아요. 잠시 후 다시 시도해주세요.'),
        ),
      );
      await show(tester, const PasswordResetRequestScreen());

      await tester.enterText(find.byType(TextFormField), 'me@example.com');
      await tester.tap(find.byKey(const ValueKey('reset-send')));
      await tester.pumpAndSettle();

      // Showing the success panel anyway would tell the user to go wait for a
      // mail that was never sent.
      expect(find.byKey(const ValueKey('reset-sent')), findsNothing);
      expect(find.text('요청이 많아요. 잠시 후 다시 시도해주세요.'), findsOneWidget);
    });
  });

  group('recovery arrival', () {
    testWidgets('a reset link does not ask for the old password', (
      tester,
    ) async {
      bind(_RecordingAuthService());
      // Someone who followed a reset link cannot supply the old password --
      // not remembering it is why they are here.
      await show(tester, const NewPasswordScreen());

      expect(find.byKey(const ValueKey('current-password')), findsNothing);
      expect(find.byKey(const ValueKey('new-password')), findsOneWidget);
    });
  });
}
