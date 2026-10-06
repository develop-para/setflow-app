import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';

const _account = 'trainer-account';
const _trainer = TrainerBusinessProfile(
  id: 'trainer-profile',
  userId: _account,
  displayName: '담당 트레이너',
  status: BusinessProfileStatus.approved,
  isPublic: true,
  verified: true,
  rating: 5,
  postCount: 0,
  coachingTotal: 0,
);
const _access = BusinessAccess(
  userId: _account,
  accountRole: UserRole.trainer,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
  trainer: _trainer,
);

void main() {
  late _Auth auth;
  final shares = <Map<String, dynamic>>[];
  final copies = <String>[];
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  setUp(() {
    auth = _Auth();
    Auth.use(auth);
    shares.clear();
    copies.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shares.add(Map<String, dynamic>.from(call.arguments as Map));
          return 'com.test.messages';
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() async {
    Auth.reset();
    await auth.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('empty trainer list explains the actual member acceptance step', (
    tester,
  ) async {
    await _mount(tester, _Repository());
    expect(find.text('회원 연결'), findsOneWidget);
    expect(find.text('아직 연결된 회원이 없어요'), findsOneWidget);
    expect(find.textContaining('회원이 수락하면 이 목록'), findsOneWidget);
    await _open(tester);
    expect(find.textContaining('회원마다 새 링크'), findsOneWidget);
    expect(find.textContaining('전체 운동 기록 조회·수정은 별도의 동의'), findsOneWidget);
  });

  testWidgets('sharing and copying an issued link do not create a connection', (
    tester,
  ) async {
    final repository = _Repository();
    final state = await _mount(tester, repository);
    await _open(tester);
    await _tap(tester, 'coaching-invite-create');
    final uri = repository.uri;
    expect(
      repository.expires.single
          .difference(repository.createdAt.single)
          .inSeconds,
      inInclusiveRange(
        const Duration(days: 7).inSeconds - 60,
        const Duration(days: 7).inSeconds,
      ),
    );
    expect(find.text(uri.toString()), findsOneWidget);
    expect(state.coachingConnections, isEmpty);
    await _tap(tester, 'coaching-invite-share');
    expect(shares, hasLength(1));
    expect(shares.single['text'], contains(uri.toString()));
    expect(shares.single['text'], contains('마이 → 코칭 → 트레이너 초대 링크 입력'));
    expect(state.coachingConnections, isEmpty);
    expect(find.textContaining('연결됐어요'), findsNothing);
    await _tap(tester, 'coaching-invite-copy');
    expect(copies, [uri.toString()]);
    expect(state.coachingConnections, isEmpty);
    expect(find.text('회원이 수락했나요? 목록 확인'), findsOneWidget);
  });

  testWidgets(
    'retry keeps the same request and expiry then creates a new invite',
    (tester) async {
      final repository = _Repository()..failNext = true;
      await _mount(tester, repository);
      await _open(tester);
      await tester.enterText(
        find.byKey(const Key('coaching-invite-name')),
        '민지',
      );
      await _tap(tester, 'coaching-invite-create');
      expect(find.textContaining('같은 회원으로 다시 시도'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await _tap(tester, 'coaching-invite-create');
      expect(repository.requestIds, hasLength(2));
      expect(repository.requestIds[0], repository.requestIds[1]);
      expect(repository.expires[0], repository.expires[1]);
      expect(repository.names, ['민지', '민지']);
      final firstUri = repository.uri;
      await _tap(tester, 'coaching-invite-next-member');
      await _tap(tester, 'coaching-invite-create');
      expect(repository.requestIds.last, isNot(repository.requestIds.first));
      expect(repository.uri, isNot(firstUri));
      expect(repository.names.last, isNull);
    },
  );

  testWidgets(
    'accepted members appear after refreshing the actual server list',
    (tester) async {
      final repository = _Repository();
      final state = await _mount(tester, repository);
      await _open(tester);
      await _tap(tester, 'coaching-invite-create');
      expect(state.coachingConnections, isEmpty);
      repository.connections = [
        CoachingConnection(
          id: 'connection-minji',
          trainerId: _trainer.id,
          memberUserId: 'member-minji',
          memberName: '민지',
          trainerName: _trainer.displayName,
          status: 'active',
          createdAt: DateTime(2026, 10, 7),
        ),
      ];
      await _tap(tester, 'coaching-invite-refresh-members');
      expect(find.byKey(const Key('coaching-invite-share')), findsNothing);
      expect(state.coachingConnections.single.memberName, '민지');
      expect(find.text('민지'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('logout hides a link and a late issuance cannot restore it', (
    tester,
  ) async {
    final repository = _Repository()..pending = Completer();
    await _mount(tester, repository);
    await _open(tester);
    await tester.tap(find.byKey(const Key('coaching-invite-create')));
    await tester.pump();
    await auth.signOut();
    await tester.pump();
    expect(
      find.byKey(const Key('coaching-invite-account-expired')),
      findsOneWidget,
    );
    repository.pending!.complete(repository.creation);
    await tester.pumpAndSettle();
    expect(find.text(repository.uri.toString()), findsNothing);
    expect(find.byKey(const Key('coaching-invite-share')), findsNothing);
    auth.signInAs(const AuthUser(id: _account, displayName: '담당 트레이너'));
    await tester.pump();
    expect(
      find.byKey(const Key('coaching-invite-account-expired')),
      findsOneWidget,
    );
    expect(find.text(repository.uri.toString()), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing workspace hides issued links immediately', (
    tester,
  ) async {
    final repository = _Repository();
    final state = await _mount(tester, repository);
    await _open(tester);
    await _tap(tester, 'coaching-invite-create');
    expect(find.text(repository.uri.toString()), findsOneWidget);
    state.chooseRole(UserRole.member);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(repository.uri.toString()), findsNothing);
    expect(
      find.byKey(const Key('coaching-invite-account-expired')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an account without approval cannot issue an invite', (
    tester,
  ) async {
    final repository = _Repository()
      ..access = const BusinessAccess(
        userId: _account,
        accountRole: UserRole.member,
        resolvedRole: UserRole.member,
        availableRoles: {UserRole.member},
      );
    await _mount(tester, repository);
    await _open(tester);
    expect(find.byKey(const ValueKey('pro-gate-title')), findsOneWidget);
    expect(find.byKey(const Key('coaching-invite-create')), findsNothing);
    expect(repository.requestIds, isEmpty);
  });

  testWidgets('connection entry and sheet fit large text and the keyboard', (
    tester,
  ) async {
    final repository = _Repository();
    await _mount(
      tester,
      repository,
      size: const Size(320, 568),
      textScale: 2,
      keyboard: 240,
      dark: true,
    );
    await _open(tester);
    await _tap(tester, 'coaching-invite-create');
    await _tap(tester, 'coaching-invite-copy');
    expect(copies, [repository.uri.toString()]);
    expect(tester.takeException(), isNull);
  });
}

Future<AppState> _mount(
  WidgetTester tester,
  _Repository repository, {
  Size size = const Size(432, 900),
  double textScale = 1,
  double keyboard = 0,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  final state = AppState(businessRepository: repository);
  await state.initialize();
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: dark ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            padding: const EdgeInsets.only(bottom: 28),
          ),
          child: child!,
        ),
        home: const PeoplePage(role: UserRole.trainer),
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

Future<void> _open(WidgetTester tester) async {
  final button = find.byKey(const Key('trainer-connect-member'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

class _Auth extends Fake implements AuthService {
  AuthUser? _user = const AuthUser(id: _account, displayName: '담당 트레이너');
  final _changes = StreamController<AuthChange>.broadcast(sync: true);
  @override
  AuthUser? get currentUser => _user;
  @override
  bool get hasAuthenticatedUser => _user != null;
  @override
  Stream<AuthChange> get authChanges => _changes.stream;
  @override
  Future<bool> isVerifiedAdmin() async => false;
  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(const AuthChange(AuthEvent.signedOut, null));
  }

  void signInAs(AuthUser user) {
    _user = user;
    _changes.add(AuthChange(AuthEvent.signedIn, user));
  }

  Future<void> dispose() => _changes.close();
}

class _Repository extends Fake
    implements BusinessRepository, MobileCoachingRepository {
  BusinessAccess access = _access;
  List<CoachingConnection> connections = [];
  final requestIds = <String>[];
  final expires = <DateTime>[];
  final createdAt = <DateTime>[];
  final names = <String?>[];
  bool failNext = false;
  Completer<CoachingConnectionInviteCreation>? pending;

  Uri get uri => Uri.parse(
    'com.teampara.setflow://coaching-invite/${requestIds.last.replaceAll('-', '').padLeft(64, '0')}',
  );
  CoachingConnectionInviteCreation get creation =>
      CoachingConnectionInviteCreation(tokenIssued: true, uri: uri);

  @override
  Future<BusinessAccess> loadAccess() async => access;
  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async =>
      BusinessWorkspaceData(
        role: role,
        access: access,
        profile: _trainer,
        dashboardStats: const BusinessDashboardMetrics(),
        coachingConnections: connections,
      );
  @override
  Future<CoachingConnectionInviteCreation> createCoachingConnectionInvite({
    required String requestId,
    required DateTime expiresAt,
    String? recipientName,
  }) async {
    requestIds.add(requestId);
    expires.add(expiresAt);
    createdAt.add(DateTime.now().toUtc());
    names.add(recipientName);
    if (failNext) {
      failNext = false;
      throw StateError('network unavailable');
    }
    return pending?.future ?? Future.value(creation);
  }

  @override
  Future<List<CoachingConnection>> listCoachingConnections() async =>
      connections;
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
}
