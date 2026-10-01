import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/consultation_chat_screen.dart';
import 'package:setflow/screens/coaching_workout_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/services/push_service.dart';
import 'package:setflow/theme.dart';

const _memberId = 'member-chat';
const _trainerId = 'trainer-chat';
const _consultationId = 'consultation-chat';

void main() {
  setUp(() => Auth.use(_ChatAuth()));
  tearDown(() {
    Auth.reset();
    Push.bind(const DisabledPushService());
  });

  testWidgets('member history opens chat and keeps survey withdrawal in info', (
    tester,
  ) async {
    final repository = _ChatRepository();
    final state = AppState(businessRepository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    await _pump(tester, state, const ConsultationHistoryScreen());
    await tester.tap(
      find.byKey(const ValueKey('consultation-history-item-$_consultationId')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ConsultationChatScreen), findsOneWidget);
    expect(find.text('예전 답변'), findsOneWidget);
    await tester.tap(find.byTooltip('상담 정보 보기'));
    await tester.pumpAndSettle();
    expect(find.text('상담 상세'), findsOneWidget);
    final revoke = find.byKey(const ValueKey('consultation-profile-revoke'));
    await tester.ensureVisible(revoke);
    await tester.tap(revoke);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('consultation-profile-revoke-confirm')),
    );
    await tester.pumpAndSettle();

    expect(repository.revokeCalls, 1);
    expect(find.textContaining('공유 철회됨'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member information hides the previous account after sign-out', (
    tester,
  ) async {
    final repository = _ChatRepository();
    final state = AppState(businessRepository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    await _pump(tester, state, const ConsultationHistoryScreen());
    await tester.tap(
      find.byKey(const ValueKey('consultation-history-item-$_consultationId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('상담 정보 보기'));
    await tester.pumpAndSettle();
    expect(find.text('나의 신청 내용'), findsOneWidget);

    Auth.reset();
    state.handleExternalAuthSignedOut();
    await tester.pumpAndSettle();

    expect(find.text('나의 신청 내용'), findsNothing);
    expect(
      find.byKey(const ValueKey('coaching-account-expired')),
      findsOneWidget,
    );
    expect(find.byType(CoachingAccountBoundary), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final role in [UserRole.trainer, UserRole.gym]) {
    testWidgets('$role inbox opens chat and keeps consultation information', (
      tester,
    ) async {
      final repository = _ChatRepository(role: role);
      final state = AppState(businessRepository: repository);
      addTearDown(state.dispose);
      await state.initialize();
      state.businessWorkspace = await repository.loadWorkspace(role);
      await _pump(tester, state, ConsultationQueuePage(role: role));
      await tester.tap(find.text('채팅 회원'));
      await tester.pumpAndSettle();

      expect(find.byType(ConsultationChatScreen), findsOneWidget);
      expect(
        tester
            .widget<ConsultationChatScreen>(find.byType(ConsultationChatScreen))
            .role,
        role,
      );
      await tester.tap(find.byTooltip('상담 정보 보기'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('trainer-shared-recommendation-profile')),
        findsOneWidget,
      );
      expect(find.text('답변 작성'), findsNothing);
      if (role == UserRole.gym) {
        await tester.tap(find.byKey(const Key('consultation-trainer-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('담당 코치').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('consultation-assign-trainer')));
        await tester.pumpAndSettle();
        expect(repository.assignCalls, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('member follow-up restores unanswered inbox and latest preview', (
    tester,
  ) async {
    final repository = _ChatRepository(role: UserRole.trainer)
      ..includeFollowUp = true;
    final state = AppState(businessRepository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    state.businessWorkspace = await repository.loadWorkspace(UserRole.trainer);
    await _pump(
      tester,
      state,
      const ConsultationQueuePage(role: UserRole.trainer),
    );

    expect(find.text('미답변 1'), findsOneWidget);
    expect(find.text('다음은요?'), findsOneWidget);
    expect(find.text('처음 질문'), findsNothing);
    await tester.tap(find.text('미답변 1'));
    await tester.pump();
    expect(find.text('채팅 회원'), findsOneWidget);
    expect(find.text('다음은요?'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('member active consultation previews the latest follow-up', (
    tester,
  ) async {
    final repository = _ChatRepository()..includeFollowUp = true;
    final state = AppState(businessRepository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    await _pump(tester, state, const CoachingScreen());
    final row = find.byKey(
      const ValueKey('coaching-active-consultation-$_consultationId'),
    );
    expect(
      find.descendant(of: row, matching: find.text('다음은요?')),
      findsOneWidget,
    );
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(ConsultationChatScreen), findsOneWidget);
  });

  for (final event in [
    'consultation_reply',
    'consultation_message',
    'consultation_assigned',
  ]) {
    testWidgets('$event opens uncached conversation by ID only once', (
      tester,
    ) async {
      final repository = _ChatRepository()..omitListCache = true;
      final notification = PushOpen(
        kind: 'coaching_feedback',
        data: {'event': event, 'consultationId': _consultationId},
      );
      final push = _ChatPush(notification);
      Push.bind(push);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await push.events.close();
      });
      await tester.pumpWidget(SetflowApp(businessRepository: repository));
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pumpAndSettle();

      final opened = find.byType(ConsultationChatScreen);
      expect(opened, findsOneWidget);
      expect(
        tester.widget<ConsultationChatScreen>(opened).consultationId,
        _consultationId,
      );
      expect(repository.loadCalls, 1);
      expect(find.text('처음 질문'), findsOneWidget);
      push.events.add(notification);
      await tester.pumpAndSettle();
      expect(
        find.byType(ConsultationChatScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pump(WidgetTester tester, AppState state, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(480, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(theme: SetflowTheme.light, home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

class _ChatRepository extends Fake
    implements
        BusinessRepository,
        ConsultationChatRepository,
        ConsultationRecommendationProfileShareRepository {
  _ChatRepository({this.role = UserRole.member});

  final UserRole role;
  bool includeFollowUp = false;
  bool omitListCache = false;
  bool revoked = false;
  int revokeCalls = 0;
  int assignCalls = 0;
  int loadCalls = 0;
  String? assignedTrainerId;

  BusinessConsultation get consultation => BusinessConsultation(
    id: _consultationId,
    userId: _memberId,
    trainerId: _trainerId,
    assignedTrainerId: assignedTrainerId,
    gymId: 'gym-chat',
    status: includeFollowUp && role == UserRole.member
        ? BusinessConsultationStatus.pending
        : BusinessConsultationStatus.replied,
    isRead: true,
    memberName: '채팅 회원',
    trainerName: '담당 코치',
    gymName: '채팅 센터',
    goal: '근력 향상',
    level: '초급',
    question: '처음 질문',
    createdAt: DateTime.utc(2026, 9, 25),
    sharedRecommendationProfile: RecommendationProfile(
      experienceLevel: TrainingExperienceLevel.beginner,
      availableEquipment: const {TrainingEquipment.bodyweight},
      painRegions: const {},
      painLevel: 0,
      restrictedMovements: const {},
      injuryNote: '',
      recoveryStatus: TrainingRecoveryStatus.normal,
      recoveryRecordedAt: DateTime.utc(2026, 9, 25),
      updatedAt: DateTime.utc(2026, 9, 25),
    ),
    recommendationProfileShareRevokedAt: revoked ? DateTime.now() : null,
    messages: [
      BusinessConsultationMessage(
        id: 'initial-answer',
        consultationId: _consultationId,
        sender: BusinessMessageSender.trainer,
        senderId: 'trainer-user',
        text: '예전 답변',
        createdAt: DateTime.utc(2026, 9, 26),
      ),
      if (includeFollowUp)
        BusinessConsultationMessage(
          id: 'follow-up',
          consultationId: _consultationId,
          sender: BusinessMessageSender.member,
          senderId: _memberId,
          text: '다음은요?',
          createdAt: DateTime.utc(2026, 9, 27),
        ),
    ],
  );

  BusinessAccess get access => BusinessAccess(
    userId: _memberId,
    accountRole: role,
    resolvedRole: role,
    availableRoles: {role},
  );

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole requestedRole) async =>
      BusinessWorkspaceData(
        role: requestedRole,
        access: access,
        profile: requestedRole == UserRole.gym
            ? const GymBusinessProfile(
                id: 'gym-chat',
                ownerUserId: _memberId,
                name: '채팅 센터',
                status: BusinessProfileStatus.verified,
              )
            : null,
        dashboardStats: const BusinessDashboardMetrics(),
        consultations: [consultation],
        trainers: const [
          GymTrainerRecord(
            id: 'gym-trainer-chat',
            gymId: 'gym-chat',
            trainerId: _trainerId,
            displayName: '담당 코치',
            status: 'active',
            memberCount: 1,
            averageRating: 5,
            monthlySales: 0,
          ),
        ],
      );

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async =>
      omitListCache ? [] : [consultation];

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
  Future<BusinessConsultation> loadConsultation(String id) async {
    loadCalls++;
    return consultation;
  }

  @override
  Stream<BusinessConsultation> watchConsultation(String id) =>
      const Stream.empty();

  @override
  Future<BusinessConsultation> sendConsultationMessage(
    SendConsultationMessageInput input,
  ) async => consultation;

  @override
  Future<void> revokeRecommendationProfileShare(String id) async {
    revokeCalls++;
    revoked = true;
  }

  @override
  Future<BusinessConsultation> assignConsultation(
    AssignConsultationInput input,
  ) async {
    assignCalls++;
    assignedTrainerId = input.trainerId;
    return consultation;
  }
}

class _ChatAuth extends Fake implements AuthService {
  @override
  AuthUser get currentUser =>
      const AuthUser(id: _memberId, displayName: '채팅 회원');

  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => '채팅 회원';

  @override
  Stream<AuthChange> get authChanges => const Stream.empty();

  @override
  Future<bool> isVerifiedAdmin() async => false;
}

class _ChatPush extends DisabledPushService {
  _ChatPush(this.notification);

  final PushOpen notification;
  final events = StreamController<PushOpen>.broadcast();

  @override
  Stream<PushOpen> get opens => events.stream;

  @override
  Future<PushOpen?> initialOpen() async => notification;
}
