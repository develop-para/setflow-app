import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/bodyweight_exercise_catalog.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/exercise_catalog_repository.dart';
import 'package:setflow/data/local_equipment_repository.dart';
import 'package:setflow/data/machine_exercise_catalog.dart';
import 'package:setflow/data/offline_exercise_catalog.dart';
import 'package:setflow/domain/exercise_catalog_selection.dart';
import 'package:setflow/theme/icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recorded machine and bodyweight identities, set values and PR survive restart',
    () async {
      final store = MemoryAppRepository();
      final state = AppState(repository: store);
      addTearDown(state.dispose);
      await state.initialize();
      final machine = machineExerciseCatalog.firstWhere(
        (exercise) => exercise.name.startsWith('온힘 '),
      );
      final bodyweight = bodyweightExerciseCatalog.firstWhere(
        (exercise) => exercise.storedName == '맨몸 점프 스쿼트',
      );
      final date = DateTime(2026, 10, 20);

      // These are existing records made with the previous catalog labels.
      state.addExercise(date, machine);
      state.addExercise(date, bodyweight);
      final originalEntries = state.sessions[date]!.exercises;
      final machineSet = originalEntries.first.sets.first;
      state.updateSet(
        machineSet,
        weight: 77.5,
        reps: 8,
        restSeconds: 120,
        rir: 2,
      );
      await state.toggleSet(machineSet, startRest: false);
      final bodyweightSet = originalEntries.last.sets.first;
      state.updateSet(bodyweightSet, weight: 0, reps: 12, restSeconds: 60);
      await state.toggleSet(bodyweightSet, startRest: false);
      final originalPr = state.performanceFor(machine)!;
      await state.flushPersistence();

      final restarted = AppState(repository: _reopenedStore(store));
      addTearDown(restarted.dispose);
      await restarted.initialize();
      final restored = restarted.sessions[date]!;
      expect(
        restored.exercises.map((entry) => entry.id),
        originalEntries.map((entry) => entry.id),
      );
      expect(restored.exercises.map((entry) => entry.template.id), [
        machine.id,
        bodyweight.id,
      ]);
      expect(restored.exercises.first.template.storedName, machine.storedName);
      expect(
        restored.exercises.last.template.storedName,
        bodyweight.storedName,
      );
      expect(
        restored.exercises.last.template.measurement,
        ExerciseMeasurement.repsOnly,
      );
      expect(
        restored.exercises.last.template.resolvedEquipmentKey,
        'body_only',
      );
      final restoredSet = restored.exercises.first.sets.first;
      expect(restoredSet.weight, 77.5);
      expect(restoredSet.reps, 8);
      expect(restoredSet.restSeconds, 120);
      expect(restoredSet.rir, 2);
      expect(restoredSet.completed, isTrue);
      expect(restored.exercises.last.sets.first.reps, 12);
      expect(restored.exercises.last.sets.first.completed, isTrue);
      expect(restored.volume, 620);
      final restoredPr = restarted.performanceFor(machine)!;
      expect(restoredPr.weightPr.set.weight, originalPr.weightPr.set.weight);
      expect(restoredPr.currentE1rm, originalPr.currentE1rm);
      for (final original in [machine, bodyweight]) {
        final selectable = restarted.selectableExercises.singleWhere(
          (exercise) => exercise.id == original.id,
        );
        expect(selectable.name, original.name);
        expect(selectable.storedName, original.storedName);
      }
      expect(
        restarted.selectableExercises.any(
          (exercise) => exercise.id == machineExerciseCatalog.last.id,
        ),
        isFalse,
      );
    },
  );

  for (final custom in [
    (
      name: '온힘 내 등 운동',
      muscle: '등',
      measurement: ExerciseMeasurement.weightReps,
    ),
    (
      name: '맨몸 내 코어 운동',
      muscle: '복근',
      measurement: ExerciseMeasurement.duration,
    ),
  ]) {
    test(
      'custom label stays selectable after restart: ${custom.name}',
      () async {
        final store = MemoryAppRepository();
        final state = AppState(repository: store);
        addTearDown(state.dispose);
        await state.initialize();
        final original = state.createCustomExercise(
          name: custom.name,
          muscle: custom.muscle,
          measurement: custom.measurement,
        )!;
        await state.flushPersistence();

        final restarted = AppState(repository: _reopenedStore(store));
        addTearDown(restarted.dispose);
        await restarted.initialize();
        expect(restarted.sessions, isEmpty);
        final selectable = restarted.selectableExercises.singleWhere(
          (exercise) => exercise.id == original.id,
        );
        expect(selectable.name, original.name);
        expect(selectable.storedName, original.storedName);
        expect(selectable.measurement, original.measurement);
        expect(restarted.customExercises.single.id, original.id);
      },
    );
  }

  test(
    'device equipment keeps its chosen name and input mode without a record',
    () async {
      const item = LocalEquipment(
        id: 'equipment_saved_core',
        name: '맨몸 우리 짐 코어 운동',
        muscle: '복근',
        brand: '뉴텍',
        model: '온힘',
        measurement: ExerciseMeasurement.duration,
      );
      final store = MemoryAppRepository();
      final equipmentStore = MemoryLocalEquipmentRepository();
      final state = AppState(
        repository: store,
        localEquipmentRepository: equipmentStore,
      );
      addTearDown(state.dispose);
      await state.initialize();
      await state.saveLocalEquipment(item);
      await state.flushPersistence();

      final restarted = AppState(
        repository: _reopenedStore(store),
        localEquipmentRepository: equipmentStore,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      final selectable = restarted.selectableExercises.singleWhere(
        (exercise) => exercise.id == item.id,
      );
      expect(selectable.name, item.name);
      expect(selectable.storedName, item.name);
      expect(selectable.measurement, ExerciseMeasurement.duration);
      expect(restarted.localEquipment.single.model, item.model);
      expect(restarted.sessions, isEmpty);
    },
  );

  test(
    'saved routine keeps a machine available with its original set plan',
    () async {
      final machine = machineExerciseCatalog.first;
      final store = MemoryAppRepository(
        initialSnapshot: _snapshot(
          routines: [
            RoutineData(
              id: 'saved-machine-routine',
              name: '저장해 둔 하체 운동',
              description: '',
              color: RoutineData.defaultColor,
              exercises: [machine],
              setPlans: {
                machine.id: const [
                  RoutineSetPlan(
                    number: 1,
                    weight: 60,
                    reps: 10,
                    restSeconds: 120,
                  ),
                ],
              },
            ),
          ],
        ),
      );
      final state = AppState(repository: _reopenedStore(store));
      addTearDown(state.dispose);
      await state.initialize();

      final selectable = state.selectableExercises.singleWhere(
        (exercise) => exercise.id == machine.id,
      );
      expect(selectable.name, machine.name);
      expect(selectable.storedName, machine.storedName);
      expect(state.sessions, isEmpty);
      final routine = state.routines.single;
      expect(routine.exercises.single.id, machine.id);
      expect(routine.setsFor(selectable).single.weight, 60);
      expect(routine.setsFor(selectable).single.reps, 10);
      expect(routine.setsFor(selectable).single.restSeconds, 120);
    },
  );

  test(
    'late shared catalog metadata keeps recorded identity and input mode',
    () async {
      const original = ExerciseTemplate(
        id: 'shared-recorded-bodyweight',
        name: '맨몸 기록한 코어 운동',
        muscle: '복근',
        icon: SetflowIcons.record,
        measurement: ExerciseMeasurement.duration,
        equipmentKey: 'body_only',
        sourceName: 'free-exercise-db',
        sourceId: 'Recorded_Core_Hold',
      );
      const refreshed = ExerciseTemplate(
        id: 'shared-recorded-bodyweight',
        name: '맨몸 기록한 코어 운동',
        muscle: '복근',
        icon: SetflowIcons.record,
        measurement: ExerciseMeasurement.duration,
        equipmentKey: 'body_only',
        sourceName: 'free-exercise-db',
        sourceId: 'Recorded_Core_Hold',
        databaseId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        aliases: ['core hold', '코어 홀드'],
      );
      final repository = _DelayedCatalogRepository([original]);
      final state = AppState(exerciseCatalogRepository: repository);
      addTearDown(state.dispose);
      await state.initialize();
      final date = DateTime(2026, 10, 21);
      final selected = state.selectableExercises.singleWhere(
        (exercise) => exercise.id == original.id,
      );
      expect(selected.name, '기록한 코어 운동');
      expect(selected.storedName, original.storedName);
      state.addExercise(date, selected);
      final set = state.sessions[date]!.exercises.single.sets.first;
      state.updateSet(set, durationSeconds: 45);
      await state.toggleSet(set, startRest: false);
      final entryId = state.sessions[date]!.exercises.single.id;

      repository.complete([refreshed]);
      for (
        var attempt = 0;
        attempt < 10 && state.exerciseCatalogLoading;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.exerciseCatalogLoading, isFalse);
      final recorded = state.sessions[date]!.exercises.single;
      final selectable = state.selectableExercises.singleWhere(
        (exercise) => exercise.id == original.id,
      );
      expect(recorded.id, entryId);
      expect(recorded.template.id, original.id);
      expect(recorded.template.databaseId, refreshed.databaseId);
      expect(recorded.template.storedName, original.storedName);
      expect(recorded.template.name, '기록한 코어 운동');
      expect(recorded.template.measurement, ExerciseMeasurement.duration);
      expect(recorded.sets.first.durationSeconds, 45);
      expect(recorded.sets.first.completed, isTrue);
      expect(selectable.name, '기록한 코어 운동');
      expect(selectable.measurement, ExerciseMeasurement.duration);
    },
  );

  for (final olderRecordFirst in [true, false]) {
    test('a newly simplified label survives restart beside an older label '
        '(older record first: $olderRecordFirst)', () async {
      final store = MemoryAppRepository();
      final state = AppState(repository: store);
      addTearDown(state.dispose);
      await state.initialize();
      final original = bodyweightExerciseCatalog.firstWhere(
        (exercise) => exercise.storedName == '맨몸 점프 스쿼트',
      );
      final selected = state.selectableExercises.singleWhere(
        (exercise) => exercise.id == original.id,
      );
      expect(selected.name, '점프 스쿼트');
      expect(selected.storedName, original.storedName);
      final oldDate = DateTime(2026, 10, 19);
      final newDate = DateTime(2026, 10, 22);
      if (olderRecordFirst) {
        state.addExercise(oldDate, original);
        state.addExercise(newDate, selected);
      } else {
        state.addExercise(newDate, selected);
        state.addExercise(oldDate, original);
      }
      final set = state.sessions[newDate]!.exercises.single.sets.first;
      state.updateSet(set, reps: 15);
      await state.toggleSet(set, startRest: false);
      await state.flushPersistence();

      final restarted = AppState(repository: _reopenedStore(store));
      addTearDown(restarted.dispose);
      await restarted.initialize();
      final oldRecord = restarted.sessions[oldDate]!.exercises.single;
      final newRecord = restarted.sessions[newDate]!.exercises.single;
      expect(oldRecord.template.id, original.id);
      expect(oldRecord.template.name, original.name);
      expect(oldRecord.template.storedName, original.storedName);
      expect(newRecord.template.id, original.id);
      expect(newRecord.template.name, '점프 스쿼트');
      expect(newRecord.template.storedName, original.storedName);
      expect(newRecord.template.measurement, ExerciseMeasurement.repsOnly);
      expect(newRecord.template.resolvedEquipmentKey, 'body_only');
      expect(newRecord.sets.first.reps, 15);
      expect(newRecord.sets.first.completed, isTrue);
    });
  }

  test(
    'a historical inline machine stays selectable without catalog metadata',
    () async {
      const oldMachine = ExerciseTemplate(
        id: 'machine_discontinued_personal_row',
        name: '온힘 예전에 기록한 로우',
        muscle: '등',
        icon: SetflowIcons.record,
        equipmentKey: 'machine',
        sourceName: 'manufacturer-catalog',
      );
      final date = DateTime(2026, 9, 20);
      final store = MemoryAppRepository(
        initialSnapshot: _snapshot(
          sessions: {
            date: WorkoutSession(
              date: date,
              exercises: [
                WorkoutExercise(
                  id: 'old-inline-entry',
                  template: oldMachine,
                  sets: [
                    WorkoutSetEntry(
                      number: 1,
                      weight: 55,
                      reps: 9,
                      completed: true,
                    ),
                  ],
                ),
              ],
            ),
          },
        ),
      );
      final state = AppState(repository: _reopenedStore(store));
      addTearDown(state.dispose);
      await state.initialize();

      final selectable = state.selectableExercises.singleWhere(
        (exercise) => exercise.id == oldMachine.id,
      );
      expect(selectable.name, oldMachine.name);
      expect(selectable.storedName, oldMachine.storedName);
      expect(selectable.resolvedEquipmentKey, 'machine');
      expect(state.performanceFor(selectable)!.weightPr.set.weight, 55);
      expect(state.sessions[date]!.exercises.single.id, 'old-inline-entry');
    },
  );

  test('a saved bodyweight UUID resolves its simplified squat label', () {
    final weighted = exerciseCatalog.firstWhere(
      (exercise) => exercise.id == 'squat',
    );
    final bodyweight = exerciseCatalog.firstWhere(
      (exercise) => exercise.id == 'bodyweight_squat',
    );
    final resolved = resolveCatalogExerciseReference(
      catalog: [weighted, bodyweight],
      referenceId: '2f6b6525-2731-57e0-9b9f-75ff31b4b5e1',
      name: '스쿼트',
    );

    expect(resolved, isNotNull);
    expect(resolved!.id, bodyweight.id);
    expect(resolved.name, '스쿼트');
    expect(resolved.storedName, '맨몸 스쿼트');
    expect(resolved.displayNameOverride, '스쿼트');
    expect(resolved.measurement, ExerciseMeasurement.repsOnly);
    expect(resolved.resolvedEquipmentKey, 'body_only');
  });

  test(
    'an older squat name without an ID keeps the exact weighted exercise',
    () {
      final weighted = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'squat',
      );
      final bodyweight = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'bodyweight_squat',
      );
      final resolved = resolveCatalogExerciseReference(
        catalog: [weighted, bodyweight],
        name: '스쿼트',
      );

      expect(resolved, isNotNull);
      expect(resolved!.id, weighted.id);
      expect(resolved.measurement, ExerciseMeasurement.weightReps);
      expect(resolved.displayNameOverride, isNull);
    },
  );

  test(
    'new bodyweight selection exposes a stable server ID and exports its visible label',
    () {
      final selected = buildSelectableExerciseCatalog(
        catalog: exerciseCatalog,
      ).singleWhere((exercise) => exercise.id == 'bodyweight_squat');
      expect(
        selected.databaseReferenceId,
        '2f6b6525-2731-57e0-9b9f-75ff31b4b5e1',
      );
      expect(selected.name, '스쿼트');
      expect(selected.storedName, '맨몸 스쿼트');
      final date = DateTime(2026, 10, 23);
      final encoded =
          jsonDecode(
                AppSnapshotCodec.encode(
                  _snapshot(
                    sessions: {
                      date: WorkoutSession(
                        date: date,
                        exercises: [
                          WorkoutExercise(
                            id: 'new-bodyweight-squat',
                            template: selected,
                            sets: [
                              WorkoutSetEntry(number: 1, weight: 0, reps: 12),
                            ],
                          ),
                        ],
                      ),
                    },
                    routines: [
                      RoutineData(
                        id: 'new-bodyweight-routine',
                        name: '맨몸 하체 운동',
                        description: '',
                        color: RoutineData.defaultColor,
                        exercises: [selected],
                      ),
                    ],
                  ),
                ),
              )
              as Map<String, dynamic>;
      final session = (encoded['sessions'] as List).single as Map;
      final recorded = (session['exercises'] as List).single as Map;
      final inlineTemplate = recorded['template'] as Map;
      final routine = (encoded['routines'] as List).single as Map;
      final routineTemplate = (routine['exercises'] as List).single as Map;
      for (final template in [inlineTemplate, routineTemplate]) {
        // SQL and shared readers consume `name`; raw source labels live apart.
        expect(template['name'], '스쿼트');
        expect(template['storedName'], '맨몸 스쿼트');
        expect(template['displayNameOverride'], '스쿼트');
        expect(template['measurement'], 'repsOnly');
        expect(template['databaseId'], selected.databaseReferenceId);
      }

      final restored = AppSnapshotCodec.decode(
        jsonEncode(encoded),
        offlineExerciseCatalog,
      )!;
      for (final template in [
        restored.sessions[date]!.exercises.single.template,
        restored.routines.single.exercises.single,
      ]) {
        expect(template.id, selected.id);
        expect(template.name, '스쿼트');
        expect(template.storedName, '맨몸 스쿼트');
        expect(template.measurement, ExerciseMeasurement.repsOnly);
        expect(template.databaseReferenceId, selected.databaseReferenceId);
      }
    },
  );
}

MemoryAppRepository _reopenedStore(MemoryAppRepository store) =>
    MemoryAppRepository(
      initialSnapshot: AppSnapshotCodec.decode(
        AppSnapshotCodec.encode(store.snapshot!),
        offlineExerciseCatalog,
      ),
    );

AppSnapshot _snapshot({
  Map<DateTime, WorkoutSession> sessions = const {},
  List<RoutineData> routines = const [],
}) => AppSnapshot(
  role: UserRole.member,
  isDarkMode: false,
  weightUnit: 'kg',
  restDefaultSeconds: 90,
  sessions: sessions,
  routines: routines,
);

class _DelayedCatalogRepository implements ExerciseCatalogRepository {
  _DelayedCatalogRepository(this.cached);

  final List<ExerciseTemplate> cached;
  final _refresh = Completer<List<ExerciseTemplate>>();

  void complete(List<ExerciseTemplate> catalog) => _refresh.complete(catalog);

  @override
  Future<List<ExerciseTemplate>> loadCached() async => cached;

  @override
  Future<List<ExerciseTemplate>> refreshCatalog() => _refresh.future;
}
