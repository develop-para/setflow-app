import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/personal_coaching_screen.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

import 'personal_coaching_test.dart' as fixtures;

Future<AppState> pump(
  WidgetTester tester, {
  bool small = false,
  bool beta = true,
  bool workout = false,
  bool withHistory = true,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 700) : const Size(432, 1000),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(personalCoachingBetaAvailable: beta);
  addTearDown(state.dispose);
  await state.initialize();
  state.sessions.clear();
  state.setMemberProfile(goals: ['근육 증가']);
  state.markPrecisionRecommendationPrompted();
  await state.flushPersistence();
  if (withHistory) {
    for (final item in fixtures.history()) {
      state.sessions[item.date] = item;
    }
  }
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: small ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(small ? 2 : 1),
            padding: const EdgeInsets.only(top: 24, bottom: 28),
          ),
          child: child!,
        ),
        home: workout
            ? DailyWorkoutScreen(date: fixtures.day)
            : PersonalCoachingScreen(date: fixtures.day),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> tap(
  WidgetTester tester,
  Finder finder, {
  double delta = 200,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
  }
  if (tester.widget(finder) is SwitchListTile) {
    finder = find.descendant(of: finder, matching: find.byType(Switch));
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'guest beta shows real targets, changes frequency, and preserves existing work',
    (tester) async {
      final state = await pump(tester);
      final original =
          state.sessions.values.first.exercises.single.sets.first.reps;
      expect(find.text('개인 코칭 (베타)'), findsOneWidget);
      expect(find.text('0 / 8세트 · 주 2회'), findsOneWidget);
      await tap(
        tester,
        find.byKey(const ValueKey('personal-coaching-enabled')),
      );
      expect(state.recommendationPreferences.personalCoachingEnabled, isTrue);
      await tap(tester, find.byKey(const ValueKey('personal-coaching-days-1')));
      expect(state.recommendationPreferences.plannedTrainingDays, 1);
      expect(find.text('0 / 8세트 · 주 1회'), findsOneWidget);
      expect(
        state.sessions.values.first.exercises.single.sets.first.reps,
        original,
      );
      await tap(tester, find.byKey(const ValueKey('personal-coaching-rir')));
      expect(state.useRir, isTrue);
      await tap(
        tester,
        find.byKey(const ValueKey('personal-coaching-enabled')),
        delta: -200,
      );
      expect(state.personalCoachingPlanForDate(fixtures.day), isNull);
    },
  );

  testWidgets(
    'workout settings reaches coaching and recommendations expose personal evidence',
    (tester) async {
      final state = await pump(tester, workout: true);
      await tap(tester, find.byTooltip('기록 메뉴'));
      await tap(tester, find.text('시간·추천 설정'));
      await tap(tester, find.byKey(const ValueKey('personal-coaching-open')));
      await tap(
        tester,
        find.byKey(const ValueKey('personal-coaching-enabled')),
      );
      state.setPersonalCoaching(trainingDays: 1);
      await tap(tester, find.byTooltip('Back'));
      await tap(tester, find.text('닫기'));
      await tap(tester, find.text('운동 선택'));
      await tap(tester, find.byKey(const ValueKey('training-focus-chest')));
      await tap(tester, find.byKey(const ValueKey('training-focus-apply')));
      expect(
        find.byKey(const ValueKey('recommendation-personal-coaching')),
        findsOneWidget,
      );
      expect(find.textContaining('RIR 2 이상'), findsOneWidget);
      await tap(tester, find.text('추천 운동 추가'));
      expect(state.sessionFor(fixtures.day).exercises, hasLength(1));
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'small dark screen at double text scale scrolls targets and progression without overflow',
    (tester) async {
      await pump(tester, small: true);
      await tap(
        tester,
        find.byKey(const ValueKey('personal-coaching-enabled')),
      );
      final exercise = find.byKey(
        const ValueKey('personal-coaching-exercise-bench'),
      );
      await tester.scrollUntilVisible(
        exercise,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(tester, exercise);
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'insufficient records and unavailable non-beta access are explicit',
    (tester) async {
      await pump(tester, withHistory: false);
      expect(find.text('기록 부족 · 기본값'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, beta: false, withHistory: false);
      expect(find.text('이용권 다시 확인'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('personal-coaching-enabled')),
        findsNothing,
      );
      expect(find.textContaining('기본 운동 추천은 계속'), findsOneWidget);
    },
  );
}
