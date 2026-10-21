import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/data/trainer_client_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/coaching_management_screen.dart';
import 'package:setflow/screens/member_detail_screens.dart';
import 'package:setflow/screens/trainer_client_screen.dart';
import 'package:setflow/screens/trainer_managed_client_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';
import 'package:setflow/widgets/workout_history_calendar.dart';

const _trainer = TrainerBusinessProfile(
  id: 'trainer',
  userId: 'trainer-user',
  displayName: '정코치',
  status: BusinessProfileStatus.approved,
  isPublic: true,
  verified: true,
  rating: 0,
  postCount: 0,
  coachingTotal: 0,
);
const _access = BusinessAccess(
  userId: 'trainer-user',
  accountRole: UserRole.trainer,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
  trainer: _trainer,
);

void main() {
  setUp(() => Auth.use(_SignedIn()));
  tearDown(Auth.reset);

  testWidgets(
    'namesakes from separate record sources keep separate rows and identities',
    (tester) async {
      final fixture = _Fixture(
        clients: [_client('direct-minji')],
        connections: [_connection('coaching-minji', 'personal-minji')],
        members: const [
          BusinessMember(
            id: 'center-membership',
            gymId: 'gym',
            userId: 'center-minji',
            name: '민지',
            remainingPtSessions: 0,
          ),
        ],
      );
      await _mount(tester, fixture);
      expect(find.text('전체 3명'), findsOneWidget);
      expect(find.text('민지'), findsNWidgets(3));

      await tester.tap(
        find.byKey(const ValueKey('managed-client-direct-minji')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TrainerManagedClientScreen>(
              find.byType(TrainerManagedClientScreen),
            )
            .client
            .id,
        'direct-minji',
      );
      expect(fixture.repository.loadedClientIds, ['direct-minji']);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('trainer-member-coaching:coaching-minji')),
      );
      await tester.pumpAndSettle();
      final coaching = tester.widget<TrainerClientScreen>(
        find.byType(TrainerClientScreen),
      );
      expect(coaching.connection.id, 'coaching-minji');
      expect(coaching.connection.memberUserId, 'personal-minji');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('trainer-member-center-membership')),
      );
      await tester.pumpAndSettle();
      final center = tester.widget<MemberDetailScreen>(
        find.byType(MemberDetailScreen),
      );
      expect(center.member.id, 'center-membership');
      expect(center.member.userId, 'center-minji');
      expect(fixture.repository.loadedMemberIds, ['center-membership']);
    },
  );

  testWidgets(
    'only the same linked user is merged and their original coaching stays reachable',
    (tester) async {
      final fixture = _Fixture(
        clients: [_client('linked-minji', userId: 'personal-minji')],
        connections: [
          _connection('coaching-minji', 'personal-minji'),
          _connection('other-minji', 'other-personal-minji'),
        ],
        members: const [
          BusinessMember(
            id: 'same-user-membership',
            gymId: 'gym',
            userId: 'personal-minji',
            name: '민지',
            remainingPtSessions: 0,
          ),
        ],
      );
      await _mount(tester, fixture);
      expect(find.text('전체 2명'), findsOneWidget);
      expect(find.text('민지'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('trainer-member-coaching:coaching-minji')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-member-coaching:other-minji')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('trainer-member-same-user-membership')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('managed-client-linked-minji')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutHistoryCalendar), findsOneWidget);
      expect(fixture.repository.loadedClientIds, ['linked-minji']);
      expect(find.byType(TrainerClientScreen), findsNothing);

      await tester.tap(find.byKey(const ValueKey('managed-client-info')));
      await tester.pumpAndSettle();
      final openCoaching = find.byKey(
        const ValueKey('managed-client-open-coaching'),
      );
      await tester.ensureVisible(openCoaching);
      await tester.tap(openCoaching);
      await tester.pumpAndSettle();
      final coaching = tester.widget<TrainerClientScreen>(
        find.byType(TrainerClientScreen),
      );
      expect(coaching.connection.id, 'coaching-minji');
      expect(coaching.connection.memberUserId, 'personal-minji');
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets(
    'one search accepts partial phone numbers with or without hyphens',
    (tester) async {
      final fixture = _Fixture(
        clients: [
          _client('minji', phone: '010-1234-5678'),
          _client('junho', name: '준호', phone: '01098765432'),
        ],
        connections: [_connection('connected', 'connected-user', name: '서연')],
      );
      await _mount(tester, fixture);
      for (final query in ['1234', '0101234', '010-1234', '민지']) {
        await tester.enterText(find.byType(TextField), query);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('managed-client-minji')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('managed-client-junho')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('trainer-member-coaching:connected')),
          findsNothing,
        );
      }
      await tester.tap(find.byTooltip('검색어 지우기'));
      await tester.pumpAndSettle();
      expect(find.text('전체 3명'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'a direct-only roster has no contradictory connection empty state',
    (tester) async {
      final fixture = _Fixture(clients: [_client('direct-minji')]);
      await _mount(tester, fixture);
      expect(find.text('전체 1명'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('managed-client-direct-minji')),
        findsOneWidget,
      );
      expect(find.byType(EmptyState), findsNothing);
      expect(find.textContaining('연결된 회원이 없어요'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets(
    'reply waiting applies to the merged row using its exact linked identity',
    (tester) async {
      final fixture = _Fixture(
        clients: [
          _client('linked-minji', userId: 'replying-minji'),
          _client('unlinked-minji', phone: '01087654321'),
        ],
        connections: [
          _connection('replying', 'replying-minji'),
          _connection('quiet', 'quiet-minji'),
        ],
        consultations: [
          BusinessConsultation(
            id: 'chat-replying',
            userId: 'replying-minji',
            trainerId: 'trainer',
            memberName: '민지',
            status: BusinessConsultationStatus.answered,
            isRead: true,
            messages: [
              BusinessConsultationMessage(
                id: 'follow-up',
                consultationId: 'chat-replying',
                sender: BusinessMessageSender.member,
                text: '다음 운동은 어떻게 할까요?',
                createdAt: DateTime(2026, 10, 21),
              ),
            ],
          ),
        ],
      );
      await _mount(tester, fixture);
      await tester.tap(find.widgetWithText(FilterChip, '답변 대기'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('managed-client-linked-minji')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('managed-client-unlinked-minji')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-member-coaching:replying')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('trainer-member-coaching:quiet')),
        findsNothing,
      );
      expect(find.text('1명'), findsOneWidget);
    },
  );

  testWidgets(
    'member add opens the real form directly and saves into the new calendar',
    (tester) async {
      final fixture = _Fixture();
      await _mount(tester, fixture);
      await tester.tap(
        find.byKey(const ValueKey('trainer-add-managed-client')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TrainerClientFormScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await _enterForm(tester, 'managed-client-name', '새 회원');
      await _enterForm(tester, 'managed-client-phone', '01012345678');
      final save = find.byKey(const ValueKey('managed-client-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fixture.repository.createdMembers, [('새 회원', '01012345678')]);
      final calendar = tester.widget<TrainerManagedClientScreen>(
        find.byType(TrainerManagedClientScreen),
      );
      expect(calendar.client.id, 'created-client');
      expect(calendar.client.name, '새 회원');
      expect(find.byType(WorkoutHistoryCalendar), findsOneWidget);
    },
  );

  testWidgets(
    'member menu still opens working invitation and record sharing flows',
    (tester) async {
      final fixture = _Fixture(clients: [_client('minji')]);
      await _mount(tester, fixture);
      await tester.tap(find.byTooltip('회원 관리 메뉴'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trainer-connect-member')));
      await tester.pumpAndSettle();
      final recipient = find.descendant(
        of: find.byKey(const Key('coaching-invite-name')),
        matching: find.byType(TextField),
      );
      await tester.enterText(recipient, '초대 민지');
      await tester.ensureVisible(
        find.byKey(const Key('coaching-invite-create')),
      );
      await tester.tap(find.byKey(const Key('coaching-invite-create')));
      await tester.pumpAndSettle();
      expect(fixture.repository.invitedNames, ['초대 민지']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('회원 관리 메뉴'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trainer-connection-requests')));
      await tester.pumpAndSettle();
      expect(find.byType(TrainerMemberRecordsScreen), findsOneWidget);
      expect(fixture.repository.loadedManagementRoles, [
        CoachingManagementRole.trainer,
      ]);
      expect(fixture.repository.loadedCorrectionRoles, [
        CoachingManagementRole.trainer,
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}

TrainerManagedClient _client(
  String id, {
  String name = '민지',
  String phone = '01012345678',
  String? userId,
}) => TrainerManagedClient(
  id: id,
  name: name,
  phone: phone,
  notes: '',
  memberUserId: userId,
);

CoachingConnection _connection(
  String id,
  String userId, {
  String name = '민지',
}) => CoachingConnection(
  id: id,
  trainerId: 'trainer',
  memberUserId: userId,
  memberName: name,
  trainerName: '정코치',
  status: 'active',
  createdAt: DateTime(2026, 10),
);

class _Fixture {
  _Fixture({
    List<TrainerManagedClient> clients = const [],
    List<CoachingConnection> connections = const [],
    List<BusinessMember> members = const [],
    List<BusinessConsultation> consultations = const [],
  }) {
    repository.clients = clients;
    state = _RosterState(businessRepository: repository)
      ..role = UserRole.trainer
      ..businessAccess = _access
      ..businessWorkspace = BusinessWorkspaceData(
        role: UserRole.trainer,
        access: _access,
        profile: _trainer,
        dashboardStats: const BusinessDashboardMetrics(),
        coachingConnections: connections,
        members: members,
        consultations: consultations,
      );
  }

  final repository = _Repository();
  late final _RosterState state;
}

class _RosterState extends AppState {
  _RosterState({super.businessRepository})
    : super(loadBusinessWithoutAuth: true);

  @override
  Future<void> refreshBusinessDashboard(UserRole role) async =>
      notifyListeners();
}

Future<void> _mount(WidgetTester tester, _Fixture fixture) async {
  await tester.binding.setSurfaceSize(const Size(432, 1100));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.state.dispose();
    await tester.pump(const Duration(seconds: 4));
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    AppScope(
      notifier: fixture.state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        home: const PeoplePage(role: UserRole.trainer),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterForm(WidgetTester tester, String key, String text) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextFormField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

class _SignedIn implements AuthService {
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

class _Repository
    implements
        BusinessRepository,
        TrainerClientRepository,
        CoachingManagementRepository,
        MobileCoachingRepository {
  List<TrainerManagedClient> clients = [];
  final loadedClientIds = <String>[];
  final loadedMemberIds = <String>[];
  final createdMembers = <(String, String)>[];
  final invitedNames = <String?>[];
  final loadedManagementRoles = <CoachingManagementRole>[];
  final loadedCorrectionRoles = <CoachingManagementRole>[];

  @override
  Future<List<TrainerManagedClient>> listTrainerClients() async => clients;

  @override
  Future<List<TrainerClientWorkout>> listTrainerClientWorkouts(
    String clientId,
  ) async {
    loadedClientIds.add(clientId);
    return [];
  }

  @override
  Future<TrainerManagedClient> createTrainerClient({
    required String name,
    required String phone,
    required String notes,
    required String requestId,
  }) async {
    createdMembers.add((name, phone));
    final client = TrainerManagedClient(
      id: 'created-client',
      name: name,
      phone: phone,
      notes: notes,
    );
    clients = [...clients, client];
    return client;
  }

  @override
  Future<BusinessMemberDetail> loadMemberDetail(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    loadedMemberIds.add(memberId);
    return BusinessMemberDetail(
      memberId: memberId,
      memberUserId: 'center-minji',
      shareBodyData: false,
      shareWorkoutRecords: false,
      canReadWorkouts: false,
      sessions: const [],
    );
  }

  @override
  Future<CoachingConnectionInviteCreation> createCoachingConnectionInvite({
    required String requestId,
    required DateTime expiresAt,
    String? recipientName,
  }) async {
    invitedNames.add(recipientName);
    return CoachingConnectionInviteCreation(
      tokenIssued: true,
      token: 'invite-token',
      uri: Uri.parse('https://setflow.app/coaching-join/invite-token'),
    );
  }

  @override
  Future<List<CoachingManagementLink>> listManagementLinks({
    required CoachingManagementRole role,
  }) async {
    loadedManagementRoles.add(role);
    return [];
  }

  @override
  Future<List<WorkoutCorrection>> listWorkoutCorrections({
    required CoachingManagementRole role,
  }) async {
    loadedCorrectionRoles.add(role);
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
