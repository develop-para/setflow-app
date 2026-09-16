import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/screens/training_focus_sheet.dart';
import 'package:setflow/services/resistance_prescription_engine.dart';
import 'package:setflow/theme.dart';

void main() {
  final day = DateTime(2026, 9, 15);
  Future<AppState> pumpDay(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.setMemberProfile(goals: ['근육 증가']);
    state.markPrecisionRecommendationPrompted();
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: DailyWorkoutScreen(date: day),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<void> applyFocus(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('training-focus-apply'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'choose chest before recommendation, apply weight once, undo only propagation',
    (tester) async {
      final state = await pumpDay(tester);
      await tester.tap(find.text('운동 선택'));
      await tester.pumpAndSettle();
      expect(find.text('오늘 운동 부위'), findsOneWidget);
      expect(find.text('오늘의 첫 운동 추천'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('training-focus-chest')));
      await applyFocus(tester);
      expect(state.sessionFor(day).trainingFocus, {TrainingMuscle.chest});
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      await tester.ensureVisible(find.text('추천 운동 추가'));
      await tester.tap(find.text('추천 운동 추가'));
      await tester.pumpAndSettle();
      final exercise = state.sessionFor(day).exercises.single;
      expect(exercise.template.muscle, '가슴');
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.byKey(const ValueKey('inline-set-weight-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('number-dial-direct-input')),
        '60',
      );
      await tester.tap(find.text('적용'));
      await tester.pumpAndSettle();
      expect(exercise.sets.map((set) => set.weight), everyElement(60));
      expect(exercise.sets.first.completed, isFalse);
      await tester.tap(find.text('되돌리기'));
      await tester.pumpAndSettle();
      expect(exercise.sets.first.weight, 60);
      expect(exercise.sets.skip(1).map((set) => set.weight), everyElement(0));
      state.cancelRestTimer();
    },
  );

  testWidgets(
    'split presets and cancellation preserve the last committed daily choice',
    (tester) async {
      final state = await pumpDay(tester);
      await tester.tap(find.byKey(const ValueKey('daily-training-focus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('training-focus-presets')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('등 · 이두'));
      await tester.tap(find.text('등 · 이두'));
      await applyFocus(tester);
      expect(state.sessionFor(day).trainingFocus, {
        TrainingMuscle.back,
        TrainingMuscle.biceps,
      });
      await tester.tap(find.byKey(const ValueKey('daily-training-focus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('training-focus-auto')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(state.sessionFor(day).trainingFocus, {
        TrainingMuscle.back,
        TrainingMuscle.biceps,
      });
      expect(
        state.sessionFor(day.add(const Duration(days: 1))).trainingFocus,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('daily-training-focus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('training-focus-presets')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('팔 날'));
      await tester.tap(find.text('팔 날'));
      await applyFocus(tester);
      expect(state.sessionFor(day).trainingFocus, {
        TrainingMuscle.biceps,
        TrainingMuscle.triceps,
      });
    },
  );

  testWidgets(
    'finishing chest keeps next recommendation inside chest without a survey',
    (tester) async {
      final state = await pumpDay(tester);
      state.setTrainingFocus(day, {TrainingMuscle.chest});
      final bench = state.exercises.firstWhere(
        (exercise) => exercise.id == 'bench',
      );
      state.addExercise(day, bench);
      final exercise = state.sessionFor(day).exercises.single;
      for (final set in exercise.sets) {
        set.weight = 60;
        set.completed = true;
      }
      exercise.sets.last.completed = false;
      state.precisionRecommendationPrompted = false;
      state.autoStartRestTimer = false;
      await tester.pumpAndSettle();
      final row = find.byKey(
        ValueKey('inline-set-weight-${exercise.sets.last.number}'),
      );
      await tester.ensureVisible(row);
      await tester.drag(row, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(find.text('추천을 더 정확하게'), findsNothing);
      expect(find.text('다음 운동 추천'), findsOneWidget);
      final next = state.nextExerciseRecommendationForDate(
        day,
        completedExercise: exercise,
      )!;
      expect(ResistancePrescriptionEngine.primaryMuscles(next.template), {
        TrainingMuscle.chest,
      });
      expect(find.text(next.template.name), findsOneWidget);
      await tester.ensureVisible(find.text('추천 운동 추가'));
      await tester.tap(find.text('추천 운동 추가'));
      await tester.pumpAndSettle();
      expect(state.sessionFor(day).exercises.last.template.muscle, '가슴');
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'focus sheet fits 320px and 2x text with bottom navigation inset ($dark)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Set<TrainingMuscle>? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? SetflowTheme.dark : SetflowTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                padding: const EdgeInsets.only(bottom: 28),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showTrainingFocusSheet(context);
                  },
                  child: const Text('부위 선택'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('부위 선택'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('training-focus-chest')),
        );
        await tester.tap(find.byKey(const ValueKey('training-focus-chest')));
        await applyFocus(tester);
        expect(selected, {TrainingMuscle.chest});
        expect(tester.takeException(), isNull);
      },
    );
  }
}
