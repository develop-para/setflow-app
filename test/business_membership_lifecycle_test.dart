import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _gymId = '22222222-2222-4222-8222-222222222222';
const _memberId = '33333333-3333-4333-8333-333333333333';

void main() {
  test('membership migration fails closed by role and active relationship', () {
    final sql = File(
      'supabase/migrations/20260816035904_business_membership_lifecycle.sql',
    ).readAsStringSync();
    final scheduleSql = File(
      'supabase/migrations/20260816125326_coaching_schedule_atomic_create.sql',
    ).readAsStringSync();
    final routineGuardSql = File(
      'supabase/migrations/20260816133000_active_membership_routine_share_guard.sql',
    ).readAsStringSync();

    expect(sql, contains("status = 'ended'"));
    expect(sql, contains('ended_by_user_id'));
    expect(
      sql,
      contains(
        'revoke update (status, ended_at, ended_by_user_id, rejoined_at)',
      ),
    );
    expect(sql, contains('m.user_id = v_user_id'));
    expect(sql, contains('g.owner_user_id = v_user_id'));
    expect(sql, contains("g.status = 'verified'"));
    expect(sql, contains('set active = false'));
    expect(sql, contains('business_membership_end_requests'));
    expect(sql, contains('r.ended_by_user_id, r.response'));
    expect(sql, contains('v_request_actor_id is distinct from v_user_id'));
    expect(sql, contains('if v_response is not null then'));
    expect(sql, contains('return v_response;'));
    expect(sql, contains("m.status = 'active'"));
    expect(sql, contains('has_active_member_business_relationship'));
    expect(sql, contains('has_active_coaching_schedule_relationship'));
    expect(sql, contains('accept_business_invite_before_membership_lifecycle'));
    expect(sql, contains("when status = 'ended' then statement_timestamp()"));
    expect(
      sql,
      contains('revoke all on function public.end_business_membership'),
    );
    expect(scheduleSql, contains("m.status = 'active'"));
    expect(routineGuardSql, contains("member.status = 'active'"));
    expect(
      routineGuardSql,
      contains("new.status in ('pending', 'accepted', 'declined')"),
    );
    expect(routineGuardSql, contains("set status = 'expired'"));
  });

  test(
    'delayed end retry replays its snapshot before any rejoined row mutation',
    () {
      final sql = File(
        'supabase/migrations/20260816035904_business_membership_lifecycle.sql',
      ).readAsStringSync();
      final replayIndex = sql.indexOf('if v_response is not null then');
      final mutationIndex = sql.indexOf("if v_member.status = 'active' then");

      expect(replayIndex, greaterThan(0));
      expect(mutationIndex, greaterThan(replayIndex));
      expect(sql, contains('set response = v_response'));
      expect(sql, contains("status = 'active',\n        ended_at = null"));
    },
  );

  test('accepted invite replay cannot reactivate a later-ended membership', () {
    final sql = File(
      'supabase/migrations/20260816035904_business_membership_lifecycle.sql',
    ).readAsStringSync();
    final wrapperIndex = sql.indexOf(
      'create or replace function private.accept_business_invite(',
    );
    final authCheckIndex = sql.indexOf(
      'if v_user_id is null then',
      wrapperIndex,
    );
    final requestCheckIndex = sql.indexOf(
      'if p_request_id is null then',
      wrapperIndex,
    );
    final tokenCheckIndex = sql.indexOf(
      "if v_token !~ '^[0-9a-f]{64}\$' then",
      wrapperIndex,
    );
    final pendingCaptureIndex = sql.indexOf(
      "select bi.status = 'pending' into v_was_pending",
      wrapperIndex,
    );
    final legacyCallIndex = sql.indexOf(
      'v_result := private.accept_business_invite_before_membership_lifecycle(',
      wrapperIndex,
    );
    final guardedReactivationIndex = sql.indexOf(
      'if v_was_pending',
      legacyCallIndex,
    );
    final activeMutationIndex = sql.indexOf(
      "status = 'active',",
      guardedReactivationIndex,
    );

    expect(wrapperIndex, greaterThan(0));
    expect(authCheckIndex, greaterThan(wrapperIndex));
    expect(requestCheckIndex, greaterThan(authCheckIndex));
    expect(tokenCheckIndex, greaterThan(requestCheckIndex));
    expect(pendingCaptureIndex, greaterThan(tokenCheckIndex));
    expect(legacyCallIndex, greaterThan(pendingCaptureIndex));
    expect(guardedReactivationIndex, greaterThan(legacyCallIndex));
    expect(activeMutationIndex, greaterThan(guardedReactivationIndex));
  });

  test('post-deployment routine delta guards every direct share transition', () {
    const deployedRoutineVersion = '20260816093402';
    const deltaVersion = '20260816133000';
    final sql = File(
      'supabase/migrations/${deltaVersion}_active_membership_routine_share_guard.sql',
    ).readAsStringSync();

    expect(deltaVersion.compareTo(deployedRoutineVersion), greaterThan(0));
    expect(
      sql,
      contains('rename to share_coaching_routine_before_active_membership'),
    );
    expect(
      sql,
      contains('rename to respond_routine_share_before_active_membership'),
    );
    expect(sql, contains('assert_active_routine_share_targets'));
    expect(sql, contains('assert_active_direct_routine_share_recipient'));
    expect(sql, contains('routine_shares_active_membership_guard'));
    expect(sql, contains('members_expire_pending_routine_shares'));
    expect(sql, contains('business_membership_end_requests_actor_idx'));
    expect(
      sql,
      contains(
        'select private.share_coaching_routine(\$1, \$2, \$3, \$4, \$5)',
      ),
    );
    expect(
      sql,
      contains('select private.respond_routine_share(\$1, \$2, \$3)'),
    );
    expect(sql, contains("new.status in ('pending', 'accepted', 'declined')"));
    expect(sql, contains("set status = 'expired'"));
    expect(sql, contains("and share_type = 'direct'"));
    expect(sql, contains("and status = 'pending'"));
    expect(sql, contains('can_read_active_shared_coaching_routine'));
    expect(sql, contains("share.share_type = 'link'"));
    expect(sql, contains("share.share_type = 'direct'"));
    expect(sql, contains("member.status = 'active'"));
    expect(sql, contains('read_coaching_routines_authenticated'));
    expect(sql, contains('read_coaching_exercises_authenticated'));
    expect(sql, contains('read_coaching_sets_authenticated'));
  });

  test('active membership checks precede deployed routine RPC replay paths', () {
    final sql = File(
      'supabase/migrations/20260816133000_active_membership_routine_share_guard.sql',
    ).readAsStringSync();
    final shareWrapper = sql.indexOf(
      'create or replace function private.share_coaching_routine(',
    );
    final shareGuard = sql.indexOf(
      'perform private.assert_active_routine_share_targets(',
      shareWrapper,
    );
    final shareLegacy = sql.indexOf(
      'return private.share_coaching_routine_before_active_membership(',
      shareWrapper,
    );
    final respondWrapper = sql.indexOf(
      'create or replace function private.respond_routine_share(',
    );
    final respondGuard = sql.indexOf(
      'perform private.assert_active_direct_routine_share_recipient(',
      respondWrapper,
    );
    final respondLegacy = sql.indexOf(
      'return private.respond_routine_share_before_active_membership(',
      respondWrapper,
    );

    expect(shareWrapper, greaterThan(0));
    expect(shareGuard, greaterThan(shareWrapper));
    expect(shareLegacy, greaterThan(shareGuard));
    expect(respondWrapper, greaterThan(shareLegacy));
    expect(respondGuard, greaterThan(respondWrapper));
    expect(respondLegacy, greaterThan(respondGuard));
  });

  test(
    'termination retries use the same request UUID and refresh workspace',
    () async {
      final repository = _MembershipRepository(
        role: UserRole.gym,
        failFirstRefreshAfterEnd: true,
      );
      final state = AppState(businessRepository: repository);
      state.role = UserRole.gym;
      state.businessAccess = repository.access;
      state.businessWorkspace = repository.workspace;
      addTearDown(state.dispose);

      await expectLater(
        state.endBusinessMembership(_memberId),
        throwsA(isA<StateError>()),
      );
      await state.endBusinessMembership(_memberId);

      expect(repository.endInputs, hasLength(2));
      expect(repository.endInputs.map((item) => item.memberId), {_memberId});
      expect(
        repository.endInputs[0].requestId,
        repository.endInputs[1].requestId,
      );
      expect(state.businessMembers, isEmpty);
    },
  );

  testWidgets('gym People UI exposes exact member termination action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MembershipRepository(role: UserRole.gym);
    final state = AppState(businessRepository: repository);
    state.role = UserRole.gym;
    state.businessAccess = repository.access;
    state.businessWorkspace = repository.workspace;
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const PeoplePage(role: UserRole.gym),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('테스트 회원'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('end-membership-$_memberId')),
      findsOneWidget,
    );
  });

  testWidgets('member can end their own center connection from settings flow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MembershipRepository(role: UserRole.member);
    final state = AppState(businessRepository: repository);
    state.role = UserRole.member;
    state.businessAccess = repository.access;
    state.memberMemberships = [repository.activeMember];
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const MemberMembershipScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('member-end-membership-$_memberId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('연결 종료'));
    await tester.pumpAndSettle();

    expect(repository.endInputs.single.memberId, _memberId);
    expect(state.memberMemberships, isEmpty);
    expect(find.text('연결된 센터가 없어요'), findsOneWidget);
  });
}

class _MembershipRepository
    implements BusinessRepository, BusinessMembershipRepository {
  _MembershipRepository({
    required this.role,
    this.failFirstRefreshAfterEnd = false,
  });

  final UserRole role;
  final bool failFirstRefreshAfterEnd;
  final List<EndBusinessMembershipInput> endInputs = [];
  bool ended = false;
  bool refreshFailed = false;

  BusinessMember get activeMember => const BusinessMember(
    id: _memberId,
    gymId: _gymId,
    userId: _userId,
    name: '테스트 회원',
    gymName: '테스트 센터',
    remainingPtSessions: 4,
  );

  GymBusinessProfile get gym => const GymBusinessProfile(
    id: _gymId,
    ownerUserId: _userId,
    name: '테스트 센터',
    status: BusinessProfileStatus.verified,
  );

  BusinessAccess get access => BusinessAccess(
    userId: _userId,
    accountRole: role,
    resolvedRole: role,
    availableRoles: {role, UserRole.member},
    gym: role == UserRole.gym ? gym : null,
  );

  BusinessWorkspaceData get workspace => BusinessWorkspaceData(
    role: UserRole.gym,
    access: access,
    profile: gym,
    dashboardStats: BusinessDashboardMetrics(activeMembers: ended ? 0 : 1),
    members: ended ? const [] : [activeMember],
  );

  @override
  Future<BusinessAccess> loadAccess() async {
    if (ended && failFirstRefreshAfterEnd && !refreshFailed) {
      refreshFailed = true;
      throw StateError('refresh interrupted');
    }
    return access;
  }

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async => workspace;

  @override
  Future<BusinessMember> endBusinessMembership(
    EndBusinessMembershipInput input,
  ) async {
    endInputs.add(input);
    ended = true;
    return BusinessMember(
      id: _memberId,
      gymId: _gymId,
      userId: _userId,
      name: '테스트 회원',
      gymName: '테스트 센터',
      remainingPtSessions: 4,
      status: 'ended',
      endedAt: DateTime(2026, 8, 16),
    );
  }

  @override
  Future<List<BusinessMember>> listMyBusinessMemberships() async =>
      ended ? const [] : [activeMember];

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
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => const [];

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
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
