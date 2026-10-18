import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/screens/member_detail_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';
import 'package:setflow/widgets/exercise_muscle_map.dart';
import 'package:setflow/widgets/workout_history_calendar.dart';

const _memberId = '44444444-4444-4444-8444-444444444444';
const _memberUserId = '11111111-1111-4111-8111-111111111111';
const _sessionId = '55555555-5555-4555-8555-555555555555';

void main() {
  Future<AppState> pumpMemberDetail(
    WidgetTester tester,
    _FakeBusinessRepository repository, {
    UserRole role = UserRole.guest,
    BusinessAccess? access,
  }) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState(businessRepository: repository)
      ..role = role
      ..businessAccess = access;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: MemberDetailScreen(member: _member(), role: UserRole.trainer),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets(
    'live detail requests the selected member UUID and blocks unconsented records',
    (tester) async {
      final repository = _FakeBusinessRepository(
        detail: _memberDetail(canReadWorkouts: false),
      );

      await pumpMemberDetail(tester, repository);

      expect(repository.requestedMemberIds, [_memberId]);
      expect(find.text('운동 기록 공유가 꺼져 있어요'), findsOneWidget);
      expect(find.text('바벨 벤치 프레스 · E2E'), findsNothing);
      expect(find.textContaining('82.5'), findsNothing);
      expect(find.byType(WorkoutHistoryCalendar), findsNothing);
    },
  );

  testWidgets('local member library survives a narrow screen at 2x text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    Widget app(double scale) => AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: child!,
        ),
        home: MemberDetailScreen(member: _member(), role: UserRole.trainer),
      ),
    );

    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    final tabBarContext = tester.element(find.byType(TabBar));
    DefaultTabController.of(tabBarContext).animateTo(3);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseMuscleMap), findsWidgets);

    await tester.pumpWidget(app(2));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseMuscleMap), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('consented live detail renders nested exercises and sets', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository(
      detail: _memberDetail(canReadWorkouts: true),
    );

    await pumpMemberDetail(tester, repository);
    await _expandSession(tester);

    expect(find.text('바벨 벤치 프레스 · E2E'), findsOneWidget);
    expect(find.textContaining('82.5'), findsOneWidget);
    expect(find.textContaining('8회'), findsOneWidget);
    expect(find.textContaining('120초'), findsOneWidget);
  });

  testWidgets(
    'returning from record sharing reloads consent and the selected month',
    (tester) async {
      Auth.use(_TrainerAuth());
      addTearDown(Auth.reset);
      final repository = _SharingBusinessRepository(
        detail: _memberDetail(canReadWorkouts: true),
      );
      final state = await pumpMemberDetail(
        tester,
        repository,
        role: UserRole.trainer,
        access: repository.access,
      );
      await tester.tap(find.byKey(const ValueKey('member-records-calendar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('이전 달'));
      await tester.pumpAndSettle();
      final selectedRange = repository.requestedRanges.last;
      await tester.tap(find.byKey(const ValueKey('member-detail-sharing')));
      await tester.pumpAndSettle();
      expect(find.text('실회원 기록 공유'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state.businessMemberDetail(_memberId)?.canReadWorkouts, isTrue);
      expect(find.text('운동 기록 공유가 꺼져 있어요'), findsNothing);
      expect(find.text('2026.07'), findsOneWidget);
      expect(repository.requestedRanges.last, selectedRange);
      expect(repository.requestedMemberIds, hasLength(3));
    },
  );

  testWidgets('calendar selects one day and retains the month on refresh', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository(
      detail: _memberDetail(
        canReadWorkouts: true,
        sessions: [
          _session(),
          _session(id: 'second-session', date: DateTime(2026, 8, 14)),
        ],
      ),
    );
    final state = await pumpMemberDetail(tester, repository);
    expect(find.byType(WorkoutHistoryCalendar), findsNothing);
    expect(
      find.byKey(const ValueKey('member-session-second-session')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('member-records-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('2026.08'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('member-session-$_sessionId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('member-session-second-session')),
      findsNothing,
    );
    final day = find.byKey(const ValueKey('history-calendar-day-2026-08-14'));
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('member-session-second-session')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('member-session-$_sessionId')),
      findsNothing,
    );

    await tester.ensureVisible(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026.07'), findsOneWidget);
    expect(repository.requestedRanges.last, (
      from: DateTime(2026, 7),
      to: DateTime(2026, 7, 31),
    ));
    expect(find.text('이 날짜에는 저장된 운동 기록이 없어요.'), findsOneWidget);
    await state.loadBusinessMemberDetail(_memberId, force: true);
    await tester.pumpAndSettle();
    expect(find.text('2026.07'), findsOneWidget);
    expect(repository.requestedRanges.last, (
      from: DateTime(2026, 7),
      to: DateTime(2026, 7, 31),
    ));
    final recent = find.byKey(const ValueKey('member-records-recent'));
    await tester.ensureVisible(recent);
    await tester.tap(recent);
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutHistoryCalendar), findsNothing);
    expect(
      find.byKey(const ValueKey('member-session-$_sessionId')),
      findsOneWidget,
    );
    expect(repository.requestedRanges.last, repository.requestedRanges.first);
  });

  testWidgets(
    'session feedback sends the session UUID once and disables duplicate submission',
    (tester) async {
      final feedbackCompleter = Completer<BusinessSessionFeedback>();
      final repository = _FakeBusinessRepository(
        detail: _memberDetail(canReadWorkouts: true),
        feedbackCompleter: feedbackCompleter,
      );
      await pumpMemberDetail(tester, repository);
      await _openFeedback(tester);

      final field = find.byKey(
        const ValueKey('session-feedback-field-$_sessionId'),
      );
      final submit = find.byKey(
        const ValueKey('session-feedback-submit-$_sessionId'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, '다음 세션에서는 하강 구간을 2초간 유지해주세요.');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(repository.feedbackInputs, hasLength(1));
      expect(repository.feedbackInputs.single.sessionId, _sessionId);
      expect(
        repository.feedbackInputs.single.text,
        '다음 세션에서는 하강 구간을 2초간 유지해주세요.',
      );
      final pendingButton = tester.widget<AppButton>(submit);
      expect(pendingButton.onPressed, isNull);
      expect(find.text('전송 중...'), findsOneWidget);

      await tester.tap(submit, warnIfMissed: false);
      await tester.pump();
      expect(repository.feedbackInputs, hasLength(1));

      feedbackCompleter.complete(
        BusinessSessionFeedback(
          id: '99999999-9999-4999-8999-999999999999',
          sessionId: _sessionId,
          trainerUserId: '22222222-2222-4222-8222-222222222222',
          authorName: '정코치',
          text: repository.feedbackInputs.single.text,
          createdAt: DateTime.utc(2026, 8, 16, 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.feedbackInputs, hasLength(1));
    },
  );

  testWidgets(
    'feedback opens before set details and retains a collapsed draft',
    (tester) async {
      final repository = _FakeBusinessRepository(
        detail: _memberDetail(canReadWorkouts: true),
      );
      await pumpMemberDetail(tester, repository);
      expect(find.textContaining('82.5kg'), findsNothing);
      await _openFeedback(tester);
      final field = find.byKey(
        const ValueKey('session-feedback-field-$_sessionId'),
      );
      expect(find.text('2026.08.15 운동에 보낼 피드백'), findsOneWidget);
      expect(find.textContaining('82.5kg'), findsNothing);
      await tester.enterText(field, '호흡을 유지해주세요.');
      await _openFeedback(tester);
      expect(field, findsNothing);
      await _openFeedback(tester);
      expect(find.text('호흡을 유지해주세요.'), findsOneWidget);
      await tester.tap(find.text('피드백').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('운동 기록').first);
      await tester.pumpAndSettle();
      expect(find.text('호흡을 유지해주세요.'), findsOneWidget);
      expect(repository.feedbackInputs, isEmpty);
    },
  );

  testWidgets('feedback history identifies and opens the exact workout', (
    tester,
  ) async {
    final repository = _FakeBusinessRepository(
      detail: _memberDetail(
        canReadWorkouts: true,
        sessions: [
          _session(
            feedbacks: [
              BusinessSessionFeedback(
                id: 'history-feedback',
                sessionId: _sessionId,
                trainerUserId: 'trainer-user',
                authorName: '정코치',
                text: '다음 운동에서도 호흡을 유지해주세요.',
                createdAt: DateTime(2026, 8, 16),
              ),
            ],
          ),
        ],
      ),
    );
    await pumpMemberDetail(tester, repository);
    await tester.tap(find.text('피드백').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('member-feedback-period')),
      findsOneWidget,
    );
    expect(find.text('2026.08.15 운동'), findsOneWidget);
    await tester.tap(find.text('2026.08.15 운동'));
    await tester.pumpAndSettle();
    expect(find.text('실회원 운동 피드백'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-feedback-field-$_sessionId')),
      findsOneWidget,
    );
  });

  testWidgets(
    'live recent records and feedback work on a narrow screen at 2x text',
    (tester) async {
      final repository = _FakeBusinessRepository(
        detail: _memberDetail(canReadWorkouts: true),
      );
      await pumpMemberDetail(tester, repository);
      await tester.binding.setSurfaceSize(const Size(320, 900));
      final appContext = tester.element(find.byType(MemberDetailScreen));
      final state = AppScope.of(appContext);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: MemberDetailScreen(member: _member(), role: UserRole.trainer),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openFeedback(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('2026.08.15 운동에 보낼 피드백'), findsOneWidget);
    },
  );
}

Future<void> _openFeedback(WidgetTester tester) async {
  final open = find.byKey(const ValueKey('session-feedback-open-$_sessionId'));
  await tester.ensureVisible(open);
  await tester.tap(open);
  await tester.pumpAndSettle();
}

Future<void> _expandSession(WidgetTester tester) async {
  final card = find.byKey(const ValueKey('member-session-$_sessionId'));
  expect(card, findsOneWidget);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: card, matching: find.byType(ListTile)).first,
  );
  await tester.pumpAndSettle();
}

BusinessMember _member() => const BusinessMember(
  id: _memberId,
  gymId: '33333333-3333-4333-8333-333333333333',
  userId: _memberUserId,
  name: '실회원',
  goal: '근력 향상',
  level: '중급',
  remainingPtSessions: 8,
  completionRate: 75,
);

BusinessMemberDetail _memberDetail({
  required bool canReadWorkouts,
  List<BusinessWorkoutSession>? sessions,
}) {
  return BusinessMemberDetail(
    memberId: _memberId,
    memberUserId: _memberUserId,
    shareBodyData: canReadWorkouts,
    shareWorkoutRecords: canReadWorkouts,
    canReadWorkouts: canReadWorkouts,
    // The server may still return a defensive payload. The UI must honor the
    // explicit consent decision before rendering any nested workout data.
    sessions: sessions ?? [_session()],
  );
}

BusinessWorkoutSession _session({
  String id = _sessionId,
  DateTime? date,
  List<BusinessSessionFeedback> feedbacks = const [],
}) => BusinessWorkoutSession(
  id: id,
  userId: _memberUserId,
  date: date ?? DateTime(2026, 8, 15),
  category: 'strength',
  intensity: 'moderate',
  startedAt: DateTime.utc(2026, 8, 15, 9),
  endedAt: DateTime.utc(2026, 8, 15, 10),
  exercises: [
    BusinessWorkoutExercise(
      id: '66666666-6666-4666-8666-666666666666',
      name: '바벨 벤치 프레스 · E2E',
      targetMuscle: '가슴',
      orderIndex: 0,
      sets: [
        BusinessWorkoutSet(
          id: '77777777-7777-4777-8777-777777777777',
          setNumber: 1,
          type: 'normal',
          weight: 82.5,
          reps: 8,
          rir: 2,
          memo: '하강 2초',
          completed: true,
          completedAt: DateTime.utc(2026, 8, 15, 9, 15),
          estimated1Rm: 104.5,
          restSeconds: 120,
        ),
      ],
    ),
  ],
  feedbacks: feedbacks,
);

class _FakeBusinessRepository implements BusinessRepository {
  _FakeBusinessRepository({required this.detail, this.feedbackCompleter});

  final BusinessMemberDetail detail;
  final Completer<BusinessSessionFeedback>? feedbackCompleter;
  final List<String> requestedMemberIds = [];
  final requestedRanges = <({DateTime? from, DateTime? to})>[];
  final List<SendSessionFeedbackInput> feedbackInputs = [];

  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async {
    return const MemberSharingPreferences(
      shareBodyData: false,
      shareWorkoutRecords: false,
      marketing: false,
    );
  }

  @override
  Future<MemberSharingPreferences> updateMySharingPreferences(
    MemberSharingPreferences preferences,
  ) async => preferences;

  @override
  Future<BusinessMemberDetail> loadMemberDetail(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    requestedMemberIds.add(memberId);
    requestedRanges.add((from: from, to: to));
    return detail;
  }

  @override
  Future<BusinessSessionFeedback> sendSessionFeedback(
    SendSessionFeedbackInput input,
  ) {
    feedbackInputs.add(input);
    final pending = feedbackCompleter;
    if (pending != null) return pending.future;
    return Future.value(
      BusinessSessionFeedback(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        sessionId: input.sessionId,
        trainerUserId: '22222222-2222-4222-8222-222222222222',
        authorName: '정코치',
        text: input.text,
        createdAt: DateTime.utc(2026, 8, 16),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrainerAuth implements AuthService {
  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'trainer-user', displayName: '정코치');
  @override
  bool get hasAuthenticatedUser => true;
  @override
  String get currentDisplayName => '정코치';
  @override
  Stream<AuthChange> get authChanges => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SharingBusinessRepository extends _FakeBusinessRepository
    implements CoachingManagementRepository {
  _SharingBusinessRepository({required super.detail});
  final access = const BusinessAccess(
    userId: 'trainer-user',
    accountRole: UserRole.trainer,
    resolvedRole: UserRole.trainer,
    availableRoles: {UserRole.member, UserRole.trainer},
  );

  @override
  Future<BusinessAccess> loadAccess() async => access;
  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async =>
      BusinessWorkspaceData(
        role: role,
        access: access,
        dashboardStats: const BusinessDashboardMetrics(),
        members: [_member()],
      );
  @override
  Future<List<CoachingManagementLink>> listManagementLinks({
    required CoachingManagementRole role,
  }) async => [];
  @override
  Future<List<WorkoutCorrection>> listWorkoutCorrections({
    required CoachingManagementRole role,
  }) async => [];
}
