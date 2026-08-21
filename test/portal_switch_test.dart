import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/member_screens.dart';

void main() {
  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
  }

  testWidgets('header switcher swaps portals behind the brand hold', (
    tester,
  ) async {
    await launch(tester);

    expect(find.byType(MemberShell), findsOneWidget);
    expect(find.text('일반인'), findsOneWidget);
    expect(find.text('트레이너'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('portal-segment-trainer')));
    await tester.pump();

    // The hold covers the swap instead of a route transition.
    expect(
      find.byKey(const ValueKey('portal-transition-logo')),
      findsOneWidget,
    );

    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('portal-transition-logo')), findsNothing);
    expect(find.byType(BusinessShell), findsOneWidget);
    expect(find.byType(MemberShell), findsNothing);

    await tester.tap(find.byKey(const ValueKey('portal-segment-client')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('portal-transition-logo')),
      findsOneWidget,
    );

    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();

    expect(find.byType(MemberShell), findsOneWidget);
    expect(find.byType(BusinessShell), findsNothing);
  });

  testWidgets('header row leaves both shells overflow-free on a small phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SetflowApp());
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('portal-segment-trainer')));
    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(BusinessShell), findsOneWidget);
  });

  testWidgets('tapping the active portal does nothing', (tester) async {
    await launch(tester);

    await tester.tap(find.byKey(const ValueKey('portal-segment-client')));
    await tester.pump();

    expect(find.byKey(const ValueKey('portal-transition-logo')), findsNothing);
    expect(find.byType(MemberShell), findsOneWidget);
  });
}
