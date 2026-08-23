import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/main.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/admin_content_screens.dart';
import 'package:setflow/screens/admin_system_screens.dart';
import 'package:setflow/screens/business_detail_screens.dart';
import 'package:setflow/screens/business_routine_flow_screens.dart';
import 'package:setflow/screens/consultation_retarget_screen.dart';
import 'package:setflow/screens/email_auth_screen.dart';
import 'package:setflow/screens/member_detail_screens.dart';
import 'package:setflow/screens/member_goal_screen.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/screens/password_screens.dart';
import 'package:setflow/screens/recommendation_profile_screen.dart';
import 'package:setflow/screens/routine_editor_screen.dart';
import 'package:setflow/screens/stats_detail_screens.dart';
import 'package:setflow/screens/welcome_screen.dart';
import 'package:setflow/screens/workspace_screen.dart';
import 'package:setflow/screens/business_screens.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/screens/evidence_library_screen.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/settlement_detail_screens.dart';
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

    // Text fields count too: one pinned under the navigation bar cannot be
    // focused, and on the sheets that carry a "직접 입력" box that is the whole
    // point of the sheet.
    for (final element
        in find
            .byWidgetPredicate(
              (w) =>
                  w is ButtonStyleButton ||
                  w is IconButton ||
                  w is EditableText,
            )
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
    for (final tab in ['홈', '함께', '커뮤니티', '마이']) {
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

  /// Pump one screen on its own, the way a route push would.
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    applySystemBars(tester);
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(theme: SetflowTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('every trainer-portal tab keeps its pinned buttons reachable', (
    tester,
  ) async {
    // The pro shell still uses Material's NavigationBar rather than
    // SetflowActionNavBar, so it insets itself differently from the member one.
    for (final role in [UserRole.trainer, UserRole.gym, UserRole.admin]) {
      var inspected = 0;
      await pumpScreen(tester, BusinessShell(role: role));

      final tabs = find.byType(NavigationDestination).evaluate().length;
      expect(tabs, greaterThan(0), reason: '$role 셸에 탭이 없다');

      for (var i = 0; i < tabs; i++) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await tester.pumpAndSettle();
        final result = sweep(tester);
        inspected += result.inspected;
        expect(
          result.offenders,
          isEmpty,
          reason: '$role 셸 $i번 탭에서 버튼이 시스템 바에 가린다',
        );
      }
      expect(inspected, greaterThan(0), reason: '$role 셸에서 본 고정 버튼이 없다');
    }
  });

  testWidgets('pushed detail screens keep their pinned buttons reachable', (
    tester,
  ) async {
    final screens = <String, Widget>{
      'BodyCompositionScreen': const BodyCompositionScreen(),
      'PostComposerScreen': const PostComposerScreen(),
      'CoachingDetailScreen': const CoachingDetailScreen(),
      'MemberMembershipScreen': const MemberMembershipScreen(),
      'MyPageScreen': const MyPageScreen(),
      'EvidenceLibraryScreen': const EvidenceLibraryScreen(),
      'BusinessSettingsListScreen': const BusinessSettingsListScreen(
        role: UserRole.trainer,
      ),
      'BusinessSettingsPlanScreen': const BusinessSettingsPlanScreen(
        role: UserRole.trainer,
      ),
      'BusinessSettingsNotificationsScreen':
          const BusinessSettingsNotificationsScreen(role: UserRole.trainer),
      'BusinessSettingsWithdrawScreen': const BusinessSettingsWithdrawScreen(
        role: UserRole.trainer,
      ),
      'BusinessBadgeRenewScreen': const BusinessBadgeRenewScreen(),
      'BusinessProfileEditScreen': const BusinessProfileEditScreen(
        role: UserRole.trainer,
      ),
      'SettlementRefundsPage': const SettlementRefundsPage(role: UserRole.gym),
      'TrainerSettlementBreakdownPage': const TrainerSettlementBreakdownPage(
        role: UserRole.trainer,
      ),
      'SettlementCommissionPage': const SettlementCommissionPage(
        role: UserRole.gym,
      ),
      'SettlementFinalConfirmPage': const SettlementFinalConfirmPage(
        role: UserRole.gym,
      ),
      'AdminSystemScreen': const AdminSystemScreen(),
      'AdminSystemRankingScreen': const AdminSystemRankingScreen(),
      'AdminSystemOcrScreen': const AdminSystemOcrScreen(),
      'AdminSystemPlansScreen': const AdminSystemPlansScreen(),
      'AdminSystemKeywordsScreen': const AdminSystemKeywordsScreen(),
      'AdminSystemLogsScreen': const AdminSystemLogsScreen(),
    };

    // Collected rather than asserted per screen: stopping at the first offender
    // would hide the rest, and the whole point is to see every one of them.
    var inspected = 0;
    final broken = <String>[];
    for (final entry in screens.entries) {
      await pumpScreen(tester, entry.value);
      final error = tester.takeException();
      // A layout overflow is as real a break as an unreachable button: it means
      // content the screen cannot show. Attribute it to the screen that threw.
      if (error != null) broken.add('${entry.key}: $error');
      final result = sweep(tester);
      inspected += result.inspected;
      for (final offender in result.offenders) {
        broken.add('${entry.key}: $offender');
      }
    }
    expect(broken, isEmpty, reason: '이 화면들의 버튼이 시스템 바에 가린다');
    expect(inspected, greaterThan(0), reason: '스윕이 고정 버튼을 하나도 보지 못했다');
  });

  testWidgets('screens built from real data keep their buttons reachable', (
    tester,
  ) async {
    // These take arguments, so they can only be swept with something real in
    // hand. The demo state carries routines, posts and consultations; a gym
    // member is the one shape it has none of, so it is built here.
    final fixtures = AppState();
    await fixtures.initialize();
    addTearDown(fixtures.dispose);
    final date = DateTime(2026, 11, 1);
    fixtures.addExercise(date, fixtures.exercises.first);

    final routine = fixtures.routines.first;
    final post = fixtures.communityPosts.first;
    final consultation = fixtures.consultations.first;
    final exercise =
        fixtures.sessions[fixtures.dateOnly(date)]!.exercises.first;
    const member = BusinessMember(
      id: 'm-1',
      gymId: 'g-1',
      name: '박소현',
      remainingPtSessions: 7,
      goal: '체지방 감량',
      level: '중급',
    );

    final screens = <String, Widget>{
      'RoutineStatsPage': RoutineStatsPage(routine: routine),
      'RoutineEditorScreen': RoutineEditorScreen(routine: routine),
      'ExpertRoutineDetailScreen': ExpertRoutineDetailScreen(routine: routine),
      'CommunityPostDetailScreen': CommunityPostDetailScreen(post: post),
      'ConsultationDetailScreen': ConsultationDetailScreen(
        consultation: consultation,
      ),
      'ExerciseSetScreen': ExerciseSetScreen(date: date, exercise: exercise),
      'MemberDetailScreen': const MemberDetailScreen(
        member: member,
        role: UserRole.trainer,
      ),
      'BusinessRoutineEditorScreen': const BusinessRoutineEditorScreen(
        ownerRole: UserRole.trainer,
      ),
      'TrainerPerformancePage': const TrainerPerformancePage(
        name: '김동현',
        membersLabel: '담당 24명',
        feedbackRate: '92%',
        rating: 4.8,
        monthlySales: 4200000,
        accentColor: SetflowColors.ink,
      ),
      'WorkspaceScreen': const WorkspaceScreen(role: UserRole.trainer),
      'ConsultationRetargetScreen': const ConsultationRetargetScreen(
        role: UserRole.trainer,
      ),
      'BusinessSetupScreen': const BusinessSetupScreen(role: UserRole.trainer),
      'MemberGoalScreen': const MemberGoalScreen(),
      'RecommendationProfileScreen': const RecommendationProfileScreen(),
      'WelcomeScreen': const WelcomeScreen(),
      'EmailAuthScreen': const EmailAuthScreen(),
      'PasswordResetRequestScreen': const PasswordResetRequestScreen(),
      'NewPasswordScreen': const NewPasswordScreen(),
      'AdminContentRoutinesScreen': const AdminContentRoutinesScreen(),
      'AdminContentReportsScreen': const AdminContentReportsScreen(),
      'AdminUserSanctionHistoryScreen': const AdminUserSanctionHistoryScreen(),
      'AdminContentMinorAlertsScreen': const AdminContentMinorAlertsScreen(),
      for (final section in SettingSection.values)
        'SettingDetailScreen.${section.name}': SettingDetailScreen(
          section: section,
        ),
      for (final tool in BusinessTool.values)
        'BusinessToolScreen.${tool.name}': BusinessToolScreen(
          tool: tool,
          role: UserRole.trainer,
        ),
    };

    var inspected = 0;
    final broken = <String>[];
    for (final entry in screens.entries) {
      await pumpScreen(tester, entry.value);
      final error = tester.takeException();
      // A layout overflow is as real a break as an unreachable button: it means
      // content the screen cannot show. Attribute it to the screen that threw.
      if (error != null) broken.add('${entry.key}: $error');
      final result = sweep(tester);
      inspected += result.inspected;
      for (final offender in result.offenders) {
        broken.add('${entry.key}: $offender');
      }
    }
    expect(broken, isEmpty, reason: '이 화면들의 버튼이 시스템 바에 가린다');
    expect(inspected, greaterThan(0), reason: '스윕이 고정 버튼을 하나도 보지 못했다');
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
