import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _trainerId = '22222222-2222-4222-8222-222222222222';
const _consultationId = '33333333-3333-4333-8333-333333333333';

void main() {
  test(
    'trainer dashboard migration keeps an invoker-only least-privilege view',
    () {
      final migrations = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where(
            (file) => file.path.endsWith(
              '_fix_trainer_consultation_inbox_dashboard.sql',
            ),
          )
          .toList(growable: false);

      expect(
        migrations,
        hasLength(1),
        reason:
            'The consultation inbox repair must have one tracked migration.',
      );
      final sql = migrations.single.readAsStringSync().toLowerCase();
      final normalized = sql.replaceAll(RegExp(r'\s+'), ' ');
      final viewMatch = RegExp(
        r'create\s+view\s+public\.v_trainer_dashboard\b.*?'
        r'as\s+select\s+(.*?)\s+from\s+public\.trainers\s+t\s*;',
        dotAll: true,
      ).firstMatch(sql);

      expect(
        viewMatch,
        isNotNull,
        reason: 'The dashboard view must be rebuilt.',
      );
      expect(
        normalized,
        matches(
          RegExp(
            r'create view public\.v_trainer_dashboard\s+'
            r'with\s*\(\s*security_invoker\s*=\s*true\s*\)',
          ),
        ),
      );

      final viewProjection = viewMatch!.group(1)!;
      expect(viewProjection, isNot(contains('t.user_id')));
      expect(viewProjection, isNot(contains('t.status')));

      final revokeRoles = RegExp(
        r'revoke\s+all\s+on\s+(?:table\s+)?'
        r'public\.v_trainer_dashboard\s+from\s+([^;]+);',
      ).allMatches(normalized).map((match) => match.group(1)!).join(',');
      expect(revokeRoles, contains('public'));
      expect(revokeRoles, contains('anon'));
      expect(revokeRoles, contains('authenticated'));

      final selectGrantRoles = RegExp(
        r'grant\s+select\s+on\s+(?:table\s+)?'
        r'public\.v_trainer_dashboard\s+to\s+([^;]+);',
      ).allMatches(normalized).map((match) => match.group(1)!).join(',');
      expect(selectGrantRoles, contains('authenticated'));
      expect(selectGrantRoles, contains('service_role'));
      expect(selectGrantRoles, isNot(contains('anon')));
    },
  );

  testWidgets(
    'pending direct consultation is rendered in the live trainer inbox',
    (tester) async {
      final repository = _InboxRepository();
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
            home: const ConsultationQueuePage(role: UserRole.trainer),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('business-consultations-empty')),
        findsNothing,
      );
      expect(find.text('상담 요청 회원'), findsOneWidget);
      expect(find.text('근력 향상'), findsOneWidget);
      expect(find.text('스쿼트 중량을 어떻게 올리면 좋을까요?'), findsOneWidget);
      expect(find.text('정밀 추천 정보 공유됨'), findsOneWidget);
      expect(find.text('미답변 1'), findsOneWidget);
      await tester.tap(find.text('상담 요청 회원'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('trainer-shared-recommendation-profile')),
        findsOneWidget,
      );
      expect(find.text('오른쪽 어깨 불편'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}

class _InboxRepository extends Fake implements BusinessRepository {
  static const profile = TrainerBusinessProfile(
    id: _trainerId,
    userId: _userId,
    displayName: '수신 담당 트레이너',
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: 4.9,
    postCount: 3,
    coachingTotal: 9,
  );

  static const access = BusinessAccess(
    userId: _userId,
    accountRole: UserRole.trainer,
    resolvedRole: UserRole.trainer,
    availableRoles: {UserRole.trainer},
    trainer: profile,
  );

  static final pendingConsultation = BusinessConsultation(
    id: _consultationId,
    userId: '44444444-4444-4444-8444-444444444444',
    trainerId: _trainerId,
    status: BusinessConsultationStatus.pending,
    isRead: false,
    memberName: '상담 요청 회원',
    goal: '근력 향상',
    level: '초급',
    question: '스쿼트 중량을 어떻게 올리면 좋을까요?',
    sharedRecommendationProfile: _recommendationProfile(),
    messages: [],
  );

  static final workspace = BusinessWorkspaceData(
    role: UserRole.trainer,
    access: access,
    profile: profile,
    dashboardStats: BusinessDashboardMetrics(unreadConsultations: 1),
    consultations: [pendingConsultation],
  );

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async => workspace;

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => [
    pendingConsultation,
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
}

RecommendationProfile _recommendationProfile() {
  final recordedAt = DateTime.utc(2026, 8, 21);
  return RecommendationProfile(
    experienceLevel: TrainingExperienceLevel.intermediate,
    availableEquipment: const {TrainingEquipment.dumbbells},
    painRegions: const {TrainingPainRegion.shoulder},
    painLevel: 3,
    restrictedMovements: const {TrainingMovementRestriction.overheadPress},
    injuryNote: '오른쪽 어깨 불편',
    recoveryStatus: TrainingRecoveryStatus.normal,
    recoveryRecordedAt: recordedAt,
    updatedAt: recordedAt,
  );
}
