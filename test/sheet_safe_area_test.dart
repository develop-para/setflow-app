import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

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

  /// The contract every sheet inherits.
  ///
  /// An architecture rule keeps `showModalBottomSheet` inside common.dart, so
  /// every sheet in the app opens through `showSetflowSheet`. That makes these
  /// three cases the guarantee for all of them, rather than something each
  /// sheet has to be driven and measured to prove.
  Future<Rect> probeSheet(
    WidgetTester tester, {
    required Widget Function(Widget probe) wrap,
    double keyboard = 0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screen;
    tester.view.viewPadding = const FakeViewPadding(bottom: navBar);
    // The keyboard covers the navigation bar's strip, so the OS reports the
    // padding as consumed while viewPadding still describes the hardware.
    tester.view.padding = FakeViewPadding(bottom: keyboard > 0 ? 0 : navBar);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSetflowSheet<void>(
                context,
                builder: (_) => wrap(
                  const SizedBox(
                    key: Key('sheet-probe'),
                    height: 40,
                    width: double.infinity,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(const Key('sheet-probe')));
  }

  testWidgets('showSetflowSheet clears the navigation bar for its content', (
    tester,
  ) async {
    final rect = await probeSheet(tester, wrap: (probe) => probe);
    expect(rect.bottom, safeBottom, reason: '시트 콘텐츠가 내비게이션 바를 비켜서지 않았다');
  });

  testWidgets('a sheet that wraps itself in SafeArea is not padded twice', (
    tester,
  ) async {
    // Landing on safeBottom rather than safeBottom - navBar is what says the
    // inner SafeArea found the padding already consumed. Each case gets its own
    // pump: a second sheet inside one test opens on top of the first's route.
    final rect = await probeSheet(
      tester,
      wrap: (probe) => SafeArea(child: probe),
    );
    expect(rect.bottom, safeBottom, reason: '중첩 SafeArea가 여백을 두 번 넣었다');
  });

  testWidgets('an open keyboard does not stack with the navigation bar', (
    tester,
  ) async {
    // With the keyboard up the helper must add nothing, or the content would
    // float a navigation bar's height above the keyboard. Clearing the keyboard
    // itself stays with the sheet's own content, via viewInsets.
    final rect = await probeSheet(
      tester,
      wrap: (probe) => probe,
      keyboard: 300,
    );
    expect(rect.bottom, 852.0);
  });

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
