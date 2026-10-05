import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/exercise_guides.dart';
import 'package:setflow/data/exercise_visuals.dart';
import 'package:setflow/data/offline_exercise_catalog.dart';
import 'package:setflow/data/supabase_exercise_catalog_repository.dart'
    show exerciseTemplateFromCatalogRow;
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/exercise_visual_viewer.dart';

final _date = DateTime(2026, 11, 8);

Future<AppState> _pumpScreen(
  WidgetTester tester,
  Widget Function(AppState) screen, {
  bool largeText = false,
}) async {
  await tester.binding.setSurfaceSize(Size(largeText ? 320 : 432, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState();
  await state.initialize();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: largeText ? SetflowTheme.dark : SetflowTheme.light,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: largeText ? 2 : 1,
          maxScaleFactor: largeText ? 2 : 1,
          child: child!,
        ),
        home: screen(state),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('a projected coaching exercise opens the same exact guide', (
    tester,
  ) async {
    final template = exerciseCatalog.singleWhere(
      (exercise) => exercise.id == 'row',
    );
    final state = await _pumpScreen(tester, (state) {
      state
          .sessionFor(_date)
          .exercises
          .add(
            WorkoutExercise(
              id: 'coached-row',
              template: template,
              sets: [WorkoutSetEntry(number: 1, weight: 40, reps: 10)],
              coachingWorkoutId: 'coached-workout',
              coachingAuthor: '트레이너',
            ),
          );
      return DailyWorkoutScreen(date: _date);
    });
    expect(find.byType(ExerciseVisualViewer), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('coached-exercise-guide-coached-row')),
    );
    await tester.pumpAndSettle();
    final viewer = tester.widget<ExerciseVisualViewer>(
      find.byType(ExerciseVisualViewer),
    );
    expect(viewer.visual, same(exerciseVisuals['row']));
    expect(find.text(exerciseGuides['row']!.first), findsOneWidget);
    final exercise = state.sessionFor(_date).exercises.single;
    expect(exercise.coachingWorkoutId, 'coached-workout');
    expect(exercise.sets.single.completed, isFalse);
    expect(exercise.sets.single.weight, 40);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final largeText in [false, true]) {
    testWidgets(
      'library previews exact guidance without selecting or adding ($largeText)',
      (tester) async {
        var additions = 0;
        final state = await _pumpScreen(
          tester,
          (_) => ExerciseLibraryScreen(date: _date, onAdded: () => additions++),
          largeText: largeText,
        );
        await tester.enterText(find.byType(TextFormField), '바벨 벤치 프레스');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('exercise-guide-bench')));
        await tester.pumpAndSettle();
        final viewer = tester.widget<ExerciseVisualViewer>(
          find.byType(ExerciseVisualViewer),
        );
        expect(viewer.visual, same(exerciseVisuals['bench']));
        expect(viewer.exerciseName, '바벨 벤치 프레스');
        expect(find.text(exerciseGuides['bench']!.first), findsOneWidget);
        expect(find.text('동작 예시 (데모)'), findsOneWidget);
        expect(find.textContaining('로그인'), findsNothing);
        expect(state.sessionFor(_date).exercises, isEmpty);
        expect(additions, 0);
        expect(tester.takeException(), isNull);

        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        expect(find.byTooltip('선택 해제'), findsNothing);
        await tester.tap(find.byTooltip('선택').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('1개 추가'));
        await tester.pumpAndSettle();
        expect(state.sessionFor(_date).exercises.single.template.id, 'bench');
        expect(additions, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final id in ['row', 'plank', 'stationary_bike']) {
    testWidgets('set screen opens exact $id guidance on request', (
      tester,
    ) async {
      final template = exerciseCatalog.singleWhere(
        (exercise) => exercise.id == id,
      );
      final state = await _pumpScreen(tester, (state) {
        state.addExercise(_date, template);
        return ExerciseSetScreen(
          date: _date,
          exercise: state.sessionFor(_date).exercises.single,
        );
      });
      expect(find.byType(ExerciseVisualViewer), findsNothing);
      await tester.tap(find.byKey(const ValueKey('exercise-guide')));
      await tester.pumpAndSettle();
      final viewer = tester.widget<ExerciseVisualViewer>(
        find.byType(ExerciseVisualViewer),
      );
      expect(viewer.visual, same(exerciseVisuals[id]));
      expect(viewer.exerciseName, template.name);
      expect(find.text(exerciseGuides[id]!.first), findsOneWidget);
      expect(state.sessionFor(_date).exercises, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'an unsupported variant has no guide in the library or set screen',
    (tester) async {
      final template = offlineExerciseCatalog.singleWhere(
        (exercise) => exercise.id == '5b34c34c-cc4f-54f1-bd64-ab37af17d01d',
      );
      final state = await _pumpScreen(
        tester,
        (_) => ExerciseLibraryScreen(date: _date),
      );
      await tester.enterText(find.byType(TextFormField), template.name);
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, template.name).first;
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('수행 방법')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('exercise-guide-${template.id}')),
        findsNothing,
      );
      state.addExercise(_date, template);
      Navigator.of(tester.element(tile)).push(
        MaterialPageRoute<void>(
          builder: (_) => ExerciseSetScreen(
            date: _date,
            exercise: state.sessionFor(_date).exercises.single,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exercise-guide')), findsNothing);
      expect(find.byType(ExerciseVisualViewer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  final snapshot =
      jsonDecode(
            File(
              'test/fixtures/exercise_visual_shared_rows.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final raw in snapshot['rows'] as List) {
    final template = exerciseTemplateFromCatalogRow(
      Map<String, dynamic>.from(raw as Map),
    );
    testWidgets('shared ${template.sourceId} opens its own steps and visual', (
      tester,
    ) async {
      await _pumpScreen(tester, (state) {
        state.addExercise(_date, template);
        return ExerciseSetScreen(
          date: _date,
          exercise: state.sessionFor(_date).exercises.single,
        );
      });
      await tester.tap(find.byKey(const ValueKey('exercise-guide')));
      await tester.pumpAndSettle();
      final viewer = tester.widget<ExerciseVisualViewer>(
        find.byType(ExerciseVisualViewer),
      );
      expect(viewer.visual, same(exerciseVisuals[template.id]));
      expect(viewer.exerciseName, template.name);
      expect(find.text(exerciseGuides[template.id]!.first), findsOneWidget);
      expect(find.textContaining('로그인'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
