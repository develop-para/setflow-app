import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/common.dart';

void main() {
  Future<AppState> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    state.startRestTimer(90);
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: state,
            builder: (_, _) => Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.white)),
                if (state.restRemaining > 0)
                  Positioned.fill(
                    child: FloatingRestTimer(
                      sessionId: state.restSessionId,
                      seconds: state.restRemaining,
                      totalSeconds: 90,
                      onAddTime: state.extendRestTimer,
                      onCancel: state.cancelRestTimer,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  testWidgets('outside closes the small window without stopping the timer', (
    tester,
  ) async {
    final state = await mount(tester);
    expect(tester.getSize(find.byType(GlobalRestTimerOverlay)).width, 240);
    await tester.tapAt(const Offset(20, 650));
    await tester.pump();
    expect(find.byType(GlobalRestTimerOverlay), findsNothing);
    expect(state.restRemaining, 90);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(GlobalRestTimerOverlay), findsNothing);
    expect(state.restRemaining, greaterThan(0));
    state.extendRestTimer();
    await tester.pump();
    expect(find.byType(GlobalRestTimerOverlay), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rest-floating-reopen')));
    await tester.pump();
    expect(find.byType(GlobalRestTimerOverlay), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rest-bar-finish')));
    await tester.pump();
    expect(state.restRemaining, 0);
  });

  testWidgets(
    'a new rest reopens and can be dragged in both axes within bounds',
    (tester) async {
      final state = await mount(tester);
      final panel = find.byType(GlobalRestTimerOverlay);
      final before = tester.getTopLeft(panel);
      await tester.dragFrom(
        before + const Offset(30, 20),
        const Offset(-65, 90),
      );
      await tester.pump();
      final after = tester.getTopLeft(panel);
      expect(after.dx, lessThan(before.dx));
      expect(after.dy, greaterThan(before.dy));
      await tester.dragFrom(
        after + const Offset(30, 20),
        const Offset(-500, 900),
      );
      await tester.pump();
      expect(tester.getRect(panel).left, greaterThanOrEqualTo(8));
      expect(tester.getRect(panel).bottom, lessThanOrEqualTo(712));
      await tester.tapAt(const Offset(350, 10));
      await tester.pump();
      expect(panel, findsNothing);
      state.startRestTimer(60);
      await tester.pump();
      expect(panel, findsOneWidget);
      expect(find.text('01:00'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(280, 400));
      await tester.pump();
      expect(tester.getRect(panel).right, lessThanOrEqualTo(272));
      expect(tester.getRect(panel).bottom, lessThanOrEqualTo(392));
      expect(tester.takeException(), isNull);
      state.cancelRestTimer();
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
