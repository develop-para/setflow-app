import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/main.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/widgets/portal.dart';

const _clientSegment = ValueKey('portal-segment-client');
const _trainerSegment = ValueKey('portal-segment-trainer');

/// The access shape `loadAccess()` returns for an approved trainer.
BusinessAccess _approvedTrainer() => const BusinessAccess(
  userId: '00000000-0000-0000-0000-000000000001',
  accountRole: UserRole.member,
  resolvedRole: UserRole.trainer,
  availableRoles: {UserRole.member, UserRole.trainer},
  applicationStatus: BusinessApplicationStatus.approved,
);

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

  testWidgets('a guest is not offered a portal they cannot open', (
    tester,
  ) async {
    await launch(tester);

    // The pro side needs an admin-approved account, so a guest has nothing to
    // switch to — the control is absent rather than gated.
    expect(find.byType(MemberShell), findsOneWidget);
    expect(find.byKey(_clientSegment), findsNothing);
    expect(find.byKey(_trainerSegment), findsNothing);
  });

  testWidgets('approval is what puts the switcher on screen', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: const MaterialApp(home: Scaffold(body: PortalHeaderBar())),
      ),
    );
    expect(find.byKey(_trainerSegment), findsNothing);

    // Approval is the granted role, not the application row.
    state.businessAccess = _approvedTrainer();
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.byKey(_clientSegment), findsOneWidget);
    expect(find.byKey(_trainerSegment), findsOneWidget);
    // Glyphs, not words: "일반인" is nobody's name for themselves.
    expect(find.text('일반인'), findsNothing);
    expect(find.text('트레이너'), findsNothing);
  });

  testWidgets('switching portals swaps the shell behind the brand hold', (
    tester,
  ) async {
    await launch(tester);

    // Driven through the state rather than the header, because the header now
    // shows the switcher only to an approved account, which a widget test on
    // the demo build has no way to become.
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

    // Standing in the pro shell always keeps the way back visible, and coming
    // back is never gated.
    await tester.tap(find.byKey(_clientSegment));
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

    unawaited(stateOf(tester).switchPortal(AppPortal.trainer));
    await tester.pump(AppState.portalSwitchDuration);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_trainerSegment));
    await tester.pump();

    expect(find.byKey(const ValueKey('portal-transition-logo')), findsNothing);
    expect(find.byType(BusinessShell), findsOneWidget);
  });
}
