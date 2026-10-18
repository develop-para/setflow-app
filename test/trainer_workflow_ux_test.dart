import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/data/coaching_workout_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/coaching_management_screen.dart';
import 'package:setflow/screens/coaching_workout_screens.dart';
import 'package:setflow/screens/consultation_chat_screen.dart';
import 'package:setflow/screens/member_detail_screens.dart';
import 'package:setflow/screens/trainer_client_screen.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';
import 'package:setflow/widgets/trainer_daily_work.dart';

const _access = BusinessAccess(
  userId: 'trainer-user',
  accountRole: UserRole.trainer,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
  trainer: TrainerBusinessProfile(
    id: 'trainer',
    userId: 'trainer-user',
    displayName: '정코치',
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: 0,
    postCount: 0,
    coachingTotal: 0,
  ),
);

const _accessWithoutTrainer = BusinessAccess(
  userId: 'trainer-user',
  accountRole: UserRole.trainer,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
);

void main() {
  setUp(() => Auth.use(_SignedInAuth()));
  tearDown(Auth.reset);

  testWidgets('a center member opens their detail directly in one tap', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, const PeoplePage(role: UserRole.trainer));
    await tester.tap(find.text('센터 민지'));
    await tester.pumpAndSettle();
    final detail = tester.widget<MemberDetailScreen>(
      find.byType(MemberDetailScreen),
    );
    expect(detail.member.id, 'membership-minji');
    expect(detail.member.userId, 'member-minji');
    expect(fixture.repository.memberDetails, ['membership-minji']);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('운동 기록 공유가 꺼져 있어요'), findsOneWidget);
    await _unmount(tester, fixture);
  });

  testWidgets(
    'a personal client keeps their identity across records assignments and chat',
    (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture, const PeoplePage(role: UserRole.trainer));
      await tester.tap(find.text('개인 준호'));
      await tester.pumpAndSettle();
      expect(find.byType(TrainerClientScreen), findsOneWidget);
      expect(find.text('개인 준호'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('trainer-client-assignments')),
      );
      await tester.pumpAndSettle();
      final assignments = tester.widget<CoachingAssignmentsScreen>(
        find.byType(CoachingAssignmentsScreen),
      );
      expect(assignments.memberUserId, 'member-junho');
      expect(assignments.memberName, '개인 준호');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('trainer-client-records')));
      await tester.pumpAndSettle();
      final records = tester.widget<TrainerMemberRecordsScreen>(
        find.byType(TrainerMemberRecordsScreen),
      );
      expect(records.memberUserId, 'member-junho');
      expect(records.memberName, '개인 준호');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('trainer-client-chat')));
      await tester.pumpAndSettle();
      final chat = tester.widget<ConsultationChatScreen>(
        find.byType(ConsultationChatScreen),
      );
      expect(chat.consultationId, 'chat-junho');
      expect(fixture.repository.loadedChats, ['chat-junho']);
      await _unmount(tester, fixture);
    },
  );

  testWidgets(
    'a follow-up from a member returns them to reply waiting and filters survive back',
    (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture, const PeoplePage(role: UserRole.trainer));
      await tester.tap(find.widgetWithText(FilterChip, '답변 대기'));
      await tester.pumpAndSettle();
      expect(find.text('센터 민지'), findsOneWidget);
      expect(find.text('개인 준호'), findsNothing);
      expect(find.text('무계획 서연'), findsNothing);
      await tester.enterText(find.byType(TextField), '민지');
      await tester.pumpAndSettle();
      await tester.tap(find.text('센터 민지'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '민지',
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '답변 대기'))
            .selected,
        true,
      );
      expect(find.text('센터 민지'), findsOneWidget);
      expect(find.text('개인 준호'), findsNothing);
      await _unmount(tester, fixture);
    },
  );

  testWidgets(
    'missing plan is classified only after a successful workout query',
    (tester) async {
      final fixture = _Fixture();
      fixture.workouts.gate = Completer<List<CoachingWorkout>>();
      await _mount(
        tester,
        fixture,
        const PeoplePage(role: UserRole.trainer),
        settle: false,
      );
      expect(find.widgetWithText(FilterChip, '예정 운동 없음'), findsNothing);
      fixture.workouts.gate!.complete([
        _workout('minji-plan', memberId: 'member-minji'),
      ]);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '예정 운동 없음'));
      await tester.pumpAndSettle();
      expect(find.text('센터 민지'), findsNothing);
      expect(find.text('개인 준호'), findsOneWidget);
      expect(find.text('무계획 서연'), findsOneWidget);
      await _unmount(tester, fixture);
    },
  );

  testWidgets('a failed workout query does not expose a missing plan filter', (
    tester,
  ) async {
    final fixture = _Fixture();
    fixture.workouts.fail = true;
    await _mount(tester, fixture, const PeoplePage(role: UserRole.trainer));
    expect(find.widgetWithText(FilterChip, '예정 운동 없음'), findsNothing);
    expect(find.text('센터 민지'), findsOneWidget);
    expect(find.text('개인 준호'), findsOneWidget);
    await _unmount(tester, fixture);
  });

  testWidgets(
    'today work exposes only unfinished lessons actual completed sets and their actions',
    (tester) async {
      final fixture = _Fixture();
      fixture.repository.schedules = [
        _schedule('today-lesson'),
        _schedule('completed-lesson', completed: true),
        _schedule('tomorrow-lesson', tomorrow: true),
        _schedule('my-own-pt', trainerId: 'another-coach'),
      ];
      fixture.workouts.items = [
        _workout('actual', completed: true),
        _workout('empty-complete', completed: true, actualSets: 0),
        _workout('pending'),
        _workout('cancelled', completed: true, cancelled: true),
        _workout(
          'my-own-pt',
          completed: true,
          memberId: 'trainer-user',
          trainerId: 'another-coach',
        ),
      ];
      final selected = <String>[];
      await _mount(
        tester,
        fixture,
        Scaffold(
          body: ListView(
            children: [
              TrainerDailyWork(
                onSchedule: (item) => selected.add('lesson:${item.id}'),
                onConsultation: (item) => selected.add('reply:${item.id}'),
                onWorkout: (item) => selected.add('workout:${item.id}'),
              ),
            ],
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('trainer-today-lesson-today-lesson')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('trainer-today-lesson-completed-lesson')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-today-lesson-tomorrow-lesson')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-today-lesson-my-own-pt')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-reply-chat-minji')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('trainer-reply-chat-junho')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-completed-actual')),
        findsOneWidget,
      );
      for (final excluded in [
        'empty-complete',
        'pending',
        'cancelled',
        'my-own-pt',
      ]) {
        expect(
          find.byKey(ValueKey('trainer-completed-$excluded')),
          findsNothing,
        );
      }
      expect(find.textContaining('실제 2세트'), findsOneWidget);
      for (final key in [
        'trainer-today-lesson-today-lesson',
        'trainer-reply-chat-minji',
        'trainer-completed-actual',
      ]) {
        await tester.tap(find.byKey(ValueKey(key)));
      }
      expect(selected, [
        'lesson:today-lesson',
        'reply:chat-minji',
        'workout:actual',
      ]);
      await _unmount(tester, fixture);
    },
  );

  testWidgets('live trainer home places actionable work above monthly income', (
    tester,
  ) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, const Scaffold(body: TrainerHome()));
    expect(
      tester.getTopLeft(find.text('오늘 할 일')).dy,
      lessThan(tester.getTopLeft(find.text('이번 달 예상 수익')).dy),
    );
    await _unmount(tester, fixture);
  });

  testWidgets(
    'missing trainer identity never turns personal PT into customer work',
    (tester) async {
      final fixture = _Fixture(hasTrainerIdentity: false);
      fixture.repository.schedules = [_schedule('unverified-lesson')];
      fixture.workouts.items = [
        _workout('unverified-workout', completed: true),
      ];
      await _mount(
        tester,
        fixture,
        Scaffold(
          body: ListView(
            children: [
              TrainerDailyWork(
                onSchedule: (_) {},
                onConsultation: (_) {},
                onWorkout: (_) {},
              ),
            ],
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('trainer-today-lesson-unverified-lesson')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-completed-unverified-workout')),
        findsNothing,
      );
      await _unmount(tester, fixture);
    },
  );

  testWidgets(
    'a client without record chat or assignment services has no dead action buttons',
    (tester) async {
      final fixture = _Fixture(basic: true);
      await _mount(
        tester,
        fixture,
        TrainerClientScreen(connection: fixture.connection),
      );
      expect(
        find.byKey(const ValueKey('trainer-client-records')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('trainer-client-chat')), findsNothing);
      expect(
        find.byKey(const ValueKey('trainer-client-assignments')),
        findsNothing,
      );
      expect(find.text('개인 준호'), findsOneWidget);
      await _unmount(tester, fixture);
    },
  );
}

class _Fixture {
  _Fixture({bool basic = false, bool hasTrainerIdentity = true}) {
    final access = hasTrainerIdentity ? _access : _accessWithoutTrainer;
    state = _WorkflowState(
      businessRepository: basic ? _BasicRepository() : repository,
      coachingWorkoutRepository: basic ? null : workouts,
    );
    state.role = UserRole.trainer;
    state.businessAccess = access;
    state.businessDashboards[UserRole.trainer] = BusinessDashboardData(
      role: UserRole.trainer,
      facts: {'displayName': '정코치', 'members': '3', 'revenue': '120,000원'},
      tasks: [],
      notifications: [],
      lastSyncedAt: DateTime.now(),
    );
    state.businessWorkspace = BusinessWorkspaceData(
      role: UserRole.trainer,
      access: access,
      dashboardStats: const BusinessDashboardMetrics(),
      coachingConnections: [connection],
      members: const [
        BusinessMember(
          id: 'membership-minji',
          gymId: 'gym',
          userId: 'member-minji',
          name: '센터 민지',
          remainingPtSessions: 5,
        ),
        BusinessMember(
          id: 'membership-seoyeon',
          gymId: 'gym',
          userId: 'member-seoyeon',
          name: '무계획 서연',
          remainingPtSessions: 3,
        ),
      ],
      consultations: [
        _conversation('chat-minji', 'member-minji', '센터 민지', followUp: true),
        _conversation('chat-junho', 'member-junho', '개인 준호'),
      ],
    );
    repository.chats = state.businessConsultations;
  }
  final repository = _BusinessRepository();
  final workouts = _Workouts();
  late final _WorkflowState state;
  final connection = CoachingConnection(
    id: 'connection-junho',
    trainerId: 'trainer',
    memberUserId: 'member-junho',
    memberName: '개인 준호',
    trainerName: '정코치',
    status: 'active',
    createdAt: DateTime(2026, 10),
    sessionCount: 4,
  );
}

class _WorkflowState extends AppState {
  _WorkflowState({super.businessRepository, super.coachingWorkoutRepository})
    : super(loadBusinessWithoutAuth: true);
  @override
  Future<void> refreshBusinessDashboard(UserRole role) async =>
      notifyListeners();
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture,
  Widget page, {
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 1300));
  await tester.pumpWidget(
    AppScope(
      notifier: fixture.state,
      child: MaterialApp(theme: SetflowTheme.light, home: page),
    ),
  );
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  fixture.state.dispose();
  await fixture.repository.changes.close();
  await tester.pump(const Duration(seconds: 4));
  await tester.binding.setSurfaceSize(null);
}

BusinessConsultation _conversation(
  String id,
  String userId,
  String name, {
  bool followUp = false,
}) => BusinessConsultation(
  id: id,
  userId: userId,
  trainerId: 'trainer',
  memberName: name,
  status: BusinessConsultationStatus.answered,
  isRead: true,
  messages: [
    BusinessConsultationMessage(
      id: '$id-answer',
      consultationId: id,
      sender: BusinessMessageSender.trainer,
      text: '이전 답변',
      createdAt: DateTime(2026, 10, 17),
    ),
    if (followUp)
      BusinessConsultationMessage(
        id: '$id-question',
        consultationId: id,
        sender: BusinessMessageSender.member,
        text: '다음 운동은 어떻게 할까요?',
        createdAt: DateTime(2026, 10, 18),
      ),
  ],
);

BusinessCoachingSchedule _schedule(
  String id, {
  bool completed = false,
  bool tomorrow = false,
  String trainerId = 'trainer',
}) {
  final date = DateUtils.dateOnly(
    DateTime.now(),
  ).add(Duration(days: tomorrow ? 1 : 0));
  return BusinessCoachingSchedule(
    id: id,
    trainerId: trainerId,
    title: '하체 수업',
    date: date,
    startMinutes: 600,
    endMinutes: 660,
    memberUserId: 'member-minji',
    memberName: '센터 민지',
    createdAt: date,
    completedAt: completed ? date : null,
  );
}

CoachingWorkout _workout(
  String id, {
  String memberId = 'member-minji',
  bool completed = false,
  bool cancelled = false,
  int actualSets = 2,
  String trainerId = 'trainer',
}) {
  final date = DateUtils.dateOnly(DateTime.now());
  return CoachingWorkout(
    id: id,
    kind: CoachingWorkoutKind.assignment,
    status: cancelled
        ? CoachingWorkoutStatus.cancelled
        : completed
        ? CoachingWorkoutStatus.completed
        : CoachingWorkoutStatus.assigned,
    trainerId: trainerId,
    memberUserId: memberId,
    trainerName: '정코치',
    memberName: '센터 민지',
    title: '하체 운동',
    instruction: '',
    date: date,
    version: 1,
    canEdit: false,
    recordingAllowed: true,
    session: WorkoutSession(
      date: date,
      exercises: [
        WorkoutExercise(
          id: 'squat-$id',
          template: const ExerciseTemplate(
            id: 'squat',
            name: '스쿼트',
            muscle: '하체',
            icon: SetflowIcons.record,
          ),
          sets: [
            for (var i = 0; i < actualSets; i++)
              WorkoutSetEntry(
                number: i + 1,
                weight: 40,
                reps: 8,
                completed: completed,
              ),
          ],
        ),
      ],
    ),
  );
}

class _BasicRepository implements BusinessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BusinessRepository extends _BasicRepository
    implements ConsultationChatRepository, CoachingManagementRepository {
  List<BusinessCoachingSchedule> schedules = [];
  List<BusinessConsultation> chats = [];
  final memberDetails = <String>[];
  final loadedChats = <String>[];
  final changes = StreamController<BusinessConsultation>.broadcast();
  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => schedules;
  @override
  Future<BusinessMemberDetail> loadMemberDetail(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    memberDetails.add(memberId);
    return BusinessMemberDetail(
      memberId: memberId,
      memberUserId: 'member-minji',
      shareBodyData: false,
      shareWorkoutRecords: false,
      canReadWorkouts: false,
      sessions: const [],
    );
  }

  @override
  Future<List<CoachingManagementLink>> listManagementLinks({
    required CoachingManagementRole role,
  }) async => const [];
  @override
  Future<List<WorkoutCorrection>> listWorkoutCorrections({
    required CoachingManagementRole role,
  }) async => const [];
  @override
  Future<BusinessConsultation> loadConsultation(String consultationId) async {
    loadedChats.add(consultationId);
    return chats.singleWhere((item) => item.id == consultationId);
  }

  @override
  Stream<BusinessConsultation> watchConsultation(String consultationId) =>
      changes.stream;
}

class _Workouts implements CoachingWorkoutRepository {
  List<CoachingWorkout> items = [];
  bool fail = false;
  Completer<List<CoachingWorkout>>? gate;
  @override
  Future<List<CoachingWorkout>> listCoachingWorkouts({
    String? memberUserId,
  }) async {
    if (fail) throw StateError('Cannot load workouts');
    return gate?.future ?? items;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignedInAuth implements AuthService {
  @override
  AuthUser get currentUser =>
      const AuthUser(id: 'trainer-user', displayName: '정코치');
  @override
  bool get hasAuthenticatedUser => true;
  @override
  Stream<AuthChange> get authChanges => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
