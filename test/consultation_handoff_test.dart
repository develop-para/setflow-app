import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _gymId = '22222222-2222-4222-8222-222222222222';
const _trainerId = '33333333-3333-4333-8333-333333333333';
const _consultationId = '44444444-4444-4444-8444-444444444444';

void main() {
  test('handoff migration enforces owner, trainer, idempotency and RLS', () {
    final sql = File(
      'supabase/migrations/'
      '20260816130351_consultation_trainer_handoff.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/data/supabase_business_repository.dart',
    ).readAsStringSync();

    expect(sql, contains('consultation_assignment_requests'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains("g.status = 'verified'"));
    expect(sql, contains('g.owner_user_id = v_user_id'));
    expect(sql, contains("t.status = 'approved'"));
    expect(sql, contains("gt.status = 'active'"));
    expect(sql, contains('can_access_business_consultation'));
    expect(sql, contains('if not (v_is_trainer or v_is_gym)'));
    expect(sql, contains("'status', v_status"));
    expect(
      sql,
      contains('revoke update, delete on table public.consultations'),
    );
    expect(repository, contains("'assign_business_consultation'"));
    expect(repository, contains('assigned_trainer_id.eq.'));
  });

  test(
    'consultation create and reply migration rejects duplicate payloads',
    () {
      final sql = File(
        'supabase/migrations/'
        '20260816131113_consultation_request_idempotency.sql',
      ).readAsStringSync();

      expect(sql, contains('consultations_user_request_uidx'));
      expect(sql, contains('consultation_messages_sender_request_uidx'));
      expect(sql, contains('create_business_consultation'));
      expect(sql, contains('consultation_create:'));
      expect(sql, contains('consultation_reply:'));
      expect(sql, contains('cannot be reused with different data'));
      expect(sql, contains("cr.status = 'approved'"));
      expect(
        sql,
        contains('drop policy if exists consultations_requester_insert'),
      );
      expect(
        sql,
        contains('select private.reply_business_consultation(null, \$1, \$2)'),
      );
    },
  );

  test('failed consultation create keeps its request UUID', () async {
    final repository = _HandoffRepository(createFailuresRemaining: 1);
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();

    Future<void> create() => state.addConsultation(
      gymId: _gymId,
      trainerName: '실센터',
      specialty: '근력',
      goal: '근력 향상',
      level: '초급',
      question: '안전한 운동 구성을 알려주세요.',
    );
    await expectLater(create(), throwsA(isA<StateError>()));
    await create();

    expect(repository.createInputs, hasLength(2));
    expect(
      repository.createInputs[1].requestId,
      repository.createInputs[0].requestId,
    );
  });

  test('failed consultation reply keeps its request UUID', () async {
    final repository = _HandoffRepository(replyFailuresRemaining: 1);
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();

    Future<void> reply() => state.answerBusinessConsultationById(
      role: UserRole.gym,
      consultationId: _consultationId,
      answer: '허리 부담을 낮춘 단계별 구성을 안내합니다.',
    );
    await expectLater(reply(), throwsA(isA<StateError>()));
    await reply();

    expect(repository.replyInputs, hasLength(2));
    expect(
      repository.replyInputs[1].requestId,
      repository.replyInputs[0].requestId,
    );
  });

  test('failed handoff retry keeps one request UUID until success', () async {
    final repository = _HandoffRepository(failuresRemaining: 1);
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();

    Future<BusinessConsultation> assign() => state.assignBusinessConsultation(
      consultationId: _consultationId,
      trainerId: _trainerId,
    );
    await expectLater(assign(), throwsA(isA<StateError>()));
    final assigned = await assign();

    expect(assigned.assignedTrainerId, _trainerId);
    expect(repository.inputs, hasLength(2));
    expect(repository.inputs[1].requestId, repository.inputs[0].requestId);
    expect(repository.inputs.last.consultationId, _consultationId);
    expect(repository.inputs.last.gymId, _gymId);
    expect(repository.inputs.last.trainerId, _trainerId);
  });

  testWidgets('gym consultation sheet selects and assigns an active trainer', (
    tester,
  ) async {
    final repository = _HandoffRepository();
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
          home: const ConsultationQueuePage(role: UserRole.gym),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('회원 A'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('consultation-trainer-select')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('consultation-trainer-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('실트레이너').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('consultation-assign-trainer')));
    await tester.pumpAndSettle();

    expect(repository.inputs, hasLength(1));
    expect(find.text('담당 트레이너에게 상담을 배정했어요.'), findsOneWidget);
  });
}

class _HandoffRepository implements BusinessRepository {
  _HandoffRepository({
    this.failuresRemaining = 0,
    this.createFailuresRemaining = 0,
    this.replyFailuresRemaining = 0,
  });

  int failuresRemaining;
  int createFailuresRemaining;
  int replyFailuresRemaining;
  final List<AssignConsultationInput> inputs = [];
  final List<CreateConsultationInput> createInputs = [];
  final List<ReplyConsultationInput> replyInputs = [];
  BusinessConsultation consultation = const BusinessConsultation(
    id: _consultationId,
    userId: '55555555-5555-4555-8555-555555555555',
    gymId: _gymId,
    status: BusinessConsultationStatus.pending,
    isRead: false,
    memberName: '회원 A',
    question: '허리 부담 없이 하체 운동을 하고 싶어요.',
    messages: [],
  );

  static const gym = GymBusinessProfile(
    id: _gymId,
    ownerUserId: _userId,
    name: '실센터',
    status: BusinessProfileStatus.verified,
  );
  static const access = BusinessAccess(
    userId: _userId,
    accountRole: UserRole.gym,
    resolvedRole: UserRole.gym,
    availableRoles: {UserRole.member, UserRole.gym},
    gym: gym,
  );

  BusinessWorkspaceData get workspace => BusinessWorkspaceData(
    role: UserRole.gym,
    access: access,
    profile: gym,
    dashboardStats: const BusinessDashboardMetrics(),
    trainers: const [
      GymTrainerRecord(
        id: '66666666-6666-4666-8666-666666666666',
        gymId: _gymId,
        trainerId: _trainerId,
        trainerUserId: '77777777-7777-4777-8777-777777777777',
        displayName: '실트레이너',
        status: 'active',
        memberCount: 3,
        averageRating: 5,
        monthlySales: 0,
      ),
    ],
    consultations: [consultation],
  );

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async => workspace;

  @override
  Future<BusinessConsultation> assignConsultation(
    AssignConsultationInput input,
  ) async {
    inputs.add(input);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('response lost');
    }
    consultation = BusinessConsultation(
      id: consultation.id,
      userId: consultation.userId,
      gymId: consultation.gymId,
      assignedTrainerId: input.trainerId,
      status: BusinessConsultationStatus.assigned,
      isRead: true,
      memberName: consultation.memberName,
      question: consultation.question,
      messages: consultation.messages,
    );
    return consultation;
  }

  @override
  Future<BusinessConsultation> createConsultation(
    CreateConsultationInput input,
  ) async {
    createInputs.add(input);
    if (createFailuresRemaining > 0) {
      createFailuresRemaining--;
      throw StateError('response lost');
    }
    consultation = BusinessConsultation(
      id: _consultationId,
      userId: consultation.userId,
      trainerId: input.trainerId,
      gymId: input.gymId,
      routineId: input.routineId,
      status: BusinessConsultationStatus.pending,
      isRead: false,
      specialty: input.specialty,
      goal: input.goal,
      level: input.level,
      question: input.question,
      messages: const [],
    );
    return consultation;
  }

  @override
  Future<BusinessConsultation> replyConsultation(
    ReplyConsultationInput input,
  ) async {
    replyInputs.add(input);
    if (replyFailuresRemaining > 0) {
      replyFailuresRemaining--;
      throw StateError('response lost');
    }
    consultation = BusinessConsultation(
      id: consultation.id,
      userId: consultation.userId,
      trainerId: consultation.trainerId,
      gymId: consultation.gymId,
      routineId: consultation.routineId,
      assignedTrainerId: consultation.assignedTrainerId,
      status: BusinessConsultationStatus.replied,
      isRead: true,
      memberName: consultation.memberName,
      question: consultation.question,
      messages: [
        ...consultation.messages,
        BusinessConsultationMessage(
          id: '88888888-8888-4888-8888-888888888888',
          consultationId: consultation.id,
          sender: BusinessMessageSender.gym,
          senderId: _userId,
          text: input.message,
        ),
      ],
    );
    return consultation;
  }

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => [
    consultation,
  ];

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
