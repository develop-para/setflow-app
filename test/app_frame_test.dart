import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/member_screens.dart';

/// The app ships as a phone app *and* as a web bundle, so on a desktop browser
/// something has to decide how wide it is. That decision has to be made once,
/// above the Navigator — when it lived inside the home screen instead, pushed
/// routes (the routine editor, settings, every detail screen) rendered above
/// the frame and stretched to the full browser width. The home shell was 432px
/// and the routine editor was 1400px, which is what a reader sees as "the width
/// keeps changing".
void main() {
  const desktop = Size(1400, 900);
  const frameWidth = 432.0;

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(desktop);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    // The splash runs an explicit timer; pumpAndSettle alone would race it.
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
  }

  testWidgets('a route pushed over the shell keeps the shell width', (
    tester,
  ) async {
    await launch(tester);

    final home = tester.getSize(find.byType(MemberShell)).width;
    expect(home, frameWidth, reason: 'the shell itself must be framed');

    // Push the way every real screen does — onto the root navigator, above
    // `home:`. This is the exact mechanism that used to escape the frame.
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            key: ValueKey('pushed-probe'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pushed = tester
        .getSize(find.byKey(const ValueKey('pushed-probe')))
        .width;
    expect(
      pushed,
      home,
      reason: 'a pushed route must not be wider than the shell it covers',
    );
  });

  testWidgets('a phone-sized viewport is not letterboxed', (tester) async {
    // The frame is a cap, not a fixed width: on a real phone it must not leave
    // grey gutters down the sides.
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(MemberShell)).width, 390.0);
  });
}

/// Pushing returns a future that only completes on pop; awaiting it would hang.
void unawaited(Future<void> future) {}
