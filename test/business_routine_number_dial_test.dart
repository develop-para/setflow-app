import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/screens/business_routine_flow_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  Finder routineNumberField(String label, {int index = 0}) => find
      .byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
        description: 'read-only routine number field labelled $label',
      )
      .at(index);

  Future<AppState> pumpEditor(
    WidgetTester tester,
    OwnedCoachingRoutine routine,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: SetflowTheme.light,
          home: BusinessRoutineEditorScreen(
            ownerRole: UserRole.trainer,
            routine: routine,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  Future<TextEditingController> fieldController(
    WidgetTester tester,
    String label,
  ) async {
    final field = routineNumberField(label);
    await tester.ensureVisible(field);
    await tester.pump();
    final widget = tester.widget<TextField>(field);
    expect(widget.readOnly, isTrue);
    expect(widget.canRequestFocus, isFalse);
    return widget.controller!;
  }

  Future<void> applyDialValue(
    WidgetTester tester, {
    required String label,
    required String value,
    required String expected,
  }) async {
    final field = routineNumberField(label);
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tapAt(tester.getCenter(field));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('number-dial-direct-input')),
      value,
    );
    await tester.pump();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(routineNumberField(label)).controller?.text,
      expected,
    );
  }

  Future<void> clearDialValue(
    WidgetTester tester, {
    required String label,
  }) async {
    final field = routineNumberField(label);
    await tester.ensureVisible(field);
    await tester.pump();
    final before = tester.widget<TextField>(field).controller?.text;
    await tester.tapAt(tester.getCenter(field));
    await tester.pumpAndSettle();
    expect(find.text('값 지우기'), findsOneWidget);
    await tester.tap(find.text('값 지우기'));
    await tester.pump();
    expect(
      tester.widget<TextField>(routineNumberField(label)).controller?.text,
      before,
      reason: '적용 전에 미설정 값이 draft에 반영됐다',
    );
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(routineNumberField(label)).controller?.text,
      isEmpty,
    );
  }

  testWidgets('저항운동 수치는 읽기 전용이고 다이얼 적용 후에만 바뀐다', (tester) async {
    const routine = OwnedCoachingRoutine(
      id: 'routine-strength',
      trainerId: 'trainer-id',
      title: '상체 루틴',
      status: BusinessRoutineStatus.draft,
      difficulty: BusinessRoutineDifficulty.intermediate,
      cumulativeUsers: 0,
      exercises: [
        OwnedRoutineExercise(
          id: 'routine-exercise-bench',
          routineId: 'routine-strength',
          baseExerciseId: 'bench',
          name: '바벨 벤치 프레스',
          targetMuscle: '가슴',
          orderIndex: 0,
          sets: [
            OwnedRoutineSet(
              id: 'routine-set-bench-1',
              exerciseId: 'routine-exercise-bench',
              setNumber: 1,
              type: 'normal',
              targetWeight: 40,
              targetReps: 10,
              restSeconds: 90,
            ),
          ],
        ),
      ],
    );
    await pumpEditor(tester, routine);

    final weightController = await fieldController(tester, '중량');
    await fieldController(tester, '횟수');
    await fieldController(tester, '휴식');

    final weightField = routineNumberField('중량');
    await tester.tapAt(tester.getCenter(weightField));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('number-dial-direct-input')),
      '99',
    );
    await tester.pump();
    expect(weightController.text, '40', reason: '적용 전에 draft가 바뀌었다');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(weightController.text, '40', reason: '취소한 값이 draft에 남았다');

    await clearDialValue(tester, label: '중량');
    await applyDialValue(tester, label: '중량', value: '82.5', expected: '82.5');
    await applyDialValue(tester, label: '횟수', value: '12', expected: '12');
    await applyDialValue(tester, label: '휴식', value: '120', expected: '120');

    final price = routineNumberField('판매 가격 (선택)');
    expect(tester.widget<TextField>(price).readOnly, isFalse);
  });

  testWidgets('유산소 시간 거리 RPE도 같은 다이얼로 편집한다', (tester) async {
    const routine = OwnedCoachingRoutine(
      id: 'routine-cardio',
      trainerId: 'trainer-id',
      title: '러닝 루틴',
      status: BusinessRoutineStatus.draft,
      difficulty: BusinessRoutineDifficulty.intermediate,
      cumulativeUsers: 0,
      exercises: [
        OwnedRoutineExercise(
          id: 'routine-exercise-run',
          routineId: 'routine-cardio',
          baseExerciseId: 'run',
          name: '트레드밀 러닝',
          targetMuscle: '유산소',
          orderIndex: 0,
          sets: [
            OwnedRoutineSet(
              id: 'routine-set-run-1',
              exerciseId: 'routine-exercise-run',
              setNumber: 1,
              type: 'normal',
              restSeconds: 0,
              durationSeconds: 1200,
              distanceMeters: 3000,
              intensityRpe: 4,
            ),
          ],
        ),
      ],
    );
    await pumpEditor(tester, routine);

    await fieldController(tester, '시간');
    await fieldController(tester, '거리');
    await fieldController(tester, '강도');
    await applyDialValue(tester, label: '시간', value: '42.5', expected: '42.5');
    await applyDialValue(tester, label: '거리', value: '7.5', expected: '7.5');
    await applyDialValue(tester, label: '강도', value: '6.5', expected: '6.5');
    await clearDialValue(tester, label: '거리');
  });
}
