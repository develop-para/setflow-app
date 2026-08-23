import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// The loop this app exists for: lift, log, rest, again.
///
/// Every set used to cost the same trip — open a dial for the reps that came out
/// different, tap the circle, scroll past the cards already done. These three
/// behaviours are what make the second and third set cheaper than the first.
void main() {
  final date = DateTime(2026, 11, 5);

  Future<AppState> pumpDay(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    final exercise = state.sessions[state.dateOnly(date)]!.exercises.single;
    while (exercise.sets.length < 3) {
      state.addSet(exercise);
    }
    for (final set in exercise.sets) {
      state.updateSet(set, weight: 100, reps: 10);
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

  WorkoutExercise exerciseOf(AppState state) =>
      state.sessions[state.dateOnly(date)]!.exercises.single;

  /// Logging a set starts the rest timer and raises a toast, both of which own
  /// a timer. The binding fails a test that ends with one still pending, so
  /// they are wound down inside the test body rather than in a tearDown.
  Future<void> settle(WidgetTester tester, AppState state) async {
    state.cancelRestTimer();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  testWidgets('a logged set folds to one line that still shows its numbers', (
    tester,
  ) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    // Open before: the dials are there to be edited.
    expect(find.byKey(const ValueKey('inline-set-weight-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
    await tester.pumpAndSettle();

    expect(sets.first.completed, isTrue);
    // Folded, but the numbers stay readable — that is the whole point of
    // folding rather than removing.
    expect(find.byKey(const ValueKey('inline-set-weight-1')), findsNothing);
    expect(find.byKey(const ValueKey('inline-set-done-1')), findsOneWidget);
    expect(find.textContaining('100kg × 10회'), findsOneWidget);

    // And it reopens: a logged set is still editable.
    await tester.tap(find.byKey(const ValueKey('inline-set-done-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inline-set-weight-1')), findsOneWidget);
    await settle(tester, state);
  });

  testWidgets('swiping a set right logs it', (tester) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;
    expect(sets.first.completed, isFalse);

    await tester.drag(
      find.byKey(const ValueKey('inline-set-weight-1')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();

    expect(sets.first.completed, isTrue, reason: '오른쪽으로 밀어도 완료되지 않았다');
    expect(find.byKey(const ValueKey('inline-set-done-1')), findsOneWidget);
    await settle(tester, state);
  });

  testWidgets('a small drag does not log the set', (tester) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    // Well under the 40% threshold: the row lives in a vertical scroll, and an
    // accidental completion would start the rest timer too.
    await tester.drag(
      find.byKey(const ValueKey('inline-set-weight-1')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();

    expect(sets.first.completed, isFalse);
    await settle(tester, state);
  });

  testWidgets('a set out of turn cannot be swiped', (tester) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    // Set 1 is untouched, so set 3 is not this set's turn.
    await tester.drag(
      find.byKey(const ValueKey('inline-set-weight-3')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();

    expect(sets[2].completed, isFalse, reason: '순서를 건너뛴 세트가 완료됐다');
    expect(sets.first.completed, isFalse);
    await settle(tester, state);
  });

  testWidgets('a set out of turn cannot be tapped either', (tester) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    await tester.tap(find.byKey(const ValueKey('inline-set-complete-3')));
    await tester.pumpAndSettle();

    expect(sets[2].completed, isFalse, reason: '순서를 건너뛴 세트가 탭으로 완료됐다');
    await settle(tester, state);
  });

  testWidgets('the turn moves to the next set once one is logged', (
    tester,
  ) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Set 2 is live now; set 3 still is not.
    await tester.tap(find.byKey(const ValueKey('inline-set-complete-3')));
    await tester.pumpAndSettle();
    expect(sets[2].completed, isFalse);

    await tester.tap(find.byKey(const ValueKey('inline-set-complete-2')));
    await tester.pumpAndSettle();
    expect(sets[1].completed, isTrue, reason: '차례가 된 세트가 완료되지 않았다');
    await settle(tester, state);
  });

  testWidgets('a set out of turn cannot restart the rest timer', (
    tester,
  ) async {
    final state = await pumpDay(tester);

    await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
    await tester.pumpAndSettle();
    expect(state.restRemaining, greaterThan(0), reason: '완료가 휴식을 시작하지 않았다');

    await tester.pump(const Duration(seconds: 5));
    final afterFive = state.restRemaining;

    // Tapping a set whose turn has not come must not put the clock back.
    await tester.tap(find.byKey(const ValueKey('inline-set-complete-3')));
    await tester.pumpAndSettle();

    expect(
      state.restRemaining,
      lessThanOrEqualTo(afterFive),
      reason: '차례가 아닌 세트가 휴식 시간을 되돌렸다',
    );
    await settle(tester, state);
  });

  testWidgets('the sets still ahead inherit what was actually lifted', (
    tester,
  ) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    // Planned ten, got eight.
    state.updateSet(sets.first, reps: 8);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
    await tester.pumpAndSettle();

    expect(sets[1].reps, 8, reason: '2세트가 계획값 10에 머물렀다');
    expect(sets[2].reps, 8, reason: '3세트가 계획값 10에 머물렀다');
    expect(sets[1].completed, isFalse, reason: '전파가 완료 상태까지 건드렸다');
    await settle(tester, state);
  });

  testWidgets('the propagation can be handed straight back', (tester) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    state.updateSet(sets.first, reps: 8);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
    await tester.pumpAndSettle();
    expect(sets[1].reps, 8);

    await tester.tap(find.text('되돌리기'));
    await tester.pumpAndSettle();

    expect(sets[1].reps, 10, reason: '되돌리기가 계획값을 복구하지 않았다');
    expect(sets[2].reps, 10);
    expect(sets.first.reps, 8, reason: '되돌리기가 이미 기록한 세트까지 건드렸다');
    await settle(tester, state);
  });

  testWidgets('a completed set is never overwritten by a later one', (
    tester,
  ) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    state.updateSet(sets.first, reps: 12);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inline-set-complete-1')));
    await tester.pumpAndSettle();

    // The propagation toast sits over the rows and is tap-to-dismiss, so a tap
    // aimed at set 2 while it is up would land on the toast instead. Let it go
    // first — this is the one case where the app earned the interruption.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Set 2 is logged as it stands, then set 3 is what set 2 propagates onto.
    await tester.tap(find.byKey(const ValueKey('inline-set-complete-2')));
    await tester.pumpAndSettle();

    expect(sets.first.reps, 12, reason: '기록된 1세트가 덮어써졌다');
    expect(sets[1].completed, isTrue);
    await settle(tester, state);
  });
}
