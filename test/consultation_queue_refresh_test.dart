import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

const _trainerId = '11111111-1111-4111-8111-111111111111';
const _userId = '22222222-2222-4222-8222-222222222222';

void main() {
  Future<AppState> createState(_RefreshRepository repository) async {
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();
    return state;
  }

  Future<void> pumpQueue(WidgetTester tester, AppState state) async {
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
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('live consultation queue refreshes once after page entry', (
    tester,
  ) async {
    final repository = _RefreshRepository(
      consultations: const [_cachedConsultation],
    );
    final state = await createState(repository);
    expect(repository.workspaceLoadCount, 1);

    repository.consultations = const [_latestConsultation];
    await pumpQueue(tester, state);

    expect(repository.workspaceLoadCount, 2);
    expect(find.text('새 상담 회원'), findsOneWidget);
    expect(find.text('캐시 상담 회원'), findsNothing);
    expect(
      find.byKey(const ValueKey('business-consultations-refresh-indicator')),
      findsOneWidget,
    );
  });

  testWidgets('failed refresh keeps cached consultations and retry recovers', (
    tester,
  ) async {
    final repository = _RefreshRepository(
      consultations: const [_cachedConsultation],
    );
    final state = await createState(repository);
    repository
      ..consultations = const [_latestConsultation]
      ..failNextWorkspaceLoad = true;

    await pumpQueue(tester, state);

    expect(repository.workspaceLoadCount, 2);
    expect(find.text('캐시 상담 회원'), findsOneWidget);
    expect(find.text('새 상담 회원'), findsNothing);
    expect(
      find.byKey(const ValueKey('business-consultations-refresh-error')),
      findsOneWidget,
    );
    expect(find.text('기존에 불러온 상담 목록을 계속 표시합니다.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('business-consultations-refresh-retry')),
    );
    await tester.pumpAndSettle();

    expect(repository.workspaceLoadCount, 3);
    expect(find.text('새 상담 회원'), findsOneWidget);
    expect(find.text('캐시 상담 회원'), findsNothing);
    expect(
      find.byKey(const ValueKey('business-consultations-refresh-error')),
      findsNothing,
    );
  });

  testWidgets('refresh controls share one in-flight workspace request', (
    tester,
  ) async {
    final repository = _RefreshRepository(
      consultations: const [_cachedConsultation],
    );
    final state = await createState(repository);
    await pumpQueue(tester, state);
    expect(repository.workspaceLoadCount, 2);

    final gate = Completer<void>();
    repository.blockNextWorkspaceLoad = gate;
    final indicator = tester.widget<RefreshIndicator>(
      find.byKey(const ValueKey('business-consultations-refresh-indicator')),
    );
    final firstRefresh = indicator.onRefresh();
    await tester.pump();
    expect(repository.workspaceLoadCount, 3);

    final secondRefresh = tester
        .widget<RefreshIndicator>(
          find.byKey(
            const ValueKey('business-consultations-refresh-indicator'),
          ),
        )
        .onRefresh();
    expect(identical(firstRefresh, secondRefresh), isTrue);
    expect(repository.workspaceLoadCount, 3);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('business-consultations-refresh')),
          )
          .onPressed,
      isNull,
    );

    gate.complete();
    await firstRefresh;
    await tester.pumpAndSettle();

    expect(repository.workspaceLoadCount, 3);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('business-consultations-refresh')),
          )
          .onPressed,
      isNotNull,
    );
  });
}

const _cachedConsultation = BusinessConsultation(
  id: '33333333-3333-4333-8333-333333333333',
  userId: '44444444-4444-4444-8444-444444444444',
  trainerId: _trainerId,
  status: BusinessConsultationStatus.pending,
  isRead: false,
  memberName: '캐시 상담 회원',
  goal: '근력 향상',
  question: '기존 상담입니다.',
  messages: [],
);

const _latestConsultation = BusinessConsultation(
  id: '55555555-5555-4555-8555-555555555555',
  userId: '66666666-6666-4666-8666-666666666666',
  trainerId: _trainerId,
  status: BusinessConsultationStatus.pending,
  isRead: false,
  memberName: '새 상담 회원',
  goal: '체력 향상',
  question: '방금 접수한 상담입니다.',
  messages: [],
);

class _RefreshRepository implements BusinessRepository {
  _RefreshRepository({required this.consultations});

  List<BusinessConsultation> consultations;
  int workspaceLoadCount = 0;
  bool failNextWorkspaceLoad = false;
  Completer<void>? blockNextWorkspaceLoad;

  static const profile = TrainerBusinessProfile(
    id: _trainerId,
    userId: _userId,
    displayName: '상담 트레이너',
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: 4.9,
    postCount: 3,
    coachingTotal: 12,
  );

  static const access = BusinessAccess(
    userId: _userId,
    accountRole: UserRole.trainer,
    resolvedRole: UserRole.trainer,
    availableRoles: {UserRole.member, UserRole.trainer},
    trainer: profile,
  );

  BusinessWorkspaceData get workspace => BusinessWorkspaceData(
    role: UserRole.trainer,
    access: access,
    profile: profile,
    dashboardStats: BusinessDashboardMetrics(
      unreadConsultations: consultations.length,
    ),
    consultations: List<BusinessConsultation>.unmodifiable(consultations),
  );

  @override
  Future<BusinessAccess> loadAccess() async => access;

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async {
    workspaceLoadCount++;
    final gate = blockNextWorkspaceLoad;
    blockNextWorkspaceLoad = null;
    if (gate != null) await gate.future;
    if (failNextWorkspaceLoad) {
      failNextWorkspaceLoad = false;
      throw StateError('workspace temporarily unavailable');
    }
    return workspace;
  }

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => const [];

  @override
  Future<List<BusinessConsultation>> listMyConsultations() async =>
      List<BusinessConsultation>.unmodifiable(consultations);

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
