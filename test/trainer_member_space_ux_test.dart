import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/trainer_client_repository.dart';
import 'package:setflow/screens/trainer_client_workout_screen.dart';
import 'package:setflow/screens/trainer_managed_client_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';
import 'package:setflow/widgets/workout_history_calendar.dart';

const _client = TrainerManagedClient(
  id: 'client-one',
  name: '민지',
  phone: '01012345678',
  notes: '오른쪽 어깨 상태 확인\n운동 전 통증 여부를 확인해주세요.',
);
final _today = DateUtils.dateOnly(DateTime.now());

void main() {
  tearDown(Auth.reset);

  testWidgets('one visible record action resumes only the trainer record', (
    tester,
  ) async {
    final repository = _Repository(
      records: [_record('member-own', member: true), _record('trainer-own')],
    );
    await _mount(tester, repository);

    final action = find.byKey(const ValueKey('managed-client-add-workout'));
    expect(action.hitTestable(), findsOneWidget);
    expect(find.text('기록 이어서 작성'), findsOneWidget);
    expect(find.text('회원 앱 연결 코드'), findsNothing);
    expect(find.text('기록 이어서 작성·수정'), findsNothing);

    await tester.tap(action);
    await tester.pumpAndSettle();
    final editor = tester.widget<TrainerClientWorkoutScreen>(
      find.byType(TrainerClientWorkoutScreen),
    );
    expect(editor.workout!.id, 'trainer-own');
    expect(editor.client.id, _client.id);
    expect(editor.date, _today);
  });

  testWidgets('selecting a saved date updates the single record action', (
    tester,
  ) async {
    final otherDate = DateTime(
      _today.year,
      _today.month,
      _today.day == 1 ? 2 : 1,
    );
    final repository = _Repository(
      records: [
        _record('today'),
        _record('other-date', date: otherDate),
      ],
    );
    await _mount(tester, repository);
    final cell = find.byKey(
      ValueKey(
        'history-calendar-day-${otherDate.year}-'
        '${otherDate.month.toString().padLeft(2, '0')}-'
        '${otherDate.day.toString().padLeft(2, '0')}',
      ),
    );
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('managed-client-add-workout')));
    await tester.pumpAndSettle();
    final editor = tester.widget<TrainerClientWorkoutScreen>(
      find.byType(TrainerClientWorkoutScreen),
    );
    expect(editor.date, otherDate);
    expect(editor.workout!.id, 'other-date');
  });

  testWidgets(
    'member-authored history stays read-only while adding a trainer note',
    (tester) async {
      final repository = _Repository(
        records: [_record('member-own', member: true)],
      );
      await _mount(tester, repository);
      expect(find.text('운동 기록하기'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('managed-client-add-workout')),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<TrainerClientWorkoutScreen>(
        find.byType(TrainerClientWorkoutScreen),
      );
      expect(editor.workout, isNull);
      expect(editor.date, _today);
    },
  );

  testWidgets('member info exposes full private notes and existing coaching', (
    tester,
  ) async {
    var coachingOpened = 0;
    await _mount(tester, _Repository(), onOpenCoaching: () => coachingOpened++);
    await tester.tap(
      find.byKey(const ValueKey('managed-client-private-notes')),
    );
    await tester.pumpAndSettle();
    expect(find.text(_client.notes), findsOneWidget);
    expect(find.text('트레이너에게만 보여요.'), findsOneWidget);
    expect(find.text('회원 앱 연결 코드'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('managed-client-open-coaching')),
    );
    await tester.pumpAndSettle();
    expect(coachingOpened, 1);
    expect(find.text('트레이너에게만 보여요.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('managed-client-info')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('managed-client-edit-info')));
    await tester.pumpAndSettle();
    expect(find.byType(TrainerClientFormScreen), findsOneWidget);
    expect(find.text(_client.phone), findsOneWidget);
    expect(find.text(_client.notes), findsOneWidget);
  });

  testWidgets(
    'app link retry keeps the same invitation request from member info',
    (tester) async {
      final repository = _Repository(inviteFailures: 1);
      await _mount(tester, repository);
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byKey(const ValueKey('managed-client-info')));
        await tester.pumpAndSettle();
        final connect = find.byKey(
          const ValueKey('managed-client-connect-app'),
        );
        await tester.ensureVisible(connect);
        await tester.tap(connect);
        await tester.pumpAndSettle();
      }
      expect(repository.inviteCalls, hasLength(2));
      expect(repository.inviteCalls[0], repository.inviteCalls[1]);
      expect(find.text('회원 앱 연결'), findsOneWidget);
      expect(find.text('one-use-link-token'), findsOneWidget);
    },
  );

  testWidgets(
    'member info and fixed record action fit small screens with large text',
    (tester) async {
      await _mount(tester, _Repository(), small: true);
      expect(tester.takeException(), isNull);
      final action = find.byKey(const ValueKey('managed-client-add-workout'));
      expect(action.hitTestable(), findsOneWidget);
      final buttonBounds = tester.getRect(action);
      expect(buttonBounds.bottom, lessThanOrEqualTo(740 - 34));
      await tester.tap(find.byKey(const ValueKey('managed-client-info')));
      await tester.pumpAndSettle();
      final connect = find.byKey(const ValueKey('managed-client-connect-app'));
      await tester.ensureVisible(connect);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(connect.hitTestable(), findsOneWidget);
    },
  );

  testWidgets('compact calendar keeps a six-week month readable and tappable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final date = DateTime(2026, 8, 15);
    final day = WorkoutHistoryDay.workout(
      WorkoutSession(
        date: date,
        exercises: [
          WorkoutExercise(
            id: 'bench',
            template: const ExerciseTemplate(
              id: 'bench',
              name: '벤치 프레스',
              muscle: '가슴',
              icon: SetflowIcons.record,
            ),
            sets: [
              WorkoutSetEntry(number: 1, weight: 40, reps: 8, completed: true),
              WorkoutSetEntry(number: 2, weight: 40, reps: 8),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: SetflowInsets.pageList,
            child: WorkoutHistoryCalendar(
              compact: true,
              initialDate: date,
              days: [day],
              recordBuilder: (_) => const Text('선택일 상세'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.childrenDelegate.estimatedChildCount, 42);
    final cell = find.byKey(const ValueKey('history-calendar-day-2026-08-15'));
    expect(tester.getSize(cell).height, 68);
    final dateTarget = find.ancestor(
      of: cell,
      matching: find.byType(Semantics),
    );
    expect(tester.getSize(dateTarget.first).height, greaterThanOrEqualTo(48));
    expect(
      find.descendant(of: cell, matching: find.text('가슴')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cell, matching: find.text('320kg')),
      findsOneWidget,
    );
    final fill = tester.widget<Ink>(
      find.byKey(const ValueKey('history-calendar-fill-2026-08-15')),
    );
    expect((fill.decoration! as BoxDecoration).gradient, isNotNull);
    expect(
      tester.widget<Semantics>(dateTarget.first).properties.label,
      contains('1/2 완료'),
    );
    await tester.ensureVisible(cell);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('선택일 상세'));
    expect(tester.takeException(), isNull);
  });
}

TrainerClientWorkout _record(
  String id, {
  bool member = false,
  DateTime? date,
}) => TrainerClientWorkout(
  id: id,
  clientId: _client.id,
  session: WorkoutSession(date: date ?? _today, exercises: []),
  notes: member ? '회원 메모' : '수업 메모',
  authorName: member ? '민지' : '지훈',
  source: member
      ? TrainerClientWorkoutSource.member
      : TrainerClientWorkoutSource.trainer,
  version: 1,
  canEdit: !member,
);

Future<void> _mount(
  WidgetTester tester,
  _Repository repository, {
  VoidCallback? onOpenCoaching,
  bool small = false,
}) async {
  Auth.use(_SignedIn());
  final state = AppState(businessRepository: repository)
    ..role = UserRole.trainer
    ..businessAccess = BusinessAccess(
      userId: 'trainer-user',
      accountRole: UserRole.trainer,
      resolvedRole: UserRole.trainer,
      availableRoles: {UserRole.member, UserRole.trainer},
    );
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 740) : const Size(432, 900),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    await tester.pump(const Duration(seconds: 4));
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(small ? 2 : 1),
            padding: const EdgeInsets.only(bottom: 34),
          ),
          child: child!,
        ),
        home: TrainerManagedClientScreen(
          client: _client,
          onOpenCoaching: onOpenCoaching,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SignedIn implements AuthService {
  @override
  AuthUser get currentUser =>
      const AuthUser(id: 'trainer-user', displayName: '지훈');
  @override
  bool get hasAuthenticatedUser => true;
  @override
  String get currentDisplayName => '지훈';
  @override
  Stream<AuthChange> get authChanges => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements BusinessRepository, TrainerClientRepository {
  _Repository({this.records = const [], this.inviteFailures = 0});
  final List<TrainerClientWorkout> records;
  int inviteFailures;
  final inviteCalls = <(String, DateTime, String)>[];

  @override
  Future<List<TrainerManagedClient>> listTrainerClients() async => [_client];
  @override
  Future<List<TrainerClientWorkout>> listTrainerClientWorkouts(
    String clientId,
  ) async => records;
  @override
  Future<TrainerClientInvitation> createTrainerClientInvitation({
    required String clientId,
    required DateTime expiresAt,
    required String requestId,
  }) async {
    inviteCalls.add((clientId, expiresAt, requestId));
    if (inviteFailures-- > 0) throw StateError('response lost');
    return TrainerClientInvitation(
      clientId: clientId,
      token: 'one-use-link-token',
      expiresAt: expiresAt,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
