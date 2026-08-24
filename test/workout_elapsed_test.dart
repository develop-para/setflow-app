import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/models.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

/// "몇 시간 몇 분 운동했나"는 첫 세트를 완료한 도장과 마지막 도장 사이의
/// 시간이다 — 계획도, 화면을 연 시각도 아니다.
void main() {
  test('the clock starts at the first completed set and survives undo', () {
    final session = WorkoutSession(date: DateTime(2026, 11, 7), exercises: []);
    // 시작 전에는 시간이 없다. "0분"은 정보가 아니다.
    expect(session.elapsedUntil(DateTime(2026, 11, 7, 10)), isNull);

    session.startedAt = DateTime(2026, 11, 7, 10);
    expect(
      session.elapsedUntil(DateTime(2026, 11, 7, 11, 23)),
      const Duration(hours: 1, minutes: 23),
    );
  });

  test('completing a set stamps the session it belongs to', () async {
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);

    final date = DateTime(2026, 11, 7);
    state.addExercise(date, state.exercises.firstWhere((e) => !e.isCardio));
    final session = state.sessions[state.dateOnly(date)]!;
    expect(session.startedAt, isNull, reason: '추가만으로 시계가 돌면 안 된다');

    final set = session.exercises.first.sets.first;
    await state.toggleSet(set, startRest: false);
    expect(session.startedAt, isNotNull);
    expect(session.endedAt, isNotNull);

    // 되돌려도 시작 도장은 남는다 — 운동을 시작했다는 사실은 취소되지 않는다.
    final started = session.startedAt;
    await state.toggleSet(set, startRest: false);
    expect(session.startedAt, started);
  });

  test('the stamps survive the snapshot round trip', () {
    final catalog = [
      ExerciseTemplate(
        id: 'bench',
        name: '바벨 벤치 프레스',
        muscle: '가슴',
        icon: Icons.fitness_center,
      ),
    ];
    final session = WorkoutSession(
      date: DateTime(2026, 11, 7),
      exercises: [],
      startedAt: DateTime(2026, 11, 7, 10, 0),
      endedAt: DateTime(2026, 11, 7, 11, 23),
    );
    final decoded = AppSnapshotCodec.decode(
      AppSnapshotCodec.encode(
        AppSnapshot(
          role: UserRole.member,
          isDarkMode: false,
          weightUnit: 'kg',
          restDefaultSeconds: 90,
          sessions: {session.date: session},
          routines: const [],
        ),
      ),
      catalog,
    )!;
    final back = decoded.sessions[session.date]!;
    expect(back.startedAt, session.startedAt);
    expect(back.endedAt, session.endedAt);
  });

  testWidgets('the summary bar shows hours and minutes once training starts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = DateTime.now();
    state.addExercise(date, state.exercises.firstWhere((e) => !e.isCardio));
    final session = state.sessions[state.dateOnly(date)]!;

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
    expect(find.byKey(const ValueKey('workout-elapsed')), findsNothing);

    // 1시간 23분 전에 시작한 것으로 도장을 찍는다 — 표시 형식이 검증 대상이다.
    final set = session.exercises.first.sets.first;
    await state.toggleSet(set, startRest: false);
    session.startedAt = DateTime.now().subtract(
      const Duration(hours: 1, minutes: 23),
    );
    state.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workout-elapsed')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^1시간 2[34]분$')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
  });
}
