import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// Sheets opened with `useSafeArea: true` get `SafeArea(bottom: false)` from
/// Flutter — the bottom inset is deliberately left to the sheet so its
/// background can paint under the gesture bar. If the sheet's content forgets
/// to add it back, its buttons end up under the system navigation bar.
///
/// That is not cosmetic here: the dial's 적용 is the only thing that writes a
/// weight/reps/rest value (AGENTS.md 5), so a 적용 the thumb cannot reach is a
/// set that cannot be logged.
void main() {
  const navBar = 48.0;
  const screen = Size(393, 852);
  const safeBottom = 852.0 - navBar;
  final date = DateTime(2026, 11, 1);

  /// A phone with a system navigation bar at the bottom.
  Future<AppState> pumpWithNavBar(WidgetTester tester, Widget home) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screen;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    tester.view.padding = const FakeViewPadding(bottom: navBar);
    addTearDown(tester.view.reset);

    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.addExercise(date, state.exercises.first);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: home),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  /// The button box, not just its label — the label can clear the bar while the
  /// tappable box below it does not.
  /// byType matches the exact runtime type, which misses the `.icon` variants
  /// (FilledButton.icon builds a private subclass), so match on the supertype.
  Rect buttonRect(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        )
        .first,
  );

  testWidgets('the number dial keeps 적용 above the navigation bar', (
    tester,
  ) async {
    await pumpWithNavBar(tester, DailyWorkoutScreen(date: date));

    await tester.tap(find.byKey(const ValueKey('inline-set-weight-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('number-dial-direct-input')), findsOneWidget);

    expect(
      buttonRect(tester, '적용').bottom,
      lessThanOrEqualTo(safeBottom),
      reason: '적용 is under the system navigation bar',
    );
    expect(
      buttonRect(tester, '취소').bottom,
      lessThanOrEqualTo(safeBottom),
      reason: '취소 is under the system navigation bar',
    );
  });

  testWidgets('the create-exercise sheet keeps 운동 만들기 above the bar', (
    tester,
  ) async {
    await pumpWithNavBar(tester, ExerciseLibraryScreen(date: date));

    await tester.tap(find.byTooltip('새 운동 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('운동 만들기'), findsOneWidget);

    expect(
      buttonRect(tester, '운동 만들기').bottom,
      lessThanOrEqualTo(safeBottom),
      reason: '운동 만들기 is under the system navigation bar',
    );
  });
}
