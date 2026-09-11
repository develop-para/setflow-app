import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/screens/coaching_workout_history_screen.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';

const _memberUserId = '11111111-1111-4111-8111-111111111111';
const _trainerId = '22222222-2222-4222-8222-222222222222';
const _gymId = '33333333-3333-4333-8333-333333333333';
const _scheduleId = '44444444-4444-4444-8444-444444444444';

void main() {
  testWidgets(
    'class history opens sets, loads older pages and clears revoked data',
    (tester) async {
      final repository = _HealthConsentFake();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      await state.initialize();
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: CoachingWorkoutHistoryScreen(
              schedule: _HealthConsentFake.schedule,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2020.01.01'), findsOneWidget);
      await tester.tap(find.text('2020.01.01'));
      await tester.pumpAndSettle();
      expect(find.text('스쿼트'), findsOneWidget);
      expect(find.textContaining('100.0kg × 8회'), findsOneWidget);
      expect(find.textContaining('자세 메모'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('coaching-history-more')),
      );
      await tester.tap(find.byKey(const ValueKey('coaching-history-more')));
      await tester.pumpAndSettle();
      expect(repository.historyCursors.last?.sessionId, 'old-session');
      expect(find.text('2018.01.01'), findsOneWidget);
      expect(find.byKey(const ValueKey('coaching-history-more')), findsNothing);
      repository.historyRevoked = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('2020.01.01'), findsNothing);
      expect(find.text('2018.01.01'), findsNothing);
      expect(find.textContaining('공유 동의와 수업 상태'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  test('history rejects a response belonging to another member', () async {
    final repository = _HealthConsentFake()..wrongHistoryMember = true;
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();
    await expectLater(
      state.loadCoachingWorkoutHistory(_scheduleId),
      throwsStateError,
    );
  });

  test('health access is member-owned, class-scoped, and never snapshotted', () {
    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('coaching_health_data_consent.sql'))
        .toList(growable: false);
    expect(migrations, hasLength(1));
    final sql = migrations.single
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .toLowerCase();

    expect(sql, contains('create table public.coaching_health_consents'));
    expect(sql, contains('create table public.coaching_health_consent_events'));
    expect(sql, contains('create table public.coaching_health_access_logs'));
    expect(
      sql,
      contains(
        'alter table public.coaching_health_consents enable row level security',
      ),
    );
    expect(sql, contains('member_user_id = (select auth.uid())'));
    expect(sql, contains('schedule.completed_at is null'));
    expect(sql, contains('private.coaching_health_access_role'));
    expect(sql, contains('private.can_read_member_body_data'));
    expect(sql, contains('set share_body_data = false'));
    expect(sql, contains('access automatically ends'));
    expect(sql, isNot(contains('alter table public.coaching_session_records')));
    expect(
      sql,
      contains(
        'revoke all on table public.coaching_health_consents,\n  public.coaching_health_consent_events',
      ),
    );
  });

  test(
    'member independently approves trainer and gym for one schedule',
    () async {
      final repository = _HealthConsentFake();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final consent = await state.updateCoachingHealthConsent(
        scheduleId: _scheduleId,
        shareWithTrainer: true,
        shareWithGym: false,
      );

      expect(consent.shareWithTrainer, isTrue);
      expect(consent.shareWithGym, isFalse);
      expect(repository.lastShareWithTrainer, isTrue);
      expect(repository.lastShareWithGym, isFalse);
      expect(repository.lastRequestId, isNotNull);
      expect(
        state.coachingSchedules.single.healthConsent?.shareWithTrainer,
        isTrue,
      );

      final overview = await state.loadCoachingHealthOverview(_scheduleId);
      expect(overview.memberUserId, _memberUserId);
      expect(overview.accessEndsOnCompletion, isTrue);
      expect(repository.healthOverviewReads, 1);
    },
  );

  test('member and business screens expose the consent contract', () {
    final memberScreen = File(
      'lib/screens/member_screens.dart',
    ).readAsStringSync();
    final businessScreen = File(
      'lib/screens/business_detail_screens.dart',
    ).readAsStringSync();
    final settingsScreen = File(
      'lib/screens/detail_screens.dart',
    ).readAsStringSync();

    expect(memberScreen, contains("Key('health-consent-trainer')"));
    expect(memberScreen, contains("Key('health-consent-gym')"));
    expect(memberScreen, contains('수업 완료 또는 취소 즉시 접근이 자동 종료'));
    expect(businessScreen, contains("Key('coaching-health-view-"));
    expect(businessScreen, contains('열람 사실은 회원의 감사 기록에 남고'));
    expect(settingsScreen, contains('건강정보는 수업마다 직접 선택'));
    expect(settingsScreen, isNot(contains('담당 트레이너에게 체성분 공유')));
  });
}

class _HealthConsentFake
    implements
        BusinessRepository,
        CoachingHealthConsentRepository,
        CoachingWorkoutHistoryRepository {
  static const access = BusinessAccess(
    userId: _memberUserId,
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: {UserRole.member},
  );

  static final schedule = BusinessCoachingSchedule(
    id: _scheduleId,
    trainerId: _trainerId,
    memberUserId: _memberUserId,
    gymId: _gymId,
    title: '회원 동의 수업',
    date: DateTime(2026, 9, 1),
    startMinutes: 600,
    endMinutes: 660,
    trainerName: '동의 트레이너',
    gymName: '동의 헬스장',
    createdAt: DateTime(2026, 8, 30),
  );

  bool historyRevoked = false;
  bool wrongHistoryMember = false;
  final historyCursors = <CoachingWorkoutCursor?>[];

  @override
  Future<CoachingWorkoutHistoryPage> listCoachingWorkoutHistory(
    String scheduleId, {
    CoachingWorkoutCursor? before,
  }) async {
    historyCursors.add(before);
    if (historyRevoked) throw StateError('동의 철회');
    return CoachingWorkoutHistoryPage(
      scheduleId: scheduleId,
      memberUserId: wrongHistoryMember ? 'other-member' : _memberUserId,
      nextCursor: before == null
          ? CoachingWorkoutCursor(
              date: DateTime(2020),
              sessionId: 'old-session',
            )
          : null,
      sessions: [
        BusinessWorkoutSession(
          id: before == null ? 'old-session' : 'older-session',
          userId: _memberUserId,
          date: DateTime(before == null ? 2020 : 2018),
          feedbacks: const [],
          exercises: const [
            BusinessWorkoutExercise(
              id: 'exercise',
              name: '스쿼트',
              orderIndex: 0,
              sets: [
                BusinessWorkoutSet(
                  id: 'set',
                  setNumber: 1,
                  type: 'normal',
                  weight: 100,
                  reps: 8,
                  completed: true,
                  restSeconds: 90,
                  memo: '자세 메모',
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  bool? lastShareWithTrainer;
  bool? lastShareWithGym;
  String? lastRequestId;
  int healthOverviewReads = 0;

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async =>
      const BusinessWorkspaceData(
        role: UserRole.member,
        access: access,
        dashboardStats: BusinessDashboardMetrics(),
        memberSharingPreferences: MemberSharingPreferences(
          shareBodyData: false,
          shareWorkoutRecords: false,
          marketing: false,
        ),
      );

  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => [schedule];

  @override
  Future<CoachingHealthConsent> setCoachingHealthConsent({
    required String scheduleId,
    required bool shareWithTrainer,
    required bool shareWithGym,
    required String requestId,
  }) async {
    lastShareWithTrainer = shareWithTrainer;
    lastShareWithGym = shareWithGym;
    lastRequestId = requestId;
    final now = DateTime(2026, 8, 30, 12);
    return CoachingHealthConsent(
      scheduleId: scheduleId,
      memberUserId: _memberUserId,
      trainerId: _trainerId,
      gymId: _gymId,
      shareWithTrainer: shareWithTrainer,
      shareWithGym: shareWithGym,
      trainerConsentedAt: shareWithTrainer ? now : null,
      gymConsentedAt: shareWithGym ? now : null,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<CoachingHealthOverview> getCoachingHealthOverview(
    String scheduleId,
  ) async {
    healthOverviewReads++;
    return CoachingHealthOverview(
      scheduleId: scheduleId,
      memberUserId: _memberUserId,
      trainerId: _trainerId,
      gymId: _gymId,
      accessRole: 'member',
      memberName: '회원',
      accessEndsOnCompletion: true,
      bodyCompositions: const [],
      readAt: DateTime(2026, 8, 30, 12),
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
