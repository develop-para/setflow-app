import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

final _day = DateTime(2026, 10, 4);

Future<AppState> _pump(
  WidgetTester tester, {
  bool dark = false,
  bool small = false,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 700) : const Size(432, 1100),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  state.sessions.clear();
  state.setMemberProfile(goals: ['근육 증가']);
  state.markPrecisionRecommendationPrompted();
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: dark ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(small ? 2 : 1),
            padding: const EdgeInsets.only(top: 24, bottom: 28),
          ),
          child: child!,
        ),
        home: DailyWorkoutScreen(date: _day),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester, {bool chooseTime = false}) async {
  await _tap(tester, find.text('운동 선택'));
  await _tap(tester, find.byKey(const ValueKey('training-focus-chest')));
  if (chooseTime) {
    await _tap(tester, find.byKey(const ValueKey('training-time-30')));
  }
  await _tap(tester, find.byKey(const ValueKey('training-focus-apply')));
}

Future<void> _settings(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('기록 메뉴'));
  await _tap(tester, find.text('시간·추천 설정'));
}

void main() {
  testWidgets(
    'first recommendation accepts daily time and shows a concrete reason with data sufficiency',
    (tester) async {
      final state = await _pump(tester);
      await _start(tester, chooseTime: true);
      expect(state.sessionFor(_day).timeBudgetMinutes, 30);
      expect(
        find.byKey(const ValueKey('recommendation-time-estimate')),
        findsOneWidget,
      );
      expect(find.textContaining('기록 부족'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('recommendation-details')));
      expect(find.textContaining('소요시간은 추정치'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      expect(state.sessionFor(_day).exercises, hasLength(1));
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'canceling the start sheet keeps previously committed focus and time',
    (tester) async {
      final state = await _pump(tester);
      await _tap(tester, find.text('운동 선택'));
      await _tap(tester, find.byKey(const ValueKey('training-time-30')));
      Navigator.of(
        tester.element(find.byKey(const ValueKey('training-focus-apply'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(state.sessionFor(_day).timeBudgetMinutes, isNull);
      expect(state.sessionFor(_day).trainingFocus, isNull);
      expect(state.sessionFor(_day).exercises, isEmpty);
    },
  );

  testWidgets(
    'unavailable equipment requests an equivalent and records only a daily exclusion',
    (tester) async {
      final state = await _pump(tester);
      state.setTrainingFocus(_day, {TrainingMuscle.chest});
      final first = state.firstExerciseRecommendationForDate(_day)!;
      await _tap(tester, find.text('운동 선택'));
      await _tap(tester, find.byKey(const Key('recommendation-no-equipment')));
      expect(state.sessionFor(_day).unavailableEquipmentExerciseIds, {
        first.template.id,
      });
      expect(state.recommendationPreferences.excludedExerciseIds, isEmpty);
      expect(find.textContaining('대신 같은 동작'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      final added = state.sessionFor(_day).exercises.single;
      expect(added.template.muscle, first.template.muscle);
      expect(added.template.id, isNot(first.template.id));
      expect(state.recommendationPreferences.manualSelectionDays, isEmpty);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final always in [false, true]) {
    testWidgets('exclusion choice remembers the intended scope ($always)', (
      tester,
    ) async {
      final state = await _pump(tester);
      state.setTrainingFocus(_day, {TrainingMuscle.chest});
      final first = state.firstExerciseRecommendationForDate(_day)!;
      await _tap(tester, find.text('운동 선택'));
      await _tap(
        tester,
        find.byKey(const ValueKey('recommendation-exclusions')),
      );
      await _tap(
        tester,
        find.byKey(
          ValueKey(
            always
                ? 'recommendation-exclude-always'
                : 'recommendation-skip-today',
          ),
        ),
      );
      expect(
        state.recommendationPreferences.excludedExerciseIds.contains(
          first.template.id,
        ),
        always,
      );
      expect(
        state
            .sessionFor(_day)
            .skippedRecommendationIds
            .contains(first.template.id),
        !always,
      );
      expect(find.text(first.template.name), findsNothing);
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      expect(
        state.sessionFor(_day).exercises.single.template.id,
        isNot(first.template.id),
      );
      await tester.pump(const Duration(seconds: 4));
    });
  }

  testWidgets(
    'settings restores both daily and permanent exclusions and changes only future recommendations',
    (tester) async {
      final state = await _pump(tester);
      state.skipRecommendedExercise(_day, 'bench', equipmentUnavailable: true);
      state.setExerciseExcludedFromRecommendations('squat', true);
      await _settings(tester);
      await _tap(tester, find.byKey(const ValueKey('recommendation-time-15')));
      await _tap(
        tester,
        find.byKey(const ValueKey('recommendation-restore-bench')),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('recommendation-restore-squat')),
      );
      expect(state.sessionFor(_day).timeBudgetMinutes, 15);
      expect(state.sessionFor(_day).skippedRecommendationIds, isEmpty);
      expect(state.sessionFor(_day).unavailableEquipmentExerciseIds, isEmpty);
      expect(state.recommendationPreferences.excludedExerciseIds, isEmpty);
      expect(find.text('제외한 운동이 없어요.'), findsOneWidget);
      await _tap(tester, find.text('닫기'));
    },
  );

  testWidgets(
    'next recommendation manual choice actually opens the exercise library without a new survey',
    (tester) async {
      final state = await _pump(tester);
      state.setTrainingFocus(_day, {TrainingMuscle.chest});
      state.autoStartRestTimer = false;
      state.addExercise(
        _day,
        state.exercises.firstWhere((exercise) => exercise.id == 'bench'),
      );
      final exercise = state.sessionFor(_day).exercises.single;
      for (final set in exercise.sets) {
        set.completed = true;
      }
      exercise.sets.last.completed = false;
      state.precisionRecommendationPrompted = false;
      await tester.pumpAndSettle();
      final row = find.byKey(
        ValueKey('inline-set-weight-${exercise.sets.last.number}'),
      );
      await tester.ensureVisible(row);
      await tester.drag(row, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(find.text('다음 운동 추천'), findsOneWidget);
      expect(find.text('추천을 더 정확하게'), findsNothing);
      await _tap(tester, find.text('직접 선택'));
      expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'recommendation and settings fit small screens with 2x text and safe area ($dark)',
      (tester) async {
        final state = await _pump(tester, dark: dark, small: true);
        await _start(tester, chooseTime: true);
        expect(tester.takeException(), isNull);
        await _tap(
          tester,
          find.byKey(const ValueKey('recommendation-details')),
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('추천 운동 추가'));
        await tester.pump(const Duration(seconds: 4));
        expect(state.sessionFor(_day).exercises, hasLength(1));
        expect(tester.takeException(), isNull);
        state.setExerciseExcludedFromRecommendations(
          'bulgarian_split_squat',
          true,
        );
        await _tap(tester, find.byTooltip('기록 메뉴'));
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('오늘 30분 · 추천 설정'));
        await _tap(
          tester,
          find.byKey(
            const ValueKey('recommendation-restore-bulgarian_split_squat'),
          ),
        );
        await _tap(
          tester,
          find.byKey(const ValueKey('recommendation-time-15')),
        );
        await _tap(tester, find.text('닫기'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
