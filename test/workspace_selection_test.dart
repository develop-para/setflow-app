import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/member_menu_screen.dart';
import 'package:setflow/screens/workspace_selection_screen.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';

BusinessAccess _access(Set<UserRole> roles) => BusinessAccess(
  userId: _userId,
  accountRole: UserRole.member,
  resolvedRole: UserRole.member,
  availableRoles: roles,
);

class _Auth implements AuthService {
  AuthUser? user = const AuthUser(id: _userId, displayName: '테스트');
  final changes = StreamController<AuthChange>.broadcast();
  @override
  Stream<AuthChange> get authChanges => changes.stream;
  @override
  Future<void> signIn({required String email, required String password}) async {
    user = const AuthUser(id: _userId, displayName: '테스트');
    changes.add(AuthChange(AuthEvent.signedIn, user));
  }

  @override
  Future<void> signOut() async {
    user = null;
    changes.add(const AuthChange(AuthEvent.signedOut, null));
  }

  @override
  AuthUser? get currentUser => user;
  @override
  bool get hasAuthenticatedUser => user != null;
  @override
  String get currentDisplayName => user?.displayName ?? '회원';
  @override
  Future<bool> isVerifiedAdmin() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements BusinessRepository {
  BusinessAccess access = _access({
    UserRole.member,
    UserRole.trainer,
    UserRole.gym,
  });
  int accessReads = 0;
  Object? failure;
  Completer<BusinessAccess>? pending;
  @override
  Future<BusinessAccess> loadAccess() async {
    accessReads++;
    if (failure case final Object error) throw error;
    return pending == null ? access : pending!.future;
  }

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async =>
      BusinessWorkspaceData(
        role: role,
        access: access,
        dashboardStats: const BusinessDashboardMetrics(),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Auth auth;
  late _Repository repository;
  late AppState state;

  setUp(() async {
    Auth.reset();
    repository = _Repository();
    state = AppState(businessRepository: repository);
    await state.initialize();
    auth = _Auth();
    Auth.use(auth);
  });
  tearDown(() {
    state.dispose();
    unawaited(auth.changes.close());
    Auth.reset();
  });

  Future<void> launch(WidgetTester tester, {bool largeText = false}) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(largeText ? 2 : 1),
              padding: const EdgeInsets.only(top: 24, bottom: 28),
            ),
            child: child!,
          ),
          home: const RootScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
  }

  testWidgets('launch shows every granted role before opening a workspace', (
    tester,
  ) async {
    await state.refreshBusinessAccess();
    await launch(tester);
    expect(find.byType(WorkspaceSelectionScreen), findsOneWidget);
    expect(find.byType(BusinessShell), findsNothing);
    expect(find.byKey(const ValueKey('workspace-member')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-trainer')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-gym')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-admin')), findsNothing);
    final reads = repository.accessReads;
    await tester.tap(find.byKey(const ValueKey('workspace-gym')));
    await tester.pumpAndSettle();
    expect(repository.accessReads, reads + 1);
    expect(state.role, UserRole.gym);
    expect(find.byType(WorkspaceSelectionScreen), findsNothing);
    expect(
      tester.widget<BusinessShell>(find.byType(BusinessShell)).role,
      UserRole.gym,
    );
  });

  testWidgets(
    'member-only accounts and guests go straight to personal records',
    (tester) async {
      repository.access = _access({UserRole.member});
      await state.refreshBusinessAccess();
      await launch(tester);
      expect(find.byType(MemberShell), findsOneWidget);
      expect(find.byType(WorkspaceSelectionScreen), findsNothing);
      auth.user = null;
      state.handleExternalAuthSignedOut();
      await tester.pumpAndSettle();
      expect(find.byType(MemberShell), findsOneWidget);
    },
  );

  testWidgets('revocation between the list and a tap prevents entry', (
    tester,
  ) async {
    await state.refreshBusinessAccess();
    await launch(tester);
    repository.access = _access({UserRole.member});
    await tester.tap(find.byKey(const ValueKey('workspace-trainer')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.role, UserRole.member);
    expect(find.byType(BusinessShell), findsNothing);
    expect(find.text('이 역할의 이용 권한이 없어요. 다시 확인해주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-retry')), findsOneWidget);
  });

  testWidgets('offline access offers retry and personal records', (
    tester,
  ) async {
    repository.failure = Exception('offline');
    await state.refreshBusinessAccess();
    await launch(tester);
    expect(find.byKey(const ValueKey('workspace-trainer')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-personal')));
    await tester.pumpAndSettle();
    expect(find.byType(MemberShell), findsOneWidget);
  });

  testWidgets('retry restores the server role list', (tester) async {
    repository.failure = Exception('offline');
    await state.refreshBusinessAccess();
    await launch(tester);
    repository.failure = null;
    await tester.tap(find.byKey(const ValueKey('workspace-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-gym')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-retry')), findsNothing);
  });

  testWidgets(
    'small screens and double text scale keep all choices reachable',
    (tester) async {
      await state.refreshBusinessAccess();
      await launch(tester, largeText: true);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('workspace-gym')),
        150,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('workspace-gym'))).bottom,
        lessThanOrEqualTo(540),
      );
    },
  );

  test('a late server response cannot restore access after logout', () async {
    repository.pending = Completer<BusinessAccess>();
    final entry = state.enterWorkspace(UserRole.trainer);
    auth.user = null;
    state.handleExternalAuthSignedOut();
    repository.pending!.complete(repository.access);
    expect(await entry, isFalse);
    expect(state.role, UserRole.guest);
    expect(state.businessAccess, isNull);
  });

  test('portal switching cannot bypass member-only grants', () async {
    repository.access = _access({UserRole.member});
    await state.refreshBusinessAccess();
    state.chooseRole(UserRole.member);
    await state.switchPortal(AppPortal.trainer);
    expect(state.role, UserRole.member);
    expect(state.businessWorkspace, isNull);
  });

  test(
    'returning to personal records does not wait for a server check',
    () async {
      await state.refreshBusinessAccess();
      state.chooseRole(UserRole.trainer);
      await Future<void>.delayed(Duration.zero);
      final reads = repository.accessReads;
      repository.failure = Exception('offline');
      await state.switchPortal(AppPortal.client);
      expect(state.role, UserRole.member);
      expect(repository.accessReads, reads);
      expect(state.needsWorkspaceSelection, isFalse);
    },
  );

  test(
    'a server session refusal clears the previously loaded workspace',
    () async {
      expect(await state.enterWorkspace(UserRole.trainer), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(state.businessWorkspace, isNotNull);
      repository.failure = const BusinessAccessDenied();
      await expectLater(
        state.refreshBusinessDashboard(UserRole.trainer),
        throwsA(isA<BusinessAccessDenied>()),
      );
      expect(state.businessWorkspace, isNull);
      expect(state.businessAccess, isNull);
      expect(state.role, UserRole.member);
      expect(state.businessLoading, isFalse);
      expect(state.needsWorkspaceSelection, isTrue);
    },
  );

  test('entry choice does not reappear on ordinary access refresh', () async {
    expect(await state.enterWorkspace(UserRole.member), isTrue);
    await state.refreshBusinessAccess();
    expect(state.needsWorkspaceSelection, isFalse);
  });

  test(
    'approval received during a member session does not interrupt it',
    () async {
      repository.access = _access({UserRole.member});
      await state.refreshBusinessAccess();
      repository.access = _access({UserRole.member, UserRole.trainer});
      await state.refreshBusinessAccess();
      expect(state.needsWorkspaceSelection, isFalse);
    },
  );

  testWidgets('a login from a pushed menu reveals the choice at the root', (
    tester,
  ) async {
    auth.user = null;
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(SetflowApp(businessRepository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(MemberMenuScreen), findsOneWidget);
    await auth.signIn(email: 'member@example.test', password: 'test-password');
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceSelectionScreen), findsOneWidget);
    expect(find.byType(MemberMenuScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('workspace-member')));
    await tester.pumpAndSettle();
    expect(find.byType(MemberShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
