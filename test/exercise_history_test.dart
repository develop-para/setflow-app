import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// The history button used to raise a toast saying the history had loaded and
/// then show nothing. The records were in state all along.
void main() {
  testWidgets('the history sheet shows the sets actually logged', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    final template = state.exercises.first;
    // 두 날에 걸쳐 이 종목을 했고, 무게가 올랐다.
    for (final (date, weight) in [
      (DateTime(2026, 11, 1), 60.0),
      (DateTime(2026, 11, 8), 65.0),
    ]) {
      state.addExercise(date, template);
      final exercise = state.sessions[state.dateOnly(date)]!.exercises.single;
      for (final set in exercise.sets) {
        state.updateSet(set, weight: weight, reps: 8);
        set.completed = true;
      }
    }

    final today = DateTime(2026, 11, 15);
    state.addExercise(today, template);
    final exercise = state.sessions[state.dateOnly(today)]!.exercises.single;

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: ExerciseSetScreen(date: today, exercise: exercise),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('exercise-history')));
    await tester.pumpAndSettle();

    expect(find.text('2일치 기록'), findsOneWidget);
    expect(find.text('11월 8일'), findsOneWidget);
    expect(find.text('11월 1일'), findsOneWidget);
    // 최근이 위로 온다.
    expect(
      tester.getRect(find.text('11월 8일')).top,
      lessThan(tester.getRect(find.text('11월 1일')).top),
    );
    // 그날의 세트가 한 줄에 이어 붙는다. 세트가 여럿이면 같은 문구가 반복된다.
    expect(find.textContaining('65kg × 8'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('an exercise with no history says so plainly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    final today = DateTime(2026, 11, 15);
    state.addExercise(today, state.exercises.first);
    final exercise = state.sessions[state.dateOnly(today)]!.exercises.single;

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: ExerciseSetScreen(date: today, exercise: exercise),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('exercise-history')));
    await tester.pumpAndSettle();

    // 빈 상태가 "불러왔습니다" 라고 거짓말하지 않는다.
    expect(find.text('아직 기록이 없어요'), findsOneWidget);
    expect(find.textContaining('불러왔습니다'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
