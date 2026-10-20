import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/trainer_client_repository.dart';
import 'package:setflow/screens/coaching_workout_screens.dart';
import 'package:setflow/screens/trainer_client_workout_screen.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';

const _client = TrainerManagedClient(
  id: 'client-1',
  name: '민지',
  phone: '01012345678',
  notes: '',
);
const _strength = ExerciseTemplate(
  id: 'client-squat',
  name: '스쿼트',
  muscle: '하체',
  icon: SetflowIcons.record,
);
const _cardio = ExerciseTemplate(
  id: 'client-cardio',
  name: '달리기',
  muscle: '유산소',
  icon: SetflowIcons.record,
);
final _date = DateTime(2026, 10, 19);

void main() {
  testWidgets('creates a dated member note without changing trainer sessions', (
    tester,
  ) async {
    final repository = _Repository();
    final state = await _mount(tester, repository);
    final personal = WorkoutSession(date: _date, exercises: []);
    state.sessions[_date] = personal;
    await tester.enterText(
      find.byKey(const ValueKey('client-workout-notes')),
      '어깨 상태 확인',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('client-workout-save')));
    await tester.pumpAndSettle();
    expect(repository.saves.single.clientId, _client.id);
    expect(repository.saves.single.session.date, _date);
    expect(repository.saves.single.session.exercises, isEmpty);
    expect(repository.saves.single.notes, '어깨 상태 확인');
    expect(repository.saves.single.version, 0);
    expect(state.sessions[_date], same(personal));
    expect(find.byType(TrainerClientWorkoutScreen), findsNothing);
    await _unmount(tester, state);
  });

  testWidgets(
    'strength uses apply-only dials, sequential swipes, collapsed completed rows',
    (tester) async {
      final repository = _Repository();
      final original = _workout();
      final before = AppSnapshotCodec.sessionToJson(original.session);
      final state = await _mount(tester, repository, workout: original);
      final rows = find.byType(CoachingSetRow);
      final first = tester.widget<CoachingSetRow>(rows.at(0));
      final second = tester.widget<CoachingSetRow>(rows.at(1));
      expect(first.live, isTrue);
      expect(second.live, isFalse);
      expect(
        tester
            .widget<Dismissible>(
              find.descendant(
                of: rows.at(1),
                matching: find.byType(Dismissible),
              ),
            )
            .direction,
        DismissDirection.none,
      );

      final weight = find.byKey(
        const ValueKey('coaching-value-client-squat-1-무게'),
      );
      await tester.tap(weight);
      await tester.pumpAndSettle();
      expect(find.text('적용'), findsOneWidget);
      Navigator.of(tester.element(find.text('적용'))).pop();
      await tester.pumpAndSettle();
      expect(tester.widget<CoachingSetRow>(rows.first).set.weight, 50);
      expect(repository.saves, isEmpty);

      await _swipe(tester, rows.first, right: true);
      expect(tester.widget<CoachingSetRow>(rows.first).set.completed, isTrue);
      expect(find.text('1세트  50kg × 8회 · 완료'), findsOneWidget);
      expect(tester.widget<CoachingSetRow>(rows.at(1)).live, isTrue);
      expect(tester.widget<CoachingSetRow>(rows.at(1)).set.weight, 60);
      expect(tester.widget<CoachingSetRow>(rows.at(1)).set.reps, 10);
      expect(repository.saves, isEmpty);
      expect(AppSnapshotCodec.sessionToJson(original.session), before);
      await tester.tap(find.byKey(const ValueKey('client-workout-save')));
      await tester.pumpAndSettle();
      expect(repository.saves.single.session.completedSets, 1);
      expect(repository.saves.single.session.startedAt, isNull);
      expect(state.sessions, isEmpty);
      await _unmount(tester, state);
    },
  );

  testWidgets('propagation has undo and preserves observed RIR and RPE', (
    tester,
  ) async {
    final repository = _Repository();
    final original = _workout();
    original.session.exercises.single.sets[1].weight = 40;
    original.session.exercises.single.sets.first.rir = 2;
    original.session.exercises.single.sets.first.intensityRpe = 8;
    final state = await _mount(tester, repository, workout: original);
    await _swipe(tester, find.byType(CoachingSetRow).first, right: true);
    var second = tester
        .widget<CoachingSetRow>(find.byType(CoachingSetRow).at(1))
        .set;
    expect(second.reps, 8);
    expect(second.weight, 50);
    expect(second.rir, isNull);
    expect(second.intensityRpe, 0);
    await tester.tap(find.text('되돌리기'));
    await tester.pump();
    second = tester
        .widget<CoachingSetRow>(find.byType(CoachingSetRow).at(1))
        .set;
    expect(second.reps, 10);
    expect(second.weight, 40);
    await tester.tap(find.byKey(const ValueKey('client-workout-save')));
    await tester.pumpAndSettle();
    final saved = repository.saves.single.session.exercises.single.sets;
    expect(saved.first.completed, isTrue);
    expect(saved.first.rir, 2);
    expect(saved.first.intensityRpe, 8);
    expect(saved.last.completed, isFalse);
    await _unmount(tester, state);
  });

  testWidgets('new exercise starts as a plan and left swipe deletes a set', (
    tester,
  ) async {
    final repository = _Repository();
    final state = await _mount(tester, repository);
    await tester.tap(find.byKey(const ValueKey('client-workout-add-exercise')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '종목 검색'), '스쿼트');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '스쿼트').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CoachingSetRow>(find.byType(CoachingSetRow)).set.completed,
      isFalse,
    );
    await tester.ensureVisible(find.text('세트 추가'));
    await tester.pump();
    await tester.tap(find.text('세트 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachingSetRow), findsNWidgets(2));
    await _swipe(tester, find.byType(CoachingSetRow).first, right: false);
    expect(find.byType(CoachingSetRow), findsOneWidget);
    expect(
      tester.widget<CoachingSetRow>(find.byType(CoachingSetRow)).set.number,
      1,
    );
    await tester.tap(find.byKey(const ValueKey('client-workout-save')));
    await tester.pumpAndSettle();
    expect(repository.saves.single.session.completedSets, 0);
    expect(repository.saves.single.session.totalSets, 1);
    expect(state.sessions, isEmpty);
    await _unmount(tester, state);
  });

  testWidgets(
    'concurrent first save reviews same-day server entry before replacing draft',
    (tester) async {
      final repository = _Repository()..conflict = true;
      final latest = _workout();
      repository.latest = TrainerClientWorkout(
        id: latest.id,
        clientId: _client.id,
        session: latest.session,
        notes: '다른 기기에서 적은 내용',
        authorName: latest.authorName,
        source: latest.source,
        version: 9,
        canEdit: true,
      );
      final state = await _mount(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('client-workout-notes')),
        '내가 적은 내용',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('client-workout-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('최신 기록 확인').last);
      await tester.pumpAndSettle();
      expect(find.text('내가 적은 내용'), findsWidgets);
      expect(find.text('다른 기기에서 적은 내용'), findsOneWidget);
      await tester.tap(find.text('입력 유지'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('client-workout-notes')),
            )
            .controller!
            .text,
        '내가 적은 내용',
      );
      await tester.tap(find.text('최신 기록 확인').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('최신 기록으로 전환'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('client-workout-notes')),
            )
            .controller!
            .text,
        '다른 기기에서 적은 내용',
      );
      repository.conflict = false;
      await tester.ensureVisible(
        find.byKey(const ValueKey('client-workout-notes')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('client-workout-notes')),
        '확인 후 보완',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('client-workout-save')));
      await tester.pumpAndSettle();
      expect(repository.saves.last.id, latest.id);
      expect(repository.saves.last.version, 9);
      expect(repository.saves.first.id, isNot(latest.id));
      expect(
        repository.saves.first.requestId,
        isNot(repository.saves.last.requestId),
      );
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'failed save freezes the payload and retries the same id and request',
    (tester) async {
      final repository = _Repository()..fail = true;
      final state = await _mount(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('client-workout-notes')),
        '저장할 메모',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('client-workout-save')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('client-workout-save-error')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('client-workout-notes')),
            )
            .readOnly,
        isTrue,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('client-workout-add-exercise')),
            )
            .onPressed,
        isNull,
      );
      repository.fail = false;
      await tester.tap(find.byKey(const ValueKey('client-workout-save')));
      await tester.pumpAndSettle();
      expect(repository.saves, hasLength(2));
      expect(repository.saves[0].id, repository.saves[1].id);
      expect(repository.saves[0].requestId, repository.saves[1].requestId);
      expect(repository.saves[0].notes, repository.saves[1].notes);
      expect(
        AppSnapshotCodec.sessionToJson(repository.saves[0].session),
        AppSnapshotCodec.sessionToJson(repository.saves[1].session),
      );
      await _unmount(tester, state);
    },
  );

  testWidgets('back navigation keeps draft until an explicit discard', (
    tester,
  ) async {
    final repository = _Repository();
    final state = await _mount(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('client-workout-notes')),
      '아직 작성 중',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('아직 저장 전이에요'), findsOneWidget);
    await tester.tap(find.text('계속 기록'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('client-workout-notes')))
          .controller!
          .text,
      '아직 작성 중',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('버리고 나가기'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainerClientWorkoutScreen), findsNothing);
    expect(repository.saves, isEmpty);
    await _unmount(tester, state);
  });

  testWidgets(
    'member authored records are read only even when canEdit is true',
    (tester) async {
      final repository = _Repository();
      final state = await _mount(
        tester,
        repository,
        workout: _workout(member: true),
      );
      expect(find.text('회원이 직접 기록한 운동'), findsOneWidget);
      expect(find.byKey(const ValueKey('client-workout-save')), findsNothing);
      expect(
        find.byKey(const ValueKey('client-workout-add-exercise')),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('client-workout-notes')),
            )
            .readOnly,
        isTrue,
      );
      for (final row in tester.widgetList<Dismissible>(
        find.byType(Dismissible),
      )) {
        expect(row.direction, DismissDirection.none);
      }
      expect(repository.saves, isEmpty);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'cardio fields, new sets, and fixed save fit large text and system inset',
    (tester) async {
      final repository = _Repository();
      final original = _workout(cardio: true);
      original.session.exercises.single.sets.first.completed = true;
      original.session.exercises.single.sets.first.intensityRpe = 8;
      original.session.exercises.single.sets.first.rir = 1;
      final state = await _mount(
        tester,
        repository,
        workout: original,
        small: true,
      );
      await tester.ensureVisible(find.text('세트 추가'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('세트 추가'));
      await tester.pumpAndSettle();
      final last = tester
          .widget<CoachingSetRow>(find.byType(CoachingSetRow).last)
          .set;
      expect(last.completed, isFalse);
      expect(last.intensityRpe, 0);
      expect(last.rir, isNull);
      final time = find.byKey(
        const ValueKey('coaching-value-client-cardio-2-시간'),
      );
      await tester.ensureVisible(time);
      await tester.pumpAndSettle();
      await tester.tap(time);
      await tester.pumpAndSettle();
      expect(find.text('적용'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('적용'))).pop();
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('client-workout-save'));
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(740 - 28));
      expect(tester.takeException(), isNull);
      await _unmount(tester, state);
    },
  );

  testWidgets(
    'account change closes an open dial and removes the client draft',
    (tester) async {
      final repository = _Repository();
      final state = await _mount(tester, repository, workout: _workout());
      await tester.tap(
        find.byKey(const ValueKey('coaching-value-client-squat-1-무게')),
      );
      await tester.pumpAndSettle();
      state.changeAccount();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('coaching-account-expired')),
        findsOneWidget,
      );
      expect(find.text('적용'), findsNothing);
      expect(find.byKey(const ValueKey('client-workout-notes')), findsNothing);
      expect(repository.saves, isEmpty);
      await _unmount(tester, state);
    },
  );
}

TrainerClientWorkout _workout({bool member = false, bool cardio = false}) =>
    TrainerClientWorkout(
      id: 'workout-1',
      clientId: _client.id,
      session: WorkoutSession(
        date: _date,
        exercises: [
          WorkoutExercise(
            id: 'exercise-1',
            template: cardio ? _cardio : _strength,
            sets: [
              WorkoutSetEntry(
                number: 1,
                weight: 50,
                reps: 8,
                durationSeconds: cardio ? 600 : 0,
              ),
              if (!cardio) WorkoutSetEntry(number: 2, weight: 60, reps: 10),
            ],
          ),
        ],
      ),
      notes: '',
      authorName: '지훈',
      source: member
          ? TrainerClientWorkoutSource.member
          : TrainerClientWorkoutSource.trainer,
      version: 1,
      canEdit: true,
    );

class _State extends AppState {
  _State(BusinessRepository repository) : super(businessRepository: repository);
  void changeAccount() {
    businessAccess = const BusinessAccess(
      userId: 'other',
      accountRole: UserRole.member,
      resolvedRole: UserRole.member,
      availableRoles: {UserRole.member},
    );
    role = UserRole.member;
    notifyListeners();
  }
}

Future<_State> _mount(
  WidgetTester tester,
  _Repository repository, {
  TrainerClientWorkout? workout,
  bool small = false,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 740) : const Size(430, 1100),
  );
  final state = _State(repository)
    ..role = UserRole.trainer
    ..businessAccess = const BusinessAccess(
      userId: 'trainer-1',
      accountRole: UserRole.trainer,
      resolvedRole: UserRole.trainer,
      availableRoles: {UserRole.member, UserRole.trainer},
    );
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(small ? 2 : 1),
            padding: EdgeInsets.only(bottom: small ? 28 : 0),
          ),
          child: child!,
        ),
        home: Navigator(
          onGenerateInitialRoutes: (_, _) => [
            MaterialPageRoute<void>(builder: (_) => const Scaffold()),
            MaterialPageRoute<TrainerClientWorkout>(
              builder: (_) => TrainerClientWorkoutScreen(
                client: _client,
                date: _date,
                workout: workout,
              ),
            ),
          ],
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
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
  await tester.pump();
  final rect = tester.getRect(row);
  final gesture = await tester.startGesture(
    Offset(rect.left + (right ? 20 : rect.width - 20), rect.center.dy),
  );
  for (var index = 0; index < 8; index++) {
    await gesture.moveBy(Offset(rect.width * (right ? .08 : -.08), 0));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 500));
}

class _Save {
  _Save(
    this.clientId,
    this.id,
    this.requestId,
    this.version,
    this.session,
    this.notes,
  );
  final String clientId;
  final String id;
  final String requestId;
  final int version;
  final WorkoutSession session;
  final String notes;
}

class _Repository implements BusinessRepository, TrainerClientRepository {
  final saves = <_Save>[];
  bool fail = false;
  bool conflict = false;
  TrainerClientWorkout? latest;

  @override
  Future<List<TrainerClientWorkout>> listTrainerClientWorkouts(
    String clientId,
  ) async => [?latest];

  @override
  Future<TrainerClientWorkout> saveTrainerClientWorkout({
    required String clientId,
    required WorkoutSession session,
    required String notes,
    required String requestId,
    required String workoutId,
    required int expectedVersion,
  }) async {
    saves.add(
      _Save(clientId, workoutId, requestId, expectedVersion, session, notes),
    );
    if (conflict) throw const TrainerClientWorkoutConflict();
    if (fail) throw StateError('connection unavailable');
    return TrainerClientWorkout(
      id: workoutId,
      clientId: clientId,
      session: session,
      notes: notes,
      authorName: '지훈',
      source: TrainerClientWorkoutSource.trainer,
      version: expectedVersion + 1,
      canEdit: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
