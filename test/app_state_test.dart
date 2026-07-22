import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';

void main() {
  group('AppState workout flow', () {
    test('adds an exercise and starts rest timer on completion', () {
      final state = AppState();
      final date = DateTime(2030, 1, 1);

      state.addExercise(date, state.exercises.first);
      final session = state.sessionFor(date);

      expect(session.exercises, hasLength(1));
      expect(session.totalSets, 3);

      state.toggleSet(session.exercises.first.sets.first);

      expect(session.completedSets, 1);
      expect(state.restRemaining, state.restDefaultSeconds);
      state.dispose();
    });

    test('copies a workout with completion reset', () {
      final state = AppState();
      final sourceDate = DateTime(2030, 1, 2);
      final targetDate = DateTime(2030, 1, 3);

      state.addExercise(sourceDate, state.exercises.first);
      state.toggleSet(state.sessionFor(sourceDate).exercises.first.sets.first);
      state.copySession(sourceDate, targetDate);

      final copied = state.sessionFor(targetDate);
      expect(copied.exercises, hasLength(1));
      expect(copied.completedSets, 0);
      state.dispose();
    });

    test('imports an expert routine only once', () {
      final state = AppState();
      final routine = state.marketRoutines.first;
      final before = state.routines.length;

      state.importRoutine(routine);
      state.importRoutine(routine);

      expect(state.routines.length, before + 1);
      state.dispose();
    });
  });
}
