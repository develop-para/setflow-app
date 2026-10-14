import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

final _monday = DateTime(2026, 10, 12);
const _recommendationButton = ValueKey('exercise-library-recommendation');

WorkoutSession _benchSession(
  DateTime day, {
  bool completed = true,
  int sets = 12,
}) => WorkoutSession(
  date: day,
  exercises: [
    WorkoutExercise(
      id: 'bench-${day.toIso8601String()}',
      template: exerciseCatalog.firstWhere((item) => item.id == 'bench'),
      sets: [
        for (var index = 0; index < sets; index++)
          WorkoutSetEntry(
            number: index + 1,
            weight: 60,
            reps: 10,
            completed: completed,
          ),
      ],
    ),
  ],
);

Future<AppState> _pump(
  WidgetTester tester, {
  required DateTime day,
  required WorkoutSession record,
  VoidCallback? onAdded,
  void Function(AppState)? configure,
  bool small = false,
  bool dark = false,
}) async {
  await tester.binding.setSurfaceSize(
    small ? const Size(320, 700) : const Size(432, 1100),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  state.sessions.clear();
  state.sessions[record.date] = record;
  state.setMemberProfile(goals: ['근육 증가']);
  state.setAutoRecommendNextExercise(true);
  state.markPrecisionRecommendationPrompted();
  state.setTrainingFocus(day, {TrainingMuscle.chest});
  configure?.call(state);
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
        home: ExerciseLibraryScreen(date: day, onAdded: onAdded ?? () {}),
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

Future<void> _closeRecovery(WidgetTester tester) async {
  Navigator.of(
    tester.element(find.byKey(const ValueKey('recommendation-stop-reason'))),
  ).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Monday first and next recommendations work after last Sunday reached its limit',
    (tester) async {
      final previous = _benchSession(_monday.subtract(const Duration(days: 1)));
      var additions = 0;
      final state = await _pump(
        tester,
        day: _monday,
        record: previous,
        onAdded: () => additions++,
      );
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recommendation-stop-reason')),
        findsNothing,
      );
      await _tap(tester, find.text('추천 운동 추가'));
      expect(additions, 1);
      final session = state.sessionFor(_monday);
      expect(session.exercises, hasLength(1));
      expect(session.exercises.single.sets.first.weight, 60);

      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('다음 운동 추천'), findsOneWidget);
      await _tap(tester, find.text('추천 운동 추가'));
      expect(additions, 2);
      expect(session.exercises, hasLength(2));
      expect(
        session.exercises.every((exercise) => exercise.template.muscle == '가슴'),
        isTrue,
      );
      expect(
        session.exercises.expand((exercise) => exercise.sets).length,
        lessThanOrEqualTo(6),
      );
      expect(previous.exercises.single.sets, hasLength(12));
      expect(
        previous.exercises.single.sets.every((set) => set.completed),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'an explicit first request continues past the automatic weekly plan without an override popup',
    (tester) async {
      final previous = _benchSession(_monday);
      final day = _monday.add(const Duration(days: 1));
      final state = await _pump(tester, day: day, record: previous);
      final explanation = state.recommendationVolumeStopReasonForDate(day);
      expect(explanation, contains('오늘 전체 0세트'));
      expect(explanation, contains('가슴 오늘 0세트 · 이번 주 12세트'));
      expect(explanation, isNot(contains('미완료')));
      expect(
        state.firstExerciseRecommendationResultForDate(day).stopReason,
        ExerciseRecommendationStopReason.volumeReached,
      );
      expect(state.sessionFor(day).exercises, isEmpty);
      expect(previous.exercises.single.sets, hasLength(12));
      await _tap(tester, find.byKey(_recommendationButton));
      expect(
        find.byKey(const ValueKey('recommendation-stop-reason')),
        findsNothing,
      );
      expect(find.text('오늘의 첫 운동 추천'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recommendation-additional-volume')),
        findsOneWidget,
      );
      await _tap(tester, find.text('추천 운동 추가'));
      expect(state.sessionFor(day).exercises, hasLength(1));
      expect(
        state.sessionFor(day).exercises.single.sets.length,
        greaterThan(1),
      );
      expect(previous.exercises.single.sets, hasLength(12));
      expect(
        previous.exercises.single.sets.every((set) => set.completed),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'reserved plans remain unfinished when the user explicitly asks for another exercise',
    (tester) async {
      final planned = _benchSession(_monday, completed: false, sets: 6);
      final state = await _pump(tester, day: _monday, record: planned);
      final explanation = state.recommendationVolumeStopReasonForDate(_monday);
      expect(explanation, contains('오늘 전체 6세트 (미완료 6세트 포함)'));
      expect(explanation, contains('가슴 오늘 6세트 · 이번 주 6세트'));
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.text('다음 운동 추천'), findsOneWidget);
      expect(
        planned.exercises.single.sets.every((set) => !set.completed),
        isTrue,
      );
      expect(state.sessionFor(_monday).exercises, hasLength(1));
      Navigator.of(tester.element(find.text('다음 운동 추천'))).pop();
      await tester.pumpAndSettle();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'eight completed chest sets allow explicit extra recommendation on a small large-text screen ($dark)',
      (tester) async {
        final previous = _benchSession(_monday, sets: 8);
        final originalExercise = previous.exercises.single;
        final state = await _pump(
          tester,
          day: _monday,
          record: previous,
          small: true,
          dark: dark,
          configure: (state) => state.setRecommendationProfile(
            RecommendationProfile(
              experienceLevel: TrainingExperienceLevel.advanced,
              availableEquipment: TrainingEquipment.values,
              painRegions: {},
              painLevel: 0,
              restrictedMovements: {},
              injuryNote: '',
              recoveryStatus: TrainingRecoveryStatus.normal,
              recoveryRecordedAt: _monday,
              updatedAt: _monday,
            ),
          ),
        );
        expect(
          state.recommendationVolumeStopReasonForDate(_monday),
          contains('가슴 오늘 8세트 · 이번 주 8세트'),
        );
        await _tap(tester, find.byKey(_recommendationButton));
        expect(
          find.byKey(const ValueKey('recommendation-stop-reason')),
          findsNothing,
        );
        expect(find.text('다음 운동 추천'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('recommendation-additional-volume')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('추천 운동 추가'));
        final session = state.sessionFor(_monday);
        expect(session.exercises, hasLength(2));
        expect(session.exercises.last.template.muscle, '가슴');
        expect(session.exercises.last.sets.length, greaterThan(1));
        expect(session.exercises.first, same(originalExercise));
        expect(originalExercise.sets, hasLength(8));
        expect(
          originalExercise.sets.every(
            (set) => set.completed && set.weight == 60 && set.reps == 10,
          ),
          isTrue,
        );
        expect(
          state
              .nextExerciseRecommendationResultForDate(
                _monday,
                completedExercise: session.exercises.last,
              )
              .stopReason,
          ExerciseRecommendationStopReason.volumeReached,
        );
        await _tap(tester, find.byKey(_recommendationButton));
        expect(
          find.byKey(const ValueKey('recommendation-stop-reason')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('recommendation-additional-volume')),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.text('다음 운동 추천'))).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }

  testWidgets('explicit extra volume keeps the workout time budget in force', (
    tester,
  ) async {
    final previous = _benchSession(_monday, sets: 8);
    final state = await _pump(
      tester,
      day: _monday,
      record: previous,
      configure: (state) => state.setWorkoutTimeBudget(_monday, 5),
    );
    await _tap(tester, find.byKey(_recommendationButton));
    expect(find.textContaining('설정한 운동 시간 안에'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recommendation-additional-volume')),
      findsNothing,
    );
    expect(state.sessionFor(_monday).exercises, hasLength(1));
    expect(previous.exercises.single.sets, hasLength(8));
    await _closeRecovery(tester);
  });
}
