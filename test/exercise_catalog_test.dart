import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_repository.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/exercise_catalog_repository.dart';
import 'package:setflow/data/supabase_exercise_catalog_repository.dart';
import 'package:setflow/theme/icons.dart';

void main() {
  test(
    'database catalog row keeps equipment and multilingual search facets',
    () {
      final exercise = exerciseTemplateFromCatalogRow({
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'name': 'Incline Dumbbell Press',
        'name_en': 'Incline Dumbbell Press',
        'target_muscle': '가슴',
        'equipment': '덤벨',
        'equipment_key': 'dumbbell',
        'input_type': 'weight_reps',
        'aliases': ['인클라인', '프레스', '흉근'],
        'difficulty': 'beginner',
        'category': 'strength',
        'source_name': 'free-exercise-db',
      });

      expect(exercise.resolvedEquipmentKey, 'dumbbell');
      expect(exercise.resolvedEquipmentName, '덤벨');
      expect(exercise.matchesCatalogQuery('가슴 덤벨'), isTrue);
      expect(exercise.matchesCatalogQuery('incline press'), isTrue);
      expect(exercise.matchesCatalogQuery('흉근 프레스'), isTrue);
      expect(exercise.matchesCatalogQuery('인클라인프레스'), isTrue);
      expect(exercise.matchesCatalogQuery('케이블'), isFalse);
    },
  );

  test('confirmed database duplicate keeps the original domain ID', () {
    final exercise = exerciseTemplateFromCatalogRow({
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'source_id': 'Barbell_Bench_Press_-_Medium_Grip',
      'name': 'Barbell Bench Press - Medium Grip',
      'name_en': 'Barbell Bench Press - Medium Grip',
      'target_muscle': '가슴',
      'equipment': '바벨',
      'equipment_key': 'barbell',
      'input_type': 'weight_reps',
      'aliases': ['가슴', '바벨', '프레스'],
      'source_name': 'free-exercise-db',
    });

    expect(exercise.id, 'bench');
    expect(exercise.name, '바벨 벤치 프레스');
    expect(exercise.databaseId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(
      exercise.referencesId('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
      isTrue,
    );
    expect(exercise.matchesCatalogQuery('barbell press'), isTrue);
  });

  test('crosswalk keeps a more specific built-in equipment facet', () {
    final exercise = exerciseTemplateFromCatalogRow({
      'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'source_id': 'Running_Treadmill',
      'name': 'Running, Treadmill',
      'name_en': 'Running, Treadmill',
      'target_muscle': '유산소',
      'equipment': '머신',
      'equipment_key': 'machine',
      'input_type': 'distance',
      'aliases': ['유산소', '러닝'],
      'source_name': 'free-exercise-db',
    });

    expect(exercise.id, 'run');
    expect(exercise.resolvedEquipmentKey, 'treadmill');
    expect(exercise.resolvedEquipmentName, '트레드밀');

    final rowing = exerciseTemplateFromCatalogRow({
      'id': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'source_id': 'Rowing_Stationary',
      'name': 'Rowing, Stationary',
      'name_en': 'Rowing, Stationary',
      'target_muscle': '유산소',
      'equipment': '머신',
      'equipment_key': 'machine',
      'input_type': 'distance',
      'aliases': ['유산소', '로잉'],
      'source_name': 'free-exercise-db',
    });
    expect(rowing.resolvedEquipmentKey, 'rowing_machine');
    expect(rowing.resolvedEquipmentName, '로잉 머신');
  });

  test(
    'cached database exercises are selectable after initialization',
    () async {
      final remote = exerciseTemplateFromCatalogRow({
        'id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'name': 'Cable Iron Cross',
        'name_en': 'Cable Iron Cross',
        'target_muscle': '가슴',
        'equipment': '케이블',
        'equipment_key': 'cable',
        'input_type': 'weight_reps',
        'aliases': ['케이블', '가슴'],
      });
      final state = AppState(
        exerciseCatalogRepository: _MemoryExerciseCatalogRepository([remote]),
      );
      addTearDown(state.dispose);

      await state.initialize();

      expect(state.exercises.any((item) => item.id == remote.id), isTrue);
      expect(state.exercises.length, exerciseCatalog.length + 1);
    },
  );

  test('inline template preserves a database workout without its cache', () {
    final date = DateTime(2026, 8, 31);
    const remote = ExerciseTemplate(
      id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      name: 'Kettlebell Turkish Get-Up',
      nameEnglish: 'Kettlebell Turkish Get-Up',
      muscle: '복근',
      icon: SetflowIcons.record,
      equipmentKey: 'kettlebell',
      equipmentName: '케틀벨',
      aliases: ['터키시 겟업', '코어'],
      sourceName: 'free-exercise-db',
    );
    final snapshot = AppSnapshot(
      role: UserRole.member,
      isDarkMode: false,
      weightUnit: 'kg',
      restDefaultSeconds: 90,
      sessions: {
        date: WorkoutSession(
          date: date,
          exercises: [
            WorkoutExercise(
              id: 'remote-entry',
              template: remote,
              sets: [WorkoutSetEntry(number: 1, weight: 16, reps: 5)],
            ),
          ],
        ),
      },
      routines: const [],
    );

    final decoded = AppSnapshotCodec.decode(
      AppSnapshotCodec.encode(snapshot),
      exerciseCatalog,
    )!;
    final restored = decoded.sessions[date]!.exercises.single.template;

    expect(restored.id, remote.id);
    expect(restored.name, remote.name);
    expect(restored.resolvedEquipmentName, '케틀벨');
    expect(restored.sourceName, 'free-exercise-db');
  });

  test('inline crosswalk metadata wins over a cold built-in template', () {
    final date = DateTime(2026, 9, 1);
    final remote = exerciseTemplateFromCatalogRow({
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'source_id': 'Barbell_Bench_Press_-_Medium_Grip',
      'name': 'Barbell Bench Press - Medium Grip',
      'name_en': 'Barbell Bench Press - Medium Grip',
      'target_muscle': '가슴',
      'equipment': '바벨',
      'equipment_key': 'barbell',
      'input_type': 'weight_reps',
      'aliases': ['가슴', '바벨', '프레스'],
      'source_name': 'free-exercise-db',
    });
    final snapshot = _snapshotWithExercise(date, remote);

    final restored = AppSnapshotCodec.decode(
      AppSnapshotCodec.encode(snapshot),
      exerciseCatalog,
    )!.sessions[date]!.exercises.single.template;

    expect(restored.id, 'bench');
    expect(restored.databaseId, remote.databaseId);
    expect(restored.nameEnglish, 'Barbell Bench Press - Medium Grip');
  });

  test('bundled workouts do not repeat inline template metadata', () {
    final date = DateTime(2026, 9, 2);
    final root =
        jsonDecode(
              AppSnapshotCodec.encode(
                _snapshotWithExercise(date, exerciseCatalog[0]),
              ),
            )
            as Map<String, dynamic>;
    final session = (root['sessions'] as List).single as Map<String, dynamic>;
    final exercise =
        (session['exercises'] as List).single as Map<String, dynamic>;

    expect(exercise.containsKey('template'), isFalse);
  });

  test(
    'late catalog refresh rebinds existing records and removes duplicates',
    () async {
      final repository = _DelayedExerciseCatalogRepository();
      final state = AppState(exerciseCatalogRepository: repository);
      addTearDown(state.dispose);
      await state.initialize();
      final date = DateTime(2026, 9, 3);
      state.addExercise(date, exerciseCatalog.first);
      final remote = exerciseTemplateFromCatalogRow({
        'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'source_id': 'Barbell_Bench_Press_-_Medium_Grip',
        'name': 'Barbell Bench Press - Medium Grip',
        'name_en': 'Barbell Bench Press - Medium Grip',
        'target_muscle': '가슴',
        'equipment': '바벨',
        'equipment_key': 'barbell',
        'input_type': 'weight_reps',
        'aliases': ['가슴', '바벨', '프레스'],
        'source_name': 'free-exercise-db',
      });

      repository.complete([remote]);
      await repository.finished;
      for (
        var attempt = 0;
        attempt < 10 && state.exerciseCatalogLoading;
        attempt++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(state.exercises.length, exerciseCatalog.length);
      expect(
        state.sessions[date]!.exercises.single.template.databaseId,
        remote.databaseId,
      );
    },
  );
}

AppSnapshot _snapshotWithExercise(DateTime date, ExerciseTemplate exercise) =>
    AppSnapshot(
      role: UserRole.member,
      isDarkMode: false,
      weightUnit: 'kg',
      restDefaultSeconds: 90,
      sessions: {
        date: WorkoutSession(
          date: date,
          exercises: [
            WorkoutExercise(
              id: 'entry-${exercise.id}',
              template: exercise,
              sets: [WorkoutSetEntry(number: 1, weight: 20, reps: 10)],
            ),
          ],
        ),
      },
      routines: const [],
    );

class _MemoryExerciseCatalogRepository implements ExerciseCatalogRepository {
  const _MemoryExerciseCatalogRepository(this.catalog);

  final List<ExerciseTemplate> catalog;

  @override
  Future<List<ExerciseTemplate>> loadCached() async => catalog;

  @override
  Future<List<ExerciseTemplate>> refreshCatalog() async => catalog;
}

class _DelayedExerciseCatalogRepository implements ExerciseCatalogRepository {
  final _refresh = Completer<List<ExerciseTemplate>>();
  final _finished = Completer<void>();

  Future<void> get finished => _finished.future;

  void complete(List<ExerciseTemplate> catalog) => _refresh.complete(catalog);

  @override
  Future<List<ExerciseTemplate>> loadCached() async => const [];

  @override
  Future<List<ExerciseTemplate>> refreshCatalog() async {
    final catalog = await _refresh.future;
    _finished.complete();
    return catalog;
  }
}
