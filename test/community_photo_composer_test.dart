import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:setflow/app_state.dart';
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/screens/member_social_detail_screens.dart';
import 'package:setflow/services/auth_service.dart';
import 'package:setflow/services/community_photo_renderer.dart';
import 'package:setflow/services/post_media_picker.dart';
import 'package:setflow/theme.dart';

void main() {
  for (final source in PostMediaSource.values) {
    testWidgets('$source publishes the photo with its visible overlays', (
      tester,
    ) async {
      final media = _photo();
      final picker = _Picker(media);
      final repository = _Repository();
      await _openComposer(tester, repository, picker: picker);

      await _pick(tester, source);
      expect(picker.sources, [source]);
      expect(find.text('사진 변경'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('게시'));
        for (
          var attempt = 0;
          attempt < 100 && repository.inputs.isEmpty;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(repository.inputs, hasLength(1));
      final input = repository.inputs.single;
      final uploaded = input.media!;
      expect(uploaded.bytes, isNot(orderedEquals(media.bytes)));
      final image = image_lib.decodeImage(uploaded.bytes)!;
      expect(image.width, image.height);
      expect(image.width, lessThanOrEqualTo(1600));
      expect(uploaded.bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
      expect(input.activeOverlays, containsAll(['날짜', '시간', '완료 루틴']));

      // The solid source cannot contain bright text. Both upper labels and
      // the workout label must have been baked into the uploaded pixels.
      expect(_brightPixels(image, 0, .5, 0, .3), greaterThan(0));
      expect(_brightPixels(image, .5, 1, 0, .3), greaterThan(0));
      expect(_brightPixels(image, 0, 1, .7, 1), greaterThan(0));

      // The editor's centered "사진 변경" badge belongs only to the editor.
      final middle = image.getPixel(image.width ~/ 2, image.height ~/ 2);
      final nearby = image.getPixel(
        image.width ~/ 2,
        (image.height * .65).floor(),
      );
      expect(middle.r, nearby.r);
      expect(middle.g, nearby.g);
      expect(middle.b, nearby.b);
      expect(find.byType(SocialPostComposerScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabling every overlay publishes the original photo', (
    tester,
  ) async {
    final media = _photo();
    final renderer = _Renderer();
    final repository = _Repository();
    await _openComposer(
      tester,
      repository,
      picker: _Picker(media),
      renderer: renderer,
    );
    await _pick(tester, PostMediaSource.gallery);
    for (final label in ['날짜', '시간', '완료 루틴']) {
      final chip = find.widgetWithText(FilterChip, label);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
    }
    await tester.tap(find.text('게시'));
    await tester.pumpAndSettle();

    expect(renderer.overlays.every((overlay) => overlay.isEmpty), isTrue);
    expect(repository.inputs.single.media, same(media));
    expect(repository.inputs.single.activeOverlays, isEmpty);
  });

  testWidgets('a pending photo selection cannot publish without that photo', (
    tester,
  ) async {
    final pending = Completer<CommunityPostMedia?>();
    final picker = _Picker(_photo())..pending = pending.future;
    final renderer = _Renderer();
    final repository = _Repository();
    await _openComposer(tester, repository, picker: picker, renderer: renderer);
    await tester.enterText(find.byType(TextFormField), '사진과 함께 남길 기록');
    await tester.tap(find.text('촬영'));
    await tester.pump();
    await tester.tap(find.text('게시'));
    await tester.pump();
    expect(repository.inputs, isEmpty);
    expect(renderer.overlays, isEmpty);

    pending.complete(picker.media);
    await tester.pumpAndSettle();
    await tester.tap(find.text('게시'));
    await tester.pumpAndSettle();
    expect(repository.inputs, hasLength(1));
    expect(repository.inputs.single.content, '사진과 함께 남길 기록');
    expect(repository.inputs.single.media, isNotNull);
  });

  testWidgets('rendering freezes preview text and prevents duplicate posts', (
    tester,
  ) async {
    final media = _photo();
    final pending = Completer<CommunityPostMedia>();
    final renderer = _Renderer()..pending = pending.future;
    final repository = _Repository();
    final state = await _openComposer(
      tester,
      repository,
      picker: _Picker(media),
      renderer: renderer,
    );
    await _pick(tester, PostMediaSource.gallery);
    final preview = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is CommunityPhotoOverlayPainter,
      ),
    );
    final visible = (preview.painter! as CommunityPhotoOverlayPainter).overlay;
    expect(visible.workoutText, state.todayWorkoutMetric);
    expect(visible.workoutText, isNot('오늘 운동 완료'));
    await tester.enterText(find.byType(TextFormField), '한 번만 게시할 기록');
    await tester.tap(find.text('게시'));
    await tester.pump();
    final exported = renderer.overlays.single;
    expect(exported.dateText, visible.dateText);
    expect(exported.timeText, visible.timeText);
    expect(exported.workoutText, visible.workoutText);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip))) {
      expect(chip.onSelected, isNull);
    }
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .onSelectionChanged,
      isNull,
    );
    await tester.tap(find.text('게시'));
    await tester.pump();
    expect(renderer.overlays, hasLength(1));
    expect(repository.inputs, isEmpty);

    pending.complete(media);
    await tester.pumpAndSettle();
    expect(repository.inputs, hasLength(1));
    expect(repository.inputs.single.content, '한 번만 게시할 기록');
  });

  testWidgets(
    'render and upload failures retain the photo and draft for retry',
    (tester) async {
      final renderer = _Renderer()..error = StateError('render failed');
      final repository = _Repository();
      await _openComposer(
        tester,
        repository,
        picker: _Picker(_photo()),
        renderer: renderer,
      );
      await _pick(tester, PostMediaSource.gallery);
      await tester.enterText(find.byType(TextFormField), '실패해도 보존할 운동 기록');
      await tester.tap(find.text('게시'));
      await tester.pump();
      expect(repository.inputs, isEmpty);
      expect(find.byType(SocialPostComposerScreen), findsOneWidget);
      expect(find.text('사진 변경'), findsOneWidget);
      expect(_draft(tester), '실패해도 보존할 운동 기록');

      renderer.error = null;
      repository.error = const CommunityOperationException('사진을 저장하지 못했어요.');
      await tester.tap(find.text('게시'));
      await tester.pump();
      expect(repository.inputs, hasLength(1));
      expect(find.text('사진을 저장하지 못했어요.'), findsOneWidget);
      expect(find.text('사진 변경'), findsOneWidget);
      expect(_draft(tester), '실패해도 보존할 운동 기록');

      repository.error = null;
      await tester.tap(find.text('게시'));
      await tester.pumpAndSettle();
      expect(repository.inputs, hasLength(2));
      expect(repository.inputs.last.content, '실패해도 보존할 운동 기록');
      expect(repository.inputs.last.media, isNotNull);
      expect(find.byType(SocialPostComposerScreen), findsNothing);
    },
  );

  testWidgets('workout summary stays aligned with the photo during rendering', (
    tester,
  ) async {
    final media = _photo();
    final pending = Completer<CommunityPostMedia>();
    final renderer = _Renderer()..pending = pending.future;
    final repository = _Repository();
    final state = await _openComposer(
      tester,
      repository,
      picker: _Picker(media),
      renderer: renderer,
    );
    final day = state.dateOnly(DateTime.now());
    final nextSet = WorkoutSetEntry(number: 2, weight: 50, reps: 10);
    state.sessions[day] = WorkoutSession(
      date: day,
      exercises: [
        WorkoutExercise(
          id: 'live-workout',
          template: state.exercises.firstWhere(
            (exercise) => !exercise.isCardio,
          ),
          sets: [
            WorkoutSetEntry(number: 1, weight: 50, reps: 10, completed: true),
            nextSet,
          ],
        ),
      ],
    );
    await _pick(tester, PostMediaSource.gallery);
    final snapshot = state.todayWorkoutMetric;
    await tester.tap(find.text('게시'));
    await tester.pump();
    expect(renderer.overlays.single.workoutText, snapshot);

    // Another workout surface finishes a real set while the photo encoder is
    // still running. The published summary belongs to the captured image.
    nextSet.completed = true;
    expect(state.todayWorkoutMetric, isNot(snapshot));
    pending.complete(media);
    await tester.pumpAndSettle();

    expect(repository.inputs, hasLength(1));
    expect(repository.inputs.single.metric, snapshot);
    expect(
      repository.inputs.single.metric,
      renderer.overlays.single.workoutText,
    );
  });

  testWidgets(
    'changing accounts during rendering never posts as the new user',
    (tester) async {
      final media = _photo();
      final pending = Completer<CommunityPostMedia>();
      final renderer = _Renderer()..pending = pending.future;
      final repository = _Repository();
      final state = await _openComposer(
        tester,
        repository,
        picker: _Picker(media),
        renderer: renderer,
      );
      await _pick(tester, PostMediaSource.camera);
      await tester.tap(find.text('게시'));
      await tester.pump();
      expect(renderer.overlays, hasLength(1));
      expect(repository.inputs, isEmpty);

      Auth.use(const _Auth('other-member'));
      state.handleExternalAuthSignedOut();
      await tester.pump();
      pending.complete(media);
      await tester.pumpAndSettle();
      expect(repository.inputs, isEmpty);
      expect(state.communityPosts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('turning off workout attachment leaves only date and time', (
    tester,
  ) async {
    final renderer = _Renderer();
    final repository = _Repository();
    await _openComposer(
      tester,
      repository,
      picker: _Picker(_photo()),
      renderer: renderer,
    );
    await _pick(tester, PostMediaSource.gallery);
    final attachment = find.byType(SwitchListTile);
    await tester.ensureVisible(attachment);
    await tester.tap(attachment);
    await tester.pump();
    await tester.tap(find.text('게시'));
    await tester.pumpAndSettle();
    final overlay = renderer.overlays.single;
    expect(overlay.dateText, isNotEmpty);
    expect(overlay.timeText, isNotEmpty);
    expect(overlay.workoutText, isNull);
    expect(repository.inputs.single.activeOverlays, isNot(contains('완료 루틴')));
  });

  testWidgets('changing accounts during upload keeps the new feed empty', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = _Repository()..pending = pending.future;
    final state = await _openComposer(
      tester,
      repository,
      picker: _Picker(_photo()),
      renderer: _Renderer(),
    );
    await _pick(tester, PostMediaSource.gallery);
    await tester.tap(find.text('게시'));
    await tester.pump();
    expect(repository.inputs, hasLength(1));

    Auth.use(const _Auth('other-member'));
    state.handleExternalAuthSignedOut();
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(repository.inputs, hasLength(1));
    expect(state.communityPosts, isEmpty);
    expect(find.byType(SocialPostComposerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<AppState> _openComposer(
  WidgetTester tester,
  _Repository repository, {
  required PostMediaPicker picker,
  CommunityPhotoRenderer? renderer,
}) async {
  Auth.use(const _Auth('photo-author'));
  addTearDown(Auth.reset);
  await tester.binding.setSurfaceSize(const Size(432, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = AppState(communityRepository: repository);
  await state.initialize();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: SetflowTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => SocialPostComposerScreen(
                    mediaPicker: picker,
                    photoRenderer: renderer,
                  ),
                ),
              ),
              child: const Text('사진 글 쓰기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('사진 글 쓰기'));
  await tester.pumpAndSettle();
  return state;
}

Future<void> _pick(WidgetTester tester, PostMediaSource source) async {
  await tester.tap(find.text(source == PostMediaSource.camera ? '촬영' : '갤러리'));
  await tester.pumpAndSettle();
}

String _draft(WidgetTester tester) =>
    tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text;

CommunityPostMedia _photo() {
  final source = image_lib.Image(width: 640, height: 480);
  image_lib.fill(source, color: image_lib.ColorRgb8(170, 80, 50));
  return CommunityPostMedia(
    bytes: Uint8List.fromList(image_lib.encodePng(source)),
    fileName: 'my-workout.png',
    contentType: 'image/png',
  );
}

int _brightPixels(
  image_lib.Image image,
  double left,
  double right,
  double top,
  double bottom,
) {
  var count = 0;
  for (var y = (image.height * top).floor(); y < image.height * bottom; y++) {
    for (var x = (image.width * left).floor(); x < image.width * right; x++) {
      final pixel = image.getPixel(x, y);
      if (pixel.r > 220 && pixel.g > 220 && pixel.b > 220) count++;
    }
  }
  return count;
}

class _Picker implements PostMediaPicker {
  _Picker(this.media);

  final CommunityPostMedia media;
  final sources = <PostMediaSource>[];
  Future<CommunityPostMedia?>? pending;

  @override
  Future<CommunityPostMedia?> pick(PostMediaSource source) async {
    sources.add(source);
    return pending == null ? media : await pending!;
  }

  @override
  Future<CommunityPostMedia?> recoverLostImage() async => null;
}

class _Renderer implements CommunityPhotoRenderer {
  final overlays = <CommunityPhotoOverlay>[];
  Future<CommunityPostMedia>? pending;
  Object? error;

  @override
  Future<CommunityPostMedia> render({
    required CommunityPostMedia media,
    required CommunityPhotoOverlay overlay,
  }) async {
    overlays.add(overlay);
    if (error != null) throw error!;
    return pending == null ? media : await pending!;
  }
}

class _Repository implements CommunityRepository {
  final inputs = <CreateCommunityPostInput>[];
  Object? error;
  Future<void>? pending;

  @override
  Future<CommunityPostRecord> createPost(CreateCommunityPostInput input) async {
    inputs.add(input);
    if (error != null) throw error!;
    if (pending != null) await pending!;
    return CommunityPostRecord(
      post: CommunityPost(
        id: 'photo-${inputs.length}',
        author: '사진 작성자',
        content: input.content,
        metric: input.metric,
        createdAt: DateTime(2026, 10, 18),
        visualKey: input.visualKey,
        color: SetflowColors.teal,
        imageUrl: 'https://example.com/uploaded.jpg',
        activeOverlays: input.activeOverlays,
        isMine: true,
      ),
      authorUserId: 'photo-author',
    );
  }

  @override
  Future<List<CommunityPostRecord>> fetchPosts({
    int limit = 50,
    int offset = 0,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthService {
  const _Auth(this.id);

  final String id;

  @override
  AuthUser get currentUser => AuthUser(id: id, displayName: '사진 작성자');

  @override
  bool get hasAuthenticatedUser => true;

  @override
  String get currentDisplayName => currentUser.displayName;

  @override
  Stream<AuthChange> get authChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
