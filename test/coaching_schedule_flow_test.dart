import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_detail_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _memberUserId = '22222222-2222-4222-8222-222222222222';
const _trainerId = '33333333-3333-4333-8333-333333333333';
const _gymId = '44444444-4444-4444-8444-444444444444';
const _memberId = '55555555-5555-4555-8555-555555555555';
const _scheduleId = '66666666-6666-4666-8666-666666666666';

void main() {
  test(
    'atomic schedule migration locks overlaps and removes direct create',
    () {
      final sql = File(
        'supabase/migrations/'
        '20260816125326_coaching_schedule_atomic_create.sql',
      ).readAsStringSync();

      expect(sql, contains('coaching_schedules_trainer_request_uidx'));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(sql, contains('coaching_schedule:trainer:'));
      expect(sql, contains('coaching_schedule:member:'));
      expect(sql, contains('COACHING_SCHEDULE_TRAINER_OVERLAP'));
      expect(sql, contains('COACHING_SCHEDULE_MEMBER_OVERLAP'));
      expect(sql, contains("c.status = 'active'"));
      expect(sql, contains("g.status = 'verified'"));
      expect(sql, contains("m.status = 'active'"));
      expect(sql, contains('ma.active'));
      expect(sql, contains('revoke insert on table public.coaching_schedules'));
      expect(
        sql,
        contains('drop policy if exists coaching_schedules_trainer_insert'),
      );
    },
  );

  test(
    'schedule mutations use exact relationship UUIDs and dedupe create',
    () async {
      final createCompleter = Completer<BusinessCoachingSchedule>();
      final repository = _ScheduleRepository.trainer(
        schedules: [_schedule()],
        createCompleter: createCompleter,
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final first = state.createCoachingSchedule(
        title: '상체 PT',
        date: DateTime(2026, 8, 20),
        startMinutes: 600,
        endMinutes: 660,
        memberId: _memberId,
      );
      final second = state.createCoachingSchedule(
        title: '중복 탭',
        date: DateTime(2026, 8, 21),
        startMinutes: 700,
        endMinutes: 760,
        memberId: _memberId,
      );

      expect(identical(first, second), isTrue);
      expect(repository.createInputs, hasLength(1));
      final input = repository.createInputs.single;
      expect(input.trainerId, _trainerId);
      expect(input.memberUserId, _memberUserId);
      expect(input.gymId, _gymId);
      expect(
        input.requestId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
            r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );

      createCompleter.complete(
        BusinessCoachingSchedule(
          id: '77777777-7777-4777-8777-777777777777',
          trainerId: _trainerId,
          memberUserId: _memberUserId,
          gymId: _gymId,
          title: input.title,
          date: input.date,
          startMinutes: input.startMinutes,
          endMinutes: input.endMinutes,
          createdAt: DateTime(2026, 8, 16),
        ),
      );
      final created = await first;
      expect(created.memberName, '실회원');

      await state.setCoachingScheduleCompleted(_scheduleId, completed: true);
      expect(repository.completedIds, [_scheduleId]);
      expect(repository.completedTrainerIds, [_trainerId]);

      await state.deleteCoachingSchedule(_scheduleId);
      expect(repository.deletedIds, [_scheduleId]);
      expect(repository.deletedTrainerIds, [_trainerId]);
    },
  );

  test('failed create retry keeps its request ID until success', () async {
    final repository = _ScheduleRepository.trainer(
      schedules: const [],
      createFailuresRemaining: 1,
    );
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();

    Future<BusinessCoachingSchedule> create() => state.createCoachingSchedule(
      title: '재시도 PT',
      date: DateTime(2026, 8, 20),
      startMinutes: 600,
      endMinutes: 660,
      memberId: _memberId,
    );

    await expectLater(create(), throwsA(isA<StateError>()));
    final created = await create();

    expect(created.trainerId, _trainerId);
    expect(repository.createInputs, hasLength(2));
    expect(
      repository.createInputs[1].requestId,
      repository.createInputs[0].requestId,
    );
  });

  testWidgets('trainer overlap shows a specific recovery message', (
    tester,
  ) async {
    final repository = _ScheduleRepository.trainer(
      schedules: const [],
      createError: const CoachingScheduleConflictException(
        CoachingScheduleConflictTarget.trainer,
      ),
    );
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const BusinessToolScreen(
            tool: BusinessTool.calendar,
            role: UserRole.trainer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('coaching-schedule-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('coaching-schedule-title')),
      '겹침 PT',
    );
    await tester.tap(find.byKey(const Key('coaching-schedule-save')));
    await tester.pumpAndSettle();

    expect(find.text('선택한 시간에 트레이너의 다른 일정이 있습니다.'), findsOneWidget);
  });

  testWidgets(
    'live trainer calendar renders server rows and enriched member name',
    (tester) async {
      final repository = _ScheduleRepository.trainer(schedules: [_schedule()]);
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: const BusinessToolScreen(
              tool: BusinessTool.calendar,
              role: UserRole.trainer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('실제 PT 일정'), findsOneWidget);
      expect(find.textContaining('실회원'), findsOneWidget);
      expect(find.byKey(const Key('coaching-schedule-create')), findsOneWidget);
      expect(
        find.byKey(const Key('coaching-schedule-complete-$_scheduleId')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'member calendar shows only the signed-in member schedule read-only',
    (tester) async {
      final repository = _ScheduleRepository.member(
        schedules: [
          _schedule(memberUserId: _userId, trainerName: '실트레이너'),
          _schedule(
            id: '88888888-8888-4888-8888-888888888888',
            memberUserId: _memberUserId,
            trainerName: '다른 트레이너',
          ),
        ],
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            // 코칭 일정 섹션은 캘린더와 함께 살다가 홈으로 옮겨 갔다.
            home: Scaffold(
              body: HomeScreen(onOpenRecord: () {}, onOpenCommunity: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('member-coaching-schedules')),
        findsOneWidget,
      );
      expect(find.text('실트레이너'), findsOneWidget);
      expect(find.text('다른 트레이너'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}

BusinessCoachingSchedule _schedule({
  String id = _scheduleId,
  String memberUserId = _memberUserId,
  String? trainerName,
}) => BusinessCoachingSchedule(
  id: id,
  trainerId: _trainerId,
  memberUserId: memberUserId,
  gymId: _gymId,
  title: '실제 PT 일정',
  date: DateTime.now().add(const Duration(days: 1)),
  startMinutes: 600,
  endMinutes: 660,
  trainerName: trainerName,
  createdAt: DateTime(2026, 8, 16),
);

class _ScheduleRepository implements BusinessRepository {
  _ScheduleRepository._({
    required this.access,
    required this.workspace,
    required List<BusinessCoachingSchedule> schedules,
    this.createCompleter,
    this.createFailuresRemaining = 0,
    this.createError,
  }) : schedules = List.of(schedules);

  factory _ScheduleRepository.trainer({
    required List<BusinessCoachingSchedule> schedules,
    Completer<BusinessCoachingSchedule>? createCompleter,
    int createFailuresRemaining = 0,
    Object? createError,
  }) {
    const trainer = TrainerBusinessProfile(
      id: _trainerId,
      userId: _userId,
      displayName: '실트레이너',
      status: BusinessProfileStatus.approved,
      isPublic: true,
      verified: true,
      rating: 5,
      postCount: 0,
      coachingTotal: 0,
    );
    const access = BusinessAccess(
      userId: _userId,
      accountRole: UserRole.trainer,
      resolvedRole: UserRole.trainer,
      availableRoles: {UserRole.member, UserRole.trainer},
      trainer: trainer,
    );
    return _ScheduleRepository._(
      access: access,
      workspace: const BusinessWorkspaceData(
        role: UserRole.trainer,
        access: access,
        profile: trainer,
        dashboardStats: BusinessDashboardMetrics(),
        members: [
          BusinessMember(
            id: _memberId,
            gymId: _gymId,
            userId: _memberUserId,
            name: '실회원',
            remainingPtSessions: 8,
          ),
        ],
        assignments: [
          BusinessMemberAssignment(
            id: '99999999-9999-4999-8999-999999999999',
            gymId: _gymId,
            memberId: _memberId,
            trainerId: _trainerId,
            active: true,
          ),
        ],
      ),
      schedules: schedules,
      createCompleter: createCompleter,
      createFailuresRemaining: createFailuresRemaining,
      createError: createError,
    );
  }

  factory _ScheduleRepository.member({
    required List<BusinessCoachingSchedule> schedules,
  }) {
    const access = BusinessAccess(
      userId: _userId,
      accountRole: UserRole.member,
      resolvedRole: UserRole.member,
      availableRoles: {UserRole.member},
    );
    return _ScheduleRepository._(
      access: access,
      workspace: const BusinessWorkspaceData(
        role: UserRole.member,
        access: access,
        dashboardStats: BusinessDashboardMetrics(),
      ),
      schedules: schedules,
    );
  }

  final BusinessAccess access;
  final BusinessWorkspaceData workspace;
  List<BusinessCoachingSchedule> schedules;
  final Completer<BusinessCoachingSchedule>? createCompleter;
  int createFailuresRemaining;
  final Object? createError;
  final List<CreateCoachingScheduleInput> createInputs = [];
  final List<String> completedIds = [];
  final List<String> completedTrainerIds = [];
  final List<String> deletedIds = [];
  final List<String> deletedTrainerIds = [];

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async => workspace;

  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => schedules;

  @override
  Future<BusinessCoachingSchedule> createCoachingSchedule(
    CreateCoachingScheduleInput input,
  ) {
    createInputs.add(input);
    if (createFailuresRemaining > 0) {
      createFailuresRemaining--;
      return Future.error(StateError('response lost'));
    }
    if (createError case final error?) return Future.error(error);
    return createCompleter?.future ?? Future.value(_schedule());
  }

  @override
  Future<BusinessCoachingSchedule> setCoachingScheduleCompleted(
    String scheduleId, {
    required String trainerId,
    required bool completed,
  }) async {
    completedIds.add(scheduleId);
    completedTrainerIds.add(trainerId);
    final current = schedules.firstWhere((item) => item.id == scheduleId);
    final updated = BusinessCoachingSchedule(
      id: current.id,
      trainerId: current.trainerId,
      memberUserId: current.memberUserId,
      gymId: current.gymId,
      title: current.title,
      date: current.date,
      startMinutes: current.startMinutes,
      endMinutes: current.endMinutes,
      trainerName: current.trainerName,
      memberName: current.memberName,
      createdAt: current.createdAt,
      completedAt: completed ? DateTime.now() : null,
    );
    schedules = [
      for (final item in schedules)
        if (item.id == scheduleId) updated else item,
    ];
    return updated;
  }

  @override
  Future<void> deleteCoachingSchedule(
    String scheduleId, {
    required String trainerId,
  }) async {
    deletedIds.add(scheduleId);
    deletedTrainerIds.add(trainerId);
    schedules.removeWhere((item) => item.id == scheduleId);
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
