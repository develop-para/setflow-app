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

    test('adds the same exercise repeatedly with prior-record defaults', () {
      final state = AppState();
      final template = state.exercises.first;
      final historyDate = DateTime(2030, 1, 1);
      final targetDate = DateTime(2030, 1, 2);
      state.addExercise(historyDate, template);
      for (final set in state.sessionFor(historyDate).exercises.single.sets) {
        state.updateSet(set, weight: 42.5, reps: 8);
        state.toggleSet(set, startRest: false);
      }

      state.addExercise(targetDate, template);
      state.addExercise(targetDate, template);

      final repeated = state.sessionFor(targetDate).exercises;
      expect(repeated, hasLength(2));
      expect(repeated.map((exercise) => exercise.id).toSet(), hasLength(2));
      expect(
        repeated.expand((exercise) => exercise.sets).map((set) => set.weight),
        everyElement(42.5),
      );
      expect(
        repeated.expand((exercise) => exercise.sets).map((set) => set.reps),
        everyElement(8),
      );
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

    test('does not grant administrator access from a local role switch', () {
      final state = AppState();

      state.chooseRole(UserRole.admin);

      expect(state.isAdmin, isFalse);
      expect(state.role, isNot(UserRole.admin));
      state.dispose();
    });
  });
}
