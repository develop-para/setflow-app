import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/app_state.dart';
import 'package:setflow/data/exercise_catalog.dart';
import 'package:setflow/data/exercise_guides.dart';
import 'package:setflow/data/offline_exercise_catalog.dart';
import 'package:setflow/data/exercise_visuals.dart';
import 'package:setflow/screens/workout_screens.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/exercise_visual_viewer.dart';

/// "렛 풀 다운" is a name, not an instruction. A beginner reading it learns
/// nothing, so each exercise carries the steps for doing it.
void main() {
  final sharedRows =
      (jsonDecode(
                File(
                  'test/fixtures/exercise_visual_shared_rows.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['rows']
          as List;
  final sharedIds = sharedRows
      .map((row) => (row as Map<String, dynamic>)['id'] as String)
      .toSet();

  test('every guide belongs to an exercise that exists', () {
    final ids = {...exerciseCatalog.map((e) => e.id), ...sharedIds};
    final orphans = exerciseGuides.keys.where((id) => !ids.contains(id));
    expect(orphans, isEmpty, reason: '카탈로그에 없는 종목의 설명이 남아 있다 — 이름이 바뀌었을 것이다');
  });

  test('shared variant guides use their exact IDs alongside their visuals', () {
    expect(sharedIds, hasLength(8));
    for (final id in sharedIds) {
      expect(exerciseGuides, contains(id), reason: id);
      expect(exerciseVisuals, contains(id), reason: id);
    }
    expect(exerciseGuides, hasLength(88));
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

  test(
    'applied guides distinguish load positions and close exercise variants',
    () {
      final squat = exerciseGuides['squat']!.join(' ');
      expect(squat, contains('승모근'));
      expect(squat, contains('발바닥 전체'));
      expect(squat, isNot(contains('후삼각근')));
      final rdl = exerciseGuides['romanian_deadlift']!.join(' ');
      expect(rdl, contains('엉덩이를 뒤로'));
      expect(rdl, contains('서 있는 시작 자세로 돌아'));
      expect(rdl, isNot(contains('허리에서 굽')));
      final bridge = exerciseGuides['glute_bridge']!.join(' ');
      expect(bridge, contains('보호 패드'));
      expect(bridge, contains('골반 앞쪽'));
      expect(bridge, isNot(contains('바벨을 허리에')));
      expect(exerciseGuides['dips']!.join(' '), contains('가슴을 앞으로'));
      expect(
        exerciseGuides['dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe']!.join(' '),
        contains('상체는 세웁니다'),
      );
      expect(exerciseGuides['bench_dip']!.join(' '), contains('양발을 바닥'));
      expect(
        exerciseGuides['straight_arm_pulldown']!.join(' '),
        contains('어깨 관절'),
      );
      expect(exerciseGuides['seated_cable_row']!.join(' '), contains('직바'));
      expect(exerciseGuides['seated_cable_row']!.join(' '), contains('오버핸드'));
      expect(
        exerciseGuides['3c358477-aeb3-5d78-a6aa-91c9fb6c81db']!.join(' '),
        contains('언더핸드'),
      );
      expect(
        exerciseGuides['bff7dff4-2b99-5357-b365-f10e1187cbb3']!.join(' '),
        contains('제자리로 돌아'),
      );
      expect(
        exerciseGuides['d1ecb818-0235-5e2f-9113-39be506aa98a']!.join(' '),
        contains('뒤로 내딛'),
      );
      expect(
        exerciseGuides['0f177240-029b-543a-be27-2e8ed0526bca']!.join(' '),
        contains('뒤쪽 벤치'),
      );
      expect(
        exerciseGuides['823846f5-2414-58b7-911e-2d9397a28f49']!.join(' '),
        contains('발바닥 전체'),
      );
      expect(
        exerciseGuides['896189fc-30d9-51df-aa19-fd5ea7fa76eb']!.join(' '),
        contains('양 무릎 안쪽'),
      );
      expect(
        exerciseGuides['58acf002-4e6d-5e95-b252-cae16252cef8']!.join(' '),
        contains('억지로 잠그지'),
      );
    },
  );

  test('corrected guides preserve each exercise grip and direction', () {
    final hammer = exerciseGuides['hammer_curl']!.join(' ');
    expect(hammer, contains('중립 그립을 끝까지 유지'));
    expect(hammer, isNot(contains('손바닥이 앞을 향할 때까지')));
    final walking = exerciseGuides['walking_lunge']!.join(' ');
    expect(walking, contains('전진'));
    expect(walking, isNot(contains('뒤로 물러나')));
    expect(exerciseGuides['rear_delt_raise']!.join(' '), isNot(contains('바벨')));
    expect(exerciseGuides['goblet_squat']!.join(' '), contains('케틀벨'));
    expect(exerciseGuides['brisk_walk']!.join(' '), isNot(contains('스텝밀')));
    expect(exerciseGuides['run']!.join(' '), contains('트레드밀'));
    expect(exerciseGuides['run']!.join(' '), isNot(contains('제자리')));
    expect(exerciseGuides['leg_extension']!.join(' '), contains('정강이'));
    expect(exerciseGuides['leg_curl']!.join(' '), contains('종아리 뒤'));
    expect(exerciseGuides['hack_squat']!.join(' '), contains('양어깨'));
    expect(exerciseGuides['hack_squat']!.join(' '), contains('편안한 범위'));
    expect(exerciseGuides['jump_rope']!.join(' '), contains('손목으로 작은 원'));
    expect(exerciseGuides['jump_rope']!.join(' '), contains('발 앞부분'));
    expect(exerciseGuides['jump_rope']!.join(' '), isNot(contains('어깨너비')));
    for (final id in ['preacher_curl', 'skull_crusher']) {
      expect(exerciseGuides[id]!.join(' '), contains('EZ바'));
      expect(
        exerciseCatalog
            .singleWhere((exercise) => exercise.id == id)
            .resolvedEquipmentKey,
        'ez_curl_bar',
      );
    }
    expect(exerciseGuides['chest_supported_row']!.join(' '), contains('엎드려'));
    expect(exerciseGuides['chest_supported_row']!.join(' '), contains('중립 그립'));
    expect(exerciseGuides['back_extension']!.join(' '), contains('엉덩이 관절'));
    expect(
      exerciseGuides['overhead_triceps_extension']!.join(' '),
      contains('손바닥은 앞'),
    );
    expect(exerciseGuides['tbar_row']!.join(' '), contains('랜드마인'));
    final overheadPress = exerciseGuides['ohp']!.join(' ');
    expect(overheadPress, contains('스탠딩 바벨 프레스'));
    expect(overheadPress, contains('무릎을 굽혀 반동을 주지 않고'));
    expect(overheadPress, isNot(contains('벤치에 앉아')));
    final arnold = exerciseGuides['arnold_press']!.join(' ');
    expect(arnold, contains('전완과 위팔이 함께'));
    expect(arnold, isNot(contains('손목을 회전시켜')));
    final closeGrip = exerciseGuides['close_grip_bench']!.join(' ');
    expect(closeGrip, contains('어깨와 나란한'));
    expect(closeGrip, isNot(contains('어깨넓이보다 좁게')));
    final oneArm = exerciseGuides['one_arm_dumbbell_row']!.join(' ');
    expect(oneArm, contains('왼손과 왼쪽 무릎을 벤치에 지지'));
    expect(oneArm, contains('몸통을 비틀어'));
    final frontSquat = exerciseGuides['front_squat']!.join(' ');
    expect(frontSquat, contains('어깨 바깥쪽'));
    expect(frontSquat, contains('팔꿈치를 앞으로 높게'));
    expect(frontSquat, contains('바벨의 무게를 앞어깨로'));
    expect(exerciseGuides['ab_wheel']!.join(' '), contains('억지로 만들지'));
    final cableCrunch = exerciseGuides['cable_crunch']!.join(' ');
    expect(cableCrunch, contains('머신을 바라보며'));
    expect(cableCrunch, contains('머리 양옆'));
    expect(cableCrunch, isNot(contains('등을 향하게')));
    expect(exerciseGuides['cable_fly']!.join(' '), contains('중립 그립'));
    expect(exerciseGuides['cable_lateral_raise']!.join(' '), contains('낮은 풀리'));
    expect(exerciseGuides['pec_deck']!.join(' '), contains('중립 그립'));
    final reversePec = exerciseGuides['reverse_pec_deck']!.join(' ');
    expect(reversePec, contains('엄지가 위'));
    expect(reversePec, isNot(contains('손바닥을 위로')));
    expect(exerciseGuides['assisted_pullup']!.join(' '), contains('양 무릎'));
    expect(exerciseGuides['assisted_pullup']!.join(' '), contains('보조 패드'));
    final rowing = exerciseGuides['rowing_machine']!.join(' ');
    expect(rowing, contains('먼저 다리로'));
    expect(rowing, contains('마지막으로 팔꿈치'));
    expect(rowing, contains('팔을 먼저 펴고'));
    expect(rowing, contains('손이 무릎을 지나면'));
    final rack = exerciseGuides['rack_pull']!.join(' ');
    expect(rack, contains('안전 받침'));
    expect(rack, contains('뒤로 젖히지'));
    final upright = exerciseGuides['upright_row']!.join(' ');
    expect(upright, contains('팔꿈치를 옆으로'));
    expect(upright, contains('어깨 높이를 넘기 전'));
    expect(upright, isNot(contains('팔꿈치를 앞으로')));
    final burpee = exerciseGuides['burpee']!.join(' ');
    expect(burpee, contains('푸시업과 수직 점프를 포함'));
    expect(burpee, contains('굽혀 착지'));
    final bike = exerciseGuides['stationary_bike']!.join(' ');
    expect(bike, contains('내려선 상태에서 안장을 조정'));
    expect(bike, contains('무릎이 조금 굽혀지고'));
    expect(bike, contains('시작 전에 양발이 미끄러지지'));
    final elliptical = exerciseGuides['elliptical']!.join(' ');
    expect(elliptical, contains('고정 손잡이'));
    expect(elliptical, contains('움직이는 양팔 손잡이'));
    expect(elliptical, contains('페달이 완전히 멈추면'));
    final stepmill = exerciseGuides['stair_climber']!.join(' ');
    expect(stepmill, contains('몸과 시선은 앞'));
    expect(stepmill, contains('팔에 체중을 매달지'));
    expect(stepmill, contains('계단이 완전히 멈춘 뒤'));
    const equipment = {
      'goblet_squat': 'kettlebell',
      'bench_dip': 'bench',
      'hanging_leg_raise': 'pullup_bar',
      'leg_raise': 'bench',
      'squat': 'barbell',
      'ohp': 'barbell',
      'incline_barbell': 'barbell',
      'front_squat': 'barbell',
      'hip_thrust': 'barbell',
      'glute_bridge': 'barbell',
      'calf_raise': 'machine',
      'assisted_pullup': 'machine',
      'pec_deck': 'machine',
      'reverse_pec_deck': 'machine',
      'latpull': 'machine',
      'front_raise': 'dumbbell',
      'rear_delt_raise': 'dumbbell',
      'bulgarian_split_squat': 'dumbbell',
      'reverse_curl': 'barbell',
      'bird_dog': 'body_only',
      'brisk_walk': 'body_only',
    };
    for (final entry in equipment.entries) {
      expect(
        exerciseCatalog
            .firstWhere((e) => e.id == entry.key)
            .resolvedEquipmentKey,
        entry.value,
      );
    }
  });

  test('plank instructions describe a stationary forearm hold', () {
    final plank = exerciseCatalog.firstWhere(
      (exercise) => exercise.id == 'plank',
    );
    expect(plank.measurement, ExerciseMeasurement.duration);
    final guide = exerciseGuides['plank']!;
    expect(guide, hasLength(3));
    final text = guide.join(' ');
    expect(text, contains('팔꿈치를 어깨 바로 아래'));
    expect(text, contains('전완을 바닥'));
    expect(text, contains('어깨·엉덩이·발목이 일직선'));
    expect(text, contains('시간 동안 움직임 없이'));
    expect(text, contains('호흡'));
    expect(text, isNot(contains('회전')));
    expect(text, isNot(contains('오른팔을 들어')));
    expect(text, isNot(contains('왼쪽도')));
  });

  test('all curated exercises have an exact imported or authored guide', () {
    // 비슷한 종목의 설명을 대신 붙이지 않는다. 마지막 맨몸 스쿼트도 정확한
    // ACE 근거를 확인한 자체 단계이며 출처 경계는 docs/exercise-guides.md에 있다.
    final uncovered = exerciseCatalog
        .map((e) => e.id)
        .where((id) => !exerciseGuides.containsKey(id))
        .toSet();
    expect(uncovered, isEmpty, reason: '완성된 종목의 수행 설명이 빠졌다');
  });

  testWidgets('the exact visual and steps are reachable together', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = DateTime(2026, 11, 7);
    final guided = exerciseCatalog.firstWhere(
      (exercise) => exercise.id == 'bench',
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
    final viewer = tester.widget<ExerciseVisualViewer>(
      find.byType(ExerciseVisualViewer),
    );
    expect(viewer.visual, same(exerciseVisuals['bench']));
    expect(viewer.exerciseName, '바벨 벤치 프레스');

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'a guest can open the authored bodyweight squat guide and visual',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(432, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = AppState();
      await state.initialize();
      addTearDown(state.dispose);
      final date = DateTime(2026, 11, 7);
      final exercise = exerciseCatalog.firstWhere(
        (exercise) => exercise.id == 'bodyweight_squat',
      );
      expect(exerciseGuides.containsKey(exercise.id), isTrue);
      state.addExercise(date, exercise);
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
      await tester.tap(find.byTooltip('운동 메뉴').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('수행 방법'));
      await tester.pump(const Duration(milliseconds: 400));
      final viewer = tester.widget<ExerciseVisualViewer>(
        find.byType(ExerciseVisualViewer),
      );
      expect(viewer.visual, same(exerciseVisuals['bodyweight_squat']));
      expect(viewer.exerciseName, '맨몸 스쿼트');
      expect(find.text(exerciseGuides[exercise.id]!.first), findsOneWidget);
      expect(find.text('동작 예시 (데모)'), findsOneWidget);
      expect(find.textContaining('로그인'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('row visual and instructions teach the same overhand variant', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = DateTime(2026, 11, 7);
    final row = exerciseCatalog.firstWhere((exercise) => exercise.id == 'row');
    state.addExercise(date, row);
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
    await tester.tap(find.byTooltip('운동 메뉴').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('수행 방법'));
    await tester.pump(const Duration(milliseconds: 400));
    final viewer = tester.widget<ExerciseVisualViewer>(
      find.byType(ExerciseVisualViewer),
    );
    expect(viewer.visual, same(exerciseVisuals['row']));
    expect(viewer.exerciseName, '바벨 로우');
    expect(find.text(exerciseGuides['row']![1]), findsOneWidget);
    expect(
      find.text(exerciseVisuals['row']!.variantDescription!),
      findsOneWidget,
    );
    final instructions = exerciseGuides['row']!.join(' ');
    expect(instructions, contains('배꼽 쪽으로'));
    expect(instructions, contains('손목은 전완과 일직선'));
    expect(instructions, isNot(contains('아래 가슴')));
    expect(find.text('동작 예시 (데모)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an unmapped exercise does not offer a substitute visual', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(432, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = AppState();
    await state.initialize();
    addTearDown(state.dispose);
    final date = DateTime(2026, 11, 7);
    final exercise = offlineExerciseCatalog.firstWhere(
      (exercise) => exercise.id == '5b34c34c-cc4f-54f1-bd64-ab37af17d01d',
    );
    state.addExercise(date, exercise);
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
    await tester.tap(find.byTooltip('운동 메뉴').first);
    await tester.pumpAndSettle();
    expect(find.text('수행 방법'), findsNothing);
    expect(find.byType(ExerciseVisualViewer), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
