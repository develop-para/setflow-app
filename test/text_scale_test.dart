import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/detail_screens.dart';
import 'package:setflow/screens/member_membership_screen.dart';
import 'package:setflow/screens/member_mypage_screen.dart';
import 'package:setflow/screens/member_screens.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// People turn the system font up. At 1.5× the app has to still hold together —
/// that is a setting, not an edge case, and it is the one most likely to be on
/// for someone reading a set row mid-workout.
void main() {
  // 1.5는 흔한 설정이다. 여기서 처음 깨졌고, 깨진 곳이 하필 기록·달력이었다.
  const scale = 1.5;

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

  testWidgets('the screens people live in survive 1.5x text', (tester) async {
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
    expect(broken, isEmpty, reason: '글자를 1.5배로 키우면 이 화면들이 깨진다');
  });
}
