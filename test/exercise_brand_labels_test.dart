import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/app_snapshot_codec.dart';
import 'package:setflow/data/business_repository.dart';
import 'package:setflow/data/coaching_management_repository.dart';
import 'package:setflow/data/machine_exercise_catalog.dart';
import 'package:setflow/data/routine_catalog_repository.dart';
import 'package:setflow/domain/exercise_display_name.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';

void main() {
  test(
    'all machine labels omit only the brand and remain separately searchable',
    () {
      expect(machineCatalog, hasLength(187));
      final ids = <String>{};
      final labels = <String>{};
      for (final machine in machineCatalog) {
        final exercise = machine.exercise;
        expect(exercise.name, '${machine.line} ${machine.name}');
        expect(
          exercise.matchesCatalogQuery('${machine.brand} ${machine.model}'),
          isTrue,
        );
        expect(exercise.resolvedEquipmentKey, 'machine');
        expect(exercise.id, 'machine_${machine.id}');
        expect(exercise.sourceId, machine.id);
        expect(exercise.nameEnglish, machine.englishName);
        ids.add(exercise.id);
        labels.add(exercise.name);
      }
      expect(ids, hasLength(187));
      expect(labels, hasLength(187));
    },
  );

  test(
    'historical brand spelling is removed without changing ordinary movement names',
    () {
      const oldLabels = {
        '테크노짐 퓨어 리니어 레그 프레스': '퓨어 리니어 레그 프레스',
        'Technogym Pure Chest Press': 'Pure Chest Press',
        'Technogym - Pure Chest Press': 'Pure Chest Press',
        '테크노짐 : 퓨어 체스트 프레스': '퓨어 체스트 프레스',
        '파나타 프리웨이트 스페셜 인클라인 체스트 프레스': '프리웨이트 스페셜 인클라인 체스트 프레스',
        '파나따 프리웨이트 스페셜 로우': '프리웨이트 스페셜 로우',
        'PANATTA Freeweight Row': 'Freeweight Row',
        '뉴텍 어드벤스 로우': '어드벤스 로우',
        'newtech Advance Row': 'Advance Row',
        'New Tech: Advance Row': 'Advance Row',
        '해머스트렝스 플레이트 로드 벨트 스쿼트': '플레이트 로드 벨트 스쿼트',
        '해머스트랭스 플레이트 로드 로우': '플레이트 로드 로우',
        '해머스랭스 플레이트 로드 하이 로우': '플레이트 로드 하이 로우',
        'Hammer Strength Plate Loaded Bench Press': 'Plate Loaded Bench Press',
      };
      for (final entry in oldLabels.entries) {
        expect(exerciseDisplayName(entry.key), entry.value);
      }
      for (final name in [
        '해머 컬',
        '해머 그립 풀업',
        '바벨 벤치 프레스',
        '덤벨 로우',
        '우리 헬스장 뉴텍 로우',
        'Newtechnical Press',
        '테크노짐핏 프레스',
        '뉴텍',
        '뉴텍 - ',
      ]) {
        expect(exerciseDisplayName(name), name);
      }
    },
  );

  test(
    'old inline workout and routine names update offline without losing any recorded values',
    () {
      final session = _oldSession(completed: true);
      final exercise = session.exercises.single;
      expect(exercise.template.name, '어드벤스 로우');
      expect(exercise.template.matchesCatalogQuery('뉴텍 로우'), isTrue);
      expect(exercise.id, 'recorded-row');
      expect(exercise.template.id, 'machine_old_row');
      expect(
        exercise.template.databaseId,
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      );
      expect(exercise.template.resolvedEquipmentKey, 'machine');
      expect(exercise.sets.single.weight, 77.5);
      expect(exercise.sets.single.reps, 8);
      expect(exercise.sets.single.restSeconds, 120);
      expect(exercise.sets.single.rir, 2);
      expect(exercise.sets.single.completed, isTrue);
      expect(session.volume, 620);
      expect(session.correctionVersions, {'row:1:weight': 'revision-2'});

      final state = AppState()..sessions[session.date] = session;
      addTearDown(state.dispose);
      final before = state.performanceFor(exercise.template)!;
      final roundTrip = AppSnapshotCodec.sessionFromJson(
        AppSnapshotCodec.sessionToJson(session),
        [],
      )!;
      state.sessions[roundTrip.date] = roundTrip;
      final after = state.performanceFor(roundTrip.exercises.single.template)!;
      expect(after.weightPr.set.weight, 77.5);
      expect(after.currentE1rm, before.currentE1rm);
      expect(roundTrip.exercises.single.template.id, exercise.template.id);
      expect(roundTrip.volume, session.volume);
      expect(roundTrip.exercises.single.template.storedName, '뉴텍 어드벤스 로우');
      expect(
        roundTrip.exercises.single.template.matchesCatalogQuery('뉴텍 로우'),
        isTrue,
      );
      final secondRoundTrip = AppSnapshotCodec.sessionFromJson(
        AppSnapshotCodec.sessionToJson(roundTrip),
        [],
      )!;
      expect(secondRoundTrip.exercises.single.template.name, '어드벤스 로우');
      expect(
        secondRoundTrip.exercises.single.template.matchesCatalogQuery('뉴텍 로우'),
        isTrue,
      );
      expect(secondRoundTrip.exercises.single.sets.single.weight, 77.5);

      final routine = AppSnapshotCodec.routineFromJson({
        'id': 'saved-routine',
        'name': '내 등 운동',
        'description': '',
        'color': SetflowNeutral.n800.toARGB32(),
        'exerciseIds': ['machine_old_row'],
        'exercises': [
          {
            ..._oldTemplate,
            'sets': [
              {'number': 1, 'weight': 65, 'reps': 10, 'restSeconds': 90},
            ],
          },
        ],
      }, [])!;
      expect(routine.exercises.single.name, '어드벤스 로우');
      expect(routine.exercises.single.id, 'machine_old_row');
      expect(routine.setsFor(routine.exercises.single).single.weight, 65);
      expect(routine.setsFor(routine.exercises.single).single.reps, 10);
    },
  );

  test(
    'server history, trainer routine and correction labels share the same cleanup',
    () {
      const workout = BusinessWorkoutExercise(
        id: 'server-exercise',
        baseExerciseId: 'base-exercise',
        name: '테크노짐 퓨어 로우 로우',
        targetMuscle: '등',
        orderIndex: 2,
        sets: [],
      );
      const routine = OwnedRoutineExercise(
        id: 'routine-exercise',
        routineId: 'routine',
        baseExerciseId: 'base-exercise',
        name: '해머스트렝스 플레이트 로드 벨트 스쿼트',
        targetMuscle: '하체',
        orderIndex: 1,
        sets: [],
      );
      final correction = WorkoutCorrection(
        id: 'correction',
        memberName: '민지',
        viewerRole: 'member',
        recordKey: 'personal:2026-10-01',
        exerciseId: 'recorded-row',
        correctionKey: 'row:1:weight',
        trainerName: '지훈',
        workoutTitle: '등 운동',
        date: DateTime(2026, 10, 1),
        exerciseName: '뉴텍 어드벤스 로우',
        setNumber: 1,
        metric: WorkoutMetric.weight,
        before: 70,
        after: 77.5,
        reason: '함께 확인한 중량',
        status: 'applied',
        canRespond: false,
      );
      expect(workout.name, '퓨어 로우 로우');
      expect(workout.id, 'server-exercise');
      expect(workout.baseExerciseId, 'base-exercise');
      expect(routine.name, '플레이트 로드 벨트 스쿼트');
      expect(routine.routineId, 'routine');
      expect(correction.exerciseName, '어드벤스 로우');
      expect(correction.exerciseId, 'recorded-row');
      expect(correction.after, 77.5);
      expect(correction.correctionKey, 'row:1:weight');
    },
  );

  test(
    'custom names reject duplicates with or without the manufacturer prefix',
    () async {
      final state = AppState();
      addTearDown(state.dispose);
      await state.initialize();
      final first = state.createCustomExercise(
        name: '뉴텍 개인 웨이티드 로우',
        muscle: '등',
      );
      expect(first, isNotNull);
      expect(first!.name, '개인 웨이티드 로우');
      expect(first.storedName, '뉴텍 개인 웨이티드 로우');
      expect(
        state.createCustomExercise(name: '뉴텍 개인 웨이티드 로우', muscle: '등'),
        isNull,
      );
      expect(
        state.createCustomExercise(name: '개인 웨이티드 로우', muscle: '등'),
        isNull,
      );
      expect(state.customExercises, hasLength(1));
    },
  );

  test(
    'old market and shared routine labels reuse machine history without a base ID',
    () async {
      final state = AppState(
        businessRepository: _RoutineBusinessRepository(),
        routineCatalogRepository: _CatalogRepository(),
        loadBusinessWithoutAuth: true,
      );
      addTearDown(state.dispose);
      await state.initialize();
      final machine = machineExerciseCatalog.firstWhere(
        (exercise) => exercise.id == _machineId,
      );
      final date = DateTime(2026, 10, 1);
      state.sessions[date] = WorkoutSession(
        date: date,
        exercises: [
          WorkoutExercise(
            id: 'recorded-machine',
            template: machine,
            sets: [
              WorkoutSetEntry(number: 1, weight: 75, reps: 8, completed: true),
            ],
          ),
        ],
      );
      final market = state.marketRoutines.single;
      final shared = state.routines.firstWhere(
        (routine) => routine.id == 'shared-routine',
      );
      for (final routine in [market, shared]) {
        expect(routine.exercises.single.id, _machineId);
        expect(routine.exercises.single.name, '어드벤스 시티드 로우');
        expect(
          state.performanceFor(routine.exercises.single)!.weightPr.set.weight,
          75,
        );
      }
      expect(
        await state.importMarketRoutine(market),
        RoutineImportResult.imported,
      );
      final imported = state.routines.firstWhere(
        (routine) => routine.id == 'imported-routine',
      );
      expect(imported.exercises.single.id, _machineId);
      expect(
        state.performanceFor(imported.exercises.single)!.weightPr.set.weight,
        75,
      );
      expect(imported.setsFor(imported.exercises.single).single.weight, 50);
    },
  );

  testWidgets(
    'recording an old offline workout shows the movement and keeps its set values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 900));
      final state = AppState();
      await state.initialize();
      final session = _oldSession();
      state.sessions[session.date] = session;
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: SetflowTheme.light,
            home: DailyWorkoutScreen(date: session.date),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('어드벤스 로우'), findsOneWidget);
      expect(find.textContaining('뉴텍'), findsNothing);
      expect(session.exercises.single.sets.single.weight, 77.5);
      expect(session.exercises.single.sets.single.reps, 8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );
}

const _oldTemplate = {
  'id': 'machine_old_row',
  'name': '뉴텍 어드벤스 로우',
  'muscle': '등',
  'equipmentKey': 'machine',
  'sourceName': 'manufacturer-catalog',
  'databaseId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
};

WorkoutSession _oldSession({bool completed = false}) =>
    AppSnapshotCodec.sessionFromJson({
      'date': '2026-10-01',
      'correctionVersions': {'row:1:weight': 'revision-2'},
      'exercises': [
        {
          'id': 'recorded-row',
          'templateId': 'machine_old_row',
          'template': _oldTemplate,
          'sets': [
            {
              'number': 1,
              'weight': 77.5,
              'reps': 8,
              'completed': completed,
              'restSeconds': 120,
              'rir': 2,
            },
          ],
        },
      ],
    }, [])!;

const _machineId = 'machine_newtech_advance_seated_row';
const _rawMachineName = '뉴텍 어드벤스 시티드 로우';

class _CatalogRepository implements RoutineCatalogRepository {
  @override
  Future<bool> hasActivePaidPlan() async => false;
  @override
  Future<void> updateAccessTier(
    String routineId,
    RoutineCatalogAccessTier accessTier,
  ) async {}
  @override
  Future<List<RoutineCatalogItem>> listPublished() async => [
    const RoutineCatalogItem(
      id: 'market-routine',
      coachingRoutineId: 'coaching-routine',
      title: '마켓 등 운동',
      description: '',
      authorName: '담당 코치',
      difficulty: '초급',
      accessTier: RoutineCatalogAccessTier.free,
      authorType: RoutineAuthorType.trainer,
      exercises: [
        RoutineCatalogExercise(
          id: 'market-exercise',
          name: _rawMachineName,
          targetMuscle: '등',
          orderIndex: 0,
          sets: [],
        ),
      ],
    ),
  ];
}

class _RoutineBusinessRepository extends Fake implements BusinessRepository {
  static const access = BusinessAccess(
    userId: 'member',
    accountRole: UserRole.member,
    resolvedRole: UserRole.member,
    availableRoles: {UserRole.member},
  );
  @override
  Future<BusinessAccess> loadAccess() async => access;
  @override
  Future<BusinessWorkspaceData> loadWorkspace(UserRole role) async =>
      const BusinessWorkspaceData(
        role: UserRole.member,
        access: access,
        dashboardStats: BusinessDashboardMetrics(),
      );
  @override
  Future<List<PublicTrainer>> listPublicTrainers() async => [];
  @override
  Future<List<BusinessConsultation>> listMyConsultations() async => [];
  @override
  Future<List<BusinessCoachingSchedule>> listCoachingSchedules({
    DateTime? from,
    DateTime? to,
  }) async => [];
  @override
  Future<List<RoutineShareRecord>> listIncomingRoutineShares() async => [];
  @override
  Future<List<RoutineShareRecord>> listOutgoingRoutineShares({
    String? routineId,
  }) async => [];
  @override
  Future<MemberSharingPreferences> loadMySharingPreferences() async =>
      const MemberSharingPreferences(
        shareBodyData: false,
        shareWorkoutRecords: false,
        marketing: false,
      );
  @override
  Future<List<PersonalRoutineRecord>> listPersonalRoutines() async => [
    _record('shared-routine'),
  ];
  @override
  Future<PersonalRoutineRecord> importMarketRoutine(
    String marketRoutineId, {
    String? requestId,
  }) async => _record('imported-routine');

  PersonalRoutineRecord _record(String id) => PersonalRoutineRecord(
    id: id,
    ownerUserId: 'member',
    name: '전문가 공유 등 운동',
    sourceCoachingRoutineId: 'coaching-routine',
    exercises: [
      OwnedRoutineExercise(
        id: 'shared-exercise',
        routineId: id,
        name: _rawMachineName,
        targetMuscle: '등',
        orderIndex: 0,
        sets: const [
          OwnedRoutineSet(
            id: 'shared-set',
            exerciseId: 'shared-exercise',
            setNumber: 1,
            type: 'normal',
            targetWeight: 50,
            targetReps: 10,
            restSeconds: 90,
          ),
        ],
      ),
    ],
  );
}
