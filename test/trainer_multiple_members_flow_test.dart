import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';

const _trainerUser = 'trainer-user';
const _trainer = TrainerBusinessProfile(
  id: 'trainer',
  userId: _trainerUser,
  displayName: '담당 트레이너',
  status: BusinessProfileStatus.approved,
  isPublic: true,
  verified: true,
  rating: 5,
  postCount: 0,
  coachingTotal: 0,
);
const _access = BusinessAccess(
  userId: _trainerUser,
  accountRole: UserRole.trainer,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
  trainer: _trainer,
);
const _members = {'thread-a': '민지', 'thread-b': '준호'};

void main() {
  setUp(() => Auth.use(_Auth()));
  tearDown(Auth.reset);

  testWidgets(
    'trainer creates separate invites for several members in one sheet',
    (tester) async {
      final repository = _Repository();
      await _mount(
        tester,
        repository,
        const PeoplePage(role: UserRole.trainer),
        size: const Size(320, 900),
        textScale: 2,
        keyboardInset: 300,
      );
      await tester.tap(find.byTooltip('개인 코칭 회원 초대'));
      await tester.pumpAndSettle();
      expect(find.textContaining('회원마다 새 링크'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('coaching-invite-name')),
        '민지',
      );
      await tester.ensureVisible(
        find.byKey(const Key('coaching-invite-create')),
      );
      await tester.tap(find.byKey(const Key('coaching-invite-create')));
      await tester.pumpAndSettle();
      final firstLink = repository.inviteUris.single;
      expect(find.text(firstLink.toString()), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('coaching-invite-next-member')),
      );
      await tester.tap(find.byKey(const Key('coaching-invite-next-member')));
      await tester.pumpAndSettle();
      expect(find.text(firstLink.toString()), findsNothing);
      final secondName = find.descendant(
        of: find.byKey(const Key('coaching-invite-name')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(secondName).controller!.text, isEmpty);
      // An unnamed second invite must still be a new request and a new link.
      await tester.ensureVisible(
        find.byKey(const Key('coaching-invite-create')),
      );
      await tester.tap(find.byKey(const Key('coaching-invite-create')));
      await tester.pumpAndSettle();
      expect(repository.inviteUris, hasLength(2));
      expect(repository.inviteUris.last, isNot(firstLink));
      expect(repository.inviteRequestIds.toSet(), hasLength(2));
      expect(find.text(repository.inviteUris.last.toString()), findsOneWidget);
      final secondLink = repository.inviteUris.last;
      await tester.ensureVisible(
        find.byKey(const Key('coaching-invite-next-member')),
      );
      await tester.tap(find.byKey(const Key('coaching-invite-next-member')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('coaching-invite-create')),
      );
      await tester.tap(find.byKey(const Key('coaching-invite-create')));
      await tester.pumpAndSettle();
      expect(repository.inviteUris.last, isNot(secondLink));
      expect(repository.inviteRequestIds.toSet(), hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepting two links refreshes both members and keeps records separate',
    (tester) async {
      final repository = _Repository()
        ..links['thread-a'] = 'pending'
        ..links['thread-b'] = 'pending';
      final state = await _mount(
        tester,
        repository,
        const PeoplePage(role: UserRole.trainer),
      );
      expect(state.coachingConnections, isEmpty);
      await tester.tap(find.byTooltip('회원 기록 관리와 수정 요청'));
      await tester.pumpAndSettle();
      expect(find.text('기록 공유 범위를 확인하고 수락해주세요.'), findsNWidgets(2));
      for (final id in _members.keys) {
        final accept = find.byKey(ValueKey('accept-link-$id'));
        await tester.ensureVisible(accept);
        await tester.tap(accept);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-management-sharing')));
        await tester.pumpAndSettle();
      }
      expect(repository.acceptedLinks, ['thread-a', 'thread-b']);

      for (final entry in _members.entries) {
        final history = find.byKey(ValueKey('management-history-${entry.key}'));
        await tester.ensureVisible(history);
        await tester.tap(history);
        await tester.pumpAndSettle();
        expect(find.text('${entry.value} 운동 기록'), findsOneWidget);
        expect(
          find.text(entry.key == 'thread-a' ? '무게 40 kg' : '무게 80 kg'),
          findsOneWidget,
        );
        expect(
          find.text(entry.key == 'thread-a' ? '무게 80 kg' : '무게 40 kg'),
          findsNothing,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(repository.readLinks, ['thread-a', 'thread-b']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state.coachingConnections.map((item) => item.memberName), [
        '민지',
        '준호',
      ]);
      expect(find.text('민지'), findsOneWidget);
      expect(find.text('준호'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one trainer answers two chats and requests each member connection',
    (tester) async {
      final repository = _Repository();
      final state = await _mount(
        tester,
        repository,
        const ConsultationQueuePage(role: UserRole.trainer),
      );

      for (final entry in _members.entries) {
        await tester.tap(find.text(entry.value));
        await tester.pumpAndSettle();
        final reply = '${entry.value}님 답변';
        await tester.enterText(
          find.byKey(const ValueKey('consultation-chat-draft')),
          reply,
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('consultation-chat-send')));
        await tester.pumpAndSettle();
        expect(repository.sentMessages.last.consultationId, entry.key);
        expect(find.text(reply), findsOneWidget);
        final otherReply = entry.key == 'thread-a' ? '준호님 답변' : '민지님 답변';
        expect(find.text(otherReply), findsNothing);

        await tester.tap(find.byTooltip('상담 정보 보기'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('trainer-consultation-management')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('request-management-link')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-management-sharing')));
        await tester.pumpAndSettle();
        expect(repository.requestedLinks.last, entry.key);
        expect(find.text('상대가 수락하면 운동 기록 공유가 시작돼요.'), findsWidgets);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.binding
            .handlePopRoute(); // Close consultation information.
        await tester.pumpAndSettle();
        await tester.pageBack(); // Return to all member conversations.
        await tester.pumpAndSettle();
      }
      expect(repository.sentMessages.map((item) => item.consultationId), [
        'thread-a',
        'thread-b',
      ]);
      expect(repository.requestedLinks, ['thread-a', 'thread-b']);
      expect(state.businessConsultations, hasLength(2));
      expect(state.businessConsultations[0].messages.single.text, '민지님 답변');
      expect(state.businessConsultations[1].messages.single.text, '준호님 답변');
      expect(tester.takeException(), isNull);
    },
  );
}

Future<AppState> _mount(
  WidgetTester tester,
  _Repository repository,
  Widget screen, {
  Size size = const Size(480, 1100),
  double textScale = 1,
  double keyboardInset = 0,
}) async {
  await tester.binding.setSurfaceSize(size);
  final state = AppState(businessRepository: repository);
  await state.initialize();
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    await tester.pump(const Duration(seconds: 4));
    await tester.binding.setSurfaceSize(null);
  });
  return state;
}

class _Repository extends Fake
    implements
        BusinessRepository,
        MobileCoachingRepository,
        CoachingManagementRepository,
        ConsultationChatRepository {
  final links = <String, String>{};
  final acceptedLinks = <String>[];
  final requestedLinks = <String>[];
  final readLinks = <String>[];
  final inviteUris = <Uri>[];
  final inviteRequestIds = <String>[];
  final sentMessages = <SendConsultationMessageInput>[];

  BusinessConsultation _consultation(String id) => BusinessConsultation(
    id: id,
    userId: 'member-$id',
    trainerId: _trainer.id,
    trainerName: _trainer.displayName,
    memberName: _members[id],
    question: '${_members[id]}님의 질문',
    status: sentMessages.any((item) => item.consultationId == id)
        ? BusinessConsultationStatus.replied
        : BusinessConsultationStatus.pending,
    isRead: false,
    messages: [
      for (final message in sentMessages.where(
        (item) => item.consultationId == id,
      ))
        BusinessConsultationMessage(
          id: message.requestId,
          consultationId: id,
          sender: BusinessMessageSender.trainer,
          senderId: _trainerUser,
          requestId: message.requestId,
          text: message.text,
          createdAt: DateTime.utc(2026, 10, 1),
        ),
    ],
  );

  @override
  Future<BusinessAccess> loadAccess() async => _access;
  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async =>
      BusinessWorkspaceData(
        role: UserRole.trainer,
        access: _access,
        profile: _trainer,
        dashboardStats: const BusinessDashboardMetrics(),
        consultations: _members.keys.map(_consultation).toList(),
        coachingConnections: await listCoachingConnections(),
      );
  @override
  Future<List<CoachingConnection>> listCoachingConnections() async => [
    for (final link in links.entries.where((entry) => entry.value == 'active'))
      CoachingConnection(
        id: link.key,
        trainerId: _trainer.id,
        memberUserId: 'member-${link.key}',
        memberName: _members[link.key]!,
        trainerName: _trainer.displayName,
        status: 'active',
        createdAt: DateTime.utc(2026, 10, 1),
      ),
  ];
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
  @override
  Future<CoachingConnectionInviteCreation> createCoachingConnectionInvite({
    required String requestId,
    required DateTime expiresAt,
    String? recipientName,
  }) async {
    inviteRequestIds.add(requestId);
    final token = inviteRequestIds.length.toString().padLeft(64, '0');
    final uri = Uri.parse('com.teampara.setflow://coaching-invite/$token');
    inviteUris.add(uri);
    return CoachingConnectionInviteCreation(
      tokenIssued: true,
      token: token,
      uri: uri,
    );
  }

  @override
  Future<BusinessConsultation> loadConsultation(String id) async =>
      _consultation(id);
  @override
  Stream<BusinessConsultation> watchConsultation(String id) =>
      const Stream.empty();
  @override
  Future<BusinessConsultation> sendConsultationMessage(
    SendConsultationMessageInput input,
  ) async {
    sentMessages.add(input);
    return _consultation(input.consultationId);
  }

  @override
  Future<List<CoachingManagementLink>> listManagementLinks({
    required CoachingManagementRole role,
  }) async => [
    for (final link in links.entries)
      CoachingManagementLink(
        id: link.key,
        memberName: _members[link.key]!,
        trainerName: _trainer.displayName,
        status: link.value,
        viewerRole: 'trainer',
        canRespond:
            link.value == 'pending' && !requestedLinks.contains(link.key),
      ),
  ];
  @override
  Future<List<WorkoutCorrection>> listWorkoutCorrections({
    required CoachingManagementRole role,
  }) async => [];
  @override
  Future<void> requestManagementLink(String consultationId) async {
    requestedLinks.add(consultationId);
    links[consultationId] = 'pending';
  }

  @override
  Future<void> respondManagementLink(
    String linkId, {
    required bool accept,
  }) async {
    acceptedLinks.add(linkId);
    links[linkId] = accept ? 'active' : 'rejected';
  }

  @override
  Future<ManagedWorkoutPage> listManagedWorkouts(
    String linkId, {
    String? before,
  }) async {
    readLinks.add(linkId);
    return ManagedWorkoutPage(
      workouts: [
        ManagedWorkout(
          key: 'personal:2026-10-01',
          revision: linkId,
          title: '개인 운동',
          kind: 'personal',
          canPropose: true,
          requiresApproval: false,
          session: WorkoutSession(
            date: DateTime(2026, 10, 1),
            exercises: [
              WorkoutExercise(
                id: 'squat',
                template: const ExerciseTemplate(
                  id: 'squat',
                  name: '스쿼트',
                  muscle: '하체',
                  icon: SetflowIcons.record,
                ),
                sets: [
                  WorkoutSetEntry(
                    number: 1,
                    weight: linkId == 'thread-a' ? 40 : 80,
                    reps: 10,
                    completed: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Auth extends Fake implements AuthService {
  @override
  AuthUser get currentUser =>
      const AuthUser(id: _trainerUser, displayName: '담당 트레이너');
  @override
  bool get hasAuthenticatedUser => true;
  @override
  Stream<AuthChange> get authChanges => const Stream.empty();
  @override
  Future<bool> isVerifiedAdmin() async => false;
}
