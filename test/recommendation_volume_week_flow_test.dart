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
}) async {
  await tester.binding.setSurfaceSize(const Size(432, 1100));
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
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
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
    'current week limit shows actual weekly sets and keeps the record',
    (tester) async {
      final previous = _benchSession(_monday);
      final day = _monday.add(const Duration(days: 1));
      final state = await _pump(tester, day: day, record: previous);
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.textContaining('오늘 전체 0세트'), findsOneWidget);
      expect(find.textContaining('가슴 오늘 0세트 · 이번 주 12세트'), findsOneWidget);
      expect(find.textContaining('미완료'), findsNothing);
      expect(state.sessionFor(day).exercises, isEmpty);
      expect(previous.exercises.single.sets, hasLength(12));
      await _closeRecovery(tester);
      expect(find.byType(ExerciseLibraryScreen), findsOneWidget);
    },
  );

  testWidgets(
    'unfinished plans explain their reserved volume without completing sets',
    (tester) async {
      final planned = _benchSession(_monday, completed: false, sets: 6);
      final state = await _pump(tester, day: _monday, record: planned);
      await _tap(tester, find.byKey(_recommendationButton));
      expect(find.textContaining('오늘 전체 6세트 (미완료 6세트 포함)'), findsOneWidget);
      expect(find.textContaining('가슴 오늘 6세트 · 이번 주 6세트'), findsOneWidget);
      expect(
        planned.exercises.single.sets.every((set) => !set.completed),
        isTrue,
      );
      expect(state.sessionFor(_monday).exercises, hasLength(1));
      await _closeRecovery(tester);
    },
  );
}
