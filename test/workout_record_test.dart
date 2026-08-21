import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// Logging a set is the one thing this app exists to do, so a number the user
/// typed must never depend on *how* they left the field.
void main() {
  final date = DateTime(2026, 11, 1);

  Future<AppState> pumpDay(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);
    state.updateSet(
      state.sessions[date]!.exercises.single.sets.first,
      weight: 40,
    );

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

  double weightOf(AppState state) =>
      state.sessions[date]!.exercises.single.sets.first.weight;

  int repsOf(AppState state) =>
      state.sessions[date]!.exercises.single.sets.first.reps;

  testWidgets('losing focus commits the typed weight', (tester) async {
    final state = await pumpDay(tester);

    await tester.enterText(find.byType(TextField).at(0), '82.5');
    await tester.pump();

    // No submit, no tap elsewhere -- this is what a screen lock, a route pop
    // or a keyboard dismiss looks like. Only onSubmitted and onTapOutside used
    // to commit, so the number stayed in the controller and was never saved.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(weightOf(state), 82.5);
  });

  testWidgets('losing focus commits typed reps too', (tester) async {
    final state = await pumpDay(tester);

    await tester.enterText(find.byType(TextField).at(1), '15');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(repsOf(state), 15);
  });

  testWidgets('a rejected value snaps back instead of being stored', (
    tester,
  ) async {
    final state = await pumpDay(tester);

    // 9999kg is a typo, not a lift. The field must show the real value again
    // rather than silently keep text that does not match what was saved.
    await tester.enterText(find.byType(TextField).at(0), '9999');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(weightOf(state), 40);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller?.text,
      '40',
    );
  });

  testWidgets('submitting still commits', (tester) async {
    final state = await pumpDay(tester);

    await tester.enterText(find.byType(TextField).at(0), '70');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(weightOf(state), 70);
  });
}
