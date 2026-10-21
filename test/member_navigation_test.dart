import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/member_navigation.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/screens/member_menu_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/bottom_bar.dart';
import 'package:setflow/widgets/member_navigation_editor.dart';

Finder keyed(String value) => find.byKey(ValueKey(value));
Finder navLabel(String label) => find.descendant(
  of: find.byType(SetflowActionNavBar),
  matching: find.text(label),
);

Future<AppState> launch(
  WidgetTester tester, {
  List<MemberDestination>? navigation,
  Widget home = const MemberShell(),
  Size size = const Size(432, 900),
  double textScale = 1,
  bool dark = false,
  double bottomInset = 0,
}) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  if (navigation != null) await state.saveMemberNavigation(navigation);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: dark ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: EdgeInsets.only(bottom: bottomInset),
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> edit(WidgetTester tester) async {
  await tester.tap(keyed('home-app-menu'));
  await tester.pumpAndSettle();
  await tester.tap(keyed('navigation-edit'));
  await tester.pumpAndSettle();
}

Future<void> dragMenu(WidgetTester tester, Finder source, int slot) async {
  final start = tester.getCenter(source);
  final end = tester.getCenter(keyed('navigation-drop-$slot'));
  final gesture = await tester.startGesture(start);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 30));
  // Separate frames catch a drag target/source being lost during a rebuild.
  for (var step = 1; step <= 12; step++) {
    await gesture.moveTo(Offset.lerp(start, end, step / 12)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

List<MemberDestination> draft(WidgetTester tester) => tester
    .widget<MemberNavigationEditor>(find.byType(MemberNavigationEditor))
    .destinations;

void main() {
  test('old and damaged preferences restore five distinct usable menus', () {
    expect(MemberNavigation.restore(null), MemberNavigation.defaults);
    expect(MemberNavigation.restore('broken'), MemberNavigation.defaults);
    expect(
      MemberNavigation.restore(['dashboard', 'dashboard', 'unknown', 42]),
      [
        MemberDestination.dashboard,
        MemberDestination.home,
        MemberDestination.together,
        MemberDestination.record,
        MemberDestination.community,
      ],
    );
  });

  test('navigation survives a guest snapshot and app restart', () async {
    final repository = MemoryAppRepository();
    final state = AppState(repository: repository);
    addTearDown(state.dispose);
    await state.initialize();
    final configured = MemberNavigation.place(
      MemberNavigation.defaults,
      MemberDestination.library,
      2,
    );
    expect(await state.saveMemberNavigation(configured), isTrue);
    final restored = AppSnapshotCodec.decode(
      AppSnapshotCodec.encode(repository.snapshot!),
      state.exercises,
    );
    final restarted = AppState(
      repository: MemoryAppRepository(initialSnapshot: restored),
    );
    addTearDown(restarted.dispose);
    await restarted.initialize();
    expect(restarted.memberNavigation, configured);
  });

  test(
    'failed persistence rolls back menus and preserves other edits',
    () async {
      final repository = _FailingRepository();
      final state = AppState(repository: repository);
      addTearDown(state.dispose);
      await state.initialize();
      state.setMemberProfile(goals: const ['근력 향상']);
      await expectLater(
        state.saveMemberNavigation(
          MemberNavigation.place(
            MemberNavigation.defaults,
            MemberDestination.dashboard,
            0,
          ),
        ),
        throwsStateError,
      );
      expect(state.memberNavigation, MemberNavigation.defaults);
      repository.fail = false;
      await state.flushPersistence();
      expect(repository.snapshot!.memberNavigation, MemberNavigation.defaults);
      expect(repository.snapshot!.goals, ['근력 향상']);
    },
  );

  testWidgets('drag replaces a menu, swaps slots, and only saves on request', (
    tester,
  ) async {
    final state = await launch(tester);
    await edit(tester);
    await tester.scrollUntilVisible(
      keyed('menu-stats'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await dragMenu(tester, keyed('menu-stats'), 0);
    expect(draft(tester).first, MemberDestination.dashboard);
    expect(state.memberNavigation, MemberNavigation.defaults);
    await dragMenu(tester, keyed('navigation-drag-0'), 2);
    expect(draft(tester).first, MemberDestination.record);
    expect(draft(tester)[2], MemberDestination.dashboard);
    expect(draft(tester).toSet().length, 5);
    await tester.tap(keyed('navigation-save'));
    await tester.pumpAndSettle();
    expect(state.memberNavigation[2], MemberDestination.dashboard);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(keyed('bottom-bar-center-action'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(keyed('home-app-menu'), findsOneWidget);
    await tester.tap(navLabel('기록'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordScreen), findsOneWidget);
    await tester.tap(navLabel('기록'));
    await tester.pumpAndSettle();
    expect(find.text('무엇으로 기록할까요?'), findsOneWidget);
    await tester.tap(navLabel('기록'));
    await tester.pumpAndSettle();
    expect(find.text('무엇으로 기록할까요?'), findsNothing);

    // Home was removed from the bar, but remains available in the full menu.
    await tester.tap(keyed('home-app-menu'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('menu-home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('tap alternatives work, back cancels, reset restores defaults', (
    tester,
  ) async {
    final customized = MemberNavigation.place(
      MemberNavigation.defaults,
      MemberDestination.dashboard,
      0,
    );
    final state = await launch(tester, navigation: customized);
    await edit(tester);
    await tester.tap(keyed('menu-record'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('navigation-assign-1'));
    await tester.pumpAndSettle();
    expect(draft(tester)[1], MemberDestination.record);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MemberMenuScreen), findsOneWidget);
    expect(find.byType(MemberNavigationEditor), findsNothing);
    expect(state.memberNavigation, customized);

    await tester.tap(keyed('navigation-edit'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('navigation-drop-0'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('navigation-pick-home'));
    await tester.pumpAndSettle();
    expect(draft(tester).first, MemberDestination.home);
    await tester.tap(keyed('navigation-reset'));
    await tester.tap(keyed('navigation-save'));
    await tester.pumpAndSettle();
    expect(state.memberNavigation, MemberNavigation.defaults);
  });

  testWidgets('system back returns through visited tabs after pushed screens', (
    tester,
  ) async {
    await launch(tester);
    for (final label in ['함께', '커뮤니티', '마이', '마이']) {
      await tester.tap(navLabel(label));
      await tester.pumpAndSettle();
    }
    await tester.tap(keyed('home-app-menu'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberMenuScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MemberMenuScreen), findsNothing);
    expect(
      tester
          .widget<SetflowActionNavBar>(find.byType(SetflowActionNavBar))
          .selectedIndex,
      3,
    );

    for (final expectedSlot in [2, 1, 0]) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SetflowActionNavBar>(find.byType(SetflowActionNavBar))
            .selectedIndex,
        expectedSlot,
      );
    }
    expect(
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop(),
      isFalse,
      reason: '같은 탭을 다시 누른 것은 뒤로가기 기록에 넣지 않는다',
    );
  });

  testWidgets('system back restores today and calendar before leaving record', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(keyed('bottom-bar-center-action'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);

    final today = DateTime.now();
    await tester.tap(
      keyed('calendar-tint-${today.year}${today.month}${today.day}'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
    await tester.tap(keyed('record-open-calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);

    // 시트를 닫는 입력은 앞서 본 화면까지 함께 되돌리면 안 된다.
    await tester.tap(keyed('bottom-bar-center-action'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('무엇으로 기록할까요?'), findsNothing);
    expect(find.byType(CalendarScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(DailyWorkoutScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop(),
      isFalse,
    );
  });

  testWidgets('guests open workout places and centre actions require sign-in', (
    tester,
  ) async {
    await launch(
      tester,
      navigation: MemberNavigation.place(
        MemberNavigation.defaults,
        MemberDestination.membership,
        2,
      ),
    );
    await tester.tap(keyed('bottom-bar-center-action'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberMembershipScreen), findsOneWidget);
    expect(keyed('auth-gate-sign-in'), findsNothing);
    expect(find.text('헬스장 찾기'), findsOneWidget);
    await tester.ensureVisible(find.text('추가'));
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(keyed('auth-gate-sign-in'), findsOneWidget);
    await tester.tap(keyed('auth-gate-dismiss'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberMembershipScreen), findsOneWidget);
  });

  testWidgets(
    'record action sheet adding first exercise reveals today automatically',
    (tester) async {
      final state = await launch(tester);
      final today = state.dateOnly(DateTime.now());
      expect(state.sessions[today]?.exercises.isNotEmpty ?? false, isFalse);
      await tester.tap(keyed('bottom-bar-center-action'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarScreen), findsOneWidget);
      await tester.tap(keyed('bottom-bar-center-action'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('record-action-library'));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseLibraryScreen), findsOneWidget);

      final exercise = state.exercises.first;
      await tester.enterText(find.byType(TextField), exercise.name);
      await tester.pumpAndSettle();
      await tester.tap(find.text(exercise.name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1개 추가'));
      await tester.pumpAndSettle();

      expect(state.sessions[today]!.exercises.single.template.id, exercise.id);
      expect(find.byType(ExerciseLibraryScreen), findsNothing);
      expect(find.byType(CalendarScreen), findsNothing);
      expect(find.byType(DailyWorkoutScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'exercise library tab adds an exercise without popping the shell',
    (tester) async {
      final state = await launch(
        tester,
        navigation: MemberNavigation.place(
          MemberNavigation.defaults,
          MemberDestination.library,
          2,
        ),
      );
      await tester.tap(keyed('bottom-bar-center-action'));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
      final exercise = state.exercises.first;
      await tester.enterText(find.byType(TextField), exercise.name);
      await tester.pumpAndSettle();
      await tester.tap(find.text(exercise.name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1개 추가'));
      await tester.pumpAndSettle();
      expect(
        state
            .sessions[state.dateOnly(DateTime.now())]!
            .exercises
            .single
            .template
            .id,
        exercise.id,
      );
      expect(find.byType(DailyWorkoutScreen), findsOneWidget);
      expect(find.byType(MemberShell), findsOneWidget);
      expect(find.byType(SetflowActionNavBar), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    testWidgets('editor fits small phones at large text, dark=$dark', (
      tester,
    ) async {
      await launch(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        dark: dark,
        bottomInset: 34,
      );
      await edit(tester);
      expect(tester.takeException(), isNull);
      final drop = tester.getRect(keyed('navigation-drop-2'));
      expect(drop.bottom, lessThanOrEqualTo(568 - 34));
      // The raised part of the center disc also belongs to the drop/tap target.
      await tester.tapAt(Offset(drop.center.dx, drop.top + 4));
      await tester.pumpAndSettle();
      expect(find.text('3번째 메뉴 선택'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('trainer has five clear tabs and records opens the member tab', (
    tester,
  ) async {
    await launch(tester, home: const BusinessShell(role: UserRole.trainer));
    final destinations = find.byType(NavigationDestination);
    expect(
      tester
          .widgetList<NavigationDestination>(destinations)
          .map((item) => item.label),
      ['오늘', '회원', '루틴', '상담', '설정'],
    );
    expect(find.byType(SetflowActionNavBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('trainer-record-member')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(find.byType(PeoplePage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(destinations.at(4));
    await tester.pumpAndSettle();
    expect(find.byType(BusinessSettingsListScreen), findsOneWidget);
    await tester.tap(destinations.at(2));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineManagerPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(destinations.at(2));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BusinessSettingsListScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(TrainerHome), findsOneWidget);
    expect(
      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop(),
      isFalse,
      reason: '이미 열린 루틴 탭을 다시 눌러도 기록이 중복되지 않는다',
    );
  });

  for (final role in [UserRole.gym, UserRole.admin]) {
    testWidgets('$role shell returns through its visited tabs', (tester) async {
      await launch(tester, home: BusinessShell(role: role));
      final destinations = find.byType(NavigationDestination);
      for (final page in [1, 2, 2]) {
        await tester.tap(destinations.at(page));
        await tester.pumpAndSettle();
      }
      for (final page in [1, 0]) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          page,
        );
      }
      expect(
        await tester.state<NavigatorState>(find.byType(Navigator)).maybePop(),
        isFalse,
      );
    });
  }
}

class _FailingRepository extends MemoryAppRepository {
  bool fail = true;

  @override
  Future<void> save(AppSnapshot snapshot) async {
    if (fail) throw StateError('disk full');
    await super.save(snapshot);
  }
}
