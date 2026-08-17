import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _trainerId = '22222222-2222-4222-8222-222222222222';
const _gymId = '33333333-3333-4333-8333-333333333333';
const _memberId = '44444444-4444-4444-8444-444444444444';
const _memberUserId = '55555555-5555-4555-8555-555555555555';
const _routineId = '66666666-6666-4666-8666-666666666666';
const _acceptedShareId = '77777777-7777-4777-8777-777777777777';
const _pendingShareId = '88888888-8888-4888-8888-888888888888';

void main() {
  testWidgets('live routine card exposes server share acceptance statuses', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = _buildTrainerState(_RepositoryMarker());
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const RoutineManagerPage(role: UserRole.trainer),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusButton = find.byKey(
      const ValueKey('routine-share-status-$_routineId'),
    );
    expect(statusButton, findsOneWidget);
    expect(find.text('수락 1'), findsOneWidget);
    expect(find.text('대기 1'), findsOneWidget);

    await tester.ensureVisible(statusButton);
    await tester.tap(statusButton);
    await tester.pumpAndSettle();

    expect(find.text('회원 전송 현황'), findsWidgets);
    expect(find.text('서버 회원'), findsNWidgets(2));
    expect(find.text('수락 완료'), findsOneWidget);
    expect(find.text('수락 대기'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('routine-share-revoke-$_pendingShareId')),
      findsNothing,
    );
  });

  testWidgets('trainer can retry and revoke only a pending direct share', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _RevocationRepository();
    final state = _buildTrainerState(repository);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: const RoutineManagerPage(role: UserRole.trainer),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final statusButton = find.byKey(
      const ValueKey('routine-share-status-$_routineId'),
    );
    await tester.ensureVisible(statusButton);
    await tester.tap(statusButton);
    await tester.pumpAndSettle();

    final revokeButton = find.byKey(
      const ValueKey('routine-share-revoke-$_pendingShareId'),
    );
    expect(revokeButton, findsOneWidget);

    await tester.tap(revokeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '공유 취소'));
    await tester.pumpAndSettle();

    expect(repository.requestIds, hasLength(1));
    expect(revokeButton, findsOneWidget);
    expect(find.textContaining('새로고침 후 상태'), findsOneWidget);

    await tester.tap(revokeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '공유 취소'));
    await tester.pumpAndSettle();

    expect(repository.requestIds, hasLength(2));
    expect(repository.requestIds[1], repository.requestIds[0]);
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(repository.requestIds.first),
      isTrue,
    );
    expect(revokeButton, findsNothing);
    expect(find.text('공유 취소'), findsOneWidget);
    expect(find.text('회원 공유를 취소했어요.'), findsOneWidget);
  });
}

AppState _buildTrainerState(BusinessRepository repository) {
  const trainer = TrainerBusinessProfile(
    id: _trainerId,
    userId: _userId,
    displayName: '실트레이너',
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: 4.9,
    postCount: 0,
    coachingTotal: 0,
  );
  const access = BusinessAccess(
    userId: _userId,
    accountRole: UserRole.trainer,
    resolvedRole: UserRole.trainer,
    availableRoles: {UserRole.member, UserRole.trainer},
    trainer: trainer,
  );
  const routine = OwnedCoachingRoutine(
    id: _routineId,
    trainerId: _trainerId,
    title: '회원 맞춤 근력 루틴',
    status: BusinessRoutineStatus.approved,
    difficulty: BusinessRoutineDifficulty.intermediate,
    cumulativeUsers: 2,
    exercises: [],
  );
  const member = BusinessMember(
    id: _memberId,
    gymId: _gymId,
    userId: _memberUserId,
    name: '서버 회원',
    remainingPtSessions: 8,
  );
  return AppState(businessRepository: repository)
    ..role = UserRole.trainer
    ..businessAccess = access
    ..businessWorkspace = const BusinessWorkspaceData(
      role: UserRole.trainer,
      access: access,
      profile: trainer,
      dashboardStats: BusinessDashboardMetrics(),
      members: [member],
      ownedRoutines: [routine],
    )
    ..outgoingRoutineShares = [
      RoutineShareRecord(
        id: _acceptedShareId,
        routineId: _routineId,
        senderUserId: _userId,
        recipientUserId: _memberUserId,
        status: RoutineShareStatus.accepted,
        kind: RoutineShareKind.direct,
        routineTitle: routine.title,
        senderName: trainer.displayName,
        createdAt: DateTime.now(),
      ),
      RoutineShareRecord(
        id: _pendingShareId,
        routineId: _routineId,
        senderUserId: _userId,
        recipientUserId: _memberUserId,
        status: RoutineShareStatus.pending,
        kind: RoutineShareKind.direct,
        routineTitle: routine.title,
        senderName: trainer.displayName,
        createdAt: DateTime.now(),
      ),
    ];
}

class _RepositoryMarker implements BusinessRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RevocationRepository
    implements BusinessRepository, RoutineShareRevocationRepository {
  final requestIds = <String>[];
  var failNext = true;

  @override
  Future<RoutineShareRecord> revokeRoutineShare(
    String shareId, {
    required String requestId,
  }) async {
    requestIds.add(requestId);
    if (failNext) {
      failNext = false;
      throw StateError('temporary failure');
    }
    return RoutineShareRecord(
      id: shareId,
      routineId: _routineId,
      senderUserId: _userId,
      recipientUserId: _memberUserId,
      status: RoutineShareStatus.revoked,
      kind: RoutineShareKind.direct,
      routineTitle: '회원 맞춤 근력 루틴',
      senderName: '실트레이너',
      respondedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
