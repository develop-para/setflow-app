import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:setflow/data/exercise_visuals.dart';
import 'package:setflow/data/offline_exercise_catalog.dart';
import 'package:setflow/data/supabase_exercise_catalog_repository.dart'
    show exerciseTemplateFromCatalogRow;
import 'package:setflow/models.dart' show ExerciseTemplate;
import 'package:setflow/theme.dart';
import 'package:setflow/widgets/exercise_visual_viewer.dart';

const _testVisual = ExerciseVisual(
  assetPath: 'test_motion.gif',
  highlightedMuscles: '대퇴사두근 · 둔근',
);

const _staticTestVisual = ExerciseVisual(
  assetPath: 'test_motion.gif',
  highlightedMuscles: '복근',
  isStaticPose: true,
);

const _oneSideTestVisual = ExerciseVisual(
  assetPath: 'test_motion.gif',
  highlightedMuscles: '복근 · 둔근',
  variantDescription: '네발 자세에서 반대쪽 팔과 다리 뻗기',
  demonstratedSide: '왼팔과 오른다리',
);

void main() {
  final snapshot =
      jsonDecode(
            File(
              'test/fixtures/exercise_visual_shared_rows.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final sharedRows = (snapshot['rows'] as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  final sharedExercises = sharedRows
      .map(exerciseTemplateFromCatalogRow)
      .toList();
  final catalogById = <String, ExerciseTemplate>{
    for (final exercise in offlineExerciseCatalog) exercise.id: exercise,
    for (final exercise in sharedExercises) exercise.id: exercise,
  };

  test('shared catalog visuals preserve all eight exact source identities', () {
    expect(snapshot['mediaIncluded'], isFalse);
    expect(sharedRows, hasLength(8));
    expect(sharedRows.map((row) => row['id']).toSet(), {
      '896189fc-30d9-51df-aa19-fd5ea7fa76eb',
      '58acf002-4e6d-5e95-b252-cae16252cef8',
      '0f177240-029b-543a-be27-2e8ed0526bca',
      '3c358477-aeb3-5d78-a6aa-91c9fb6c81db',
      'bff7dff4-2b99-5357-b365-f10e1187cbb3',
      'd1ecb818-0235-5e2f-9113-39be506aa98a',
      '823846f5-2414-58b7-911e-2d9397a28f49',
      'dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe',
    });
    expect(sharedRows.map((row) => row['source_id']).toSet(), hasLength(8));
    for (var index = 0; index < sharedRows.length; index++) {
      final row = sharedRows[index];
      final exercise = sharedExercises[index];
      expect(exercise.id, row['id'], reason: row['source_id'] as String);
      expect(exercise.databaseId, row['id']);
      expect(exercise.sourceId, row['source_id']);
      expect(exercise.sourceName, row['source_name']);
      expect(catalogById[exercise.id], same(exercise));
      expect(exerciseVisuals, contains(exercise.id));
    }
  });

  test('registered visuals have real assets and exact catalog identities', () {
    expect(exerciseVisuals.keys.toSet(), {
      'bodyweight_squat',
      'pushup',
      'bench',
      'dumbbell_bench',
      'deadlift',
      'romanian_deadlift',
      'row',
      'curl',
      'dumbbell_shoulder_press',
      'lateral',
      'calf_raise',
      'plank',
      'crunch',
      'squat',
      'front_squat',
      'goblet_squat',
      'barbell_curl',
      'ohp',
      'incline',
      'incline_barbell',
      'hip_thrust',
      'glute_bridge',
      '896189fc-30d9-51df-aa19-fd5ea7fa76eb',
      '58acf002-4e6d-5e95-b252-cae16252cef8',
      'bulgarian_split_squat',
      'pullup',
      'dips',
      'bench_dip',
      'hanging_leg_raise',
      'leg_raise',
      'bird_dog',
      'dead_bug',
      'side_plank',
      '0f177240-029b-543a-be27-2e8ed0526bca',
      '3c358477-aeb3-5d78-a6aa-91c9fb6c81db',
      'bff7dff4-2b99-5357-b365-f10e1187cbb3',
      'd1ecb818-0235-5e2f-9113-39be506aa98a',
      '823846f5-2414-58b7-911e-2d9397a28f49',
      'dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe',
      'hammer_curl',
      'reverse_curl',
      'front_raise',
      'rear_delt_raise',
      'reverse_fly',
      'cable_curl',
      'triceps_pushdown',
      'seated_cable_row',
      'latpull',
      'wall_sit',
      'russian_twist',
      'mountain_climber',
      'face_pull',
      'arnold_press',
      'one_arm_dumbbell_row',
      'close_grip_bench',
      'chest_press',
      'leg_curl',
      'leg_extension',
      'adductor_machine',
      'rack_pull',
      'tbar_row',
      'cable_crunch',
      'cable_fly',
      'cable_lateral_raise',
      'straight_arm_pulldown',
      'ab_wheel',
      'burpee',
      'walking_lunge',
      'pec_deck',
      'reverse_pec_deck',
      'assisted_pullup',
      'upright_row',
      'preacher_curl',
      'skull_crusher',
      'chest_supported_row',
      'back_extension',
      'decline_bench',
      'overhead_triceps_extension',
      'seated_calf_raise',
      'legpress',
      'hack_squat',
      'brisk_walk',
      'run',
      'jump_rope',
      'stair_climber',
      'stationary_bike',
      'elliptical',
      'rowing_machine',
    });
    expect(
      exerciseVisuals.entries
          .where((entry) => entry.value.isStaticPose)
          .map((entry) => entry.key),
      unorderedEquals(['plank', 'side_plank', 'wall_sit']),
    );
    for (final entry in exerciseVisuals.entries) {
      expect(catalogById, contains(entry.key));
      expect(File(entry.value.assetPath).existsSync(), isTrue);
      expect(entry.value.assetPath, 'assets/exercise_visuals/${entry.key}.gif');
      expect(entry.value.highlightedMuscles.trim(), isNotEmpty);
      expect(entry.value.variantDescription?.trim(), isNotEmpty);
    }
  });

  testWidgets('every registered asset decodes as its own exercise image', (
    tester,
  ) async {
    for (final entry in exerciseVisuals.entries) {
      final exercise = catalogById[entry.key]!;
      await tester.pumpWidget(
        MaterialApp(
          theme: SetflowTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExerciseVisualViewer(
                exerciseName: exercise.name,
                visual: entry.value,
              ),
            ),
          ),
        ),
      );
      await _loadFirstFrame(tester);
      expect(_currentFrame(tester), isNotNull, reason: entry.key);
      final rendered = tester.widget<Image>(find.byType(Image));
      expect(rendered.key, ValueKey(entry.value.assetPath));
      expect(find.text('동작 예시를 불러오지 못했어요.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('a static hold has a still frame and no playback controls', (
    tester,
  ) async {
    await _mount(tester, visual: _staticTestVisual, exerciseName: '플랭크');
    await _loadFirstFrame(tester);
    expect(find.text('자세를 유지하는 동작이에요.'), findsOneWidget);
    expect(find.text('동작 재생'), findsNothing);
    expect(find.text('동작 일시정지'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    final firstFrame = _currentFrame(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(_currentFrame(tester), same(firstFrame));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'selected variation and opposite-side instructions stay readable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mount(
        tester,
        textScale: 2,
        visual: _oneSideTestVisual,
        exerciseName: '버드 독',
      );
      await _loadFirstFrame(tester);
      expect(find.text(_oneSideTestVisual.variantDescription!), findsOneWidget);
      final instruction = find.text(
        '영상은 왼팔과 오른다리 동작을 보여줘요. 반대쪽도 같은 방법으로 반복하세요.',
      );
      await tester.ensureVisible(instruction);
      expect(instruction, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('manual playback advances frames and pause retains the frame', (
    tester,
  ) async {
    await _mount(tester);
    await _loadFirstFrame(tester);
    final firstFrame = _currentFrame(tester);
    expect(find.text('동작 재생'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(_currentFrame(tester), same(firstFrame));

    await tester.ensureVisible(find.text('동작 재생'));
    await tester.tap(find.text('동작 재생'));
    await tester.pump();
    await _advanceFrame(tester, firstFrame);
    expect(find.text('동작 일시정지'), findsOneWidget);

    await tester.tap(find.text('동작 일시정지'));
    await tester.pump();
    final pausedFrame = _currentFrame(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(_currentFrame(tester), same(pausedFrame));
    expect(find.text('동작 재생'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion stays still until explicit playback', (
    tester,
  ) async {
    await _mount(tester, reduceMotion: true);
    await _loadFirstFrame(tester);
    final firstFrame = _currentFrame(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_currentFrame(tester), same(firstFrame));

    await tester.ensureVisible(find.text('동작 재생'));
    await tester.tap(find.text('동작 재생'));
    await tester.pump();
    await _advanceFrame(tester, firstFrame);
    expect(find.text('동작 일시정지'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'reopening the same asset starts at the first frame without evicting shared images',
    (tester) async {
      final bundle = _MotionBundle(fail: false);
      await _mount(tester, bundle: bundle);
      await _loadFirstFrame(tester);
      final firstPixels = await _currentFramePixels(tester);
      expect(firstPixels, [255, 0, 0, 255]);

      // A normal image of this asset may be used elsewhere in the app. The
      // viewer must neither share its decoder nor evict its cached image.
      final sharedProvider = ResizeImage.resizeIfNeeded(
        384,
        null,
        AssetImage(_testVisual.assetPath, bundle: bundle),
      );
      final sharedStream = sharedProvider.resolve(ImageConfiguration.empty);
      ImageInfo? sharedFrame;
      final listener = ImageStreamListener((frame, synchronous) {
        sharedFrame?.dispose();
        sharedFrame = frame;
      });
      sharedStream.addListener(listener);
      try {
        for (var attempt = 0; attempt < 30 && sharedFrame == null; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(sharedFrame, isNotNull);
      } finally {
        sharedStream.removeListener(listener);
        sharedFrame?.dispose();
      }
      final sharedKey = await sharedProvider.obtainKey(
        ImageConfiguration.empty,
      );
      expect(
        PaintingBinding.instance.imageCache.containsKey(sharedKey),
        isTrue,
      );

      await tester.ensureVisible(find.text('동작 재생'));
      await tester.tap(find.text('동작 재생'));
      await tester.pump();
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if ((await _currentFramePixels(tester)).first != firstPixels.first) {
          break;
        }
      }
      await tester.tap(find.text('동작 일시정지'));
      await tester.pump();
      final pausedPixels = await _currentFramePixels(tester);
      expect(pausedPixels, isNot(equals(firstPixels)));
      await tester.pump(const Duration(seconds: 1));
      expect(await _currentFramePixels(tester), pausedPixels);

      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, bundle: bundle);
      await _loadFirstFrame(tester);
      expect(await _currentFramePixels(tester), firstPixels);
      expect(find.text('동작 재생'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(await _currentFramePixels(tester), firstPixels);
      expect(
        PaintingBinding.instance.imageCache.containsKey(sharedKey),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('backgrounding pauses playback and resume does not restart it', (
    tester,
  ) async {
    await _mount(tester);
    await _loadFirstFrame(tester);
    await tester.ensureVisible(find.text('동작 재생'));
    await tester.tap(find.text('동작 재생'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('동작 재생'), findsOneWidget);
    final pausedFrame = _currentFrame(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(_currentFrame(tester), same(pausedFrame));
    expect(find.text('동작 재생'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'an unavailable asset has a readable error and no fake controls',
    (tester) async {
      await _mount(tester, failAsset: true);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('동작 예시를 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('동작 재생'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a narrow screen with large Korean text remains scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, textScale: 2);
      await _loadFirstFrame(tester);
      expect(find.text('동작 예시 (데모)'), findsOneWidget);
      expect(
        find.bySemanticsLabel('맨몸 스쿼트 동작 예시. 강조 부위: 대퇴사두근 · 둔근.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('동작 재생'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _mount(
  WidgetTester tester, {
  bool reduceMotion = false,
  bool failAsset = false,
  double textScale = 1,
  ExerciseVisual visual = _testVisual,
  String exerciseName = '맨몸 스쿼트',
  _MotionBundle? bundle,
}) => tester.pumpWidget(
  MaterialApp(
    theme: SetflowTheme.light,
    home: DefaultAssetBundle(
      bundle: bundle ?? _MotionBundle(fail: failAsset),
      child: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: SetflowInsets.pageForm,
            child: ExerciseVisualViewer(
              exerciseName: exerciseName,
              visual: visual,
            ),
          ),
        ),
      ),
    ),
  ),
);

Object? _currentFrame(WidgetTester tester) =>
    tester.widget<RawImage>(find.byType(RawImage)).image;

Future<List<int>> _currentFramePixels(WidgetTester tester) async {
  final frame = tester.widget<RawImage>(find.byType(RawImage)).image!;
  final bytes = await tester.runAsync(
    () => frame.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return List.generate(4, bytes!.getUint8);
}

Future<void> _loadFirstFrame(WidgetTester tester) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.byType(RawImage).evaluate().isNotEmpty &&
        _currentFrame(tester) != null) {
      return;
    }
  }
  fail('GIF 첫 프레임이 표시되지 않았다');
}

Future<void> _advanceFrame(WidgetTester tester, Object? previousFrame) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (!identical(_currentFrame(tester), previousFrame)) return;
  }
  fail('재생을 눌러도 GIF 프레임이 바뀌지 않았다');
}

class _MotionBundle extends CachingAssetBundle {
  _MotionBundle({required this.fail});

  final bool fail;

  @override
  Future<ByteData> load(String key) async {
    if (key != _testVisual.assetPath) return rootBundle.load(key);
    if (fail) throw FlutterError('test asset unavailable');
    final encoder = image.GifEncoder(delay: 10);
    for (final color in [
      image.ColorRgb8(255, 0, 0),
      image.ColorRgb8(0, 255, 0),
      image.ColorRgb8(0, 0, 255),
    ]) {
      encoder.addFrame(
        image.fill(image.Image(width: 8, height: 8), color: color),
        duration: 10,
      );
    }
    return ByteData.sublistView(encoder.finish()!);
  }
}
