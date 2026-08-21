import 'dart:async';

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

  AppState stateOf(WidgetTester tester) =>
      AppScope.of(tester.element(find.byType(MemberShell)));

  testWidgets('a guest tapping the pro portal gets the sign-in gate', (
    tester,
  ) async {
    await launch(tester);

    expect(find.byType(MemberShell), findsOneWidget);
    expect(find.text('일반인'), findsOneWidget);
    expect(find.text('트레이너'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('portal-segment-trainer')));
    await tester.pumpAndSettle();

    // The pro side is per-account, so the guest is asked rather than switched.
    expect(find.byKey(const ValueKey('auth-gate-sign-in')), findsOneWidget);
    expect(find.byType(BusinessShell), findsNothing);
    expect(find.byType(MemberShell), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth-gate-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byType(MemberShell), findsOneWidget);
  });

  testWidgets('switching portals swaps the shell behind the brand hold', (
    tester,
  ) async {
    await launch(tester);

    // Driven through the state rather than the header, because the header now
    // gates the pro side behind a sign-in that a widget test has no way to do.
    final state = stateOf(tester);
    unawaited(state.switchPortal(AppPortal.trainer));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('portal-transition-logo')),
      findsOneWidget,
    );

    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('portal-transition-logo')), findsNothing);
    expect(find.byType(BusinessShell), findsOneWidget);
    expect(find.byType(MemberShell), findsNothing);

    // Coming back is never gated.
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

    unawaited(stateOf(tester).switchPortal(AppPortal.trainer));
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
