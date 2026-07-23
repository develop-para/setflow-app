import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';

void main() {
  group('AppSnapshotCodec', () {
    test('round-trips preferences, workouts, and routines', () {
      const catalog = [
        ExerciseTemplate(
          id: 'squat',
          name: '스쿼트',
          muscle: '하체',
          icon: Icons.accessibility_new,
        ),
      ];
      final date = DateTime(2026, 7, 23);
      final snapshot = AppSnapshot(
        role: UserRole.member,
        isDarkMode: true,
        weightUnit: 'lb',
        restDefaultSeconds: 120,
        sessions: {
          date: WorkoutSession(
            date: date,
            exercises: [
              WorkoutExercise(
                id: 'workout_1',
                template: catalog.first,
                sets: [
                  WorkoutSetEntry(
                    number: 1,
                    weight: 80,
                    reps: 8,
                    completed: true,
                  ),
                ],
              ),
            ],
          ),
        },
        routines: [
          RoutineData(
            id: 'routine_1',
            name: '하체 루틴',
            description: '스쿼트 중심',
            color: const Color(0xFF10CEBD),
            exercises: catalog,
          ),
        ],
      );

      final encoded = AppSnapshotCodec.encode(snapshot);
      final decoded = AppSnapshotCodec.decode(encoded, catalog)!;

      expect(decoded.role, UserRole.member);
      expect(decoded.isDarkMode, isTrue);
      expect(decoded.weightUnit, 'lb');
      expect(decoded.restDefaultSeconds, 120);
      expect(
        decoded.sessions[date]!.exercises.first.sets.first.completed,
        isTrue,
      );
      expect(decoded.routines.single.name, '하체 루틴');
      expect(decoded.routines.single.exercises.single.id, 'squat');
    });

    test('returns null for an unsupported schema', () {
      expect(
        AppSnapshotCodec.decode('{"schemaVersion":999}', const []),
        isNull,
      );
    });
  });

  test('AppState persists user changes through the repository', () async {
    final repository = MemoryAppRepository();
    final state = AppState(repository: repository);
    await state.initialize();

    state.chooseRole(UserRole.trainer);
    state.toggleTheme();
    state.setWeightUnit('lb');
    state.setRestDefaultSeconds(120);
    state.createRoutine('저장 테스트', '앱 재시작 후에도 유지');
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final restored = AppState(repository: repository);
    await restored.initialize();

    expect(restored.role, UserRole.trainer);
    expect(restored.isDarkMode, isTrue);
    expect(restored.weightUnit, 'lb');
    expect(restored.restDefaultSeconds, 120);
    expect(restored.routines.any((item) => item.name == '저장 테스트'), isTrue);

    state.dispose();
    restored.dispose();
  });
}
