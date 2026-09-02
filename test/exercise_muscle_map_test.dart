import 'package:flutter/material.dart';
import 'package:flutter_body_atlas/flutter_body_atlas.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/models.dart';
import 'package:setflow/theme.dart';
import 'package:setflow/theme/icons.dart';
import 'package:setflow/widgets/exercise_muscle_map.dart';

void main() {
  Future<void> pumpMap(WidgetTester tester, Widget muscleMap) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SetflowTheme.light,
        home: Scaffold(body: Center(child: muscleMap)),
      ),
    );
    await tester.pump();
  }

  SvgAssetLoader firstLoader(WidgetTester tester) =>
      tester.widget<SvgPicture>(find.byType(SvgPicture).first).bytesLoader
          as SvgAssetLoader;

  Color mappedColor(
    SvgAssetLoader loader,
    String pathId, {
    String attributeName = 'fill',
  }) {
    const original = SetflowNeutral.n200;
    return loader.colorMapper!.substitute(
      pathId,
      'path',
      attributeName,
      original,
    );
  }

  testWidgets('chest map and triceps text keep primary and secondary roles', (
    tester,
  ) async {
    const exercise = ExerciseTemplate(
      id: 'bench_press_test',
      name: '벤치프레스',
      muscle: '가슴',
      icon: SetflowIcons.record,
      primaryMuscles: <String>['chest'],
      secondaryMuscles: <String>['triceps'],
    );
    final map = ExerciseMuscleMap.forExercise(exercise: exercise);

    expect(map.primaryLabel, '주동근: 대흉근');
    expect(map.secondaryLabel, '보조근: 상완삼두근');
    expect(exerciseMuscleSummaryKo(exercise), '주동근: 대흉근 · 보조근: 상완삼두근');
    expect(map.hasMappedPrimaryMuscles, isTrue);

    await pumpMap(tester, map);

    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel('벤치프레스 근육 지도. 주동근: 대흉근. 보조근: 상완삼두근.'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
    final pictures = tester.widgetList<SvgPicture>(find.byType(SvgPicture));
    expect(pictures, hasLength(2));

    final loaders = pictures
        .map((picture) => picture.bytesLoader)
        .whereType<SvgAssetLoader>()
        .toList();
    expect(loaders.map((loader) => loader.assetName), <String>[
      AtlasAsset.musclesFront.path,
      AtlasAsset.musclesBack.path,
    ]);
    expect(
      loaders.every((loader) => loader.packageName == AtlasAsset.package),
      isTrue,
    );

    final loader = loaders.first;
    expect(mappedColor(loader, 'pectoralis_major_l'), SetflowMuscleFill.chest);
    expect(
      mappedColor(loader, 'triceps_brachii_caput_longum_r'),
      SetflowNeutral.n200,
      reason: '보조근은 주동근으로 오인되지 않도록 글자로만 표시한다',
    );
    expect(mappedColor(loader, 'underlayer'), SetflowNeutral.n200);
    expect(
      mappedColor(loader, 'pectoralis_major_l', attributeName: 'stroke'),
      SetflowNeutral.n200,
    );
  });

  testWidgets('missing detail falls back to the upper category', (
    tester,
  ) async {
    const exercise = ExerciseTemplate(
      id: 'category_fallback_test',
      name: '가슴 운동',
      muscle: '가슴',
      icon: SetflowIcons.record,
    );
    final exerciseMap = ExerciseMuscleMap.forExercise(exercise: exercise);
    final categoryMap = ExerciseMuscleMap.forCategory(category: '가슴');

    expect(exerciseMap.primaryMuscles, <String>['chest']);
    expect(categoryMap.primaryMuscles, <String>['chest']);
    expect(exerciseMap.primaryLabel, '주동근: 대흉근');
    expect(exerciseMuscleSummaryKo(exercise), '주동근: 대흉근');

    await pumpMap(tester, categoryMap);
    expect(
      mappedColor(firstLoader(tester), 'pectoralis_major_r'),
      SetflowMuscleFill.chest,
    );
  });

  testWidgets('cardio with source muscles keeps its anatomical target', (
    tester,
  ) async {
    const exercise = ExerciseTemplate(
      id: 'cardio_test',
      name: '실내 자전거',
      muscle: '유산소',
      icon: SetflowIcons.record,
      primaryMuscles: <String>['quadriceps'],
      secondaryMuscles: <String>['calves'],
    );
    final map = ExerciseMuscleMap.forExercise(exercise: exercise);

    expect(map.primaryMuscles, <String>['quadriceps']);
    expect(map.secondaryMuscles, <String>['calves']);
    expect(
      exerciseMuscleSummaryKo(exercise),
      '유산소 · 주동근: 대퇴사두근 · 보조근: 종아리·하퇴 근육군',
    );
    await pumpMap(tester, map);

    expect(find.byType(SvgPicture), findsNWidgets(2));
    expect(find.byIcon(SetflowIcons.cardio), findsNothing);
    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel('실내 자전거 근육 지도. 주동근: 대퇴사두근. 보조근: 종아리·하퇴 근육군.'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('cardio without source muscles uses the generic symbol', (
    tester,
  ) async {
    const exercise = ExerciseTemplate(
      id: 'cardio_fallback_test',
      name: '사용자 유산소',
      muscle: '유산소',
      icon: SetflowIcons.record,
    );
    final map = ExerciseMuscleMap.forExercise(exercise: exercise);

    expect(exerciseMuscleSummaryKo(exercise), '유산소 운동');
    await pumpMap(tester, map);

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byIcon(SetflowIcons.cardio), findsOneWidget);
  });

  testWidgets('the all category uses a grid symbol instead of an empty body', (
    tester,
  ) async {
    final map = ExerciseMuscleMap.forCategory(category: '전체');
    await pumpMap(tester, map);

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byIcon(SetflowIcons.appMenu), findsOneWidget);
    final semantics = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel('전체 운동'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('decorative maps do not add a duplicate semantics node', (
    tester,
  ) async {
    const exercise = ExerciseTemplate(
      id: 'decorative_test',
      name: '장식 지도',
      muscle: '가슴',
      icon: SetflowIcons.record,
      primaryMuscles: <String>['chest'],
    );
    await pumpMap(
      tester,
      ExerciseMuscleMap.forExercise(exercise: exercise, decorative: true),
    );

    final semantics = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel(RegExp('장식 지도')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('lower back remains a label without borrowing another path', (
    tester,
  ) async {
    const exercise = ExerciseTemplate(
      id: 'lower_back_test',
      name: '허리 운동',
      muscle: '등',
      icon: SetflowIcons.record,
      primaryMuscles: <String>['lower back'],
    );
    final map = ExerciseMuscleMap.forExercise(exercise: exercise);

    expect(map.primaryLabel, '주동근: 척추기립근(허리)');
    expect(exerciseMuscleSummaryKo(exercise), '주동근: 척추기립근(허리)');
    expect(map.hasMappedPrimaryMuscles, isFalse);
    await pumpMap(tester, map);

    final loader = firstLoader(tester);
    expect(mappedColor(loader, 'latissimus_dorsi_l'), SetflowNeutral.n200);
    expect(mappedColor(loader, 'trapezius_lower_r'), SetflowNeutral.n200);
    expect(mappedColor(loader, 'gluteus_maximus_l'), SetflowNeutral.n200);
    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel('허리 운동 근육 지도. 주동근: 척추기립근(허리).'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  test('summary keeps unknown and empty cases in Korean', () {
    const unknown = ExerciseTemplate(
      id: 'unknown_test',
      name: '사용자 운동',
      muscle: '기타',
      icon: SetflowIcons.record,
    );
    expect(exerciseMuscleSummaryKo(unknown), '근육 정보 없음');
    expect(exerciseMuscleNameKo('unknown source key'), '기타 부위');
  });

  test(
    'all 17 source muscle keys keep Korean labels and conservative maps',
    () {
      const mappedKeys = <String>[
        'abdominals',
        'abductors',
        'adductors',
        'biceps',
        'calves',
        'chest',
        'forearms',
        'glutes',
        'hamstrings',
        'lats',
        'quadriceps',
        'shoulders',
        'traps',
        'triceps',
      ];

      for (final key in mappedKeys) {
        final exercise = ExerciseTemplate(
          id: 'mapping_$key',
          name: '매핑 검사',
          muscle: '기타',
          icon: SetflowIcons.record,
          primaryMuscles: <String>[key],
        );
        expect(exerciseMuscleNameKo(key), isNot('기타 부위'), reason: key);
        expect(
          ExerciseMuscleMap.forExercise(
            exercise: exercise,
          ).hasMappedPrimaryMuscles,
          isTrue,
          reason: key,
        );
      }

      const textOnly = <String, String>{
        'lower back': '척추기립근(허리)',
        'middle back': '등 중앙부(능형근 등)',
        'neck': '목 근육군',
      };
      for (final entry in textOnly.entries) {
        final exercise = ExerciseTemplate(
          id: 'mapping_${entry.key}',
          name: '매핑 검사',
          muscle: '기타',
          icon: SetflowIcons.record,
          primaryMuscles: <String>[entry.key],
        );
        expect(exerciseMuscleNameKo(entry.key), entry.value);
        expect(
          ExerciseMuscleMap.forExercise(
            exercise: exercise,
          ).hasMappedPrimaryMuscles,
          isFalse,
          reason: entry.key,
        );
      }
    },
  );

  testWidgets('compact rows choose one useful body direction', (tester) async {
    const exercise = ExerciseTemplate(
      id: 'compact_back_test',
      name: '광배근 운동',
      muscle: '등',
      icon: SetflowIcons.record,
      primaryMuscles: <String>['lats'],
    );
    await pumpMap(
      tester,
      ExerciseMuscleMap.forExercise(exercise: exercise, size: 44),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(firstLoader(tester).assetName, AtlasAsset.musclesBack.path);
  });

  testWidgets('broad calves color front and back lower-leg paths', (
    tester,
  ) async {
    const exercise = ExerciseTemplate(
      id: 'lower_leg_test',
      name: '종아리 운동',
      muscle: '하체',
      icon: SetflowIcons.record,
      primaryMuscles: <String>['calves'],
    );
    await pumpMap(
      tester,
      ExerciseMuscleMap.forExercise(exercise: exercise, size: 44),
    );

    expect(find.byType(SvgPicture), findsNWidgets(2));
    final loader = firstLoader(tester);
    expect(mappedColor(loader, 'tibialis_anterior_l'), SetflowMuscleFill.legs);
    expect(mappedColor(loader, 'gastrocnemius_r'), SetflowMuscleFill.legs);
  });
}
