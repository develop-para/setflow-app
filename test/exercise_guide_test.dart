import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/exercise_guides.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// "렛 풀 다운" is a name, not an instruction. A beginner reading it learns
/// nothing, so each exercise carries the steps for doing it.
void main() {
  test('every guide belongs to an exercise that exists', () {
    final ids = exerciseCatalog.map((e) => e.id).toSet();
    final orphans = exerciseGuides.keys.where((id) => !ids.contains(id));
    expect(orphans, isEmpty, reason: '카탈로그에 없는 종목의 설명이 남아 있다 — 이름이 바뀌었을 것이다');
  });

  test('a guide is steps, not a paragraph', () {
    for (final entry in exerciseGuides.entries) {
      expect(entry.value, isNotEmpty, reason: '${entry.key}의 설명이 비었다');
      expect(
        entry.value.length,
        greaterThanOrEqualTo(2),
        reason: '${entry.key}이 한 덩어리 문장이다 — 따라 할 순서로 나뉘어야 한다',
      );
      for (final step in entry.value) {
        expect(step.trim(), isNotEmpty);
      }
    }
  });

  test('every gap in coverage is a decision, not an accident', () {
    // 데이터셋에 정확한 대응 항목이 없어 일부러 비워 둔 네 종목이다. 비슷한
    // 종목으로 억지로 이으면 초보자에게 틀린 동작을 가르치게 된다 — 근거는
    // docs/exercise-guides.md. 여기 없는 종목이 비면 매핑이 깨진 것이다.
    const deliberatelyBlank = {
      'face_pull',
      'hip_thrust',
      'bird_dog',
      'rowing_machine',
      // 맨몸운동 추가분 — 데이터셋에 정확한 대응 항목이 없다.
      'bodyweight_squat',
      'burpee',
      'side_plank',
      'mountain_climber',
      'wall_sit',
    };
    final uncovered = exerciseCatalog
        .map((e) => e.id)
        .where((id) => !exerciseGuides.containsKey(id))
        .toSet();
    expect(uncovered, deliberatelyBlank, reason: '비어 있는 종목이 문서의 결정 목록과 다르다');
  });

  testWidgets('the steps are reachable from the exercise being done', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = DateTime(2026, 11, 7);
    final guided = exerciseCatalog.firstWhere(
      (e) => exerciseGuides.containsKey(e.id),
    );
    state.addExercise(date, guided);

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

    await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('수행 방법'), findsOneWidget);

    await tester.tap(find.text('수행 방법'));
    await tester.pumpAndSettle();

    final steps = exerciseGuides[guided.id]!;
    expect(find.text(steps.first), findsOneWidget);
    expect(find.textContaining('${steps.length}단계'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
  });
}
