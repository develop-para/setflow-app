import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/coaching_workout_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/coaching_workout_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/services/push_service.dart';

void main() {
  setUp(() => Auth.use(_SignedInMember()));
  tearDown(() {
    Auth.reset();
    Push.bind(const DisabledPushService());
  });

  testWidgets(
    'cold-start coaching push waits for local restore and opens only once',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final local = _DelayedLocalRepository();
      final notification = PushOpen(
        kind: 'coaching_feedback',
        data: const {
          'event': 'coaching_workout',
          'workoutId': 'notified-workout',
        },
      );
      final push = _ColdStartPush(notification);
      Push.bind(push);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await push.events.close();
      });

      await tester.pumpWidget(
        SetflowApp(
          repository: local,
          coachingWorkoutRepository: _CoachingRepository(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1900));
      expect(local.started, isTrue);
      expect(push.initialRead, isTrue);
      expect(find.byType(CoachingWorkoutScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('setflow-loading-logo')),
        findsOneWidget,
      );

      local.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final opened = find.byType(CoachingWorkoutScreen);
      expect(opened, findsOneWidget);
      expect(
        tester.widget<CoachingWorkoutScreen>(opened).workoutId,
        'notified-workout',
      );
      expect(
        find.descendant(of: opened, matching: find.text('알림으로 받은 하체 과제')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      // 재전달과 상태 알림이 겹쳐도 같은 상세를 여러 번 쌓지 않는다.
      push.events.add(notification);
      final state = AppScope.of(tester.element(opened));
      await state.refreshCoachingWorkouts();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(CoachingWorkoutScreen, skipOffstage: false),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await state.refreshCoachingWorkouts();
      await tester.pump();
      expect(
        find.byType(CoachingWorkoutScreen, skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _DelayedLocalRepository implements AppRepository {
  final _result = Completer<AppSnapshot?>();
  bool started = false;

  void complete() => _result.complete(
    const AppSnapshot(
      role: UserRole.member,
      isDarkMode: false,
      weightUnit: 'kg',
      restDefaultSeconds: 90,
      sessions: {},
      routines: [],
    ),
  );

  @override
  Future<AppSnapshot?> load(List<ExerciseTemplate> exerciseCatalog) {
    started = true;
    return _result.future;
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}
}

class _CoachingRepository implements CoachingWorkoutRepository {
  @override
  Future<List<CoachingWorkout>> listCoachingWorkouts({
    String? memberUserId,
  }) async => [
    CoachingWorkout(
      id: 'notified-workout',
      kind: CoachingWorkoutKind.assignment,
      status: CoachingWorkoutStatus.assigned,
      trainerId: 'trainer-a',
      memberUserId: 'member-a',
      trainerName: '담당 트레이너',
      memberName: '회원',
      title: '알림으로 받은 하체 과제',
      instruction: '준비 운동 후 시작해주세요.',
      date: DateTime(2026, 9, 11),
      session: WorkoutSession(date: DateTime(2026, 9, 11), exercises: []),
      version: 1,
      canEdit: false,
      recordingAllowed: true,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ColdStartPush extends DisabledPushService {
  _ColdStartPush(this.notification);

  final PushOpen notification;
  final events = StreamController<PushOpen>.broadcast();
  bool initialRead = false;

  @override
  Stream<PushOpen> get opens => events.stream;

  @override
  Future<PushOpen?> initialOpen() async {
    initialRead = true;
    return notification;
  }
}

class _SignedInMember implements AuthService {
  @override
  AuthUser get currentUser => const AuthUser(id: 'member-a', displayName: '회원');

  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => '회원';

  @override
  Stream<AuthChange> get authChanges => const Stream.empty();

  @override
  Future<bool> isVerifiedAdmin() async => false;

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
