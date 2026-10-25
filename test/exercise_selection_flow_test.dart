import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/machine_exercise_catalog.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

final _day = DateTime(2026, 10, 25);

Future<AppState> _pumpLibrary(
  WidgetTester tester, {
  void Function(AppState)? configure,
}) async {
  await tester.binding.setSurfaceSize(const Size(432, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  state.setAutoRecommendNextExercise(false);
  configure?.call(state);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        home: ExerciseLibraryScreen(date: _day, onAdded: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets(
    'new exercise selection omits product lines and records a simple bodyweight label',
    (tester) async {
      final state = await _pumpLibrary(tester);
      await tester.enterText(find.byType(TextFormField), '온힘');
      await tester.pumpAndSettle();
      expect(find.byTooltip('선택'), findsNothing);

      // The old name remains a search term, while the result uses the movement.
      await tester.enterText(find.byType(TextFormField), '맨몸 스쿼트');
      await tester.pumpAndSettle();
      expect(find.text('스쿼트'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '맨몸 스쿼트'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, '스쿼트'));
      await tester.pumpAndSettle();
      // Close the keyboard to expose the action in the same way as on device.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('1개 추가').first);
      await tester.pumpAndSettle();

      final exercise = state.sessionFor(_day).exercises.single;
      expect(exercise.template.id, 'bodyweight_squat');
      expect(exercise.template.name, '스쿼트');
      expect(exercise.template.storedName, '맨몸 스쿼트');
      expect(exercise.template.resolvedEquipmentKey, 'body_only');
      expect(exercise.template.isRepsOnly, isTrue);
      expect(exercise.sets.every((set) => !set.completed), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'recorded machines and user-created product-like names remain selectable',
    (tester) async {
      final machine = machineExerciseCatalog.firstWhere(
        (item) => item.name.startsWith('온힘 '),
      );
      late ExerciseTemplate custom;
      final state = await _pumpLibrary(
        tester,
        configure: (state) {
          state.sessions[_day.subtract(
            const Duration(days: 1),
          )] = WorkoutSession(
            date: _day.subtract(const Duration(days: 1)),
            exercises: [
              WorkoutExercise(
                id: 'existing-machine',
                template: machine,
                sets: [
                  WorkoutSetEntry(
                    number: 1,
                    weight: 40,
                    reps: 8,
                    completed: true,
                  ),
                ],
              ),
            ],
          );
          custom = state.createCustomExercise(
            name: '온힘 맨몸 개인 운동',
            muscle: '하체',
          )!;
        },
      );
      await tester.enterText(find.byType(TextFormField), '온힘');
      await tester.pumpAndSettle();
      expect(find.text(machine.name), findsOneWidget);
      expect(find.text(custom.name), findsOneWidget);
      expect(find.byTooltip('선택'), findsNWidgets(2));
      expect(state.performanceFor(machine)!.weightPr.set.weight, 40);
      expect(custom.storedName, '온힘 맨몸 개인 운동');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
