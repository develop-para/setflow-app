import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/coaching_workout_repository.dart';
import 'package:setflow/screens/coaching_workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';

const _exercise = ExerciseTemplate(
  id: 'squat',
  name: '스쿼트',
  muscle: '하체',
  icon: SetflowIcons.record,
);

void main() {
  testWidgets(
    'account change removes visible records and dismisses their number dial',
    (tester) async {
      final repository = _Repository();
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      await tester.tap(find.text('무게 50kg').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('number-dial-direct-input')), findsOneWidget);
      state.changeAccount('another-member');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('coaching-account-expired')),
        findsOneWidget,
      );
      expect(find.text('오늘 하체 수업'), findsNothing);
      expect(find.byKey(const Key('number-dial-direct-input')), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      expect(repository.saveRequests, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CoachingWorkoutScreen), findsNothing);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'late save after account change never restores records or starts rest',
    (tester) async {
      final gate = Completer<void>();
      final repository = _Repository()..saveGate = gate;
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      await _swipe(tester, find.byType(Dismissible).first, right: true);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repository.saveRequests, hasLength(1));
      expect(find.text('회원 일지에 저장 중…'), findsOneWidget);
      state.changeAccount('another-member');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('coaching-account-expired')),
        findsOneWidget,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('오늘 하체 수업'), findsNothing);
      expect(state.coachingWorkouts, isEmpty);
      expect(state.restRemaining, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('아직 저장 전이에요'), findsNothing);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'trainers opening their own task inbox retain member reminder settings',
    (tester) async {
      final state = _state(_Repository());
      await _mount(tester, state, const CoachingAssignmentsScreen());
      expect(find.byTooltip('과제 알림 설정'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('coaching-create-assignment')),
        findsNothing,
      );
      await _unmount(tester, state);
    },
  );
  testWidgets(
    'numeric Apply retries the same request and retains failed draft',
    (tester) async {
      final repository = _Repository()..failSave = true;
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      expect(find.text('민지 회원님 대신 기록 중'), findsOneWidget);
      await tester.tap(find.text('무게 50kg').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('number-dial-direct-input')),
        '60',
      );
      expect(repository.saveRequests, isEmpty);
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coaching-save-error')), findsOneWidget);
      expect(find.text('무게 60kg'), findsOneWidget);
      expect(repository.current.session.exercises.first.sets.first.weight, 50);
      expect(state.restRemaining, 0);
      final request = repository.saveRequests.single;
      repository.failSave = false;
      await tester.tap(find.byKey(const ValueKey('coaching-save-retry')));
      await tester.pumpAndSettle();
      expect(repository.saveRequests, [request, request]);
      expect(repository.expectedVersions, [1, 1]);
      expect(repository.current.session.exercises.first.sets.first.weight, 60);
      expect(find.byKey(const ValueKey('coaching-save-error')), findsNothing);
      expect(state.restRemaining, 0);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'sets complete sequentially and propagation undo preserves completion',
    (tester) async {
      final repository = _Repository();
      repository.current.session.exercises.first.sets.first.weight = 60;
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      var rows = tester
          .widgetList<Dismissible>(find.byType(Dismissible))
          .toList();
      expect(rows[1].direction, DismissDirection.none);
      await _swipe(tester, find.byType(Dismissible).first, right: true);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        repository.current.session.exercises.first.sets.first.completed,
        isTrue,
      );
      expect(repository.current.session.exercises.first.sets[1].weight, 60);
      expect(state.restRemaining, greaterThan(0));
      expect(find.text('1세트  60kg × 10회 · 완료'), findsOneWidget);
      rows = tester.widgetList<Dismissible>(find.byType(Dismissible)).toList();
      expect(rows[1].direction, DismissDirection.horizontal);
      await tester.tap(find.text('되돌리기'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        repository.current.session.exercises.first.sets.first.completed,
        isTrue,
      );
      expect(repository.current.session.exercises.first.sets[1].weight, 50);
      await tester.tap(find.text('1세트  60kg × 10회 · 완료'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('무게 60kg'), findsOneWidget);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'failed completion does not start rest or discard input on back',
    (tester) async {
      final repository = _Repository()..failSave = true;
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      await _swipe(tester, find.byType(Dismissible).first, right: true);
      await tester.pumpAndSettle();
      expect(repository.current.session.completedSets, 0);
      expect(state.restRemaining, 0);
      expect(find.byKey(const ValueKey('coaching-save-error')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('아직 저장 전이에요'), findsOneWidget);
      await tester.tap(find.text('기록 확인'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coaching-save-error')), findsOneWidget);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'lesson time boundary disables gestures without waiting for refresh',
    (tester) async {
      final repository = _Repository();
      repository.current = repository.copy(
        startsAt: DateTime.now().add(const Duration(hours: 1)),
        endsAt: DateTime.now().add(const Duration(hours: 2)),
      );
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      expect(find.text('예약된 수업 시간에만 트레이너가 기록할 수 있어요.'), findsOneWidget);
      expect(find.byKey(const ValueKey('coaching-add-exercise')), findsNothing);
      expect(
        tester
            .widgetList<Dismissible>(find.byType(Dismissible))
            .every((row) => row.direction == DismissDirection.none),
        isTrue,
      );
      expect(repository.saveRequests, isEmpty);
      await _unmount(tester, state);
    },
  );

  testWidgets('only the member sees separate lesson recording consent', (
    tester,
  ) async {
    final repository = _Repository();
    repository.current = repository.copy(
      recordingAllowed: false,
      canEdit: false,
    );
    final state = _state(repository, member: true);
    await _mount(
      tester,
      state,
      const CoachingWorkoutScreen(scheduleId: 'lesson'),
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-recording-consent')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('lesson-recording-consent')));
    await tester.pumpAndSettle();
    expect(repository.consents, [true]);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('lesson-recording-consent')),
          )
          .value,
      isTrue,
    );
    await _unmount(tester, state);
  });

  testWidgets(
    'idle refresh picks up consent and stops showing edit controls when revoked',
    (tester) async {
      final repository = _Repository();
      repository.current = repository.copy(
        canEdit: false,
        recordingAllowed: false,
      );
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      expect(find.text('민지 회원님 대신 기록 중'), findsNothing);
      repository.current = repository.copy(
        canEdit: true,
        recordingAllowed: true,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('민지 회원님 대신 기록 중'), findsOneWidget);
      repository.current = repository.copy(
        canEdit: false,
        recordingAllowed: false,
      );
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('민지 회원님 대신 기록 중'), findsNothing);
      expect(
        tester
            .widgetList<Dismissible>(find.byType(Dismissible))
            .every((row) => row.direction == DismissDirection.none),
        isTrue,
      );
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'failed draft can be left only after explicit discard confirmation',
    (tester) async {
      final repository = _Repository()..failSave = true;
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      await _swipe(tester, find.byType(Dismissible).first, right: true);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('입력 버리고 나가기'));
      await tester.pumpAndSettle();
      expect(find.text('입력을 버릴까요?'), findsOneWidget);
      await tester.tap(find.text('버리고 나가기'));
      await tester.pumpAndSettle();
      expect(find.byType(CoachingWorkoutScreen), findsNothing);
      expect(repository.current.session.completedSets, 0);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'conflict recovery shows draft and latest before explicit replacement',
    (tester) async {
      final repository = _Repository()..failSave = true;
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const CoachingWorkoutScreen(scheduleId: 'lesson'),
      );
      await _swipe(tester, find.byType(Dismissible).first, right: true);
      await tester.pumpAndSettle();
      repository.current = repository.copy(version: 3);
      repository.current.session.exercises.first.sets.first.weight = 80;
      await tester.tap(find.byKey(const ValueKey('coaching-review-latest')));
      await tester.pumpAndSettle();
      expect(find.text('이 화면의 입력 · 1/2세트'), findsOneWidget);
      expect(find.text('서버의 최신 기록 · 0/2세트'), findsOneWidget);
      await tester.tap(find.text('입력 유지'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coaching-save-error')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('coaching-review-latest')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('최신 기록으로 전환'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coaching-save-error')), findsNothing);
      expect(find.text('무게 80kg'), findsOneWidget);
      await _unmount(tester, state);
    },
  );

  testWidgets('assignment composer sends dated plans with no completed sets', (
    tester,
  ) async {
    final repository = _Repository();
    final state = _state(repository);
    await _mount(
      tester,
      state,
      const CoachingAssignmentComposerScreen(memberUserId: 'member'),
    );
    await tester.enterText(find.byType(TextFormField), '내일도 가볍게');
    await tester.tap(find.byKey(const ValueKey('assignment-add-exercise')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '종목 검색'), '스쿼트');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '스쿼트').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('세트 추가'));
    await tester.tap(find.text('세트 추가'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('assignment-send')));
    await tester.tap(find.byKey(const ValueKey('assignment-send')));
    await tester.pumpAndSettle();
    expect(repository.createdTitle, '내일도 가볍게');
    expect(repository.createdMember, 'member');
    expect(repository.createdSession!.totalSets, 2);
    expect(repository.createdSession!.completedSets, 0);
    expect(
      repository.createdSession!.date,
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );
    await _unmount(tester, state);
  });

  testWidgets(
    'daily assignment reminder remains off until member explicitly saves',
    (tester) async {
      final repository = _Repository();
      final state = _state(repository, member: true);
      await _mount(tester, state, const CoachingAssignmentsScreen());
      await tester.tap(find.byTooltip('과제 알림 설정'));
      await tester.pumpAndSettle();
      expect(repository.reminderSaves, isEmpty);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('coaching-reminder-enabled')),
            )
            .value,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('coaching-reminder-enabled')));
      await tester.pumpAndSettle();
      expect(repository.reminderSaves, isEmpty);
      await tester.tap(find.text('알림 설정 저장'));
      await tester.pumpAndSettle();
      expect(repository.reminderSaves, [(true, 19)]);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'completed assignments retain the home entry and refresh errors stay visible',
    (tester) async {
      final repository = _Repository();
      for (final set in repository.current.session.exercises.first.sets) {
        set.completed = true;
      }
      repository.current = repository.copy(
        kind: CoachingWorkoutKind.assignment,
      );
      final state = _state(repository, member: true);
      state.coachingWorkouts = [repository.current];
      await _mount(
        tester,
        state,
        const Scaffold(body: MemberCoachingTasksCard()),
      );
      expect(find.text('오늘 남은 과제가 없어요.'), findsOneWidget);
      expect(find.text('전체 과제와 알림 설정'), findsOneWidget);
      state.coachingWorkoutsError = StateError('Offline');
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(
        tester,
        state,
        const Scaffold(body: MemberCoachingTasksCard()),
      );
      expect(find.text('최신 과제를 확인하지 못했어요. 과제함에서 다시 확인해주세요.'), findsOneWidget);
      await _unmount(tester, state);
    },
  );

  testWidgets('small screen and doubled text keep set controls reachable', (
    tester,
  ) async {
    final repository = _Repository();
    final state = _state(repository, member: true);
    await _mount(
      tester,
      state,
      const CoachingWorkoutScreen(scheduleId: 'lesson'),
      small: true,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('coaching-value-squat-1-무게')),
      200,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('무게 50kg').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('무게 50kg').first);
    await tester.pumpAndSettle();
    expect(find.text('적용'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester, state);
  });
}

_TestAppState _state(_Repository repository, {bool member = false}) {
  final state = _TestAppState(
    coachingWorkoutRepository: repository,
    loadBusinessWithoutAuth: true,
  );
  state.businessAccess = BusinessAccess(
    userId: member ? 'member' : 'trainer-user',
    accountRole: member ? UserRole.member : UserRole.trainer,
    resolvedRole: member ? UserRole.member : UserRole.trainer,
    availableRoles: {UserRole.member, if (!member) UserRole.trainer},
  );
  return state;
}

class _TestAppState extends AppState {
  _TestAppState({
    super.coachingWorkoutRepository,
    super.loadBusinessWithoutAuth,
  });

  void changeAccount(String userId) {
    businessAccess = BusinessAccess(
      userId: userId,
      accountRole: UserRole.member,
      resolvedRole: UserRole.member,
      availableRoles: const {UserRole.member},
    );
    notifyListeners();
  }
}

Future<void> _mount(
  WidgetTester tester,
  AppState state,
  Widget page, {
  bool small = false,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 740) : const Size(430, 1100),
  );
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
          child: child!,
        ),
        home: Navigator(
          onGenerateInitialRoutes: (_, _) => [
            MaterialPageRoute<void>(builder: (_) => const Scaffold()),
            MaterialPageRoute<void>(builder: (_) => page),
          ],
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => page),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox.shrink());
  state.dispose();
  await tester.pump(const Duration(seconds: 4));
  await tester.binding.setSurfaceSize(null);
}

Future<void> _swipe(
  WidgetTester tester,
  Finder row, {
  required bool right,
}) async {
  await tester.ensureVisible(row);
  final rect = tester.getRect(row);
  final gesture = await tester.startGesture(
    Offset(rect.left + (right ? 20 : rect.width - 20), rect.center.dy),
  );
  for (var step = 0; step < 8; step++) {
    await gesture.moveBy(Offset(rect.width * (right ? .08 : -.08), 0));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 300));
}

WorkoutSession _session(DateTime date) => WorkoutSession(
  date: date,
  exercises: [
    WorkoutExercise(
      id: 'squat-1',
      template: _exercise,
      sets: [
        WorkoutSetEntry(number: 1, weight: 50, reps: 10),
        WorkoutSetEntry(number: 2, weight: 50, reps: 10),
      ],
    ),
  ],
);

class _Repository implements CoachingWorkoutRepository {
  _Repository() {
    final now = DateTime.now();
    current = CoachingWorkout(
      id: 'workout',
      kind: CoachingWorkoutKind.lesson,
      status: CoachingWorkoutStatus.assigned,
      trainerId: 'trainer',
      memberUserId: 'member',
      trainerName: '지훈',
      memberName: '민지',
      title: '오늘 하체 수업',
      instruction: '',
      date: DateTime(now.year, now.month, now.day),
      session: _session(DateTime(now.year, now.month, now.day)),
      version: 1,
      canEdit: true,
      recordingAllowed: true,
      scheduleId: 'lesson',
      startsAt: now.subtract(const Duration(minutes: 10)),
      endsAt: now.add(const Duration(minutes: 40)),
    );
  }
  late CoachingWorkout current;
  bool failSave = false;
  Completer<void>? saveGate;
  final saveRequests = <String>[];
  final expectedVersions = <int>[];
  final consents = <bool>[];
  final reminderSaves = <(bool, int)>[];
  WorkoutSession? createdSession;
  String? createdTitle;
  String? createdMember;

  CoachingWorkout copy({
    WorkoutSession? session,
    int? version,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? recordingAllowed,
    bool? canEdit,
    CoachingWorkoutKind? kind,
  }) => CoachingWorkout(
    id: current.id,
    kind: kind ?? current.kind,
    status: (session ?? current.session).isComplete
        ? CoachingWorkoutStatus.completed
        : CoachingWorkoutStatus.inProgress,
    trainerId: current.trainerId,
    memberUserId: current.memberUserId,
    trainerName: current.trainerName,
    memberName: current.memberName,
    title: current.title,
    instruction: current.instruction,
    date: current.date,
    session: session ?? current.session,
    version: version ?? current.version,
    canEdit: canEdit ?? current.canEdit,
    recordingAllowed: recordingAllowed ?? current.recordingAllowed,
    scheduleId: current.scheduleId,
    startsAt: startsAt ?? current.startsAt,
    endsAt: endsAt ?? current.endsAt,
    lastEditorName: '지훈',
  );

  @override
  Future<CoachingWorkout> openLessonWorkout(String scheduleId) async => current;
  @override
  Future<List<CoachingWorkout>> listCoachingWorkouts({
    String? memberUserId,
  }) async => [current];
  @override
  Future<CoachingWorkout> saveCoachingWorkout({
    required String workoutId,
    required int expectedVersion,
    required WorkoutSession session,
    required String requestId,
  }) async {
    saveRequests.add(requestId);
    expectedVersions.add(expectedVersion);
    if (saveGate != null) await saveGate!.future;
    if (failSave || expectedVersion != current.version) {
      throw StateError('Save failed');
    }
    current = copy(session: session, version: current.version + 1);
    return current;
  }

  @override
  Future<void> setLessonRecordingConsent(
    String scheduleId,
    bool allowed,
  ) async {
    consents.add(allowed);
    current = copy(recordingAllowed: allowed);
  }

  @override
  Future<CoachingWorkout> createWorkoutAssignment({
    required String memberUserId,
    required DateTime date,
    required String title,
    required String instruction,
    required WorkoutSession session,
    required String requestId,
  }) async {
    createdSession = session;
    createdTitle = title;
    createdMember = memberUserId;
    current = copy(
      session: session,
      kind: CoachingWorkoutKind.assignment,
      canEdit: false,
    );
    return current;
  }

  @override
  Future<CoachingWorkout> cancelWorkoutAssignment({
    required String workoutId,
    required int expectedVersion,
    required String requestId,
  }) async => current;
  @override
  Future<CoachingReminderPreferences> loadMyCoachingReminder() async =>
      const CoachingReminderPreferences(enabled: false, hour: 19);
  @override
  Future<CoachingReminderPreferences> setMyCoachingReminder(
    bool enabled,
    int hour,
  ) async {
    reminderSaves.add((enabled, hour));
    return CoachingReminderPreferences(enabled: enabled, hour: hour);
  }
}
