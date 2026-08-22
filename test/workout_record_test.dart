import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// Logging a set is the one thing this app exists to do, so the number the user
/// picked must never depend on *how* they left the sheet.
///
/// The set row has no keyboard of its own: the box is the button, and the dial
/// sheet's 적용 is the only thing that writes a number.
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

  Finder dialInput() => find.byKey(const Key('number-dial-direct-input'));

  Future<void> openDial(WidgetTester tester, String fieldKey) async {
    await tester.tap(find.byKey(ValueKey(fieldKey)));
    await tester.pumpAndSettle();
  }

  Future<void> pickValue(
    WidgetTester tester,
    String fieldKey,
    String value,
  ) async {
    await openDial(tester, fieldKey);
    await tester.enterText(dialInput(), value);
    await tester.pump();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
  }

  testWidgets('the box itself opens the dial — there is no icon button', (
    tester,
  ) async {
    await pumpDay(tester);

    // The tune icon used to sit inside every number box. One number, one hit
    // target: the box.
    expect(find.byIcon(Icons.tune_rounded), findsNothing);

    await openDial(tester, 'inline-set-weight-1');
    expect(find.text('무게 선택'), findsOneWidget);
  });

  testWidgets('applying the dial commits the weight', (tester) async {
    final state = await pumpDay(tester);

    await pickValue(tester, 'inline-set-weight-1', '82.5');

    expect(weightOf(state), 82.5);
    expect(find.text('무게 선택'), findsNothing);
  });

  testWidgets('applying the dial commits reps too', (tester) async {
    final state = await pumpDay(tester);

    await pickValue(tester, 'inline-set-reps-1', '15');

    expect(repsOf(state), 15);
  });

  testWidgets('a rejected value is refused instead of stored', (tester) async {
    final state = await pumpDay(tester);

    // 9999kg is a typo, not a lift. The sheet stays open with the complaint
    // rather than closing over a number nobody meant.
    await openDial(tester, 'inline-set-weight-1');
    await tester.enterText(dialInput(), '9999');
    await tester.pump();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(find.text('무게 선택'), findsOneWidget);
    expect(weightOf(state), 40);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    // Backing out leaves the row showing what is actually saved.
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('inline-set-weight-1')),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      '40',
    );
  });

  testWidgets('submitting from the dial input still commits', (tester) async {
    final state = await pumpDay(tester);

    await openDial(tester, 'inline-set-weight-1');
    await tester.enterText(dialInput(), '70');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(weightOf(state), 70);
  });

  testWidgets('leaving the app saves the set that was just picked', (
    tester,
  ) async {
    // Android may kill the process without ever coming back, so the snapshot
    // written at pause time is the last chance to keep the lift.
    final template = ExerciseTemplate(
      id: 'bench',
      name: '바벨 벤치 프레스',
      muscle: '가슴',
      icon: exerciseIconForMuscle('가슴'),
    );
    // The centre disc always opens *today*, so the seeded session has to be
    // today's or the screen renders an empty day.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final repository = MemoryAppRepository(
      initialSnapshot: AppSnapshot(
        role: UserRole.guest,
        isDarkMode: false,
        weightUnit: 'kg',
        restDefaultSeconds: 90,
        routines: const [],
        sessions: {
          today: WorkoutSession(
            date: today,
            exercises: [
              WorkoutExercise(
                id: 'e1',
                template: template,
                sets: [WorkoutSetEntry(number: 1, weight: 40, reps: 10)],
              ),
            ],
          ),
        },
      ),
    );

    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(SetflowApp(repository: repository));
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bottom-bar-center-action')));
    await tester.pumpAndSettle();

    await pickValue(tester, 'inline-set-weight-1', '82.5');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(
      repository.snapshot?.sessions[today]?.exercises.single.sets.first.weight,
      82.5,
      reason: 'the snapshot saved at pause must include what is on screen',
    );
  });
}
