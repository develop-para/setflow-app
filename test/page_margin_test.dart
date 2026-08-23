import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/admin_content_screens.dart';
import 'package:setflow/screens/admin_system_screens.dart';
import 'package:setflow/screens/business_settings_screens.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/screens/evidence_library_screen.dart';
import 'package:setflow/screens/member_goal_screen.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/recommendation_profile_screen.dart';
import 'package:setflow/screens/settlement_detail_screens.dart';
import 'package:setflow/screens/workspace_screen.dart';
import 'package:setflow/theme.dart';

/// One page margin, everywhere.
///
/// Measured before this existed: the member screens sat at 18, the trainer and
/// onboarding screens at 24, a few at 16. It had split by author rather than by
/// what the screen was for, and the tell is that moving between tabs shifted the
/// text sideways under your eyes.
///
/// business_detail_test already held this line for the pro shell's pages. This
/// widens it to the screens that are pushed on their own, which is where the
/// drift had gone unnoticed.
void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

  /// The horizontal inset of the screen's own scrolling body.
  ({double left, double right})? bodyInset(WidgetTester tester) {
    for (final finder in [find.byType(ListView), find.byType(ListView)]) {
      for (final view in tester.widgetList<ListView>(finder)) {
        final padding = view.padding?.resolve(TextDirection.ltr);
        // A list with no padding of its own is nested inside one that has it.
        if (padding == null || (padding.left == 0 && padding.right == 0)) {
          continue;
        }
        return (left: padding.left, right: padding.right);
      }
    }
    return null;
  }

  final screens = <String, Widget>{
    'MyPageScreen': const MyPageScreen(),
    'MemberMembershipScreen': const MemberMembershipScreen(),
    'MemberGoalScreen': const MemberGoalScreen(),
    'RecommendationProfileScreen': const RecommendationProfileScreen(),
    'EvidenceLibraryScreen': const EvidenceLibraryScreen(),
    'BodyCompositionScreen': const BodyCompositionScreen(),
    'CoachingDetailScreen': const CoachingDetailScreen(),
    'WorkspaceScreen': const WorkspaceScreen(role: UserRole.trainer),
    'AdminSystemScreen': const AdminSystemScreen(),
    'AdminContentRoutinesScreen': const AdminContentRoutinesScreen(),
    'AdminContentReportsScreen': const AdminContentReportsScreen(),
    'BusinessSettingsListScreen': const BusinessSettingsListScreen(
      role: UserRole.trainer,
    ),
    'SettlementRefundsPage': const SettlementRefundsPage(role: UserRole.gym),
    'SettlementCommissionPage': const SettlementCommissionPage(
      role: UserRole.gym,
    ),
  };

  testWidgets('every pushed screen starts its content at the same margin', (
    tester,
  ) async {
    final wrong = <String>[];
    var measured = 0;
    for (final entry in screens.entries) {
      await pump(tester, entry.value);
      final inset = bodyInset(tester);
      if (inset == null) continue;
      measured++;
      if (inset.left != SetflowSpacing.gutter ||
          inset.right != SetflowSpacing.gutter) {
        wrong.add('${entry.key}: ${inset.left}/${inset.right}');
      }
    }
    // A sweep that measured nothing would pass on a completely broken app.
    expect(measured, greaterThan(6), reason: '여백을 잰 화면이 너무 적다');
    expect(
      wrong,
      isEmpty,
      reason: '이 화면들이 페이지 여백(${SetflowSpacing.gutter})을 벗어난다',
    );
  });

  test('the page presets all share one side margin', () {
    // The presets differ in how much air they leave above and below; the sides
    // are the part that must never vary, because that is the line the eye
    // follows from screen to screen.
    for (final preset in [
      SetflowInsets.pageList,
      SetflowInsets.pageListTight,
      SetflowInsets.pageHeader,
      SetflowInsets.pageForm,
      SetflowInsets.bottomAction,
    ]) {
      expect(preset.left, SetflowSpacing.gutter);
      expect(preset.right, SetflowSpacing.gutter);
    }
  });
}
