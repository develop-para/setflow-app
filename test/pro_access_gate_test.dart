import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/pro_access_gate.dart';

/// A trainer is *approved*, not merely signed in. Getting this wrong in either
/// direction is serious: shut out someone an admin already approved, or open
/// the pro portal to someone still under review.
///
/// The truth is the server's — `availableRoles` carries trainer only once the
/// application is approved — and this gate has to read it, not the application
/// row, which is the mistake the app made before.
/// Signed in is the prerequisite the gate checks first; everything this file
/// cares about happens after it. `noSuchMethod` covers the rest of the port so
/// the fake does not have to grow every time a new verb is added.
class _SignedIn implements AuthService {
  @override
  bool get hasAuthenticatedUser => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  BusinessAccess access({
    Set<UserRole> roles = const {UserRole.member},
    BusinessApplicationStatus? application,
    String? rejectReason,
  }) => BusinessAccess(
    userId: 'u1',
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: roles,
    rejectReason: rejectReason,
    trainerApplication: application == null
        ? null
        : BusinessApplication(
            id: 'a1',
            kind: BusinessApplicationKind.trainer,
            status: application,
            applicantName: '김트레이너',
          ),
  );

  test('signed out is its own state, not "never applied"', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.businessAccess = null;
    expect(proAccessStateOf(state), ProAccessState.signedOut);
  });

  test('signed in with no application means nothing has been submitted', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.businessAccess = access();
    expect(proAccessStateOf(state), ProAccessState.notApplied);
  });

  test('a submitted application is pending, not approved', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.businessAccess = access(
      application: BusinessApplicationStatus.pending,
    );
    expect(
      proAccessStateOf(state),
      ProAccessState.pending,
      reason: '심사 중인 사람에게 포탈이 열리면 안 된다',
    );
  });

  test('a rejection is distinguishable from never having applied', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.businessAccess = access(
      application: BusinessApplicationStatus.rejected,
      rejectReason: '자격증 사본이 흐립니다',
    );
    expect(proAccessStateOf(state), ProAccessState.rejected);
    // 반려 사유는 화면이 읽을 수 있어야 한다 — 무엇을 고칠지 모르면 다시 낼 수 없다.
    expect(state.businessAccess!.rejectReason, isNotNull);
  });

  test('the granted role opens the portal, not the application row', () {
    final state = AppState();
    addTearDown(state.dispose);
    // 서버가 권한을 줬는데 신청서 행이 남아 있는 경우 — 권한이 진실이다.
    state.businessAccess = access(
      roles: {UserRole.member, UserRole.trainer},
      application: BusinessApplicationStatus.pending,
    );
    expect(
      proAccessStateOf(state),
      ProAccessState.approved,
      reason: '승인된 사람이 신청서 상태 때문에 막히면 안 된다',
    );
  });

  test('a gym owner reaches the portal the same way a trainer does', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.businessAccess = access(roles: {UserRole.member, UserRole.gym});
    expect(proAccessStateOf(state), ProAccessState.approved);
  });

  Future<void> openGate(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => requireProAccess(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<AppState> signedInWith(
    WidgetTester tester,
    BusinessApplicationStatus? status, {
    String? rejectReason,
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Auth.use(_SignedIn());
    addTearDown(Auth.reset);
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.businessAccess = access(
      application: status,
      rejectReason: rejectReason,
    );
    return state;
  }

  testWidgets('a pending applicant is told to wait, not to apply again', (
    tester,
  ) async {
    final state = await signedInWith(tester, BusinessApplicationStatus.pending);
    await openGate(tester, state);

    expect(find.text('심사 중이에요'), findsOneWidget);
    // 심사 중에 "등록하기"를 다시 눌러 중복 신청을 만들면 안 된다.
    expect(find.byKey(const ValueKey('pro-gate-apply')), findsNothing);
    expect(find.byKey(const ValueKey('pro-gate-dismiss')), findsOneWidget);
  });

  testWidgets('a rejection shows the reason and the way back in', (
    tester,
  ) async {
    final state = await signedInWith(
      tester,
      BusinessApplicationStatus.rejected,
      rejectReason: '자격증 사본이 흐립니다',
    );
    await openGate(tester, state);

    expect(find.text('승인되지 않았어요'), findsOneWidget);
    // 무엇을 고쳐야 하는지 모르면 다시 낼 수 없다.
    expect(find.text('자격증 사본이 흐립니다'), findsOneWidget);
    expect(find.text('다시 신청하기'), findsOneWidget);
  });

  testWidgets('someone who never applied is pointed at registration', (
    tester,
  ) async {
    final state = await signedInWith(tester, null);
    await openGate(tester, state);

    expect(find.text('트레이너 등록이 필요해요'), findsOneWidget);
    expect(find.text('트레이너 등록하기'), findsOneWidget);
  });
}
