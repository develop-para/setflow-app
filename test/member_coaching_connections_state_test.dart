import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';

const _memberId = '11111111-1111-4111-8111-111111111111';
const _otherMemberId = '22222222-2222-4222-8222-222222222222';
const _trainerId = '33333333-3333-4333-8333-333333333333';
const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _nextToken =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppState createState(_Repository repository) {
    final state =
        AppState(businessRepository: repository, loadBusinessWithoutAuth: true)
          ..role = UserRole.member
          ..businessAccess = repository.access;
    addTearDown(state.dispose);
    return state;
  }

  test('회원 초기화는 사업장 workspace 없이 자신의 코칭 연결을 조회한다', () async {
    final repository = _Repository()..connections = [_connection('mine')];
    final state = createState(repository);
    await state.initialize();
    expect(repository.calls, 1);
    expect(repository.workspaceCalls, 0);
    expect(state.businessWorkspace, isNull);
    expect(state.coachingConnections.single.id, 'mine');
    expect(state.memberCoachingConnectionsError, isNull);
  });

  test('연결 조회 실패는 성공한 빈 목록과 구분되고 재시도할 수 있다', () async {
    final repository = _Repository();
    final state = createState(repository);
    repository.failNextConnectionLoad = true;
    await expectLater(
      state.refreshMemberCoachingConnections(),
      throwsStateError,
    );
    expect(state.coachingConnections, isEmpty);
    expect(state.memberCoachingConnectionsError, isA<StateError>());
    expect(state.memberCoachingConnectionsLoading, isFalse);
    repository.connections = [_connection('recovered')];
    await state.refreshMemberCoachingConnections();
    expect(state.coachingConnections.single.id, 'recovered');
    expect(state.memberCoachingConnectionsError, isNull);
  });

  test('다른 조회 실패가 개인 기록 전체 동기화 오류가 되지 않는다', () async {
    final repository = _Repository()..failNextConnectionLoad = true;
    final state = createState(repository);
    await state.initialize();
    expect(state.memberCoachingConnectionsError, isA<StateError>());
    expect(state.cloudSyncError, isNull);
    expect(state.businessError, isNull);
  });

  test('일시적인 실패는 같은 계정의 직전 목록과 오류를 함께 보존한다', () async {
    final repository = _Repository()..connections = [_connection('cached')];
    final state = createState(repository);
    await state.refreshMemberCoachingConnections();
    repository.failNextConnectionLoad = true;
    await expectLater(
      state.refreshMemberCoachingConnections(),
      throwsStateError,
    );
    expect(state.coachingConnections.single.id, 'cached');
    expect(state.memberCoachingConnectionsError, isNotNull);
  });

  test('겸업 트레이너가 회원 포털에서 다른 회원의 연결을 보지 않는다', () async {
    final repository = _Repository()
      ..connections = [
        _connection('mine'),
        _connection('another client', memberId: _otherMemberId),
      ];
    final state = createState(repository);
    await state.refreshMemberCoachingConnections();
    expect(state.coachingConnections.map((item) => item.id), ['mine']);
  });

  test('새로고침 응답 순서가 바뀌어도 최신 요청 결과가 유지된다', () async {
    final first = Completer<List<CoachingConnection>>();
    final second = Completer<List<CoachingConnection>>();
    final repository = _Repository()
      ..responses.addAll([first.future, second.future]);
    final state = createState(repository);
    final oldRequest = state.refreshMemberCoachingConnections();
    final newRequest = state.refreshMemberCoachingConnections();
    expect(state.memberCoachingConnectionsLoading, isTrue);
    second.complete([_connection('new')]);
    await newRequest;
    first.complete([_connection('old')]);
    await oldRequest;
    expect(state.coachingConnections.single.id, 'new');
    expect(state.memberCoachingConnectionsLoading, isFalse);
  });

  test('로그아웃 뒤 늦은 성공이 연결 정보를 되살리지 않는다', () async {
    final response = Completer<List<CoachingConnection>>();
    final repository = _Repository()..responses.add(response.future);
    final state = createState(repository);
    final request = state.refreshMemberCoachingConnections();
    state.handleExternalAuthSignedOut();
    response.complete([_connection('old account')]);
    await request;
    expect(state.coachingConnections, isEmpty);
    expect(state.memberCoachingConnectionsLoading, isFalse);
    expect(state.memberCoachingConnectionsError, isNull);
  });

  test('로그아웃 뒤 늦은 실패가 다른 화면에 오류를 남기지 않는다', () async {
    final response = Completer<List<CoachingConnection>>();
    final repository = _Repository()..responses.add(response.future);
    final state = createState(repository);
    final request = state.refreshMemberCoachingConnections();
    state.handleExternalAuthSignedOut();
    response.completeError(StateError('old request failed'));
    await request;
    expect(state.coachingConnections, isEmpty);
    expect(state.memberCoachingConnectionsLoading, isFalse);
    expect(state.memberCoachingConnectionsError, isNull);
  });

  test('계정이 바뀌면 이전 목록이 즉시 숨고 새 계정 조회만 표시된다', () async {
    final repository = _Repository()..connections = [_connection('old')];
    final state = createState(repository);
    await state.refreshMemberCoachingConnections();
    state.businessAccess = repository.accessFor(_otherMemberId);
    expect(state.coachingConnections, isEmpty);
    repository.connections = [_connection('new', memberId: _otherMemberId)];
    await state.refreshMemberCoachingConnections();
    expect(state.coachingConnections.single.id, 'new');
  });

  test('역할을 바꾸고 돌아온 뒤 이전 요청이 회원 정보를 복원하지 않는다', () async {
    final response = Completer<List<CoachingConnection>>();
    final repository = _Repository()..responses.add(response.future);
    final state = createState(repository);
    final request = state.refreshMemberCoachingConnections();
    state.chooseRole(UserRole.trainer);
    state.chooseRole(UserRole.member);
    response.complete([_connection('old member response')]);
    await request;
    expect(state.coachingConnections, isEmpty);
    expect(state.memberCoachingConnectionsLoading, isFalse);
    repository.connections = [_connection('fresh')];
    await state.refreshMemberCoachingConnections();
    expect(state.coachingConnections.single.id, 'fresh');
  });

  test('트레이너 포털은 기존 workspace의 연결 회원을 계속 사용한다', () async {
    final repository = _Repository();
    final state = createState(repository)
      ..role = UserRole.trainer
      ..businessWorkspace = repository.workspace;
    expect(state.coachingConnections.single.id, 'trainer client');
    await state.refreshMemberCoachingConnections();
    expect(repository.calls, 0);
    expect(state.coachingConnections.single.id, 'trainer client');
  });

  test('게스트는 계정 연결 조회를 호출하지 않는다', () async {
    final repository = _Repository();
    final state = createState(repository)..role = UserRole.guest;
    await state.refreshMemberCoachingConnections();
    expect(repository.calls, 0);
    expect(state.coachingConnections, isEmpty);
    expect(state.memberCoachingConnectionsError, isNull);
  });

  test('회원의 초대 수락 후 연결 목록을 실제 서버 결과로 갱신한다', () async {
    final repository = _Repository();
    final state = createState(repository);
    await state.initialize();
    state.pendingCoachingInviteToken = _token;
    final result = await state.acceptCoachingConnectionInviteToken(_token);
    expect(result.accepted, isTrue);
    expect(repository.calls, 2);
    expect(state.coachingConnections.single.id, 'accepted');
    expect(state.pendingCoachingInviteToken, isNull);
  });

  test('초대 수락 중 새로 들어온 다른 초대는 보존한다', () async {
    final response = Completer<CoachingConnectionAcceptance>();
    final repository = _Repository()..acceptanceResponse = response.future;
    final state = createState(repository)..pendingCoachingInviteToken = _token;
    final request = state.acceptCoachingConnectionInviteToken();
    state.captureIncomingUri(
      Uri.parse('com.teampara.setflow://coaching-invite/$_nextToken'),
    );
    response.complete(const CoachingConnectionAcceptance(accepted: true));
    await request;
    expect(state.pendingCoachingInviteToken, _nextToken);
  });

  test('직접 입력한 초대를 수락해도 보관 중인 다른 초대를 지우지 않는다', () async {
    final repository = _Repository();
    final state = createState(repository)
      ..pendingCoachingInviteToken = _nextToken;
    await state.acceptCoachingConnectionInviteToken(_token);
    expect(state.pendingCoachingInviteToken, _nextToken);
  });

  test('수락 후 목록 갱신 실패는 수락 결과와 별도 오류로 남는다', () async {
    final repository = _Repository()..failNextConnectionLoad = true;
    final state = createState(repository);
    final result = await state.acceptCoachingConnectionInviteToken(_token);
    expect(result.accepted, isTrue);
    expect(state.memberCoachingConnectionsError, isA<StateError>());
    expect(state.businessError, isNull);
  });
}

CoachingConnection _connection(String id, {String memberId = _memberId}) =>
    CoachingConnection(
      id: id,
      trainerId: _trainerId,
      memberUserId: memberId,
      memberName: '회원',
      trainerName: '트레이너',
      status: 'active',
      createdAt: DateTime(2026, 10, 7),
    );

class _Repository implements BusinessRepository, MobileCoachingRepository {
  int calls = 0;
  int workspaceCalls = 0;
  bool failNextConnectionLoad = false;
  Future<CoachingConnectionAcceptance>? acceptanceResponse;
  List<CoachingConnection> connections = [];
  final responses = <Future<List<CoachingConnection>>>[];

  BusinessAccess get access => accessFor(_memberId);
  BusinessAccess accessFor(String userId) => BusinessAccess(
    userId: userId,
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: const {UserRole.member, UserRole.trainer},
  );

  BusinessWorkspaceData get workspace => BusinessWorkspaceData(
    role: UserRole.trainer,
    access: access,
    dashboardStats: const BusinessDashboardMetrics(),
    coachingConnections: [
      _connection('trainer client', memberId: _otherMemberId),
    ],
  );

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async {
    workspaceCalls++;
    return workspace;
  }

  @override
  Future<List<CoachingConnection>> listCoachingConnections() {
    calls++;
    if (failNextConnectionLoad) {
      failNextConnectionLoad = false;
      return Future.error(StateError('connections offline'));
    }
    return responses.isEmpty
        ? Future.value(connections)
        : responses.removeAt(0);
  }

  @override
  Future<CoachingConnectionAcceptance> acceptCoachingConnectionInvite(
    String token, {
    required String requestId,
  }) async {
    if (acceptanceResponse case final response?) return await response;
    final accepted = _connection('accepted');
    connections = [accepted];
    return CoachingConnectionAcceptance(accepted: true, connection: accepted);
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
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => const [];

  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async =>
      const [];

  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
