import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/member_menu_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

/// 포탈 전환의 문은 헤더 세그먼트가 아니라 전체 메뉴의 한 줄이다(2026-09-01).
/// OKX의 Exchange|Wallet은 모두가 양쪽을 쓰기에 성립하는 세그먼트지만, 회원과
/// 트레이너를 오가는 사람은 극소수다 — 승인된 계정에게만 메뉴에 문이 보이고,
/// pro 셸에는 언제나 "회원 화면"이라는 돌아오는 문이 남는다.
const _menuDoor = ValueKey('menu-portal-trainer');
const _returnDoor = ValueKey('portal-return-client');

/// The access shape `loadAccess()` returns for an approved trainer.
BusinessAccess _approvedTrainer() => const BusinessAccess(
  userId: '00000000-0000-0000-0000-000000000001',
  accountRole: UserRole.member,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
  applicationStatus: BusinessApplicationStatus.approved,
);

void main() {
  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
  }

  AppState stateOf(WidgetTester tester) =>
      AppScope.of(tester.element(find.byType(MemberShell)));

  testWidgets('a guest is not offered a portal they cannot open', (
    tester,
  ) async {
    await launch(tester);

    // The pro side needs an admin-approved account, so a guest has nothing to
    // switch to — the menu entry is absent rather than gated.
    expect(find.byType(MemberShell), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(MemberMenuScreen), findsOneWidget);
    expect(find.byKey(_menuDoor), findsNothing);
  });

  testWidgets('approval is what puts the door in the menu', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const MemberMenuScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_menuDoor), findsNothing);

    // Approval is the granted role, not the application row.
    state.businessAccess = _approvedTrainer();
    state.notifyListeners();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(_menuDoor),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(_menuDoor), findsOneWidget);
    expect(find.text('트레이너 화면'), findsOneWidget);
  });

  testWidgets('the menu door swaps the shell behind the brand hold', (
    tester,
  ) async {
    // 문은 승인 게이트 앞에 로그인 게이트가 선다 — 승인된 계정은 곧 로그인된
    // 계정이므로, 데모 상태에도 로그인부터 물린다.
    Auth.use(_SignedInAuth());
    addTearDown(Auth.reset);
    await launch(tester);
    final state = stateOf(tester);
    state.businessAccess = _approvedTrainer();
    state.notifyListeners();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-app-menu')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(_menuDoor),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // scrollUntilVisible은 행이 뷰포트 끝에 반쯤 걸린 채 멈출 수 있다 —
    // 중심을 탭하려면 끝까지 끌어올려야 한다.
    await tester.ensureVisible(find.byKey(_menuDoor));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_menuDoor));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('portal-transition-logo')),
      findsOneWidget,
    );

    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('portal-transition-logo')), findsNothing);
    expect(find.byType(BusinessShell), findsOneWidget);
    expect(find.byType(MemberShell), findsNothing);

    // Standing in the pro shell always keeps the way back visible, and coming
    // back is never gated.
    await tester.tap(find.byKey(_returnDoor));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('portal-transition-logo')),
      findsOneWidget,
    );

    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();
    expect(find.byType(MemberShell), findsOneWidget);
    expect(find.byType(BusinessShell), findsNothing);
  });

  testWidgets('header row leaves both shells overflow-free on a small phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    unawaited(stateOf(tester).switchPortal(AppPortal.trainer));
    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BusinessShell), findsOneWidget);
    expect(find.byKey(_returnDoor), findsOneWidget);
  });
}

/// Signed in, and nothing else — the door asks only whether an account exists.
class _SignedInAuth implements AuthService {
  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'u-me', email: 'me@example.com', displayName: '나');

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
  }) async => const AuthSignUpResult(signedIn: true);

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
  Future<bool> verifyPassword(String password) async => true;

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  String messageFor(Object error) => '$error';
}
