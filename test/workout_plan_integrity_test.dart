import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/exercise_catalog.dart';

final _day = DateTime(2026, 10, 14);

ExerciseTemplate _template(String id) =>
    exerciseCatalog.firstWhere((exercise) => exercise.id == id);

void main() {
  test('record copies preserve completion and observations independently', () {
    final original = WorkoutSetEntry(
      number: 2,
      weight: 72.5,
      reps: 8,
      completed: true,
      type: '드랍',
      restSeconds: 120,
      durationSeconds: 600,
      distanceKm: 2.5,
      intensityRpe: 8,
      rir: 0,
    );
    final copied = original.copy();

    expect(copied, isNot(same(original)));
    expect(copied.completed, isTrue);
    expect(copied.rir, 0);
    expect(copied.intensityRpe, 8);
    expect(copied.number, 2);
    expect(copied.weight, 72.5);
    expect(copied.reps, 8);
    expect(copied.type, '드랍');
    expect(copied.restSeconds, 120);
    expect(copied.durationSeconds, 600);
    expect(copied.distanceKm, 2.5);
    copied.weight = 60;
    copied.rir = 3;
    copied.completed = false;
    expect(original.weight, 72.5);
    expect(original.rir, 0);
    expect(original.completed, isTrue);
  });

  test('copying a day creates plans without inventing observed effort', () {
    final state = AppState();
    addTearDown(state.dispose);
    final sourceSet = WorkoutSetEntry(
      number: 1,
      weight: 72.5,
      reps: 8,
      completed: true,
      restSeconds: 120,
      rir: 0,
    );
    final cardioSet = WorkoutSetEntry(
      number: 1,
      weight: 0,
      reps: 0,
      completed: true,
      restSeconds: 0,
      durationSeconds: 1200,
      distanceKm: 3,
      intensityRpe: 8,
    );
    state.sessions[_day] = WorkoutSession(
      date: _day,
      exercises: [
        WorkoutExercise(
          id: 'source-bench',
          template: _template('bench'),
          sets: [sourceSet],
        ),
        WorkoutExercise(
          id: 'source-cardio',
          template: exerciseCatalog.firstWhere((exercise) => exercise.isCardio),
          sets: [cardioSet],
        ),
      ],
    );
    final tomorrow = _day.add(const Duration(days: 1));
    final existing = WorkoutSetEntry(
      number: 1,
      weight: 40,
      reps: 10,
      completed: true,
      rir: 2,
    );
    state.sessions[tomorrow] = WorkoutSession(
      date: tomorrow,
      exercises: [
        WorkoutExercise(
          id: 'existing-curl',
          template: _template('curl'),
          sets: [existing],
        ),
      ],
    );

    expect(state.copySession(_day, tomorrow), 2);
    final planned = state.sessions[tomorrow]!.exercises[1];
    final plannedCardio = state.sessions[tomorrow]!.exercises[2];
    expect(planned.id, isNot('source-bench'));
    expect(planned.sets.single.completed, isFalse);
    expect(planned.sets.single.rir, isNull);
    expect(planned.sets.single.weight, 72.5);
    expect(planned.sets.single.reps, 8);
    expect(planned.sets.single.restSeconds, 120);
    expect(plannedCardio.sets.single.completed, isFalse);
    expect(plannedCardio.sets.single.intensityRpe, 0);
    expect(plannedCardio.sets.single.durationSeconds, 1200);
    expect(plannedCardio.sets.single.distanceKm, 3);
    expect(sourceSet.completed, isTrue);
    expect(sourceSet.rir, 0);
    expect(cardioSet.completed, isTrue);
    expect(cardioSet.intensityRpe, 8);
    expect(existing.completed, isTrue);
    expect(existing.rir, 2);
    planned.sets.single.weight = 65;
    expect(sourceSet.weight, 72.5);
    expect(state.copySession(_day, tomorrow), 0);
  });

  test(
    'record exercise copy preserves coaching provenance and observations',
    () {
      final original = WorkoutExercise(
        id: 'record-id',
        template: _template('bench'),
        coachingWorkoutId: 'coaching-id',
        coachingAuthor: '담당 트레이너',
        sets: [
          WorkoutSetEntry(
            number: 1,
            weight: 70,
            reps: 8,
            completed: true,
            rir: 2,
          ),
        ],
      );
      final record = original.copy();
      final plan = original.copy(asPlan: true);

      expect(record.id, original.id);
      expect(record.coachingWorkoutId, 'coaching-id');
      expect(record.coachingAuthor, '담당 트레이너');
      expect(record.sets, isNot(same(original.sets)));
      expect(record.sets.single, isNot(same(original.sets.single)));
      expect(record.sets.single.completed, isTrue);
      expect(record.sets.single.rir, 2);
      expect(plan.id, isNot(original.id));
      expect(plan.coachingWorkoutId, isNull);
      expect(plan.coachingAuthor, isNull);
      expect(plan.sets.single.completed, isFalse);
      expect(plan.sets.single.rir, isNull);
      expect(plan.sets.single.weight, 70);
    },
  );

  test('adding a set after deleting all sets does not invent a load', () {
    final state = AppState();
    addTearDown(state.dispose);
    final original = WorkoutSetEntry(number: 1, weight: 85, reps: 5);
    final exercise = WorkoutExercise(
      id: 'bench',
      template: _template('bench'),
      sets: [original],
    );

    state.removeSet(exercise, original);
    state.addSet(exercise);

    expect(exercise.sets.single.weight, 0);
    expect(exercise.sets.single.number, 1);
    expect(exercise.sets.single.completed, isFalse);
    expect(exercise.sets.single.rir, isNull);
    state.updateSet(exercise.sets.single, weight: 72.5, reps: 8, rir: 2);
    state.addSet(exercise);
    expect(exercise.sets.last.weight, 72.5);
    expect(exercise.sets.last.reps, 8);
    expect(exercise.sets.last.completed, isFalse);
    expect(exercise.sets.last.rir, isNull);
  });

  test('routine materialization creates plans with no observed RIR', () {
    final state = AppState();
    addTearDown(state.dispose);
    final template = _template('bench');
    final routine = RoutineData(
      id: 'explicit-routine',
      name: '직접 정한 루틴',
      description: '',
      color: RoutineData.defaultColor,
      exercises: [template],
      setPlans: {
        template.id: const [
          RoutineSetPlan(number: 1, weight: 72.5, reps: 8, restSeconds: 150),
        ],
      },
    );

    expect(state.applyRoutine(routine, _day), 1);
    final set = state.sessions[_day]!.exercises.single.sets.single;
    expect(set.completed, isFalse);
    expect(set.rir, isNull);
    expect(set.weight, 72.5);
    expect(set.reps, 8);
    expect(set.restSeconds, 150);
  });

  test(
    'new routine plans leave unknown weights for the user to select',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      final existingRoutines = List<RoutineData>.of(state.routines);
      final template = _template('bench');
      final routine = RoutineData(
        id: 'new-routine-plan',
        name: '새 루틴',
        description: '',
        color: RoutineData.defaultColor,
        exercises: [template],
      );
      state.routines.add(routine);

      expect(
        await state.updateRoutine(
          routine: routine,
          name: routine.name,
          description: '',
          exercises: [template],
        ),
        isTrue,
      );
      final updated = state.routines.singleWhere(
        (item) => item.id == routine.id,
      );
      final plans = updated.setsFor(template);
      expect(plans, hasLength(3));
      expect(plans.map((set) => set.weight), everyElement(0));
      expect(plans.map((set) => set.reps), everyElement(10));
      expect(state.routines, containsAll(existingRoutines));
      expect(state.routines, hasLength(existingRoutines.length + 1));
      expect(routine.setPlans, isEmpty);
      state.applyRoutine(updated, _day);
      final sets = state.sessions[_day]!.exercises.single.sets;
      expect(sets.map((set) => set.weight), everyElement(0));
      expect(sets.map((set) => set.completed), everyElement(isFalse));
      expect(sets.map((set) => set.rir), everyElement(isNull));
    },
  );

  test('routine defaults honor user choices and timed movements', () async {
    final state = AppState();
    addTearDown(state.dispose);
    final existingRoutines = List<RoutineData>.of(state.routines);
    state.setDefaultSetPlan(sets: 4, reps: 12);
    state.setRestDefaultSeconds(150);
    final bench = _template('bench');
    final curl = _template('curl');
    final pushup = _template('pushup');
    final plank = _template('plank');
    final routine = RoutineData(
      id: 'user-routine-plan',
      name: '사용자 계획',
      description: '',
      color: RoutineData.defaultColor,
      exercises: [bench],
      setPlans: {
        bench.id: const [RoutineSetPlan(number: 1, weight: 75, reps: 7)],
      },
    );
    state.routines.add(routine);

    expect(
      await state.updateRoutine(
        routine: routine,
        name: routine.name,
        description: '',
        exercises: [bench, curl, pushup, plank],
      ),
      isTrue,
    );
    final updated = state.routines.singleWhere((item) => item.id == routine.id);
    expect(state.routines, containsAll(existingRoutines));
    expect(state.routines, hasLength(existingRoutines.length + 1));
    expect(routine.exercises, [bench]);
    expect(routine.setPlans.keys, [bench.id]);
    expect(routine.setsFor(bench).single.weight, 75);
    expect(routine.setsFor(bench).single.reps, 7);
    expect(updated.setsFor(bench).single.weight, 75);
    expect(updated.setsFor(bench).single.reps, 7);
    for (final template in [curl, pushup, plank]) {
      final plans = updated.setsFor(template);
      expect(plans, hasLength(4));
      expect(plans.map((set) => set.weight), everyElement(0));
      expect(plans.map((set) => set.restSeconds), everyElement(150));
      expect(
        plans.map((set) => set.reps),
        everyElement(template.isDurationHold ? 0 : 12),
      );
      expect(
        plans.map((set) => set.durationSeconds),
        everyElement(template.isDurationHold ? 60 : 0),
      );
    }
  });
}
