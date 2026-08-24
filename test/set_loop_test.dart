import 'dart:io';
import 'dart:math' as math;

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
double contrastOf(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final la = lum(a);
  final lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

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

    await _logSet(tester, 1);

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

  testWidgets('a screen reader can still log a set without the circle', (
    tester,
  ) async {
    // Removing the visible control cannot remove the only non-gesture way in:
    // a swipe is not something assistive tech can perform, so the action lives
    // on the row's semantics instead.
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    Set<String> actionsFor(String fieldKey) {
      final labels = <String>{};
      final wrappers = tester.widgetList<Semantics>(
        find.ancestor(
          of: find.byKey(ValueKey(fieldKey)),
          matching: find.byType(Semantics),
        ),
      );
      for (final wrapper in wrappers) {
        final actions = wrapper.properties.customSemanticsActions;
        if (actions != null) {
          labels.addAll(
            actions.keys.map((action) => action.label).whereType<String>(),
          );
        }
      }
      return labels;
    }

    expect(
      actionsFor('inline-set-weight-1'),
      contains('완료'),
      reason: '차례인 세트에 완료 액션이 없다 — 스크린리더로 기록할 방법이 사라졌다',
    );
    expect(
      actionsFor('inline-set-weight-3'),
      isNot(contains('완료')),
      reason: '차례가 아닌 세트에 완료 액션이 노출된다',
    );
    expect(sets.first.completed, isFalse);

    await settle(tester, state);
  });

  testWidgets('the turn moves to the next set once one is logged', (
    tester,
  ) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    await _logSet(tester, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Set 2 is live now; set 3 still is not.
    await _logSet(tester, 3);
    expect(sets[2].completed, isFalse);

    await _logSet(tester, 2);
    expect(sets[1].completed, isTrue, reason: '차례가 된 세트가 완료되지 않았다');
    await settle(tester, state);
  });

  testWidgets('a set out of turn cannot restart the rest timer', (
    tester,
  ) async {
    final state = await pumpDay(tester);

    await _logSet(tester, 1);
    expect(state.restRemaining, greaterThan(0), reason: '완료가 휴식을 시작하지 않았다');

    await tester.pump(const Duration(seconds: 5));
    final afterFive = state.restRemaining;

    // Tapping a set whose turn has not come must not put the clock back.
    await _logSet(tester, 3);

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
    await _logSet(tester, 1);

    expect(sets[1].reps, 8, reason: '2세트가 계획값 10에 머물렀다');
    expect(sets[2].reps, 8, reason: '3세트가 계획값 10에 머물렀다');
    expect(sets[1].completed, isFalse, reason: '전파가 완료 상태까지 건드렸다');
    await settle(tester, state);
  });

  test('the track chips pair their fills with on-colours', () {
    // 회귀의 실체: 삭제 칩이 fill도 전경도 error라서 빨강 위 빨강 —
    // 글자 없는 알약으로 보였다. 칩 전경은 반드시 칩과 짝지어진 on색이다.
    // 미드-드래그 위젯 검사는 테스트 하네스에서 불안정해서, 계약을 두 층으로
    // 고정한다: 소스가 on색을 쓰는지, 그리고 그 on색이 실제로 읽히는지.
    final source = File('lib/screens/workout_screens.dart').readAsStringSync();
    expect(
      RegExp(
        r'secondaryBackground: _track\([^)]*onError',
        dotAll: true,
      ).hasMatch(source),
      isTrue,
      reason: '삭제 트랙의 전경이 onError가 아니다',
    );
    expect(
      source.contains('accent: context.setflowColors.error'),
      isFalse,
      reason: '트랙 전경에 채움과 같은 error를 쓰고 있다',
    );

    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final scheme = theme.colorScheme;
      expect(
        contrastOf(
          scheme.onError,
          theme.extension<SetflowSemanticColors>()!.error,
        ),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.brightness}: onError가 error 채움 위에서 안 읽힌다',
      );
      expect(
        contrastOf(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.brightness}: onPrimary가 라임 칩 위에서 안 읽힌다',
      );
    }
  });

  testWidgets('the propagation can be handed straight back', (tester) async {
    final state = await pumpDay(tester);
    final sets = exerciseOf(state).sets;

    state.updateSet(sets.first, reps: 8);
    await tester.pumpAndSettle();
    await _logSet(tester, 1);
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
    await _logSet(tester, 1);

    // The propagation toast sits over the rows and is tap-to-dismiss, so a tap
    // aimed at set 2 while it is up would land on the toast instead. Let it go
    // first — this is the one case where the app earned the interruption.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Set 2 is logged as it stands, then set 3 is what set 2 propagates onto.
    await _logSet(tester, 2);

    expect(sets.first.reps, 12, reason: '기록된 1세트가 덮어써졌다');
    expect(sets[1].completed, isTrue);
    await settle(tester, state);
  });
}

/// The circle is gone: a set is logged by pushing its row to the right.
Future<void> _logSet(WidgetTester tester, int number) async {
  await tester.drag(
    find.byKey(ValueKey('inline-set-weight-$number')),
    const Offset(400, 0),
  );
  await tester.pumpAndSettle();
}
