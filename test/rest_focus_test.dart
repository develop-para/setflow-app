import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

/// Rest is the half of the loop the app used to leave unattended: a slim bar
/// under the header, and a phone in your hand. This covers what the rest screen
/// has to do — hold your attention, tell you where you are, and still let you
/// out.
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
    state.noteRestFocus(session, exercise);
    expect(state.restFocus!.setsLeft, total - 1);
    expect(state.restFocus!.exerciseName, exercise.template.name);
    expect(state.restFocus!.nextExercise, isNull);
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
    state.noteRestFocus(session, first);

    expect(state.restFocus!.setsLeft, 0);
    expect(
      state.restFocus!.nextExercise,
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
    state.noteRestFocus(session, only);

    expect(state.restFocus!.setsLeft, 0);
    expect(state.restFocus!.nextExercise, isNull);
  });

  testWidgets('logging a set puts the rest screen up, not the slim bar', (
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
    expect(state.restFocusCollapsed, isFalse, reason: '휴식 화면이 접힌 채 시작했다');
    expect(state.restFocus, isNotNull, reason: '휴식 화면이 말할 내용이 비었다');
    expect(
      state.restFocus!.setsLeft,
      sessionOf(state).exercises.first.sets.where((s) => !s.completed).length,
    );

    state.cancelRestTimer();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('the rest screen can be folded away without ending the rest', (
    tester,
  ) async {
    // Blocking the screen must not trap anyone: a number typed wrong a moment
    // ago still has to be reachable.
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.startRestTimer(90);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Scaffold(
            body: AnimatedBuilder(
              animation: state,
              builder: (context, _) => state.restFocusCollapsed
                  ? const Text('접힘')
                  : RestFocusOverlay(
                      seconds: state.restRemaining,
                      totalSeconds: state.restDefaultSeconds,
                      exerciseName: '랫풀다운',
                      setsLeft: 2,
                      nextExercise: null,
                      onAddTime: () =>
                          state.startRestTimer(state.restRemaining + 30),
                      onFinish: state.cancelRestTimer,
                      onCollapse: state.collapseRestFocus,
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('랫풀다운'), findsOneWidget);
    expect(find.textContaining('2세트 남음'), findsOneWidget);

    final before = state.restRemaining;
    await tester.tap(find.byKey(const ValueKey('rest-focus-collapse')));
    await tester.pumpAndSettle();

    expect(find.text('접힘'), findsOneWidget);
    expect(
      state.restRemaining,
      before,
      reason: '접기가 휴식을 끝내버렸다 — 접기는 보기를 바꾸는 것뿐이어야 한다',
    );

    state.cancelRestTimer();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('finishing the rest is one tap away', (tester) async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.startRestTimer(90);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: Scaffold(
            body: RestFocusOverlay(
              seconds: state.restRemaining,
              totalSeconds: state.restDefaultSeconds,
              exerciseName: '랫풀다운',
              setsLeft: 0,
              nextExercise: '스쿼트',
              onAddTime: () {},
              onFinish: state.cancelRestTimer,
              onCollapse: state.collapseRestFocus,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 종목을 끝냈으면 남은 세트 대신 다음 종목을 말한다.
    expect(find.textContaining('다음은 스쿼트'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rest-focus-finish')));
    await tester.pumpAndSettle();
    expect(state.restRemaining, 0);
  });
}
