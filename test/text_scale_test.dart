import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// People turn the system font up. At 2× the app has to still hold together —
/// that is a setting, not an edge case, and it is the one most likely to be on
/// for someone reading a set row mid-workout.
void main() {
  // 2배까지 버틴다. 1.5배에서 기록·달력이, 2배에서 체중 차트가 깨졌었다.
  const scale = 2.0;

  Future<String?> pumpAt(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = DateTime(2026, 11, 20);
    state.addExercise(date, state.exercises.first);

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: scale,
            maxScaleFactor: scale,
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    final error = tester.takeException();
    return error?.toString();
  }

  testWidgets('the screens people live in survive 2x text', (tester) async {
    final date = DateTime(2026, 11, 20);
    final screens = <String, Widget>{
      'CalendarScreen': const Scaffold(body: CalendarScreen()),
      'DailyWorkoutScreen': DailyWorkoutScreen(date: date),
      'DashboardScreen': const DashboardScreen(),
      'MyPageScreen': const MyPageScreen(),
      'MemberMembershipScreen': const MemberMembershipScreen(),
      'BodyCompositionScreen': const BodyCompositionScreen(),
      'CoachingDetailScreen': const CoachingDetailScreen(),
    };

    final broken = <String>[];
    for (final entry in screens.entries) {
      final error = await pumpAt(tester, entry.value);
      if (error != null) broken.add('${entry.key}: $error');
    }
    expect(broken, isEmpty, reason: '글자를 2배로 키우면 이 화면들이 깨진다');
  });
}
