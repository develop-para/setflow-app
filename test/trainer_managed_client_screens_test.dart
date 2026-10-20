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

const _client = TrainerManagedClient(
  id: 'client-one',
  name: '민지',
  phone: '01012345678',
  notes: '오른쪽 어깨 상태 확인',
);
const _link = TrainerClientLink(
  clientId: 'client-one',
  trainerName: '지훈',
  clientName: '민지',
  isSharing: true,
);
final _today = DateUtils.dateOnly(DateTime.now());
const _token =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  tearDown(Auth.reset);

  testWidgets('client form validates and retries the identical registration', (
    tester,
  ) async {
    final repository = _Repository(createFailures: 1);
    final state = _state(repository);
    await _mount(tester, state, const TrainerClientFormScreen());

    await tester.tap(find.byKey(const ValueKey('managed-client-save')));
    await tester.pumpAndSettle();
    expect(find.text('이름을 입력해주세요.'), findsOneWidget);
    expect(find.text('휴대폰 번호를 확인해주세요.'), findsOneWidget);
    expect(repository.createCalls, isEmpty);

    await _enter(tester, 'managed-client-name', ' 민지 ');
    await _enter(tester, 'managed-client-phone', '010-1234-5678');
    await _enter(tester, 'managed-client-notes', ' 어깨 상태 확인 ');
    await tester.ensureVisible(
      find.byKey(const ValueKey('managed-client-save')),
    );
    await tester.tap(find.byKey(const ValueKey('managed-client-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('입력을 유지한 채 같은 내용'), findsOneWidget);
    final name = tester.widget<TextFormField>(
      find.descendant(
        of: find.byKey(const ValueKey('managed-client-name')),
        matching: find.byType(TextFormField),
      ),
    );
    expect(name.enabled, isFalse);
    expect(name.controller!.text, ' 민지 ');
    await tester.ensureVisible(find.text('같은 내용으로 다시 저장'));
    await tester.tap(find.text('같은 내용으로 다시 저장'));
    await tester.pumpAndSettle();

    expect(repository.createCalls, hasLength(2));
    expect(repository.createCalls[0], repository.createCalls[1]);
    expect(repository.createCalls.first.$1, '민지');
    expect(repository.createCalls.first.$2, '010-1234-5678');
    expect(repository.createCalls.first.$3, '어깨 상태 확인');
    expect(
      repository.createCalls.first.$4,
      matches(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    );
    expect(state.sessions, isEmpty);
  });

  testWidgets('registration opens the new member calendar without booking', (
    tester,
  ) async {
    final repository = _Repository();
    final state = _state(repository);
    await _mount(
      tester,
      state,
      const Scaffold(
        body: SingleChildScrollView(child: TrainerManagedClientsPanel()),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('trainer-add-managed-client')));
    await tester.pumpAndSettle();
    await _enter(tester, 'managed-client-name', '민지');
    await _enter(tester, 'managed-client-phone', '01012345678');
    await tester.tap(find.byKey(const ValueKey('managed-client-save')));
    await tester.pumpAndSettle();

    expect(find.byType(TrainerManagedClientScreen), findsOneWidget);
    expect(find.text('민지'), findsOneWidget);
    expect(repository.loadedClientIds, ['client-one']);
    expect(find.text('회원 앱 연결 코드'), findsOneWidget);
    expect(state.sessions, isEmpty);
  });

  testWidgets('trainer can update a member name, phone, and private notes', (
    tester,
  ) async {
    final repository = _Repository(clients: [_client]);
    final state = _state(repository);
    await _mount(
      tester,
      state,
      const TrainerManagedClientScreen(client: _client),
    );
    await tester.tap(find.byTooltip('회원 정보와 관리 메모 수정'));
    await tester.pumpAndSettle();
    await _enter(tester, 'managed-client-name', '김민지');
    await _enter(tester, 'managed-client-phone', '01087654321');
    await _enter(tester, 'managed-client-notes', '새로운 관리 메모');
    await tester.ensureVisible(
      find.byKey(const ValueKey('managed-client-save')),
    );
    await tester.tap(find.byKey(const ValueKey('managed-client-save')));
    await tester.pumpAndSettle();

    expect(repository.updatedClientIds, ['client-one']);
    expect(find.text('김민지'), findsOneWidget);
    expect(find.text('01087654321'), findsOneWidget);
    expect(find.text('새로운 관리 메모'), findsOneWidget);
    expect(find.text('회원 앱 연결 코드'), findsOneWidget);
    expect(state.sessions, isEmpty);
  });

  testWidgets('an empty calendar date launches that member workout editor', (
    tester,
  ) async {
    final repository = _Repository();
    final state = _state(repository);
    await _mount(
      tester,
      state,
      const TrainerManagedClientScreen(client: _client),
    );
    final date = DateTime(_today.year, _today.month, _today.day == 1 ? 2 : 1);
    final dateKey =
        'history-calendar-day-${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    await tester.ensureVisible(find.byKey(ValueKey(dateKey)));
    await tester.tap(find.byKey(ValueKey(dateKey)));
    await tester.pumpAndSettle();
    final editor = tester.widget<TrainerClientWorkoutScreen>(
      find.byType(TrainerClientWorkoutScreen),
    );
    expect(editor.client.id, _client.id);
    expect(editor.date, date);
    expect(editor.workout, isNull);
    expect(
      find.byKey(const ValueKey('client-workout-add-exercise')),
      findsOneWidget,
    );
    expect(state.sessions, isEmpty);
  });

  testWidgets(
    'member calendar identifies both authors and edits trainer records only',
    (tester) async {
      final repository = _Repository(
        records: [
          _record('member-own', member: true),
          _record('trainer-authored'),
        ],
      );
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const TrainerManagedClientScreen(client: _client),
      );
      final todayKey =
          'history-calendar-day-${_today.year}-'
          '${_today.month.toString().padLeft(2, '0')}-'
          '${_today.day.toString().padLeft(2, '0')}';
      await tester.ensureVisible(find.byKey(ValueKey(todayKey)));
      await tester.tap(find.byKey(ValueKey(todayKey)));
      await tester.pumpAndSettle();
      expect(find.byType(TrainerClientWorkoutScreen), findsNothing);
      await tester.ensureVisible(find.text('기록 이어서 작성·수정'));
      await tester.pumpAndSettle();

      expect(find.text('회원 직접 기록'), findsOneWidget);
      expect(find.text('트레이너 기록 · 지훈'), findsOneWidget);
      expect(find.text('회원이 남긴 메모'), findsOneWidget);
      expect(find.text('수업 메모'), findsOneWidget);
      expect(find.text('1세트 · 40.0kg × 8회 · 휴식 90초 · 완료'), findsNWidgets(2));
      expect(find.text('기록 이어서 작성·수정'), findsOneWidget);
      await tester.tap(find.text('기록 이어서 작성·수정'));
      await tester.pumpAndSettle();
      final editor = tester.widget<TrainerClientWorkoutScreen>(
        find.byType(TrainerClientWorkoutScreen),
      );
      expect(editor.workout!.id, 'trainer-authored');
      expect(editor.workout!.source, TrainerClientWorkoutSource.trainer);
      expect(repository.savedWorkouts, isEmpty);
    },
  );

  testWidgets(
    'a notes-only workout marks its date and reopens its saved notes',
    (tester) async {
      final repository = _Repository(
        records: [
          TrainerClientWorkout(
            id: 'notes-only',
            clientId: _client.id,
            session: WorkoutSession(date: _today, exercises: []),
            notes: '오늘은 어깨 상태만 확인했어요.',
            authorName: '지훈',
            source: TrainerClientWorkoutSource.trainer,
            version: 1,
            canEdit: true,
          ),
        ],
      );
      final state = _state(repository);
      await _mount(
        tester,
        state,
        const TrainerManagedClientScreen(client: _client),
      );
      final dateKey =
          'history-calendar-day-${_today.year}-'
          '${_today.month.toString().padLeft(2, '0')}-'
          '${_today.day.toString().padLeft(2, '0')}';
      final cell = find.byKey(ValueKey(dateKey));
      await tester.ensureVisible(cell);
      expect(
        find.descendant(of: cell, matching: find.text('메모')),
        findsOneWidget,
      );
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.byType(TrainerClientWorkoutScreen), findsNothing);
      await tester.ensureVisible(find.text('오늘은 어깨 상태만 확인했어요.'));
      expect(find.text('오늘은 어깨 상태만 확인했어요.'), findsOneWidget);
      expect(find.text('기록 이어서 작성·수정'), findsOneWidget);
      expect(state.sessions, isEmpty);
    },
  );

  testWidgets(
    'member explicitly consents and retries with the same invitation',
    (tester) async {
      final repository = _Repository(acceptFailures: 1);
      final state = _state(repository, member: true);
      await _mount(tester, state, const MyTrainerClientRecordsScreen());
      await tester.tap(
        find.byKey(const ValueKey('accept-managed-client-invite')),
      );
      await tester.pumpAndSettle();
      await _enter(tester, 'managed-client-invite-token', ' invalid-code ');
      final accept = find.byKey(const ValueKey('managed-client-invite-accept'));
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      expect(repository.acceptCalls, isEmpty);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(repository.acceptCalls, isEmpty);
      await _enter(tester, 'managed-client-invite-token', ' $_token ');
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(find.textContaining('같은 코드로 다시 시도'), findsOneWidget);
      expect(repository.acceptCalls, hasLength(1));
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();

      expect(repository.acceptCalls, hasLength(2));
      expect(repository.acceptCalls.first, repository.acceptCalls.last);
      expect(repository.acceptCalls.first.$1, _token);
      expect(find.text('트레이너 관리 기록'), findsOneWidget);
      expect(repository.myRecordLoads, 2);
      expect(state.sessions, isEmpty);
    },
  );

  testWidgets(
    'member sees personal and trainer workouts without private management notes',
    (tester) async {
      final repository = _Repository(records: [_record('trainer-authored')]);
      final state = _state(repository, member: true);
      state.sessions[_today] = _session();
      await _mount(tester, state, const MyTrainerClientRecordsScreen());
      await tester.ensureVisible(find.text('수업 메모'));
      await tester.pumpAndSettle();

      expect(find.text('회원 직접 기록'), findsOneWidget);
      expect(find.text('트레이너 기록 · 지훈'), findsOneWidget);
      expect(find.text('1세트 · 40.0kg × 8회 · 휴식 90초 · 완료'), findsNWidgets(2));
      expect(find.text(_client.notes), findsNothing);
      expect(find.text('기록 이어서 작성·수정'), findsNothing);
      expect(state.sessions[_today]!.exercises, hasLength(1));
    },
  );

  testWidgets('member can unlink a trainer before any workout exists', (
    tester,
  ) async {
    final repository = _Repository(links: [_link]);
    final state = _state(repository, member: true);
    await _mount(tester, state, const MyTrainerClientRecordsScreen());
    final unlink = find.text('지훈 연결 해제');
    await tester.ensureVisible(unlink);
    await tester.tap(unlink);
    await tester.pumpAndSettle();
    expect(repository.endedLinks, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '연결 해제'));
    await tester.pumpAndSettle();

    expect(repository.endedLinks, hasLength(1));
    expect(repository.endedLinks.single.$1, 'client-one');
    expect(unlink, findsNothing);
    expect(repository.myRecordLoads, 2);
    expect(state.sessions, isEmpty);
  });

  for (final entry in <String, Widget>{
    'registration': const TrainerClientFormScreen(),
    'roster': const Scaffold(
      body: SingleChildScrollView(child: TrainerManagedClientsPanel()),
    ),
    'calendar': const TrainerManagedClientScreen(client: _client),
    'member records': const MyTrainerClientRecordsScreen(),
  }.entries) {
    testWidgets('${entry.key} fits 320px with double text size', (
      tester,
    ) async {
      final repository = _Repository(
        clients: [_client],
        records: [_record('trainer-authored')],
        links: [_link],
      );
      final state = _state(repository, member: entry.key == 'member records');
      await _mount(tester, state, entry.value, small: true);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final field = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextFormField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

AppState _state(_Repository repository, {bool member = false}) {
  final role = member ? UserRole.member : UserRole.trainer;
  final user = member ? 'member-user' : 'trainer-user';
  Auth.use(_SignedIn(user));
  return AppState(businessRepository: repository)
    ..role = role
    ..businessAccess = BusinessAccess(
      userId: user,
      accountRole: role,
      resolvedRole: role,
      availableRoles: {UserRole.member, if (!member) UserRole.trainer},
    );
}

Future<void> _mount(
  WidgetTester tester,
  AppState state,
  Widget page, {
  bool small = false,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 740) : const Size(432, 1100),
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
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(small ? 2 : 1)),
          child: child!,
        ),
        home: Navigator(
          onGenerateInitialRoutes: (_, _) => [
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('테스트 시작')),
            ),
            MaterialPageRoute<void>(builder: (_) => page),
          ],
          onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => page),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

WorkoutSession _session() => WorkoutSession(
  date: _today,
  exercises: [
    WorkoutExercise(
      id: 'exercise-one',
      template: const ExerciseTemplate(
        id: 'bench',
        name: '벤치 프레스',
        muscle: '가슴',
        icon: SetflowIcons.record,
      ),
      sets: [WorkoutSetEntry(number: 1, weight: 40, reps: 8, completed: true)],
    ),
  ],
);

TrainerClientWorkout _record(String id, {bool member = false}) =>
    TrainerClientWorkout(
      id: id,
      clientId: _client.id,
      session: _session(),
      notes: member ? '회원이 남긴 메모' : '수업 메모',
      authorName: member ? '민지' : '지훈',
      source: member
          ? TrainerClientWorkoutSource.member
          : TrainerClientWorkoutSource.trainer,
      version: 1,
      canEdit: !member,
    );

class _SignedIn implements AuthService {
  _SignedIn(this.id);
  final String id;
  @override
  AuthUser get currentUser => AuthUser(id: id, displayName: '사용자');
  @override
  bool get hasAuthenticatedUser => true;
  @override
  String get currentDisplayName => '사용자';
  @override
  Stream<AuthChange> get authChanges => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements BusinessRepository, TrainerClientRepository {
  _Repository({
    this.createFailures = 0,
    this.acceptFailures = 0,
    this.clients = const [],
    this.records = const [],
    this.links = const [],
  });
  int createFailures;
  int acceptFailures;
  List<TrainerManagedClient> clients;
  List<TrainerClientWorkout> records;
  List<TrainerClientLink> links;
  final createCalls = <(String, String, String, String)>[];
  final acceptCalls = <(String, String)>[];
  final endedLinks = <(String, String)>[];
  final loadedClientIds = <String>[];
  final updatedClientIds = <String>[];
  final savedWorkouts = <WorkoutSession>[];
  int myRecordLoads = 0;

  @override
  Future<List<TrainerManagedClient>> listTrainerClients() async => clients;
  @override
  Future<TrainerManagedClient> createTrainerClient({
    required String name,
    required String phone,
    required String notes,
    required String requestId,
  }) async {
    createCalls.add((name, phone, notes, requestId));
    if (createFailures > 0) {
      createFailures--;
      throw StateError('response lost');
    }
    final created = TrainerManagedClient(
      id: _client.id,
      name: name,
      phone: phone,
      notes: notes,
    );
    clients = [...clients, created];
    return created;
  }

  @override
  Future<List<TrainerClientWorkout>> listTrainerClientWorkouts(
    String clientId,
  ) async {
    loadedClientIds.add(clientId);
    return records;
  }

  @override
  Future<TrainerManagedClient> updateTrainerClient({
    required String clientId,
    required String name,
    required String phone,
    required String notes,
    required String requestId,
  }) async {
    updatedClientIds.add(clientId);
    return TrainerManagedClient(
      id: clientId,
      name: name,
      phone: phone,
      notes: notes,
    );
  }

  @override
  Future<List<TrainerClientWorkout>> listMyTrainerClientWorkouts() async {
    myRecordLoads++;
    return records;
  }

  @override
  Future<List<TrainerClientLink>> listMyTrainerClientLinks() async => links;
  @override
  Future<void> acceptTrainerClientInvitation(
    String token, {
    required String requestId,
  }) async {
    acceptCalls.add((token, requestId));
    if (acceptFailures > 0) {
      acceptFailures--;
      throw StateError('response lost');
    }
    links = [_link];
  }

  @override
  Future<void> endMyTrainerClientLink(
    String clientId, {
    required String requestId,
  }) async {
    endedLinks.add((clientId, requestId));
    links = links.where((link) => link.clientId != clientId).toList();
  }

  @override
  Future<TrainerClientWorkout> saveTrainerClientWorkout({
    required String clientId,
    required WorkoutSession session,
    required String notes,
    required String requestId,
    required String workoutId,
    required int expectedVersion,
  }) async {
    savedWorkouts.add(session);
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
