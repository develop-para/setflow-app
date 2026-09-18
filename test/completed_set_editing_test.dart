import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  final date = DateTime(2026, 9, 18);
  final cases = [
    (
      name: 'weighted set',
      measurement: ExerciseMeasurement.weightReps,
      cardio: false,
      field: 'inline-set-weight-1',
      value: '65',
      summary: '65kg × 10회',
    ),
    (
      name: 'bodyweight set',
      measurement: ExerciseMeasurement.repsOnly,
      cardio: false,
      field: 'inline-set-reps-1',
      value: '12',
      summary: '12회',
    ),
    (
      name: 'hold set',
      measurement: ExerciseMeasurement.duration,
      cardio: false,
      field: 'inline-set-duration-1',
      value: '90',
      summary: '1분 30초',
    ),
    (
      name: 'cardio interval',
      measurement: ExerciseMeasurement.duration,
      cardio: true,
      field: 'cardio-duration-1',
      value: '25',
      summary: '25분',
    ),
  ];

  for (final item in cases) {
    for (final largeText in [false, true]) {
      testWidgets(
        'completed ${item.name} can close after editing (large text: $largeText)',
        (tester) async {
          await tester.binding.setSurfaceSize(
            largeText ? const Size(320, 1100) : const Size(432, 900),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final state = AppState();
          addTearDown(state.dispose);
          await state.initialize();
          state.sessions.clear();
          final template = state.exercises.firstWhere(
            (exercise) => item.cardio
                ? exercise.id == 'run'
                : !exercise.isCardio &&
                      exercise.measurement == item.measurement,
          );
          state.addExercise(date, template);
          final exercise = state.sessions[date]!.exercises.single;
          final set = exercise.sets.first;
          state.updateSet(
            set,
            weight: 60,
            reps: 10,
            durationSeconds: item.cardio ? 1200 : 60,
          );
          state.toggleSet(set, startRest: false);
          if (exercise.sets.length == 1) state.addSet(exercise);
          final restSession = state.restSessionId;
          final prefix = item.cardio ? 'inline-cardio' : 'inline-set';
          final done = find.byKey(ValueKey('$prefix-done-1'));
          final field = find.byKey(ValueKey(item.field));
          final collapse = find.byKey(ValueKey('$prefix-collapse-1'));

          await tester.pumpWidget(
            AppScope(
              notifier: state,
              child: MaterialApp(
                theme: largeText ? SetflowTheme.dark : SetflowTheme.light,
                builder: (context, child) => MediaQuery.withClampedTextScaling(
                  minScaleFactor: largeText ? 2 : 1,
                  maxScaleFactor: largeText ? 2 : 1,
                  child: child!,
                ),
                home: DailyWorkoutScreen(date: date),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(done, findsOneWidget);

          await tester.tap(done);
          await tester.pumpAndSettle();
          expect(field, findsOneWidget);
          expect(collapse, findsOneWidget);
          expect(
            tester.widget<IconButton>(collapse).tooltip,
            item.cardio ? '1구간 접기' : '1세트 접기',
          );

          // Checking a completed set must have a way back without any edit.
          await tester.tap(collapse);
          await tester.pumpAndSettle();
          expect(done, findsOneWidget);
          expect(field, findsNothing);
          expect(set.completed, isTrue);

          await tester.tap(done);
          await tester.pumpAndSettle();
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('number-dial-direct-input')),
            item.value,
          );
          await tester.tap(find.text('적용'));
          await tester.pumpAndSettle();
          // Keep editing open so changing another field costs no extra reopen.
          expect(field, findsOneWidget);
          // Weight propagation has an undo toast above the editor. Let that
          // transient overlay leave before tapping the row beneath it.
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();
          await tester.tap(collapse);
          await tester.pumpAndSettle();

          expect(done, findsOneWidget);
          expect(
            find.descendant(
              of: done,
              matching: find.textContaining(item.summary),
            ),
            findsOneWidget,
          );
          expect(field, findsNothing);
          expect(
            find.byKey(ValueKey(item.field.replaceFirst('-1', '-2'))),
            findsOneWidget,
            reason: '다음 세트와 운동 목록은 그대로 펼쳐져 있어야 한다',
          );
          expect(set.completed, isTrue);
          expect(exercise.sets.skip(1).every((set) => !set.completed), isTrue);
          expect(state.restSessionId, restSession);
          expect(state.restRemaining, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
