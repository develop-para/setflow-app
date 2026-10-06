import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/email_auth_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workspace_selection_screen.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/widgets/coaching_invite_accept_sheet.dart';

const _member = '11111111-1111-4111-8111-111111111111';
const _otherMember = '22222222-2222-4222-8222-222222222222';
const _trainer = '33333333-3333-4333-8333-333333333333';
const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _link = 'com.teampara.setflow://coaching-invite/$_token';

void main() {
  late _Auth auth;
  setUp(() {
    auth = _Auth();
    Auth.use(auth);
  });
  tearDown(() async {
    Auth.reset();
    await auth.changes.close();
  });

  testWidgets(
    'guest signs in through the real app and waits for account sync',
    (tester) async {
      final business = _BusinessRepository(auth)
        ..pendingAccess = Completer<BusinessAccess>();
      final storage = _Storage();
      final state = await _launch(tester, storage, business);
      await _startLogin(tester);
      expect(auth.currentUser?.id, _member);
      expect(business.acceptedAccounts, isEmpty);
      expect(
        find.byKey(const ValueKey('coaching-invite-input')),
        findsOneWidget,
      );
      expect(state.coachingInviteAcceptanceInProgress, isTrue);
      business.pendingAccess!.complete(business.accessFor(_member));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(business.acceptedAccounts, [_member]);
      expect(business.acceptedTokens, [_token]);
      expect(find.byKey(const ValueKey('coaching-invite-input')), findsNothing);
      expect(state.coachingConnections.single.memberUserId, _member);
      expect(state.coachingInviteAcceptanceInProgress, isFalse);
      expect(find.textContaining('계정이 바뀌었어요'), findsNothing);
      expect(storage.adoptedBy, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final adopt in [false, true]) {
    testWidgets(
      'email completion leaves guest import open until explicit ${adopt ? 'acceptance' : 'decline'}',
      (tester) async {
        auth.signInCompletion = Completer<void>();
        final storage = _Storage(guest: _guestSnapshot());
        final business = _BusinessRepository(auth);
        final state = await _launch(tester, storage, business);
        await _startLogin(tester);
        expect(find.byKey(const ValueKey('guest-adopt-title')), findsOneWidget);
        expect(storage.adoptedBy, isNull);
        expect(business.acceptedAccounts, isEmpty);
        // The auth stream has already opened the offer above EmailAuthScreen.
        // Completing signIn must finish its own route, not pop the offer as yes.
        auth.signInCompletion!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const ValueKey('guest-adopt-title')), findsOneWidget);
        expect(find.byType(EmailAuthScreen), findsNothing);
        expect(storage.adoptedBy, isNull);
        expect(business.acceptedAccounts, isEmpty);
        expect(state.coachingInviteAcceptanceInProgress, isTrue);
        await tester.tap(
          find.byKey(
            ValueKey(adopt ? 'guest-adopt-confirm' : 'guest-adopt-decline'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        expect(storage.adoptedBy, adopt ? _member : isNull);
        expect(business.acceptedAccounts, [_member]);
        expect(
          find.byKey(const ValueKey('coaching-invite-input')),
          findsNothing,
        );
        expect(state.coachingConnections.single.memberUserId, _member);
        if (adopt) {
          expect(
            state.routines.any((routine) => routine.id == 'guest-routine'),
            isTrue,
          );
          expect(
            storage.calls.indexOf('adopt'),
            lessThan(storage.calls.indexOf('member-load')),
          );
        } else {
          expect(storage.guest, isNotNull);
          expect(
            state.routines.any((routine) => routine.id == 'guest-routine'),
            isFalse,
          );
          expect(storage.calls, isNot(contains('adopt')));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'multiple workspaces wait for the invite consent route to finish',
    (tester) async {
      final business = _BusinessRepository(auth)
        ..roles = {UserRole.member, UserRole.trainer}
        ..pendingAcceptance = Completer<CoachingConnectionAcceptance>();
      final state = await _launch(tester, _Storage(), business);
      await _startLogin(tester);
      expect(business.acceptedAccounts, [_member]);
      expect(state.needsWorkspaceSelection, isTrue);
      expect(state.coachingInviteAcceptanceInProgress, isTrue);
      final invite = find.byKey(const ValueKey('coaching-invite-input'));
      expect(invite, findsOneWidget);
      expect(ModalRoute.of(tester.element(invite))!.isCurrent, isTrue);
      expect(find.byType(BusinessShell), findsNothing);
      business.pendingAcceptance!.complete(
        CoachingConnectionAcceptance(
          accepted: true,
          connection: _connection(_member),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(invite, findsNothing);
      expect(state.coachingInviteAcceptanceInProgress, isFalse);
      expect(find.byType(WorkspaceSelectionScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-member')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-trainer')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'another sign-in prevents a late invite result from showing success',
    (tester) async {
      final business = _BusinessRepository(auth)
        ..pendingAcceptance = Completer<CoachingConnectionAcceptance>();
      final state = await _launch(tester, _Storage(), business);
      await _startLogin(tester);
      expect(business.acceptedAccounts, [_member]);
      auth.emitSignIn(_otherMember);
      await tester.pumpAndSettle();
      business.pendingAcceptance!.complete(
        CoachingConnectionAcceptance(
          accepted: true,
          connection: _connection(_member),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(state.businessAccess?.userId, _otherMember);
      expect(state.coachingConnections, isEmpty);
      expect(find.textContaining('계정이 바뀌었어요.'), findsOneWidget);
      expect(find.textContaining('트레이너와 연결됐어요'), findsNothing);
      expect(business.acceptedAccounts, [_member]);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('coaching-invite-confirm')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<AppState> _launch(
  WidgetTester tester,
  _Storage storage,
  _BusinessRepository business,
) async {
  await tester.binding.setSurfaceSize(const Size(432, 900));
  await tester.pumpWidget(
    SetflowApp(repository: storage, businessRepository: business),
  );
  await tester.pump(const Duration(milliseconds: 1900));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(MemberShell));
  final state = AppScope.of(context);
  unawaited(showCoachingInviteAcceptance(context, initialInput: _link));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    await tester.binding.setSurfaceSize(null);
  });
  return state;
}

Future<void> _startLogin(WidgetTester tester) async {
  final confirm = find.byKey(const ValueKey('coaching-invite-confirm'));
  await tester.ensureVisible(confirm);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('auth-gate-sign-in')));
  await tester.pumpAndSettle();
  final fields = find.descendant(
    of: find.byType(EmailAuthScreen),
    matching: find.byType(TextFormField),
  );
  await tester.enterText(fields.at(0), 'member@example.test');
  await tester.enterText(fields.at(1), 'test-password');
  final login = find.text('로그인');
  await tester.ensureVisible(login);
  await tester.tap(login);
  // signIn or account sync may intentionally stay pending. Settling a loading
  // animation would advance fake time to the RPC timeout or run forever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

AppSnapshot _guestSnapshot() => AppSnapshot(
  role: UserRole.guest,
  isDarkMode: false,
  weightUnit: 'kg',
  restDefaultSeconds: 90,
  sessions: const {},
  routines: [
    RoutineData(
      id: 'guest-routine',
      name: '기기에 만든 루틴',
      description: '',
      color: Colors.grey,
      exercises: [],
    ),
  ],
);

CoachingConnection _connection(String memberId) => CoachingConnection(
  id: 'connection-$memberId',
  trainerId: _trainer,
  memberUserId: memberId,
  memberName: '회원',
  trainerName: '담당 트레이너',
  status: 'active',
  createdAt: DateTime.utc(2026, 10, 7),
);

class _Storage implements AppRepository, GuestDataAdoption {
  _Storage({this.guest});
  AppSnapshot? guest;
  String? adoptedBy;
  final calls = <String>[];
  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) async {
    final actor = Auth.instance.currentUser?.id;
    calls.add(actor == null ? 'guest-load' : 'member-load');
    return actor == null || actor == adoptedBy ? guest : null;
  }

  @override
  Future<void> save(AppSnapshot snapshot) async => calls.add('save');
  @override
  Future<void> clear() async => calls.add('clear');
  @override
  Future<AppSnapshot?> peekGuestSnapshot(
    List<ExerciseTemplate> exerciseCatalog,
  ) async => guest;
  @override
  Future<bool> adoptGuestSnapshot(String userId) async {
    calls.add('adopt');
    adoptedBy = userId;
    return true;
  }
}

class _Auth extends Fake implements AuthService {
  final changes = StreamController<AuthChange>.broadcast();
  AuthUser? user;
  Completer<void>? signInCompletion;
  @override
  AuthUser? get currentUser => user;
  @override
  bool get hasAuthenticatedUser => user != null;
  @override
  String get currentDisplayName => user?.displayName ?? '회원';
  @override
  Stream<AuthChange> get authChanges => changes.stream;
  @override
  bool isConfigured(SocialLoginProvider provider) => false;
  @override
  Future<void> signIn({required String email, required String password}) async {
    emitSignIn(_member);
    if (signInCompletion != null) await signInCompletion!.future;
  }

  void emitSignIn(String id) {
    user = AuthUser(id: id, displayName: '회원', email: 'member@example.test');
    changes.add(AuthChange(AuthEvent.signedIn, user));
  }

  @override
  Future<bool> isVerifiedAdmin() async => false;
  @override
  String messageFor(Object error) => error.toString();
}

class _BusinessRepository extends Fake
    implements BusinessRepository, MobileCoachingRepository {
  _BusinessRepository(this.auth);
  final _Auth auth;
  Set<UserRole> roles = {UserRole.member};
  Completer<BusinessAccess>? pendingAccess;
  Completer<CoachingConnectionAcceptance>? pendingAcceptance;
  final acceptedAccounts = <String>[];
  final acceptedTokens = <String>[];
  final connectionsByAccount = <String, List<CoachingConnection>>{};

  BusinessAccess accessFor(String actor) => BusinessAccess(
    userId: actor,
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: roles,
  );
  @override
  Future<BusinessAccess> loadAccess() async =>
      pendingAccess?.future ?? Future.value(accessFor(auth.currentUser!.id));
  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async =>
      BusinessWorkspaceData(
        role: role,
        access: accessFor(auth.currentUser!.id),
        dashboardStats: const BusinessDashboardMetrics(),
        coachingConnections: await listCoachingConnections(),
      );
  @override
  Future<CoachingConnectionAcceptance> acceptCoachingConnectionInvite(
    String token, {
    required String requestId,
  }) async {
    final actor = auth.currentUser!.id;
    acceptedAccounts.add(actor);
    acceptedTokens.add(token);
    final result = pendingAcceptance == null
        ? CoachingConnectionAcceptance(
            accepted: true,
            connection: _connection(actor),
          )
        : await pendingAcceptance!.future;
    if (result.accepted) connectionsByAccount[actor] = [_connection(actor)];
    return result;
  }

  @override
  Future<List<CoachingConnection>> listCoachingConnections() async =>
      connectionsByAccount[auth.currentUser?.id] ?? [];
  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => [];
  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => [];
  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => [];
  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async => [];
  @override
  Future<List<RoutineShareRecord>> listOutgoingRoutineShares({
    String? routineId,
  }) async => [];
  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async => [];
  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async =>
      const MemberSharingPreferences(
        shareBodyData: false,
        shareWorkoutRecords: false,
        marketing: false,
      );
}
