import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/domain/weight_input_unit.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  final input = find.byKey(const Key('number-dial-direct-input'));
  final swipe = find.byKey(const Key('number-dial-swipe'));
  double? result;
  bool applied = false;

  Future<void> open(
    WidgetTester tester, {
    double initial = 40,
    String suffix = 'kg',
    bool optional = false,
    bool unset = false,
    bool small = false,
  }) async {
    result = null;
    applied = false;
    await tester.binding.setSurfaceSize(
      small ? const Size(320, 568) : const Size(432, 1000),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        builder: small
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 280),
                  padding: const EdgeInsets.only(bottom: 28),
                ),
                child: child!,
              )
            : null,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                if (optional) {
                  final value = await showOptionalNumberDial(
                    context,
                    title: '무게',
                    suffix: suffix,
                    initialValue: unset ? null : initial,
                    min: 0,
                    max: 999,
                    step: .5,
                  );
                  applied = value != null;
                  result = value?.value;
                } else {
                  result = await showNumberDial(
                    context,
                    title: '무게',
                    suffix: suffix,
                    initialValue: initial,
                    min: 0,
                    max: 999,
                    step: .5,
                  );
                  applied = result != null;
                }
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  Future<void> slide(WidgetTester tester, double distance) async {
    await tester.drag(swipe, Offset(distance, 0));
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.ensureVisible(find.text('적용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
  }

  String unit(WidgetTester tester) =>
      tester.widget<TextField>(input).decoration!.suffixText!;

  testWidgets(
    'lb set input saves kg and propagates with undo without completing a set',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      final date = state.dateOnly(DateTime.now());
      state.addExercise(date, state.exercises.first);
      final session = state.sessions[date]!;
      final exercise = session.exercises.single;
      while (exercise.sets.length < 3) {
        state.addSet(exercise);
      }
      for (final set in exercise.sets) {
        state.updateSet(set, weight: 40, reps: 10);
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
      await tester.tap(find.byKey(const Key('inline-set-weight-1')));
      await tester.pumpAndSettle();
      await slide(tester, -150);
      expect(exercise.sets.every((set) => !set.completed), isTrue);
      expect(state.restRemaining, 0);
      await tester.enterText(input, '100');
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(exercise.sets.first.weight, 40);

      await tester.tap(find.byKey(const Key('inline-set-weight-1')));
      await tester.pumpAndSettle();
      await slide(tester, 150);
      await tester.enterText(input, '100');
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(
        exercise.sets.every((set) => (set.weight - 45.359237).abs() < 1e-8),
        isTrue,
      );
      expect(state.weightUnit, 'kg');
      expect(exercise.sets.every((set) => !set.completed), isTrue);
      expect(state.restRemaining, 0);
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      expect(exercise.sets[1].weight, 40);
      expect(exercise.sets.first.weight, closeTo(45.359237, 1e-8));
      await tester.drag(find.byType(Dismissible).first, const Offset(360, 0));
      await tester.pumpAndSettle();
      expect(exercise.sets.first.completed, isTrue);
      expect(session.volume, closeTo(453.59237, 1e-6));
      expect(state.todayWorkoutMetric, contains('kg·회'));
      await state.flushPersistence();
      state.cancelRestTimer();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  test(
    'lb conversion uses the international pound and preserves draft precision',
    () {
      expect(WeightInputUnit.lb.toKilograms(100), closeTo(45.359237, 1e-10));
      expect(WeightInputUnit.lb.fromKilograms(45.359237), closeTo(100, 1e-10));
      expect(WeightInputUnit.kg.toKilograms(40), 40);
      expect(formatWeightInput(45.359237), '45.359237');
      expect(formatWeightInput(0), '0');
      expect(formatWeightInput(100), '100');
    },
  );

  testWidgets('left and right swipes switch units without changing stored kg', (
    tester,
  ) async {
    await open(tester, initial: 45.359237);
    await slide(tester, -150);
    expect(unit(tester), 'lb');
    expect(tester.widget<TextField>(input).controller!.text, '100');
    await slide(tester, 150);
    expect(unit(tester), 'kg');
    await slide(tester, 150);
    expect(unit(tester), 'lb');
    await apply(tester);
    expect(result, closeTo(45.359237, 1e-10));
  });

  testWidgets('typing lb commits kg only on Apply', (tester) async {
    await open(tester);
    await slide(tester, 150);
    await tester.enterText(input, '100');
    await tester.pump();
    expect(find.text('기록: 45.4 kg'), findsOneWidget);
    expect(applied, isFalse);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await apply(tester);
    expect(result, closeTo(45.359237, 1e-10));
  });

  testWidgets('new kg draft survives unit switches and Cancel never commits', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(input, '82.5');
    await slide(tester, -150);
    await slide(tester, 150);
    expect(tester.widget<TextField>(input).controller!.text, '82.5');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    expect(result, isNull);
  });

  testWidgets('opening a converted kg value does not round it to a dial step', (
    tester,
  ) async {
    await open(tester, initial: 45.359237);
    await apply(tester);
    expect(result, closeTo(45.359237, 1e-10));
  });

  testWidgets('vertical lb dial keeps lb selected and converts its value', (
    tester,
  ) async {
    await open(tester, initial: 45.359237);
    await slide(tester, -150);
    await tester.drag(find.byType(CupertinoPicker), const Offset(0, -84));
    await tester.pumpAndSettle();
    expect(unit(tester), 'lb');
    final pounds = double.parse(
      tester.widget<TextField>(input).controller!.text,
    );
    expect(pounds, isNot(100));
    await apply(tester);
    expect(result, closeTo(pounds * .45359237, 1e-10));
  });

  testWidgets(
    'lb bounds use kg limits and invalid input cannot switch or save',
    (tester) async {
      await open(tester);
      await slide(tester, -150);
      await tester.enterText(input, '2300');
      await apply(tester);
      expect(applied, isFalse);
      expect(input, findsOneWidget);
      await slide(tester, 150);
      expect(unit(tester), 'lb');
      await tester.enterText(input, '2000');
      await apply(tester);
      expect(result, closeTo(907.18474, 1e-8));
    },
  );

  testWidgets('unit buttons provide an alternative to swiping', (tester) async {
    await open(tester);
    await tester.tap(find.text('lb'));
    await tester.pumpAndSettle();
    expect(unit(tester), 'lb');
    await tester.tap(find.text('kg'));
    await tester.pumpAndSettle();
    expect(unit(tester), 'kg');
    await apply(tester);
    expect(result, 40);
  });

  testWidgets('unset weight remains unset across unit changes', (tester) async {
    await open(tester, optional: true, unset: true);
    await slide(tester, -150);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await apply(tester);
    expect(applied, isTrue);
    expect(result, isNull);
  });

  testWidgets('reps dial keeps its unit on a horizontal swipe', (tester) async {
    await open(tester, suffix: '회', initial: 10);
    await slide(tester, -150);
    expect(unit(tester), '회');
    expect(find.text('lb'), findsNothing);
    await apply(tester);
    expect(result, 10);
  });

  testWidgets(
    'Apply is reachable with large text and keyboard on a small screen',
    (tester) async {
      await open(tester, small: true);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('lb'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(input);
      await tester.enterText(input, '100');
      await apply(tester);
      expect(result, closeTo(45.359237, 1e-10));
      expect(tester.takeException(), isNull);
    },
  );
}
