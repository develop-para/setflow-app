import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// Nothing the thumb has to reach may sit under the system bars.
///
/// The check deliberately ignores anything inside a [Scrollable]: content that
/// runs under the navigation bar can still be scrolled into reach, so flagging
/// it would be noise. A button that is *pinned* — outside every scroll view —
/// has no such escape, so it must land inside the safe area or it is simply
/// unreachable.
void main() {
  const notch = 48.0;
  const navBar = 48.0;
  const screen = Size(393, 852);

  void applySystemBars(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screen;
    tester.view.viewPadding = const FakeViewPadding(top: notch, bottom: navBar);
    tester.view.padding = const FakeViewPadding(top: notch, bottom: navBar);
    addTearDown(tester.view.reset);
  }

  bool insideScrollable(WidgetTester tester, Element leaf) {
    var scrollable = false;
    leaf.visitAncestorElements((ancestor) {
      if (ancestor.widget is Scrollable) {
        scrollable = true;
        return false;
      }
      return true;
    });
    return scrollable;
  }

  /// Every pinned, on-screen button that pokes into a system bar, plus how many
  /// buttons were actually examined — a sweep that inspects nothing would pass
  /// no matter how broken the screen is, so the count is asserted too.
  ({List<String> offenders, int inspected}) sweep(WidgetTester tester) {
    const safeTop = notch;
    const safeBottom = 852.0 - navBar;
    final found = <String>[];
    var inspected = 0;

    for (final element
        in find
            .byWidgetPredicate((w) => w is ButtonStyleButton || w is IconButton)
            .evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      if (insideScrollable(tester, element)) continue;

      final rect = box.localToGlobal(Offset.zero) & box.size;
      // Off-screen entirely (a route being swapped, an unmounted page).
      if (rect.bottom <= 0 || rect.top >= 852) continue;

      inspected++;
      if (rect.bottom > safeBottom || rect.top < safeTop) {
        found.add('${element.widget.runtimeType} at $rect');
      }
    }
    return (offenders: found, inspected: inspected);
  }

  void expectAllReachable(WidgetTester tester, {String where = ''}) {
    final result = sweep(tester);
    expect(
      result.inspected,
      greaterThan(0),
      reason: '$where 에서 검사한 고정 버튼이 하나도 없다 — 스윕이 헛돌고 있다',
    );
    expect(result.offenders, isEmpty, reason: '$where 에서 버튼이 시스템 바에 가린다');
  }

  Future<AppState> pumpApp(WidgetTester tester) async {
    applySystemBars(tester);
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    return AppScope.of(tester.element(find.byType(MemberShell)));
  }

  testWidgets('every shell tab keeps its pinned buttons reachable', (
    tester,
  ) async {
    await pumpApp(tester);

    // Some tabs put every button inside a scroll view and so have nothing
    // pinned to check; the guard against a vacuous sweep is the total.
    var inspected = 0;
    for (final tab in ['홈', '통계', '커뮤니티', '마이']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      final result = sweep(tester);
      inspected += result.inspected;
      expect(result.offenders, isEmpty, reason: '$tab 탭에서 버튼이 시스템 바에 가린다');
    }
    expect(inspected, greaterThan(0), reason: '스윕이 고정 버튼을 하나도 보지 못했다');
  });

  testWidgets('the workout screen keeps its pinned buttons reachable', (
    tester,
  ) async {
    applySystemBars(tester);
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = DateTime(2026, 11, 1);
    state.addExercise(date, state.exercises.first);

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
    // Let the 250ms persistence debounce fire; the binding fails the test if a
    // timer is still pending when the tree is torn down.
    await tester.pump(const Duration(milliseconds: 400));

    expectAllReachable(tester, where: '이 화면');
  });

  testWidgets('the exercise library keeps its pinned buttons reachable', (
    tester,
  ) async {
    applySystemBars(tester);
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: ExerciseLibraryScreen(date: DateTime(2026, 11, 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Let the 250ms persistence debounce fire; the binding fails the test if a
    // timer is still pending when the tree is torn down.
    await tester.pump(const Duration(milliseconds: 400));

    expectAllReachable(tester, where: '이 화면');
  });
}
