import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

/// Rest used to put a full-screen panel over everything; testers found it in
/// the way. Now the rest bar under the header is the only rest surface, and
/// this covers what it has to do — say where you are, give +30초 in one tap,
/// let you out in one tap, and never carry a stale story into a shared rest.
void main() {
  final date = DateTime(2026, 11, 6);

  Future<AppState> pumpDay(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    state.addExercise(date, state.exercises[1]);
    final session = state.sessions[state.dateOnly(date)]!;
    while (session.exercises.first.sets.length < 2) {
      state.addSet(session.exercises.first);
    }
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: date),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  WorkoutSession sessionOf(AppState state) =>
      state.sessions[state.dateOnly(date)]!;

  /// The bar exactly as main.dart mounts it, fed from the state's rest focus.
  Widget barFor(AppState state) {
    return AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state,
            builder: (context, _) => state.restRemaining > 0
                ? GlobalRestTimerOverlay(
                    seconds: state.restRemaining,
                    totalSeconds: state.restDefaultSeconds,
                    exerciseName: state.restFocus?.exerciseName,
                    setsLeft: state.restFocus?.setsLeft ?? 0,
                    nextExercise: state.restFocus?.nextExercise,
                    onAddTime: state.extendRestTimer,
                    onCancel: state.cancelRestTimer,
                  )
                : const Text('휴식 없음'),
          ),
        ),
      ),
    );
  }

  test('rest focus says how many sets are left', () async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    final session = state.sessions[state.dateOnly(date)]!;
    final exercise = session.exercises.single;
    state.addSet(exercise);

    final total = exercise.sets.length;
    exercise.sets.first.completed = true;
    final focus = AppState.restFocusFor(session, exercise);
    expect(focus.setsLeft, total - 1);
    expect(focus.exerciseName, exercise.template.name);
    expect(focus.nextExercise, isNull);
  });

  test('once an exercise is done the focus names what comes next', () async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    state.addExercise(date, state.exercises[1]);
    final session = state.sessions[state.dateOnly(date)]!;
    final first = session.exercises.first;

    for (final set in first.sets) {
      set.completed = true;
    }
    final focus = AppState.restFocusFor(session, first);

    expect(focus.setsLeft, 0);
    expect(
      focus.nextExercise,
      session.exercises[1].template.name,
      reason: '다음 종목을 못 찾았다',
    );
  });

  test('the last exercise has nothing after it', () async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    final session = state.sessions[state.dateOnly(date)]!;
    final only = session.exercises.single;
    for (final set in only.sets) {
      set.completed = true;
    }
    final focus = AppState.restFocusFor(session, only);

    expect(focus.setsLeft, 0);
    expect(focus.nextExercise, isNull);
  });

  test('completing a set fills the focus before the timer starts', () async {
    // The notification's second line rides on the start intent, so the focus
    // has to be there when the timer is started — not stamped on afterwards.
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    final session = state.sessions[state.dateOnly(date)]!;
    final exercise = session.exercises.single;
    state.addSet(exercise);

    await state.toggleSet(exercise.sets.first);

    expect(state.restRemaining, greaterThan(0));
    expect(state.restFocus, isNotNull, reason: '휴식 바가 말할 내용이 비었다');
    expect(state.restFocus!.exerciseName, exercise.template.name);
    expect(
      state.restFocus!.setsLeft,
      exercise.sets.where((s) => !s.completed).length,
    );
    expect(state.restTimerDetail, contains(exercise.template.name));

    state.cancelRestTimer();
  });

  test('a rest that is not about a set carries no stale story', () async {
    // A shared rest from a together room starts the same timer. The bar must
    // not keep telling you about the set you finished ten minutes ago.
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    final session = state.sessions[state.dateOnly(date)]!;
    final exercise = session.exercises.single;
    await state.toggleSet(exercise.sets.first);
    expect(state.restFocus, isNotNull);

    state.startRestTimer(60);

    expect(state.restFocus, isNull, reason: '지난 세트 얘기가 공유 휴식에 남았다');
    expect(state.restTimerDetail, isNull);

    state.cancelRestTimer();
  });

  testWidgets('logging a set starts a rest that knows where you are', (
    tester,
  ) async {
    final state = await pumpDay(tester);

    // 종목이 둘이라 1세트 키가 두 번 나온다 — 키가 세트 번호만 담아서 그렇다.
    // 첫 종목의 것이 앞에 온다.
    await tester.drag(
      find.byKey(const ValueKey('inline-set-weight-1')).first,
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();

    expect(state.restRemaining, greaterThan(0));
    expect(state.restFocus, isNotNull, reason: '휴식 바가 말할 내용이 비었다');
    expect(
      state.restFocus!.setsLeft,
      sessionOf(state).exercises.first.sets.where((s) => !s.completed).length,
    );

    state.cancelRestTimer();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('the bar says where you are and +30초 keeps that', (tester) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.startRestTimer(
      90,
      focus: const RestFocus(exerciseName: '랫풀다운', setsLeft: 2),
    );

    await tester.pumpWidget(barFor(state));
    await tester.pumpAndSettle();

    expect(find.text('휴식 중'), findsOneWidget);
    expect(find.textContaining('랫풀다운'), findsOneWidget);
    expect(find.textContaining('2세트 남음'), findsOneWidget);

    final before = state.restRemaining;
    // 바를 먼저 탭해 펼칠 필요 없이 바로 눌린다.
    await tester.tap(find.byKey(const ValueKey('rest-bar-add')));
    await tester.pumpAndSettle();

    expect(state.restRemaining, before + 30);
    expect(
      find.textContaining('2세트 남음'),
      findsOneWidget,
      reason: '+30초가 어디쯤인지를 지웠다',
    );

    state.cancelRestTimer();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a shared rest shows only the clock', (tester) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.startRestTimer(45);

    await tester.pumpWidget(barFor(state));
    await tester.pumpAndSettle();

    expect(find.text('휴식 중'), findsOneWidget);
    expect(find.text('00:45'), findsOneWidget);
    expect(find.textContaining('세트 남음'), findsNothing);
    expect(find.textContaining('다음은'), findsNothing);

    state.cancelRestTimer();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('finishing the rest is one tap away', (tester) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.startRestTimer(
      90,
      focus: const RestFocus(
        exerciseName: '랫풀다운',
        setsLeft: 0,
        nextExercise: '스쿼트',
      ),
    );

    await tester.pumpWidget(barFor(state));
    await tester.pumpAndSettle();

    // 종목을 끝냈으면 남은 세트 대신 다음 종목을 말한다.
    expect(find.textContaining('다음은 스쿼트'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rest-bar-finish')));
    await tester.pumpAndSettle();
    expect(state.restRemaining, 0);
    expect(find.text('휴식 없음'), findsOneWidget);
  });

  testWidgets('the bar grows with the text scale instead of clipping', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.startRestTimer(
      90,
      focus: const RestFocus(exerciseName: '인클라인 덤벨 프레스', setsLeft: 3),
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: barFor(state),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '2배 글자에서 바가 넘쳤다');
    expect(find.byKey(const ValueKey('rest-bar-add')), findsOneWidget);

    state.cancelRestTimer();
    await tester.pump(const Duration(seconds: 1));
  });
}
