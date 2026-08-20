import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _gymId = '33333333-3333-4333-8333-333333333333';
const _memberId = '44444444-4444-4444-8444-444444444444';
const _trainerId = '55555555-5555-4555-8555-555555555555';
const _inviteId = '66666666-6666-4666-8666-666666666666';
const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  test('custom business invite deep link captures the exact token only', () {
    final state = AppState();
    addTearDown(state.dispose);

    state.captureIncomingUri(
      Uri.parse('com.teampara.setflow://business-invite/$_token'),
    );

    expect(state.pendingBusinessInviteToken, _token);

    state.captureIncomingUri(
      Uri.parse('com.teampara.setflow://routine-share/unrelated-token'),
    );
    expect(state.pendingBusinessInviteToken, _token);

    state.clearPendingBusinessInviteToken();
    state.captureIncomingUri(
      Uri.parse('https://setflow.app/invite/not-business?token=ignored'),
    );
    expect(state.pendingBusinessInviteToken, isNull);
  });

  test(
    'gym invite creation sends exact UUIDs and deduplicates a repeated tap',
    () async {
      final createCompleter = Completer<BusinessInviteCreation>();
      final repository = _InviteBusinessRepository.gym(
        createCompleter: createCompleter,
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final first = state.createGymBusinessInvite(
        kind: BusinessInviteKind.member,
        memberId: _memberId,
        recipientName: '연결할 회원',
        recipientPhone: '01012345678',
      );
      final duplicate = state.createGymBusinessInvite(
        kind: BusinessInviteKind.member,
        memberId: _memberId,
        recipientName: '연결할 회원',
        recipientPhone: '01012345678',
      );

      expect(identical(first, duplicate), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(repository.createInputs, hasLength(1));
      final input = repository.createInputs.single;
      expect(input.gymId, _gymId);
      expect(input.kind, BusinessInviteKind.member);
      expect(input.memberId, _memberId);
      expect(input.requestId, matches(_uuidV4Pattern));

      final creation = _creation();
      createCompleter.complete(creation);
      expect(await first, same(creation));
      expect(await duplicate, same(creation));
      expect(repository.createInputs, hasLength(1));
    },
  );

  test(
    'invite create retry reuses request id and exact expiry until success',
    () async {
      final repository = _InviteBusinessRepository.gym(
        createFailuresBeforeSuccess: 1,
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      Future<BusinessInviteCreation> create() => state.createGymBusinessInvite(
        kind: BusinessInviteKind.member,
        memberId: _memberId,
        recipientName: ' 연결할 회원 ',
        recipientPhone: ' 01012345678 ',
      );

      await expectLater(create(), throwsA(isA<StateError>()));
      await create();

      expect(repository.createInputs, hasLength(2));
      expect(
        repository.createInputs[1].requestId,
        repository.createInputs[0].requestId,
      );
      expect(
        repository.createInputs[1].expiresAt,
        repository.createInputs[0].expiresAt,
      );
      expect(repository.createInputs[0].recipientName, '연결할 회원');
      expect(repository.createInputs[0].recipientPhone, '01012345678');

      await create();
      expect(repository.createInputs, hasLength(3));
      expect(
        repository.createInputs[2].requestId,
        isNot(repository.createInputs[1].requestId),
      );
    },
  );

  test(
    'different invite payloads are not collapsed into one in-flight mutation',
    () async {
      final createCompleter = Completer<BusinessInviteCreation>();
      final repository = _InviteBusinessRepository.gym(
        createCompleter: createCompleter,
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final first = state.createGymBusinessInvite(
        kind: BusinessInviteKind.member,
        recipientName: '첫 번째 회원',
      );
      final second = state.createGymBusinessInvite(
        kind: BusinessInviteKind.member,
        recipientName: '두 번째 회원',
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.createInputs, hasLength(2));
      expect(repository.createInputs.map((input) => input.recipientName), {
        '첫 번째 회원',
        '두 번째 회원',
      });
      expect(
        repository.createInputs.map((input) => input.requestId).toSet(),
        hasLength(2),
      );

      createCompleter.complete(_creation());
      await Future.wait([first, second]);
    },
  );

  test('invite revoke retry reuses request id until success', () async {
    final repository = _InviteBusinessRepository.gym(
      revokeFailuresBeforeSuccess: 1,
    );
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();

    await expectLater(
      state.revokeBusinessInvite(_inviteId),
      throwsA(isA<StateError>()),
    );
    await state.revokeBusinessInvite(_inviteId);

    expect(repository.revokeInputs, hasLength(2));
    expect(repository.revokeInputs[1].$2, repository.revokeInputs[0].$2);
  });

  test(
    'accept sends the exact token, clears pending state, and refreshes access',
    () async {
      final repository = _InviteBusinessRepository.member(
        acceptance: _acceptance(accepted: true),
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      expect(repository.loadAccessCount, 1);

      state.captureIncomingUri(
        Uri.parse('com.teampara.setflow://business-invite/$_token'),
      );
      final result = await state.acceptBusinessInviteToken();

      expect(result.accepted, isTrue);
      expect(repository.acceptedTokens, [_token]);
      expect(repository.acceptRequestIds.single, matches(_uuidV4Pattern));
      expect(state.pendingBusinessInviteToken, isNull);
      expect(repository.loadAccessCount, 2);
    },
  );

  test(
    'accept retry reuses the same request id after a network failure',
    () async {
      final repository = _InviteBusinessRepository.member(
        acceptance: _acceptance(accepted: true),
        acceptFailuresBeforeSuccess: 1,
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      state.captureIncomingUri(
        Uri.parse('com.teampara.setflow://business-invite/$_token'),
      );

      await expectLater(
        state.acceptBusinessInviteToken(),
        throwsA(isA<StateError>()),
      );
      expect(state.pendingBusinessInviteToken, _token);

      final result = await state.acceptBusinessInviteToken();

      expect(result.accepted, isTrue);
      expect(repository.acceptedTokens, [_token, _token]);
      expect(repository.acceptRequestIds, hasLength(2));
      expect(repository.acceptRequestIds.first, matches(_uuidV4Pattern));
      expect(
        repository.acceptRequestIds.last,
        repository.acceptRequestIds.first,
      );
      expect(state.pendingBusinessInviteToken, isNull);
    },
  );

  test(
    'expired invite returns accepted=false and is cleared after refresh',
    () async {
      final repository = _InviteBusinessRepository.member(
        acceptance: _acceptance(accepted: false),
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      state.captureIncomingUri(
        Uri.parse('com.teampara.setflow://business-invite/$_token'),
      );

      final result = await state.acceptBusinessInviteToken();

      expect(result.accepted, isFalse);
      expect(result.invite.status, BusinessInviteStatus.expired);
      expect(state.pendingBusinessInviteToken, isNull);
      expect(repository.loadAccessCount, 2);
    },
  );

  testWidgets('live People page opens the server-backed member invite form', (
    tester,
  ) async {
    final state = AppState(
      businessRepository: _InviteBusinessRepository.gym(),
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();
    await _pumpScreen(tester, state, const PeoplePage(role: UserRole.gym));

    expect(find.text('초대'), findsOneWidget);
    expect(find.textContaining('gym-7K2M9'), findsNothing);

    await tester.tap(find.text('초대'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('business-invite-create')), findsOneWidget);
    expect(find.text('회원 초대'), findsOneWidget);
    expect(find.textContaining('gym-7K2M9'), findsNothing);
  });

  testWidgets(
    'live TrainerManagement opens the server-backed trainer invite form',
    (tester) async {
      final state = AppState(
        businessRepository: _InviteBusinessRepository.gym(),
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      await _pumpScreen(tester, state, const TrainerManagementPage());

      expect(find.byTooltip('트레이너 초대'), findsOneWidget);
      expect(find.textContaining('trainer-GYM7K2'), findsNothing);

      await tester.tap(find.byTooltip('트레이너 초대'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('business-invite-create')), findsOneWidget);
      expect(find.text('트레이너 초대'), findsWidgets);
      expect(find.textContaining('trainer-GYM7K2'), findsNothing);
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AppState state,
  Widget screen,
) async {
  await tester.binding.setSurfaceSize(const Size(432, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(theme: SetflowTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

BusinessInviteCreation _creation() => BusinessInviteCreation(
  invite: _invite(),
  tokenIssued: true,
  token: _token,
  uri: Uri.parse('com.teampara.setflow://business-invite/$_token'),
);

BusinessInviteAcceptance _acceptance({required bool accepted}) =>
    BusinessInviteAcceptance(
      accepted: accepted,
      invite: _invite(
        status: accepted
            ? BusinessInviteStatus.accepted
            : BusinessInviteStatus.expired,
      ),
      memberId: accepted ? _memberId : null,
    );

BusinessInviteRecord _invite({
  BusinessInviteStatus status = BusinessInviteStatus.pending,
}) {
  final now = DateTime.utc(2026, 8, 16);
  return BusinessInviteRecord(
    id: _inviteId,
    gymId: _gymId,
    kind: BusinessInviteKind.member,
    status: status,
    createdByUserId: _userId,
    memberId: _memberId,
    recipientName: '연결할 회원',
    expiresAt: now.add(const Duration(days: 7)),
    createdAt: now,
    updatedAt: now,
  );
}

class _InviteBusinessRepository implements BusinessRepository {
  _InviteBusinessRepository._({
    required this.access,
    this.workspace,
    this.createCompleter,
    this.acceptance,
    int createFailuresBeforeSuccess = 0,
    int acceptFailuresBeforeSuccess = 0,
    int revokeFailuresBeforeSuccess = 0,
  }) : _remainingCreateFailures = createFailuresBeforeSuccess,
       _remainingAcceptFailures = acceptFailuresBeforeSuccess,
       _remainingRevokeFailures = revokeFailuresBeforeSuccess;

  factory _InviteBusinessRepository.gym({
    Completer<BusinessInviteCreation>? createCompleter,
    int createFailuresBeforeSuccess = 0,
    int revokeFailuresBeforeSuccess = 0,
  }) {
    const profile = GymBusinessProfile(
      id: _gymId,
      ownerUserId: _userId,
      name: '실데이터 센터',
      status: BusinessProfileStatus.verified,
      planTier: 'enterprise',
    );
    const access = BusinessAccess(
      userId: _userId,
      accountRole: UserRole.gym,
      resolvedRole: UserRole.gym,
      availableRoles: {UserRole.gym},
      gym: profile,
    );
    return _InviteBusinessRepository._(
      access: access,
      createCompleter: createCompleter,
      createFailuresBeforeSuccess: createFailuresBeforeSuccess,
      revokeFailuresBeforeSuccess: revokeFailuresBeforeSuccess,
      workspace: BusinessWorkspaceData(
        role: UserRole.gym,
        access: access,
        profile: profile,
        dashboardStats: const BusinessDashboardMetrics(
          activeMembers: 1,
          trainerCount: 1,
        ),
        members: const [
          BusinessMember(
            id: _memberId,
            gymId: _gymId,
            userId: '77777777-7777-4777-8777-777777777777',
            name: '실회원',
            remainingPtSessions: 8,
          ),
        ],
        trainers: const [
          GymTrainerRecord(
            id: '88888888-8888-4888-8888-888888888888',
            gymId: _gymId,
            trainerId: _trainerId,
            displayName: '실트레이너',
            status: 'active',
            memberCount: 1,
            averageRating: 4.8,
            monthlySales: 1000000,
          ),
        ],
      ),
    );
  }

  factory _InviteBusinessRepository.member({
    required BusinessInviteAcceptance acceptance,
    int acceptFailuresBeforeSuccess = 0,
  }) => _InviteBusinessRepository._(
    access: const BusinessAccess(
      userId: _userId,
      accountRole: UserRole.member,
      resolvedRole: UserRole.member,
      availableRoles: {UserRole.member},
    ),
    acceptance: acceptance,
    acceptFailuresBeforeSuccess: acceptFailuresBeforeSuccess,
  );

  final BusinessAccess access;
  final BusinessWorkspaceData? workspace;
  final Completer<BusinessInviteCreation>? createCompleter;
  final BusinessInviteAcceptance? acceptance;
  int _remainingCreateFailures;
  int _remainingAcceptFailures;
  int _remainingRevokeFailures;
  final List<CreateBusinessInviteInput> createInputs = [];
  final List<String> acceptedTokens = [];
  final List<String> acceptRequestIds = [];
  final List<(String, String)> revokeInputs = [];
  int loadAccessCount = 0;

  @override
  Future<BusinessAccess> loadAccess() async {
    loadAccessCount++;
    return access;
  }

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async {
    final current = workspace;
    if (current == null || current.role != role) {
      throw StateError('workspace missing for $role');
    }
    return current;
  }

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => const [];

  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async =>
      const MemberSharingPreferences(
        shareBodyData: false,
        shareWorkoutRecords: false,
        marketing: false,
      );

  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async =>
      const [];

  @override
  Future<List<RoutineShareRecord>> listOutgoingRoutineShares({
    String? routineId,
  }) async => const [];

  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async => const [];

  @override
  Future<List<BusinessInviteRecord>> listBusinessInvites(
    String gymId, {
    BusinessInviteStatus? status,
  }) async {
    expect(gymId, _gymId);
    return const [];
  }

  @override
  Future<BusinessInviteCreation> createBusinessInvite(
    CreateBusinessInviteInput input,
  ) async {
    createInputs.add(input);
    if (_remainingCreateFailures > 0) {
      _remainingCreateFailures--;
      throw StateError('create response lost');
    }
    final completer = createCompleter;
    if (completer != null) return completer.future;
    return _creation();
  }

  @override
  Future<BusinessInviteAcceptance> acceptBusinessInvite(
    String token, {
    required String requestId,
  }) async {
    acceptedTokens.add(token);
    acceptRequestIds.add(requestId);
    if (_remainingAcceptFailures > 0) {
      _remainingAcceptFailures--;
      throw StateError('network unavailable');
    }
    return acceptance ?? _acceptance(accepted: true);
  }

  @override
  Future<BusinessInviteRecord> revokeBusinessInvite(
    String inviteId, {
    required String requestId,
  }) async {
    revokeInputs.add((inviteId, requestId));
    if (_remainingRevokeFailures > 0) {
      _remainingRevokeFailures--;
      throw StateError('revoke response lost');
    }
    return _invite(status: BusinessInviteStatus.revoked);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
