import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _memberUserId = '22222222-2222-4222-8222-222222222222';
const _trainerId = '33333333-3333-4333-8333-333333333333';
const _gymId = '44444444-4444-4444-8444-444444444444';
const _connectionId = '55555555-5555-4555-8555-555555555555';
const _scheduleId = '66666666-6666-4666-8666-666666666666';
const _recordId = '77777777-7777-4777-8777-777777777777';
const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  test('migration separates mobile coaching, class place, and gym snapshot', () {
    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('mobile_coaching_sessions.sql'))
        .toList();
    expect(migrations, hasLength(1));
    final sql = migrations.single.readAsStringSync().toLowerCase();

    expect(sql, contains('coachings_one_active_pair_uidx'));
    expect(sql, contains('coaching_connection_invites'));
    expect(sql, contains('coaching_session_records'));
    expect(sql, contains('extensions.digest(v_raw_token'));
    expect(
      sql,
      contains(
        'alter table public.coaching_session_records enable row level security',
      ),
    );
    expect(sql, contains('coaching_session_records_scoped_read'));
    expect(sql, contains('public.owns_gym(gym_id)'));
    expect(sql, contains('public.owns_trainer(trainer_id)'));
    expect(sql, contains("g.id = p_gym_id and g.status = 'verified'"));
    expect(sql, contains("c.status = 'active'"));
    expect(sql, contains('member_goal_snapshot'));
    expect(sql, contains('routine_title_snapshot'));
    expect(sql, contains('consultation_summary'));
    expect(
      sql,
      contains('revoke all on table public.coaching_session_records'),
    );
    expect(
      sql,
      contains(') on public.coaching_session_records to authenticated'),
    );
    expect(
      sql,
      isNot(
        contains(
          'grant insert on table public.coaching_session_records to authenticated',
        ),
      ),
    );
  });

  test(
    'direct connection schedules a member at the selected verified gym',
    () async {
      final repository = _MobileCoachingFake();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final schedule = await state.createCoachingSchedule(
        title: '이동 PT',
        date: DateTime(2026, 8, 31),
        startMinutes: 600,
        endMinutes: 660,
        connectionId: _connectionId,
        gymId: _gymId,
      );

      expect(schedule.memberName, '연결 회원');
      expect(repository.lastScheduleInput?.memberUserId, _memberUserId);
      expect(repository.lastScheduleInput?.gymId, _gymId);
    },
  );

  test(
    'member consent link and immutable class share use stable domain verbs',
    () async {
      final androidManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(androidManifest, contains('android:host="coaching-invite"'));

      final repository = _MobileCoachingFake();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final invite = await state.createCoachingConnectionInvite(
        recipientName: '연결 회원',
      );
      expect(invite.uri?.host, 'coaching-invite');

      state.captureIncomingUri(
        Uri.parse('com.teampara.setflow://coaching-invite/$_token'),
      );
      expect(state.pendingCoachingInviteToken, _token);
      final acceptance = await state.acceptCoachingConnectionInviteToken();
      expect(acceptance.accepted, isTrue);
      expect(state.pendingCoachingInviteToken, isNull);

      final record = await state.publishCoachingSessionRecord(
        scheduleId: _scheduleId,
        sessionSummary: '하체 가동성과 스쿼트 자세를 점검했습니다.',
        routineSummary: '스쿼트 3세트와 런지 3세트를 진행했습니다.',
        consultationSummary: '다음 수업 전까지 통증 변화를 기록하기로 했습니다.',
      );
      expect(record.gymId, _gymId);
      expect(repository.lastPublishInput?.scheduleId, _scheduleId);
      expect(repository.lastPublishInput?.sessionSummary, contains('스쿼트'));
    },
  );
}

class _MobileCoachingFake
    implements BusinessRepository, MobileCoachingRepository {
  static const trainer = TrainerBusinessProfile(
    id: _trainerId,
    userId: _userId,
    displayName: '이동 트레이너',
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: 5,
    postCount: 0,
    coachingTotal: 0,
  );
  static const access = BusinessAccess(
    userId: _userId,
    accountRole: UserRole.trainer,
    resolvedRole: UserRole.trainer,
    availableRoles: {UserRole.member, UserRole.trainer},
    trainer: trainer,
  );
  static final connection = CoachingConnection(
    id: _connectionId,
    trainerId: _trainerId,
    memberUserId: _memberUserId,
    memberName: '연결 회원',
    trainerName: '이동 트레이너',
    memberGoal: '근력 향상',
    status: 'active',
    createdAt: DateTime(2026, 8, 30),
  );

  CreateCoachingScheduleInput? lastScheduleInput;
  PublishCoachingSessionRecordInput? lastPublishInput;

  BusinessWorkspaceData get workspace => BusinessWorkspaceData(
    role: UserRole.trainer,
    access: access,
    profile: trainer,
    dashboardStats: const BusinessDashboardMetrics(),
    coachingConnections: [connection],
  );

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async => workspace;

  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => const [];

  @override
  Future<BusinessCoachingSchedule> createCoachingSchedule(
    CreateCoachingScheduleInput input,
  ) async {
    lastScheduleInput = input;
    return BusinessCoachingSchedule(
      id: _scheduleId,
      trainerId: input.trainerId,
      memberUserId: input.memberUserId,
      gymId: input.gymId,
      title: input.title,
      date: input.date,
      startMinutes: input.startMinutes,
      endMinutes: input.endMinutes,
      createdAt: DateTime(2026, 8, 30),
    );
  }

  @override
  Future<List<CoachingConnection>> listCoachingConnections() async => [
    connection,
  ];

  @override
  Future<CoachingConnectionInviteCreation> createCoachingConnectionInvite({
    required String requestId,
    required DateTime expiresAt,
    String? recipientName,
  }) async => CoachingConnectionInviteCreation(
    tokenIssued: true,
    token: _token,
    uri: Uri.parse('com.teampara.setflow://coaching-invite/$_token'),
  );

  @override
  Future<CoachingConnectionAcceptance> acceptCoachingConnectionInvite(
    String token, {
    required String requestId,
  }) async =>
      CoachingConnectionAcceptance(accepted: true, connection: connection);

  @override
  Future<CoachingSessionRecord> publishCoachingSessionRecord(
    PublishCoachingSessionRecordInput input,
  ) async {
    lastPublishInput = input;
    return CoachingSessionRecord(
      id: _recordId,
      coachingId: _connectionId,
      scheduleId: input.scheduleId,
      trainerId: _trainerId,
      memberUserId: _memberUserId,
      gymId: _gymId,
      title: '이동 PT',
      sessionDate: DateTime(2026, 8, 31),
      memberName: '연결 회원',
      trainerName: '이동 트레이너',
      gymName: '테스트짐',
      sessionSummary: input.sessionSummary,
      sharedAt: DateTime(2026, 8, 31),
    );
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
