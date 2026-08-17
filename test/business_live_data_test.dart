import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/data/routine_catalog_repository.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/theme.dart';

const _userId = '11111111-1111-4111-8111-111111111111';
const _trainerId = '22222222-2222-4222-8222-222222222222';
const _gymId = '33333333-3333-4333-8333-333333333333';
const _memberId = '44444444-4444-4444-8444-444444444444';
const _consultationId = '55555555-5555-4555-8555-555555555555';
const _personalRoutineId = '77777777-7777-4777-8777-777777777777';
const _baseExerciseId = '99999999-9999-4999-8999-999999999999';

void main() {
  Future<void> pumpBusinessScreen(
    WidgetTester tester,
    AppState state,
    Widget screen,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'live business DTO replaces every demo business seed in state and UI',
    (tester) async {
      final repository = _trainerRepository();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();
      await tester.pump(const Duration(milliseconds: 300));

      expect(state.usesLiveBusinessData, isTrue);
      expect(state.role, UserRole.trainer);
      expect(state.businessAccess?.userId, _userId);
      expect(state.businessWorkspace?.profile?.id, _trainerId);
      expect(state.businessMembers.single.id, _memberId);
      expect(
        state.dashboardFor(UserRole.trainer).facts['displayName'],
        '실데이터 정코치',
      );

      final liveStateText = [
        ...state.dashboardFor(UserRole.trainer).facts.values,
        ...state.dashboardFor(UserRole.trainer).tasks.map((item) => item.title),
        ...state.businessMembers.map((item) => item.name),
      ].join(' ');
      expect(liveStateText, isNot(contains('김코치')));
      expect(liveStateText, isNot(contains('모션짐 강남점')));
      expect(liveStateText, isNot(contains('박민지')));

      await pumpBusinessScreen(tester, state, const TrainerHome());

      expect(find.text('안녕하세요, 실데이터 정코치님'), findsOneWidget);
      expect(find.byKey(const ValueKey('business-content')), findsOneWidget);
      expect(find.textContaining('김코치'), findsNothing);
      expect(find.textContaining('모션짐 강남점'), findsNothing);
      expect(find.textContaining('박민지'), findsNothing);
    },
  );

  test(
    'server general role resolves to member and blocks local escalation',
    () async {
      final access = const BusinessAccess(
        userId: _userId,
        email: 'member@example.com',
        accountRole: UserRole.member,
        resolvedRole: UserRole.member,
        availableRoles: {UserRole.member},
      );
      final repository = _FakeBusinessRepository(access: access);
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();

      expect(state.role, UserRole.member);
      expect(state.businessAccess?.accountRole, UserRole.member);
      expect(repository.loadedWorkspaceRoles, isEmpty);

      state.chooseRole(UserRole.trainer);
      expect(state.role, UserRole.member);
      state.chooseRole(UserRole.gym);
      expect(state.role, UserRole.member);
      state.chooseRole(UserRole.admin);
      expect(state.role, UserRole.member);
    },
  );

  test(
    'approved multi-role account loads the selected live workspace',
    () async {
      final trainer = _trainerProfile();
      final gym = _gymProfile();
      final access = BusinessAccess(
        userId: _userId,
        accountRole: UserRole.trainer,
        resolvedRole: UserRole.trainer,
        availableRoles: const {UserRole.member, UserRole.trainer, UserRole.gym},
        trainer: trainer,
        gym: gym,
      );
      final repository = _FakeBusinessRepository(
        access: access,
        workspaces: {
          UserRole.trainer: BusinessWorkspaceData(
            role: UserRole.trainer,
            access: access,
            profile: trainer,
            dashboardStats: const BusinessDashboardMetrics(),
          ),
          UserRole.gym: BusinessWorkspaceData(
            role: UserRole.gym,
            access: access,
            profile: gym,
            dashboardStats: const BusinessDashboardMetrics(),
          ),
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();
      expect(state.businessWorkspace?.role, UserRole.trainer);

      state.chooseRole(UserRole.gym);
      await Future<void>.delayed(Duration.zero);

      expect(state.role, UserRole.gym);
      expect(state.businessWorkspace?.role, UserRole.gym);
      expect(repository.loadedWorkspaceRoles, [UserRole.trainer, UserRole.gym]);
    },
  );

  test(
    'name based business mutations send Supabase UUIDs to the repository',
    () async {
      final repository = _gymRepository();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();
      await state.assignBusinessMember(memberName: '실회원', trainerName: '실트레이너');

      expect(repository.assignmentInputs, hasLength(1));
      expect(repository.assignmentInputs.single.gymId, _gymId);
      expect(repository.assignmentInputs.single.memberId, _memberId);
      expect(repository.assignmentInputs.single.trainerId, _trainerId);

      await state.answerBusinessConsultation(
        role: UserRole.gym,
        consultationIndex: 0,
        answer: '실제 상담 답변입니다.',
      );

      expect(repository.replyInputs, hasLength(1));
      expect(repository.replyInputs.single.consultationId, _consultationId);
      expect(repository.replyInputs.single.message, '실제 상담 답변입니다.');
    },
  );

  testWidgets('empty live workspace renders the business empty state', (
    tester,
  ) async {
    final access = _trainerAccess(profile: null);
    final repository = _FakeBusinessRepository(
      access: access,
      workspaces: {
        UserRole.trainer: BusinessWorkspaceData(
          role: UserRole.trainer,
          access: access,
          dashboardStats: const BusinessDashboardMetrics(),
        ),
      },
    );
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);

    await state.initialize();
    await tester.pump(const Duration(milliseconds: 300));
    await pumpBusinessScreen(tester, state, const TrainerHome());

    expect(state.businessWorkspace, isNotNull);
    expect(state.businessMembers, isEmpty);
    expect(state.businessConsultations, isEmpty);
    expect(find.byKey(const ValueKey('business-empty')), findsOneWidget);
    expect(find.text('표시할 운영 데이터가 없어요'), findsOneWidget);
    expect(find.textContaining('김코치'), findsNothing);
    expect(find.textContaining('박민지'), findsNothing);
  });

  testWidgets(
    'live trainer performance shows database metrics without generated stats',
    (tester) async {
      final state = AppState(
        businessRepository: _gymRepository(),
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();
      await tester.pump(const Duration(milliseconds: 300));
      await pumpBusinessScreen(tester, state, const TrainerManagementPage());

      await tester.tap(find.text('실트레이너'));
      await tester.pumpAndSettle();

      final metricText = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => widget.text.toPlainText())
          .join(' ');
      expect(metricText, contains('950,000'));
      expect(find.text('센터 운영 데이터'), findsOneWidget);
      expect(find.text('상담 전환율'), findsNothing);
      expect(find.text('최근 상담 전환 추이'), findsNothing);
      expect(find.textContaining('김코치'), findsNothing);
    },
  );

  testWidgets(
    'live repository error never falls back to snapshot or demo data',
    (tester) async {
      final access = _trainerAccess();
      final repositoryError = StateError('workspace unavailable');
      final repository = _FakeBusinessRepository(
        access: access,
        workspaceError: repositoryError,
      );
      final staleDashboard = BusinessDashboardData(
        role: UserRole.trainer,
        facts: {'displayName': '김코치', 'members': '12'},
        tasks: [],
        notifications: [],
        lastSyncedAt: DateTime(2026, 8, 16),
      );
      final state = AppState(
        repository: MemoryAppRepository(
          initialSnapshot: AppSnapshot(
            role: UserRole.trainer,
            isDarkMode: false,
            weightUnit: 'kg',
            restDefaultSeconds: 90,
            sessions: const {},
            routines: const [],
            businessDashboards: {UserRole.trainer: staleDashboard},
          ),
        ),
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();

      expect(state.businessError, same(repositoryError));
      expect(state.cloudSyncError, same(repositoryError));
      expect(state.businessWorkspace, isNull);
      expect(state.dashboardFor(UserRole.trainer).facts, isEmpty);

      await pumpBusinessScreen(tester, state, const TrainerHome());
      expect(find.byKey(const ValueKey('business-empty')), findsOneWidget);
      expect(find.textContaining('김코치'), findsNothing);
      expect(find.textContaining('모션짐 강남점'), findsNothing);
      expect(find.textContaining('박민지'), findsNothing);
    },
  );

  test('logout invalidates a workspace request that completes late', () async {
    final profile = _trainerProfile();
    final access = _trainerAccess(profile: profile);
    final workspaceCompleter = Completer<BusinessWorkspaceData>();
    final workspaceRequested = Completer<void>();
    final repository = _FakeBusinessRepository(
      access: access,
      workspaceLoader: (role) {
        if (!workspaceRequested.isCompleted) workspaceRequested.complete();
        return workspaceCompleter.future;
      },
    );
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);

    final initializeFuture = state.initialize();
    await workspaceRequested.future;
    state.logout();
    workspaceCompleter.complete(
      BusinessWorkspaceData(
        role: UserRole.trainer,
        access: access,
        profile: profile,
        dashboardStats: const BusinessDashboardMetrics(activeMembers: 99),
      ),
    );
    await initializeFuture;

    expect(state.role, UserRole.guest);
    expect(state.businessAccess, isNull);
    expect(state.businessWorkspace, isNull);
    expect(state.businessLoading, isFalse);
    expect(state.dashboardFor(UserRole.trainer).facts, isEmpty);
  });

  test(
    'remote auth sign-out immediately clears workspace and cached PII',
    () async {
      final profile = _trainerProfile();
      final access = _trainerAccess(profile: profile);
      final repository = _FakeBusinessRepository(
        access: access,
        workspaces: {
          UserRole.trainer: BusinessWorkspaceData(
            role: UserRole.trainer,
            access: access,
            profile: profile,
            dashboardStats: const BusinessDashboardMetrics(activeMembers: 1),
            members: [_member()],
          ),
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();
      await state.loadBusinessMemberDetail(_memberId);
      expect(state.businessMemberDetail(_memberId), isNotNull);

      state.handleExternalAuthSignedOut();

      expect(state.role, UserRole.guest);
      expect(state.businessAccess, isNull);
      expect(state.businessWorkspace, isNull);
      expect(state.businessMemberDetail(_memberId), isNull);
    },
  );

  test(
    'workspace refresh invalidates cached member detail consent data',
    () async {
      final profile = _trainerProfile();
      final access = _trainerAccess(profile: profile);
      final workspace = BusinessWorkspaceData(
        role: UserRole.trainer,
        access: access,
        profile: profile,
        dashboardStats: const BusinessDashboardMetrics(activeMembers: 1),
        members: [_member()],
      );
      final repository = _FakeBusinessRepository(
        access: access,
        workspaces: {UserRole.trainer: workspace},
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();
      await state.loadBusinessMemberDetail(_memberId);
      expect(state.businessMemberDetail(_memberId), isNotNull);

      await state.refreshBusinessDashboard(UserRole.trainer);

      expect(state.businessMemberDetail(_memberId), isNull);
    },
  );

  test(
    'latest role selection wins and clears loading when leaving workspace',
    () async {
      final trainer = _trainerProfile();
      final gym = _gymProfile();
      final access = BusinessAccess(
        userId: _userId,
        accountRole: UserRole.trainer,
        resolvedRole: UserRole.trainer,
        availableRoles: const {UserRole.member, UserRole.trainer, UserRole.gym},
        trainer: trainer,
        gym: gym,
      );
      final trainerWorkspace = BusinessWorkspaceData(
        role: UserRole.trainer,
        access: access,
        profile: trainer,
        dashboardStats: const BusinessDashboardMetrics(),
      );
      final gymWorkspace = BusinessWorkspaceData(
        role: UserRole.gym,
        access: access,
        profile: gym,
        dashboardStats: const BusinessDashboardMetrics(),
      );
      final trainerReload = Completer<BusinessWorkspaceData>();
      final gymLoad = Completer<BusinessWorkspaceData>();
      var trainerLoadCount = 0;
      final repository = _FakeBusinessRepository(
        access: access,
        workspaceLoader: (role) {
          if (role == UserRole.gym) return gymLoad.future;
          trainerLoadCount++;
          return trainerLoadCount == 1
              ? Future.value(trainerWorkspace)
              : trainerReload.future;
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      state.chooseRole(UserRole.gym);
      state.chooseRole(UserRole.trainer);
      expect(state.businessLoading, isTrue);
      trainerReload.complete(trainerWorkspace);
      await Future<void>.delayed(Duration.zero);
      expect(state.role, UserRole.trainer);
      expect(state.businessWorkspace?.role, UserRole.trainer);
      expect(state.businessLoading, isFalse);

      gymLoad.complete(gymWorkspace);
      await Future<void>.delayed(Duration.zero);
      expect(state.role, UserRole.trainer);
      expect(state.businessWorkspace?.role, UserRole.trainer);

      state.chooseRole(UserRole.gym);
      expect(state.businessLoading, isTrue);
      state.chooseRole(UserRole.member);
      expect(state.businessLoading, isFalse);
      expect(state.businessWorkspace, isNull);
    },
  );

  test(
    'failed refresh preserves the last good workspace and stops loading',
    () async {
      final profile = _trainerProfile();
      final access = _trainerAccess(profile: profile);
      final workspace = BusinessWorkspaceData(
        role: UserRole.trainer,
        access: access,
        profile: profile,
        dashboardStats: const BusinessDashboardMetrics(activeMembers: 3),
      );
      var shouldFail = false;
      final refreshError = StateError('refresh failed');
      final repository = _FakeBusinessRepository(
        access: access,
        workspaceLoader: (role) async {
          if (shouldFail) throw refreshError;
          return workspace;
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      final previousWorkspace = state.businessWorkspace;

      shouldFail = true;
      await expectLater(
        state.refreshBusinessDashboard(UserRole.trainer),
        throwsA(same(refreshError)),
      );

      expect(state.businessWorkspace, same(previousWorkspace));
      expect(state.businessLoading, isFalse);
      expect(state.businessError, same(refreshError));
    },
  );

  test(
    'public directory failure does not block the core business workspace',
    () async {
      final profile = _trainerProfile();
      final access = _trainerAccess(profile: profile);
      final directoryError = StateError('directory unavailable');
      final repository = _FakeBusinessRepository(
        access: access,
        publicTrainerError: directoryError,
        workspaces: {
          UserRole.trainer: BusinessWorkspaceData(
            role: UserRole.trainer,
            access: access,
            profile: profile,
            dashboardStats: const BusinessDashboardMetrics(activeMembers: 7),
          ),
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();

      expect(state.businessAccess?.userId, _userId);
      expect(state.role, UserRole.trainer);
      expect(state.businessWorkspace?.profile?.id, _trainerId);
      expect(state.businessError, same(directoryError));
      expect(state.cloudSyncError, same(directoryError));
    },
  );

  test(
    'unverified admin access fails closed to an available trainer role',
    () async {
      final profile = _trainerProfile();
      final access = BusinessAccess(
        userId: _userId,
        accountRole: UserRole.admin,
        resolvedRole: UserRole.admin,
        availableRoles: const {UserRole.admin, UserRole.trainer},
        trainer: profile,
      );
      final repository = _FakeBusinessRepository(
        access: access,
        workspaces: {
          UserRole.trainer: BusinessWorkspaceData(
            role: UserRole.trainer,
            access: access,
            profile: profile,
            dashboardStats: const BusinessDashboardMetrics(),
          ),
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();

      expect(state.isAdmin, isFalse);
      expect(state.role, UserRole.trainer);
      expect(repository.loadedWorkspaceRoles, [UserRole.trainer]);
    },
  );

  test('logout awaits sign-out and performs a final local reset', () async {
    final signOutCompleter = Completer<void>();
    final repository = _trainerRepository();
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
      authSignOut: () => signOutCompleter.future,
    );
    addTearDown(state.dispose);
    await state.initialize();

    final logoutFuture = state.logout();
    expect(state.role, UserRole.guest);
    state.setMemberProfile(goals: const ['근력 향상']);
    final syncFuture = state.syncAfterAuthentication();
    await Future<void>.delayed(Duration.zero);
    expect(repository.loadAccessCount, 1);

    signOutCompleter.complete();
    await logoutFuture;
    expect(state.goals, isEmpty);
    await syncFuture;
    expect(repository.loadAccessCount, 2);
  });

  test(
    'assigned consultation is not treated as answered without a reply',
    () async {
      final gym = _gymProfile();
      final access = BusinessAccess(
        userId: _userId,
        accountRole: UserRole.gym,
        resolvedRole: UserRole.gym,
        availableRoles: const {UserRole.gym},
        gym: gym,
      );
      final assigned = BusinessConsultation(
        id: _consultationId,
        userId: _userId,
        gymId: _gymId,
        assignedTrainerId: _trainerId,
        status: BusinessConsultationStatus.assigned,
        isRead: true,
        messages: const [],
      );
      final repository = _FakeBusinessRepository(
        access: access,
        workspaces: {
          UserRole.gym: BusinessWorkspaceData(
            role: UserRole.gym,
            access: access,
            profile: gym,
            dashboardStats: const BusinessDashboardMetrics(),
            consultations: [assigned],
          ),
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      expect(state.isBusinessConsultationAnswered(UserRole.gym, 0), isFalse);
    },
  );

  test(
    'same member mutation is deduplicated while its RPC is pending',
    () async {
      final repository = _gymRepository();
      final assignmentCompleter = Completer<BusinessMemberAssignment?>();
      repository.assignmentHandler = (_) => assignmentCompleter.future;
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final first = state.assignBusinessMemberById(
        gymId: _gymId,
        memberId: _memberId,
        trainerId: _trainerId,
      );
      final second = state.assignBusinessMemberById(
        gymId: _gymId,
        memberId: _memberId,
        trainerId: _trainerId,
      );

      expect(repository.assignmentInputs, hasLength(1));
      expect(state.hasPendingBusinessMutation, isTrue);
      expect(state.isAssigningBusinessMember(_memberId), isTrue);
      assignmentCompleter.complete(null);
      await Future.wait([first, second]);
      expect(state.isAssigningBusinessMember(_memberId), isFalse);
      expect(state.hasPendingBusinessMutation, isFalse);
    },
  );

  test(
    'ambiguous live names fail closed instead of selecting the first UUID',
    () async {
      final gym = _gymProfile();
      final access = BusinessAccess(
        userId: _userId,
        accountRole: UserRole.gym,
        resolvedRole: UserRole.gym,
        availableRoles: const {UserRole.gym},
        gym: gym,
      );
      final repository = _FakeBusinessRepository(
        access: access,
        publicTrainerRecords: [
          PublicTrainer(profile: _trainerProfile()),
          const PublicTrainer(
            profile: TrainerBusinessProfile(
              id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              userId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
              displayName: '실데이터 정코치',
              status: BusinessProfileStatus.approved,
              isPublic: true,
              verified: true,
              rating: 4.8,
              postCount: 2,
              coachingTotal: 3,
            ),
          ),
        ],
        workspaces: {
          UserRole.gym: BusinessWorkspaceData(
            role: UserRole.gym,
            access: access,
            profile: gym,
            dashboardStats: const BusinessDashboardMetrics(),
            members: [
              _member(),
              const BusinessMember(
                id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                gymId: _gymId,
                name: '실회원',
                remainingPtSessions: 4,
              ),
            ],
            trainers: const [
              GymTrainerRecord(
                id: '66666666-6666-4666-8666-666666666666',
                gymId: _gymId,
                trainerId: _trainerId,
                displayName: '실트레이너',
                status: 'active',
                memberCount: 0,
                averageRating: 0,
                monthlySales: 0,
              ),
            ],
          ),
        },
      );
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      await expectLater(
        state.assignBusinessMember(memberName: '실회원', trainerName: '실트레이너'),
        throwsA(isA<StateError>()),
      );
      expect(repository.assignmentInputs, isEmpty);

      await expectLater(
        state.addConsultation(
          trainerName: '실데이터 정코치',
          specialty: '근력',
          goal: '근력 향상',
          level: '중급',
          question: '동명이인 트레이너 중 누구에게 전달되나요?',
        ),
        throwsA(isA<StateError>()),
      );

      await state.assignBusinessMemberById(
        gymId: _gymId,
        memberId: _memberId,
        trainerId: _trainerId,
      );
      expect(repository.assignmentInputs.single.memberId, _memberId);
    },
  );

  test('catalog failure does not block live business access loading', () async {
    final catalogError = StateError('catalog unavailable');
    final state = AppState(
      businessRepository: _trainerRepository(),
      routineCatalogRepository: _FailingRoutineCatalogRepository(catalogError),
      communityRepository: _FailingCommunityRepository(
        StateError('community unavailable'),
      ),
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);

    await state.initialize();

    expect(state.businessAccess?.userId, _userId);
    expect(state.businessWorkspace?.role, UserRole.trainer);
    expect(state.marketRoutines, isEmpty);
    expect(state.communityPosts, isEmpty);
    expect(state.cloudSyncError, same(catalogError));
  });

  test('live routine input uses the requested set and rep counts', () async {
    final repository = _trainerRepository();
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();

    await state.createBusinessRoutine(
      ownerRole: UserRole.trainer,
      title: '실제 루틴',
      description: '사용자 설정 루틴',
      routineExercises: [state.exercises.first],
      setCount: 4,
      targetReps: 12,
    );

    final input = repository.routineInputs.single;
    expect(input.exercises.single.sets, hasLength(4));
    expect(input.exercises.single.sets.map((set) => set.setNumber), [
      1,
      2,
      3,
      4,
    ]);
    expect(
      input.exercises.single.sets.every((set) => set.targetReps == 12),
      isTrue,
    );
    await expectLater(
      state.createBusinessRoutine(
        ownerRole: UserRole.trainer,
        title: '잘못된 루틴',
        description: '',
        routineExercises: [state.exercises.first],
        setCount: 11,
        targetReps: 10,
      ),
      throwsArgumentError,
    );
  });

  test(
    'routine draft workflow keeps per-set type weight reps and rest values',
    () async {
      final repository = _trainerRepository();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      final saved = await state.saveBusinessRoutineDraft(
        ownerRole: UserRole.trainer,
        title: '세트 보존 루틴',
        description: '회원에게 공유할 실제 구성',
        difficulty: BusinessRoutineDifficulty.advanced,
        routineExercises: const [
          CreateOwnedRoutineExerciseInput(
            name: '바벨 벤치 프레스',
            targetMuscle: '가슴',
            sets: [
              CreateOwnedRoutineSetInput(
                setNumber: 1,
                type: 'warmup',
                targetWeight: 20,
                targetReps: 12,
                restSeconds: 45,
              ),
              CreateOwnedRoutineSetInput(
                setNumber: 2,
                type: 'normal',
                targetWeight: 80,
                targetReps: 8,
                restSeconds: 120,
              ),
              CreateOwnedRoutineSetInput(
                setNumber: 3,
                type: 'failure',
                targetWeight: 75,
                targetReps: 7,
                restSeconds: 180,
              ),
            ],
          ),
        ],
      );

      final input = repository.routineInputs.last;
      expect(input.title, '세트 보존 루틴');
      expect(input.exercises.single.sets.map((set) => set.type), [
        'warmup',
        'normal',
        'failure',
      ]);
      expect(input.exercises.single.sets.map((set) => set.targetWeight), [
        20,
        80,
        75,
      ]);
      expect(input.exercises.single.sets.map((set) => set.targetReps), [
        12,
        8,
        7,
      ]);
      expect(input.exercises.single.sets.map((set) => set.restSeconds), [
        45,
        120,
        180,
      ]);

      await state.submitBusinessRoutineForReview(saved.id);
      await state.shareBusinessRoutine(
        routineId: saved.id,
        memberIds: const [_memberId],
        message: '다음 수업 전까지 진행해주세요.',
      );
      expect(repository.routineShareInputs.single.memberIds, [_memberId]);
      expect(repository.routineShareInputs.single.message, contains('다음 수업'));
    },
  );

  test(
    'routine RPC retries reuse one request id per operation and payload',
    () async {
      final repository = _trainerRepository();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      Future<OwnedCoachingRoutine> createRoutine() =>
          state.createBusinessRoutine(
            ownerRole: UserRole.trainer,
            title: ' 멱등 근력 루틴 ',
            description: ' 응답 유실 재시도 ',
            routineExercises: [state.exercises.first],
            setCount: 3,
            targetReps: 8,
          );

      repository.rpcResponseLossesRemaining['routine-create'] = 1;
      final lostCreate = createRoutine();
      final duplicateCreate = createRoutine();
      await Future.wait([
        expectLater(lostCreate, throwsA(isA<TimeoutException>())),
        expectLater(duplicateCreate, throwsA(isA<TimeoutException>())),
      ]);
      expect(repository.routineInputs, hasLength(1));
      final created = await createRoutine();
      expect(repository.routineInputs, hasLength(2));
      expect(repository.routineInputs[0].requestId, isNotNull);
      expect(
        repository.routineInputs[1].requestId,
        repository.routineInputs[0].requestId,
      );

      await createRoutine();
      expect(repository.routineInputs, hasLength(3));
      expect(
        repository.routineInputs[2].requestId,
        isNot(repository.routineInputs[1].requestId),
      );

      const draftExercises = [
        CreateOwnedRoutineExerciseInput(
          name: '바벨 벤치 프레스',
          targetMuscle: '가슴',
          sets: [
            CreateOwnedRoutineSetInput(
              setNumber: 1,
              targetWeight: 80,
              targetReps: 8,
              restSeconds: 120,
            ),
          ],
        ),
      ];
      Future<OwnedCoachingRoutine> updateRoutine() =>
          state.saveBusinessRoutineDraft(
            ownerRole: UserRole.trainer,
            title: '수정 루틴',
            description: '동일 payload',
            difficulty: BusinessRoutineDifficulty.intermediate,
            routineExercises: draftExercises,
            existing: created,
          );
      repository.rpcResponseLossesRemaining['routine-update'] = 1;
      await expectLater(updateRoutine(), throwsA(isA<TimeoutException>()));
      await updateRoutine();
      expect(repository.routineUpdateInputs, hasLength(2));
      expect(
        repository.routineUpdateInputs[1].requestId,
        repository.routineUpdateInputs[0].requestId,
      );

      repository.rpcResponseLossesRemaining['routine-submit'] = 1;
      await expectLater(
        state.submitBusinessRoutineForReview(created.id),
        throwsA(isA<TimeoutException>()),
      );
      await state.submitBusinessRoutineForReview(created.id);
      expect(repository.routineSubmitRequestIds, hasLength(2));
      expect(
        repository.routineSubmitRequestIds[1],
        repository.routineSubmitRequestIds[0],
      );

      repository.rpcResponseLossesRemaining['routine-review'] = 1;
      Future<OwnedCoachingRoutine> reviewRoutine() =>
          state.reviewBusinessRoutine(
            routineId: created.id,
            approve: false,
            rejectReason: ' 세트 구성을 보완해주세요. ',
            accessTier: RoutineAccessTier.paid,
          );
      await expectLater(reviewRoutine(), throwsA(isA<TimeoutException>()));
      await reviewRoutine();
      expect(repository.routineReviewInputs, hasLength(2));
      expect(
        repository.routineReviewInputs[1].requestId,
        repository.routineReviewInputs[0].requestId,
      );
      expect(repository.routineReviewInputs[0].rejectReason, '세트 구성을 보완해주세요.');

      final shareExpiry = DateTime.utc(2026, 8, 30, 12);
      Future<List<RoutineShareRecord>> shareRoutine() =>
          state.shareBusinessRoutine(
            routineId: created.id,
            memberIds: const [
              'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              _memberId,
              _memberId,
            ],
            message: ' 다음 세션 전까지 진행 ',
            expiresAt: shareExpiry,
          );
      repository.rpcResponseLossesRemaining['routine-share'] = 1;
      await expectLater(shareRoutine(), throwsA(isA<TimeoutException>()));
      await shareRoutine();
      expect(repository.routineShareInputs, hasLength(2));
      expect(
        repository.routineShareInputs[1].requestId,
        repository.routineShareInputs[0].requestId,
      );
      expect(repository.routineShareInputs[0].memberIds, [
        _memberId,
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ]);

      Future<PersonalRoutineRecord?> declineShare() =>
          state.respondToRoutineShare(
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            accept: false,
          );
      repository.rpcResponseLossesRemaining['routine-respond'] = 1;
      await expectLater(declineShare(), throwsA(isA<TimeoutException>()));
      await declineShare();
      expect(repository.routineResponseInputs, hasLength(2));
      expect(
        repository.routineResponseInputs[1].$3,
        repository.routineResponseInputs[0].$3,
      );

      repository.personalRoutines = [_sharedPersonalRoutine(_userId)];
      Future<PersonalRoutineRecord> acceptToken() =>
          state.acceptRoutineShareToken(' opaque-token ');
      repository.rpcResponseLossesRemaining['routine-token'] = 1;
      await expectLater(acceptToken(), throwsA(isA<TimeoutException>()));
      await acceptToken();
      expect(repository.acceptedRoutineTokenInputs, hasLength(2));
      expect(
        repository.acceptedRoutineTokenInputs[1].$2,
        repository.acceptedRoutineTokenInputs[0].$2,
      );

      final marketRoutine = RoutineData(
        id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        name: '마켓 멱등 루틴',
        description: '',
        color: Colors.teal,
        exercises: [state.exercises.first],
        sourceMarketRoutineId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      );
      Future<RoutineImportResult> importRoutine() =>
          state.importMarketRoutine(marketRoutine);
      repository.rpcResponseLossesRemaining['routine-import'] = 1;
      await expectLater(importRoutine(), throwsA(isA<TimeoutException>()));
      expect(await importRoutine(), RoutineImportResult.imported);
      expect(repository.importedMarketRoutineInputs, hasLength(2));
      expect(
        repository.importedMarketRoutineInputs[1].$2,
        repository.importedMarketRoutineInputs[0].$2,
      );
    },
  );

  test(
    'uncertain one-time link result blocks automatic retry until confirmation',
    () async {
      final repository = _trainerRepository();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      final expiresAt = DateTime.utc(2026, 8, 30, 12);
      repository.rpcResponseLossesRemaining['routine-link'] = 1;

      await expectLater(
        state.createBusinessRoutineShareLink(
          'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          expiresAt: expiresAt,
        ),
        throwsA(isA<RoutineShareLinkResultUncertainException>()),
      );
      expect(repository.routineLinkInputs, hasLength(1));

      await expectLater(
        state.createBusinessRoutineShareLink(
          'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          expiresAt: expiresAt,
        ),
        throwsA(isA<RoutineShareLinkResultUncertainException>()),
      );
      expect(repository.routineLinkInputs, hasLength(1));

      final link = await state.createBusinessRoutineShareLink(
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        expiresAt: expiresAt,
        confirmCreateNewAfterUncertainResult: true,
      );
      expect(link.token, 'test-token');
      expect(repository.routineLinkInputs, hasLength(2));
      expect(
        repository.routineLinkInputs[1].$3,
        isNot(repository.routineLinkInputs[0].$3),
      );
    },
  );

  test(
    'different link response and token payloads keep independent mutations',
    () async {
      final repository = _trainerRepository();
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      repository.personalRoutines = [_sharedPersonalRoutine(_userId)];
      const routineId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

      await Future.wait([
        state.createBusinessRoutineShareLink(
          routineId,
          expiresAt: DateTime.utc(2026, 8, 28, 12),
        ),
        state.createBusinessRoutineShareLink(
          routineId,
          expiresAt: DateTime.utc(2026, 8, 29, 12),
        ),
      ]);
      expect(repository.routineLinkInputs, hasLength(2));
      expect(
        repository.routineLinkInputs.map((input) => input.$3).toSet(),
        hasLength(2),
      );

      const shareId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      await Future.wait([
        state.respondToRoutineShare(shareId, accept: false),
        state.respondToRoutineShare(shareId, accept: true),
      ]);
      expect(repository.routineResponseInputs, hasLength(2));
      expect(repository.routineResponseInputs.map((input) => input.$2), {
        false,
        true,
      });
      expect(
        repository.routineResponseInputs.map((input) => input.$3).toSet(),
        hasLength(2),
      );

      await Future.wait([
        state.acceptRoutineShareToken('first-opaque-token'),
        state.acceptRoutineShareToken('second-opaque-token'),
      ]);
      expect(repository.acceptedRoutineTokenInputs, hasLength(2));
      expect(repository.acceptedRoutineTokenInputs.map((input) => input.$1), {
        'first-opaque-token',
        'second-opaque-token',
      });
      expect(
        repository.acceptedRoutineTokenInputs.map((input) => input.$2).toSet(),
        hasLength(2),
      );
    },
  );

  test('account transition discards a failed routine request id', () async {
    final repository = _trainerRepository();
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();
    repository.personalRoutines = [_sharedPersonalRoutine(_userId)];
    final marketRoutine = RoutineData(
      id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      name: '계정 전환 루틴',
      description: '',
      color: Colors.teal,
      exercises: [state.exercises.first],
      sourceMarketRoutineId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    );
    repository.rpcResponseLossesRemaining['routine-import'] = 1;

    await expectLater(
      state.importMarketRoutine(marketRoutine),
      throwsA(isA<TimeoutException>()),
    );
    final oldRequestId = repository.importedMarketRoutineInputs.single.$2;
    state.handleExternalAuthSignedOut();
    expect(
      await state.importMarketRoutine(marketRoutine),
      RoutineImportResult.imported,
    );

    expect(repository.importedMarketRoutineInputs, hasLength(2));
    expect(repository.importedMarketRoutineInputs[1].$2, isNot(oldRequestId));
  });

  test(
    'share token acceptance creates a personal routine and exact calendar sets',
    () async {
      const memberUserId = '88888888-8888-4888-8888-888888888888';
      final access = const BusinessAccess(
        userId: memberUserId,
        accountRole: UserRole.member,
        resolvedRole: UserRole.member,
        availableRoles: {UserRole.member},
      );
      final repository = _FakeBusinessRepository(access: access);
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();

      repository.personalRoutines = [_sharedPersonalRoutine(memberUserId)];
      final uri = Uri.parse(
        'com.setflow.setflow://routine-share/opaque-share-token',
      );
      state.captureRoutineShareUri(uri);
      expect(state.pendingRoutineShareToken, 'opaque-share-token');
      final targetDate = DateTime(2026, 8, 20);
      await state.acceptRoutineShareToken(
        uri.toString(),
        applyDate: targetDate,
      );

      expect(repository.acceptedRoutineTokens, ['opaque-share-token']);
      expect(state.pendingRoutineShareToken, isNull);
      final imported = state.routines.firstWhere(
        (routine) => routine.id == 'personal-routine-1',
      );
      expect(imported.sourceCoachingRoutineId, 'coaching-routine-1');
      final sets = state.sessions[targetDate]!.exercises.single.sets;
      expect(sets.map((set) => set.weight), [20, 82.5, 70]);
      expect(sets.map((set) => set.reps), [12, 8, 10]);
      expect(sets.map((set) => set.type), ['웜업', '일반', '드랍']);
      expect(sets.map((set) => set.restSeconds), [45, 120, 30]);
    },
  );

  test(
    'server personal routine edit persists normalized data and preserves only known base UUIDs',
    () async {
      const memberUserId = '88888888-8888-4888-8888-888888888888';
      final repository = _FakeBusinessRepository(
        access: const BusinessAccess(
          userId: memberUserId,
          accountRole: UserRole.member,
          resolvedRole: UserRole.member,
          availableRoles: {UserRole.member},
        ),
      )..personalRoutines = [_serverPersonalRoutine(memberUserId)];
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      final routine = state.routines.singleWhere(
        (item) => item.id == _personalRoutineId,
      );

      expect(
        await state.updateRoutine(
          routine: routine,
          name: '수정한 공유 루틴',
          description: '정규화 저장 확인',
          exercises: [state.exercises.first, state.exercises[1]],
        ),
        isTrue,
      );

      final input = repository.personalRoutineSaveInputs.single;
      expect(input.requestId, isNotNull);
      expect(input.name, '수정한 공유 루틴');
      expect(input.exercises.first.baseExerciseId, _baseExerciseId);
      expect(input.exercises[1].baseExerciseId, isNull);
      expect(
        input.exercises.every((exercise) => exercise.sets.isNotEmpty),
        isTrue,
      );
      expect(
        state.routines
            .singleWhere((item) => item.id == _personalRoutineId)
            .name,
        '수정한 공유 루틴',
      );
    },
  );

  test('personal routine save retries with the same request ID', () async {
    const memberUserId = '88888888-8888-4888-8888-888888888888';
    final repository =
        _FakeBusinessRepository(
            access: const BusinessAccess(
              userId: memberUserId,
              accountRole: UserRole.member,
              resolvedRole: UserRole.member,
              availableRoles: {UserRole.member},
            ),
          )
          ..personalRoutines = [_serverPersonalRoutine(memberUserId)]
          ..personalRoutineSaveFailuresRemaining = 1;
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();
    final routine = state.routines.singleWhere(
      (item) => item.id == _personalRoutineId,
    );

    Future<bool> save() => state.updateRoutine(
      routine: routine,
      name: '재시도 루틴',
      description: '동일 요청 ID',
      exercises: routine.exercises,
    );

    await expectLater(save(), throwsA(isA<TimeoutException>()));
    expect(await save(), isTrue);
    expect(repository.personalRoutineSaveInputs, hasLength(2));
    expect(
      repository.personalRoutineSaveInputs[0].requestId,
      repository.personalRoutineSaveInputs[1].requestId,
    );
  });

  test('normalized personal routine edit survives a fresh app login', () async {
    const memberUserId = '88888888-8888-4888-8888-888888888888';
    final repository = _FakeBusinessRepository(
      access: const BusinessAccess(
        userId: memberUserId,
        accountRole: UserRole.member,
        resolvedRole: UserRole.member,
        availableRoles: {UserRole.member},
      ),
    )..personalRoutines = [_serverPersonalRoutine(memberUserId)];
    final firstState = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    await firstState.initialize();
    final routine = firstState.routines.singleWhere(
      (item) => item.id == _personalRoutineId,
    );
    expect(
      await firstState.updateRoutine(
        routine: routine,
        name: '재로그인 유지 루틴',
        description: '정규화 데이터가 기준',
        exercises: routine.exercises,
      ),
      isTrue,
    );
    firstState.dispose();

    final secondState = AppState(
      repository: MemoryAppRepository(
        initialSnapshot: AppSnapshot(
          role: UserRole.member,
          isDarkMode: false,
          weightUnit: 'kg',
          restDefaultSeconds: 90,
          sessions: const {},
          routines: [
            RoutineData(
              id: _personalRoutineId,
              name: '오래된 로컬 이름',
              description: 'stale snapshot',
              color: const Color(0xFF10CEBD),
              exercises: const [],
            ),
          ],
        ),
      ),
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(secondState.dispose);
    await secondState.initialize();

    expect(
      secondState.routines
          .singleWhere((item) => item.id == _personalRoutineId)
          .name,
      '재로그인 유지 루틴',
    );
  });

  test(
    'successful server deletion and empty authoritative refresh do not restore a routine',
    () async {
      const memberUserId = '88888888-8888-4888-8888-888888888888';
      final repository = _FakeBusinessRepository(
        access: const BusinessAccess(
          userId: memberUserId,
          accountRole: UserRole.member,
          resolvedRole: UserRole.member,
          availableRoles: {UserRole.member},
        ),
      )..personalRoutines = [_serverPersonalRoutine(memberUserId)];
      final state = AppState(
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      final routine = state.routines.singleWhere(
        (item) => item.id == _personalRoutineId,
      );

      expect(await state.removeRoutine(routine), isTrue);
      await state.refreshBusinessDashboard(UserRole.member);

      expect(
        repository.personalRoutineDeleteInputs.single.$1,
        _personalRoutineId,
      );
      expect(repository.personalRoutineDeleteInputs.single.$2, isNotNull);
      expect(
        state.routines.where((item) => item.id == _personalRoutineId),
        isEmpty,
      );
    },
  );

  test('personal routine delete retries with the same request ID', () async {
    const memberUserId = '88888888-8888-4888-8888-888888888888';
    final repository =
        _FakeBusinessRepository(
            access: const BusinessAccess(
              userId: memberUserId,
              accountRole: UserRole.member,
              resolvedRole: UserRole.member,
              availableRoles: {UserRole.member},
            ),
          )
          ..personalRoutines = [_serverPersonalRoutine(memberUserId)]
          ..personalRoutineDeleteFailuresRemaining = 1;
    final state = AppState(
      businessRepository: repository,
      loadBusinessWithoutAuth: true,
    );
    addTearDown(state.dispose);
    await state.initialize();
    final routine = state.routines.singleWhere(
      (item) => item.id == _personalRoutineId,
    );

    await expectLater(
      state.removeRoutine(routine),
      throwsA(isA<TimeoutException>()),
    );
    expect(await state.removeRoutine(routine), isTrue);

    expect(repository.personalRoutineDeleteInputs, hasLength(2));
    expect(
      repository.personalRoutineDeleteInputs[0].$2,
      repository.personalRoutineDeleteInputs[1].$2,
    );
  });

  test(
    'empty normalized list removes a stale UUID routine from snapshot',
    () async {
      const memberUserId = '88888888-8888-4888-8888-888888888888';
      final staleRoutine = RoutineData(
        id: _personalRoutineId,
        name: '삭제 전 이름',
        description: '오래된 snapshot',
        color: const Color(0xFF10CEBD),
        exercises: const [],
      );
      final repository = _FakeBusinessRepository(
        access: const BusinessAccess(
          userId: memberUserId,
          accountRole: UserRole.member,
          resolvedRole: UserRole.member,
          availableRoles: {UserRole.member},
        ),
      );
      final state = AppState(
        repository: MemoryAppRepository(
          initialSnapshot: AppSnapshot(
            role: UserRole.member,
            isDarkMode: false,
            weightUnit: 'kg',
            restDefaultSeconds: 90,
            sessions: const {},
            routines: [staleRoutine],
          ),
        ),
        businessRepository: repository,
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);

      await state.initialize();

      expect(
        state.routines.where((item) => item.id == _personalRoutineId),
        isEmpty,
      );
    },
  );
}

_FakeBusinessRepository _trainerRepository() {
  final profile = _trainerProfile();
  final access = _trainerAccess(profile: profile);
  final member = _member();
  return _FakeBusinessRepository(
    access: access,
    workspaces: {
      UserRole.trainer: BusinessWorkspaceData(
        role: UserRole.trainer,
        access: access,
        profile: profile,
        dashboardStats: const BusinessDashboardMetrics(
          unreadConsultations: 1,
          activeMembers: 1,
          pendingSettlement: 320000,
          monthSettled: 1280000,
          overdueFeedbacks: 1,
        ),
        members: [member],
        consultations: [_consultation(trainerName: profile.displayName)],
      ),
    },
  );
}

_FakeBusinessRepository _gymRepository() {
  final gym = _gymProfile();
  final access = BusinessAccess(
    userId: _userId,
    email: 'gym@example.com',
    accountRole: UserRole.gym,
    resolvedRole: UserRole.gym,
    availableRoles: const {UserRole.gym},
    gym: gym,
  );
  return _FakeBusinessRepository(
    access: access,
    workspaces: {
      UserRole.gym: BusinessWorkspaceData(
        role: UserRole.gym,
        access: access,
        profile: gym,
        dashboardStats: const BusinessDashboardMetrics(
          unreadConsultations: 1,
          activeMembers: 1,
          totalRevenue: 950000,
          trainerCount: 1,
        ),
        members: [_member()],
        trainers: const [
          GymTrainerRecord(
            id: '66666666-6666-4666-8666-666666666666',
            gymId: _gymId,
            trainerId: _trainerId,
            trainerUserId: '77777777-7777-4777-8777-777777777777',
            displayName: '실트레이너',
            status: 'active',
            memberCount: 1,
            averageRating: 4.9,
            monthlySales: 950000,
          ),
        ],
        consultations: [_consultation(gymName: gym.name)],
      ),
    },
  );
}

BusinessAccess _trainerAccess({TrainerBusinessProfile? profile}) {
  return BusinessAccess(
    userId: _userId,
    email: 'trainer@example.com',
    accountRole: UserRole.trainer,
    resolvedRole: UserRole.trainer,
    availableRoles: const {UserRole.trainer},
    trainer: profile,
  );
}

TrainerBusinessProfile _trainerProfile() {
  return const TrainerBusinessProfile(
    id: _trainerId,
    userId: _userId,
    displayName: '실데이터 정코치',
    keyword: '근력 향상',
    status: BusinessProfileStatus.approved,
    isPublic: true,
    verified: true,
    rating: 4.9,
    postCount: 8,
    coachingTotal: 17,
  );
}

GymBusinessProfile _gymProfile() {
  return const GymBusinessProfile(
    id: _gymId,
    ownerUserId: _userId,
    name: '실데이터 센터',
    status: BusinessProfileStatus.verified,
    address: '서울시 실제로 1',
    businessNumber: '1234567890',
    planTier: 'enterprise',
  );
}

BusinessMember _member() {
  return const BusinessMember(
    id: _memberId,
    gymId: _gymId,
    userId: '88888888-8888-4888-8888-888888888888',
    name: '실회원',
    goal: '근력 향상',
    level: '중급',
    remainingPtSessions: 8,
  );
}

BusinessConsultation _consultation({String? trainerName, String? gymName}) {
  return BusinessConsultation(
    id: _consultationId,
    userId: '88888888-8888-4888-8888-888888888888',
    trainerId: trainerName == null ? null : _trainerId,
    gymId: gymName == null ? null : _gymId,
    status: BusinessConsultationStatus.pending,
    isRead: false,
    memberName: '실회원',
    trainerName: trainerName,
    gymName: gymName,
    goal: '근력 향상',
    level: '중급',
    question: '다음 운동 중량을 어떻게 올릴까요?',
    messages: const [],
  );
}

PersonalRoutineRecord _sharedPersonalRoutine(String ownerUserId) {
  return PersonalRoutineRecord(
    id: 'personal-routine-1',
    ownerUserId: ownerUserId,
    name: '공유 벤치 루틴',
    description: '트레이너가 설정한 세트',
    source: 'trainer_share',
    sourceCoachingRoutineId: 'coaching-routine-1',
    exercises: const [
      OwnedRoutineExercise(
        id: 'shared-exercise-1',
        routineId: 'personal-routine-1',
        name: '벤치 프레스',
        targetMuscle: '가슴',
        orderIndex: 0,
        sets: [
          OwnedRoutineSet(
            id: 'shared-set-1',
            exerciseId: 'shared-exercise-1',
            setNumber: 1,
            type: 'warmup',
            targetWeight: 20,
            targetReps: 12,
            restSeconds: 45,
          ),
          OwnedRoutineSet(
            id: 'shared-set-2',
            exerciseId: 'shared-exercise-1',
            setNumber: 2,
            type: 'normal',
            targetWeight: 82.5,
            targetReps: 8,
            restSeconds: 120,
          ),
          OwnedRoutineSet(
            id: 'shared-set-3',
            exerciseId: 'shared-exercise-1',
            setNumber: 3,
            type: 'drop',
            targetWeight: 70,
            targetReps: 10,
            restSeconds: 30,
          ),
        ],
      ),
    ],
  );
}

PersonalRoutineRecord _serverPersonalRoutine(String ownerUserId) {
  const exerciseId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  return PersonalRoutineRecord(
    id: _personalRoutineId,
    ownerUserId: ownerUserId,
    name: '서버 공유 루틴',
    description: '수정 가능한 개인 사본',
    color: '#10CEBD',
    source: 'copy',
    sourceCoachingRoutineId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    exercises: const [
      OwnedRoutineExercise(
        id: exerciseId,
        routineId: _personalRoutineId,
        baseExerciseId: _baseExerciseId,
        name: '바벨 벤치 프레스',
        targetMuscle: '가슴',
        orderIndex: 0,
        sets: [
          OwnedRoutineSet(
            id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            exerciseId: exerciseId,
            setNumber: 1,
            type: 'normal',
            targetWeight: 80,
            targetReps: 8,
            restSeconds: 120,
          ),
        ],
      ),
    ],
  );
}

class _FakeBusinessRepository implements BusinessRepository {
  _FakeBusinessRepository({
    required this.access,
    this.workspaces = const {},
    this.workspaceError,
    this.workspaceLoader,
    this.publicTrainerRecords = const [],
    this.publicTrainerError,
  });

  final BusinessAccess access;
  final Map<UserRole, BusinessWorkspaceData> workspaces;
  final Object? workspaceError;
  final Future<BusinessWorkspaceData> Function(UserRole role)? workspaceLoader;
  final List<PublicTrainer> publicTrainerRecords;
  final Object? publicTrainerError;
  List<BusinessCoachingSchedule> scheduleRecords = const [];
  final List<CreateCoachingScheduleInput> scheduleInputs = [];
  int loadAccessCount = 0;
  final List<UserRole> loadedWorkspaceRoles = [];
  final List<AssignMemberInput> assignmentInputs = [];
  final List<AssignConsultationInput> consultationAssignmentInputs = [];
  final List<ReplyConsultationInput> replyInputs = [];
  final List<CreateOwnedRoutineInput> routineInputs = [];
  final List<UpdateOwnedRoutineInput> routineUpdateInputs = [];
  final List<String?> routineSubmitRequestIds = [];
  final List<ReviewOwnedRoutineInput> routineReviewInputs = [];
  final List<ShareOwnedRoutineInput> routineShareInputs = [];
  final List<(String, DateTime?, String?)> routineLinkInputs = [];
  final List<String> routineResponseIds = [];
  final List<(String, bool, String?)> routineResponseInputs = [];
  final List<String> acceptedRoutineTokens = [];
  final List<(String, String?)> acceptedRoutineTokenInputs = [];
  final List<String> importedMarketRoutineIds = [];
  final List<(String, String?)> importedMarketRoutineInputs = [];
  final List<SavePersonalRoutineInput> personalRoutineSaveInputs = [];
  final List<(String, String?)> personalRoutineDeleteInputs = [];
  final Map<String, int> rpcResponseLossesRemaining = {};
  int personalRoutineSaveFailuresRemaining = 0;
  int personalRoutineDeleteFailuresRemaining = 0;
  List<OwnedCoachingRoutine> routineReviews = const [];
  List<RoutineShareRecord> incomingRoutineShares = const [];
  List<RoutineShareRecord> outgoingRoutineShares = const [];
  List<PersonalRoutineRecord> personalRoutines = const [];
  Future<BusinessMemberAssignment?> Function(AssignMemberInput input)?
  assignmentHandler;

  @override
  Future<BusinessAccess> loadAccess() async {
    loadAccessCount++;
    return access;
  }

  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async {
    loadedWorkspaceRoles.add(role);
    final loader = workspaceLoader;
    if (loader != null) return loader(role);
    final error = workspaceError;
    if (error != null) throw error;
    final workspace = workspaces[role];
    if (workspace == null) throw StateError('workspace missing for $role');
    return workspace;
  }

  @override
  Future<List<PublicTrainer>> listPublicTrainers() async {
    final error = publicTrainerError;
    if (error != null) throw error;
    return publicTrainerRecords;
  }

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
  Future<MemberSharingPreferences> updateMySharingPreferences(
    MemberSharingPreferences preferences,
  ) async => preferences;

  @override
  Future<BusinessMemberAssignment?> assignMember(
    AssignMemberInput input,
  ) async {
    assignmentInputs.add(input);
    final handler = assignmentHandler;
    if (handler != null) return handler(input);
    if (input.trainerId == null) return null;
    return BusinessMemberAssignment(
      id: '99999999-9999-4999-8999-999999999999',
      gymId: input.gymId,
      memberId: input.memberId,
      trainerId: input.trainerId,
      trainerName: '실트레이너',
      active: true,
    );
  }

  @override
  Future<BusinessInviteCreation> createBusinessInvite(
    CreateBusinessInviteInput input,
  ) async => throw UnimplementedError();

  @override
  Future<List<BusinessInviteRecord>> listBusinessInvites(
    String gymId, {
    BusinessInviteStatus? status,
  }) async => const [];

  @override
  Future<BusinessInviteAcceptance> acceptBusinessInvite(
    String token, {
    required String requestId,
  }) async => throw UnimplementedError();

  @override
  Future<BusinessInviteRecord> revokeBusinessInvite(
    String inviteId, {
    required String requestId,
  }) async => throw UnimplementedError();

  @override
  Future<BusinessMemberDetail> loadMemberDetail(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async => BusinessMemberDetail(
    memberId: memberId,
    memberUserId: _member().userId,
    shareBodyData: false,
    canReadWorkouts: false,
    sessions: const [],
  );

  @override
  Future<BusinessSessionFeedback> sendSessionFeedback(
    SendSessionFeedbackInput input,
  ) async => BusinessSessionFeedback(
    id: 'abababab-abab-4bab-8bab-abababababab',
    sessionId: input.sessionId,
    trainerUserId: _userId,
    authorName: '실트레이너',
    text: input.text,
    createdAt: DateTime(2026, 8, 16),
  );

  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => scheduleRecords
      .where(
        (item) =>
            (from == null || !item.date.isBefore(from)) &&
            (to == null || !item.date.isAfter(to)),
      )
      .toList(growable: false);

  @override
  Future<BusinessCoachingSchedule> createCoachingSchedule(
    CreateCoachingScheduleInput input,
  ) async {
    scheduleInputs.add(input);
    final created = BusinessCoachingSchedule(
      id: '12121212-1212-4212-8212-121212121212',
      trainerId: input.trainerId,
      memberUserId: input.memberUserId,
      gymId: input.gymId,
      title: input.title,
      date: input.date,
      startMinutes: input.startMinutes,
      endMinutes: input.endMinutes,
      createdAt: DateTime(2026, 8, 16),
    );
    scheduleRecords = [...scheduleRecords, created];
    return created;
  }

  @override
  Future<BusinessCoachingSchedule> setCoachingScheduleCompleted(
    String scheduleId, {
    required String trainerId,
    required bool completed,
  }) async {
    final current = scheduleRecords.firstWhere((item) => item.id == scheduleId);
    final updated = BusinessCoachingSchedule(
      id: current.id,
      trainerId: current.trainerId,
      memberUserId: current.memberUserId,
      gymId: current.gymId,
      title: current.title,
      date: current.date,
      startMinutes: current.startMinutes,
      endMinutes: current.endMinutes,
      createdAt: current.createdAt,
      completedAt: completed ? DateTime(2026, 8, 16, 12) : null,
    );
    scheduleRecords = [
      for (final item in scheduleRecords)
        if (item.id == scheduleId) updated else item,
    ];
    return updated;
  }

  @override
  Future<void> deleteCoachingSchedule(
    String scheduleId, {
    required String trainerId,
  }) async {
    scheduleRecords = scheduleRecords
        .where((item) => item.id != scheduleId)
        .toList(growable: false);
  }

  @override
  Future<BusinessConsultation> replyConsultation(
    ReplyConsultationInput input,
  ) async {
    replyInputs.add(input);
    final current = workspaces.values
        .expand((workspace) => workspace.consultations)
        .firstWhere((item) => item.id == input.consultationId);
    return BusinessConsultation(
      id: current.id,
      userId: current.userId,
      trainerId: current.trainerId,
      gymId: current.gymId,
      routineId: current.routineId,
      assignedTrainerId: current.assignedTrainerId,
      status: BusinessConsultationStatus.replied,
      isRead: true,
      memberName: current.memberName,
      memberAvatarUrl: current.memberAvatarUrl,
      trainerName: current.trainerName,
      gymName: current.gymName,
      goal: current.goal,
      level: current.level,
      question: current.question,
      createdAt: current.createdAt,
      messages: [
        ...current.messages,
        BusinessConsultationMessage(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          consultationId: current.id,
          sender: BusinessMessageSender.gym,
          text: input.message,
        ),
      ],
    );
  }

  @override
  Future<BusinessConsultation> assignConsultation(
    AssignConsultationInput input,
  ) async {
    consultationAssignmentInputs.add(input);
    final current = workspaces.values
        .expand((workspace) => workspace.consultations)
        .firstWhere((item) => item.id == input.consultationId);
    return BusinessConsultation(
      id: current.id,
      userId: current.userId,
      trainerId: current.trainerId,
      gymId: current.gymId,
      routineId: current.routineId,
      assignedTrainerId: input.trainerId,
      status: BusinessConsultationStatus.assigned,
      isRead: true,
      memberName: current.memberName,
      memberAvatarUrl: current.memberAvatarUrl,
      trainerName: current.trainerName,
      gymName: current.gymName,
      specialty: current.specialty,
      goal: current.goal,
      level: current.level,
      question: current.question,
      createdAt: current.createdAt,
      messages: current.messages,
    );
  }

  @override
  Future<BusinessConsultation> createConsultation(
    CreateConsultationInput input,
  ) async => throw UnimplementedError();

  @override
  Future<OwnedCoachingRoutine> createOwnedRoutine(
    CreateOwnedRoutineInput input,
  ) async {
    routineInputs.add(input);
    _throwLostRpcResponseIfNeeded('routine-create');
    return OwnedCoachingRoutine(
      id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      trainerId: _trainerId,
      title: input.title,
      intro: input.intro,
      status: BusinessRoutineStatus.draft,
      difficulty: input.difficulty,
      cumulativeUsers: 0,
      exercises: const [],
    );
  }

  @override
  Future<OwnedCoachingRoutine> updateOwnedRoutine(
    UpdateOwnedRoutineInput input,
  ) async {
    routineUpdateInputs.add(input);
    _throwLostRpcResponseIfNeeded('routine-update');
    return _ownedRoutineFromInput(
      id: input.routineId,
      title: input.title,
      intro: input.intro,
      difficulty: input.difficulty,
      exercises: input.exercises,
    );
  }

  @override
  Future<OwnedCoachingRoutine> submitOwnedRoutineForReview(
    String routineId, {
    String? requestId,
  }) async {
    routineSubmitRequestIds.add(requestId);
    _throwLostRpcResponseIfNeeded('routine-submit');
    return OwnedCoachingRoutine(
      id: routineId,
      trainerId: _trainerId,
      title: '심사 루틴',
      status: BusinessRoutineStatus.review,
      difficulty: BusinessRoutineDifficulty.intermediate,
      cumulativeUsers: 0,
      exercises: const [],
    );
  }

  @override
  Future<List<OwnedCoachingRoutine>> listRoutineReviews() async =>
      routineReviews;

  @override
  Future<OwnedCoachingRoutine> reviewOwnedRoutine(
    ReviewOwnedRoutineInput input,
  ) async {
    routineReviewInputs.add(input);
    _throwLostRpcResponseIfNeeded('routine-review');
    return OwnedCoachingRoutine(
      id: input.routineId,
      trainerId: _trainerId,
      title: '심사 루틴',
      status: input.approve
          ? BusinessRoutineStatus.approved
          : BusinessRoutineStatus.rejected,
      difficulty: BusinessRoutineDifficulty.intermediate,
      cumulativeUsers: 0,
      rejectReason: input.rejectReason,
      exercises: const [],
    );
  }

  @override
  Future<List<RoutineShareRecord>> shareOwnedRoutine(
    ShareOwnedRoutineInput input,
  ) async {
    routineShareInputs.add(input);
    _throwLostRpcResponseIfNeeded('routine-share');
    return outgoingRoutineShares;
  }

  @override
  Future<RoutineShareLink> createRoutineShareLink(
    String routineId, {
    DateTime? expiresAt,
    String? requestId,
  }) async {
    routineLinkInputs.add((routineId, expiresAt, requestId));
    if ((rpcResponseLossesRemaining['routine-link'] ?? 0) > 0) {
      rpcResponseLossesRemaining['routine-link'] =
          rpcResponseLossesRemaining['routine-link']! - 1;
      throw const RoutineShareLinkResultUncertainException();
    }
    return RoutineShareLink(
      shareId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      token: 'test-token',
      uri: Uri.parse('com.setflow.setflow://routine-share/test-token'),
      expiresAt: expiresAt ?? DateTime(2026, 9),
    );
  }

  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async =>
      incomingRoutineShares;

  @override
  Future<List<RoutineShareRecord>> listOutgoingRoutineShares({
    String? routineId,
  }) async => outgoingRoutineShares
      .where((share) => routineId == null || share.routineId == routineId)
      .toList(growable: false);

  @override
  Future<PersonalRoutineRecord?> respondRoutineShare(
    String shareId, {
    required bool accept,
    String? requestId,
  }) async {
    routineResponseIds.add(shareId);
    routineResponseInputs.add((shareId, accept, requestId));
    _throwLostRpcResponseIfNeeded('routine-respond');
    return accept ? personalRoutines.firstOrNull : null;
  }

  @override
  Future<PersonalRoutineRecord> acceptRoutineShareToken(
    String token, {
    String? requestId,
  }) async {
    acceptedRoutineTokens.add(token);
    acceptedRoutineTokenInputs.add((token, requestId));
    _throwLostRpcResponseIfNeeded('routine-token');
    return personalRoutines.first;
  }

  @override
  Future<PersonalRoutineRecord> importMarketRoutine(
    String marketRoutineId, {
    String? requestId,
  }) async {
    importedMarketRoutineIds.add(marketRoutineId);
    importedMarketRoutineInputs.add((marketRoutineId, requestId));
    _throwLostRpcResponseIfNeeded('routine-import');
    return personalRoutines.first;
  }

  void _throwLostRpcResponseIfNeeded(String operation) {
    final remaining = rpcResponseLossesRemaining[operation] ?? 0;
    if (remaining <= 0) return;
    rpcResponseLossesRemaining[operation] = remaining - 1;
    throw TimeoutException('$operation response lost');
  }

  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async =>
      personalRoutines;

  @override
  Future<PersonalRoutineRecord> savePersonalRoutine(
    SavePersonalRoutineInput input,
  ) async {
    personalRoutineSaveInputs.add(input);
    if (personalRoutineSaveFailuresRemaining > 0) {
      personalRoutineSaveFailuresRemaining--;
      throw TimeoutException('save response lost');
    }
    final current = personalRoutines.firstWhere(
      (routine) => routine.id == input.routineId,
    );
    final saved = PersonalRoutineRecord(
      id: current.id,
      ownerUserId: current.ownerUserId,
      name: input.name,
      description: input.description,
      color: input.color,
      source: current.source,
      marketRoutineId: current.marketRoutineId,
      sourceCoachingRoutineId: current.sourceCoachingRoutineId,
      createdAt: current.createdAt,
      updatedAt: DateTime(2026, 8, 16),
      exercises: List.generate(input.exercises.length, (exerciseIndex) {
        final exercise = input.exercises[exerciseIndex];
        final exerciseId = 'saved-exercise-$exerciseIndex';
        return OwnedRoutineExercise(
          id: exerciseId,
          routineId: current.id,
          baseExerciseId: exercise.baseExerciseId,
          name: exercise.name,
          targetMuscle: exercise.targetMuscle,
          orderIndex: exerciseIndex,
          sets: List.generate(exercise.sets.length, (setIndex) {
            final set = exercise.sets[setIndex];
            return OwnedRoutineSet(
              id: 'saved-set-$exerciseIndex-$setIndex',
              exerciseId: exerciseId,
              setNumber: set.setNumber,
              type: set.type,
              targetWeight: set.targetWeight,
              targetReps: set.targetReps,
              restSeconds: set.restSeconds,
            );
          }),
        );
      }),
    );
    personalRoutines = [
      saved,
      ...personalRoutines.where((routine) => routine.id != saved.id),
    ];
    return saved;
  }

  @override
  Future<void> deletePersonalRoutine(
    String routineId, {
    String? requestId,
  }) async {
    personalRoutineDeleteInputs.add((routineId, requestId));
    if (personalRoutineDeleteFailuresRemaining > 0) {
      personalRoutineDeleteFailuresRemaining--;
      throw TimeoutException('delete response lost');
    }
    personalRoutines = personalRoutines
        .where((routine) => routine.id != routineId)
        .toList(growable: false);
  }

  @override
  Future<List<BusinessApplication>> listApplications({
    BusinessApplicationStatus? status,
  }) async => const [];

  @override
  Future<BusinessApplication> reviewApplication(
    ReviewBusinessApplicationInput input,
  ) async => throw UnimplementedError();

  @override
  Future<BusinessApplication> submitGymApplication(
    GymApplicationInput input,
  ) async => throw UnimplementedError();

  @override
  Future<BusinessApplication> submitTrainerApplication(
    TrainerApplicationInput input,
  ) async => throw UnimplementedError();

  @override
  Future<void> updateProfile(UpdateBusinessProfileInput input) async {}
}

OwnedCoachingRoutine _ownedRoutineFromInput({
  required String id,
  required String title,
  required String? intro,
  required BusinessRoutineDifficulty difficulty,
  required List<CreateOwnedRoutineExerciseInput> exercises,
}) {
  return OwnedCoachingRoutine(
    id: id,
    trainerId: _trainerId,
    title: title,
    intro: intro,
    status: BusinessRoutineStatus.draft,
    difficulty: difficulty,
    cumulativeUsers: 0,
    exercises: [
      for (
        var exerciseIndex = 0;
        exerciseIndex < exercises.length;
        exerciseIndex++
      )
        OwnedRoutineExercise(
          id: 'exercise-$exerciseIndex',
          routineId: id,
          baseExerciseId: exercises[exerciseIndex].baseExerciseId,
          name: exercises[exerciseIndex].name,
          targetMuscle: exercises[exerciseIndex].targetMuscle,
          orderIndex: exerciseIndex,
          sets: [
            for (final set in exercises[exerciseIndex].sets)
              OwnedRoutineSet(
                id: 'set-$exerciseIndex-${set.setNumber}',
                exerciseId: 'exercise-$exerciseIndex',
                setNumber: set.setNumber,
                type: set.type,
                targetWeight: set.targetWeight,
                targetReps: set.targetReps,
                restSeconds: set.restSeconds,
              ),
          ],
        ),
    ],
  );
}

class _FailingRoutineCatalogRepository implements RoutineCatalogRepository {
  const _FailingRoutineCatalogRepository(this.error);

  final Object error;

  @override
  Future<bool> hasActivePaidPlan() async => false;

  @override
  Future<List<RoutineCatalogItem>> listPublished() async => throw error;

  @override
  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  ) async {}
}

class _FailingCommunityRepository implements CommunityRepository {
  const _FailingCommunityRepository(this.error);

  final Object error;

  @override
  Future<PostComment> addComment({
    required String postId,
    required String content,
  }) async => throw error;

  @override
  Future<CommunityPostRecord> createPost(
    CreateCommunityPostInput input,
  ) async => throw error;

  @override
  Future<List<CommunityPostRecord>> fetchPosts({
    int limit = 50,
    int offset = 0,
  }) async => throw error;

  @override
  Future<CommunityLikeResult> toggleLike(String postId) async => throw error;
}
