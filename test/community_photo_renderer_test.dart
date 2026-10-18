import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:setflow/data/community_repository.dart';
import 'package:setflow/services/community_photo_renderer.dart';
import 'package:setflow/services/user_image_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Bold.otf'));
    await loader.load();
  });

  const smallRenderer = CanvasCommunityPhotoRenderer(outputDimension: 360);
  const allOverlays = CommunityPhotoOverlay(
    dateText: '10월 18일',
    timeText: '18:30',
    workoutText: '오늘 운동 완료',
  );

  test('disabled overlays preserve the original photo and MIME type', () async {
    final original = _whitePhoto(width: 480, height: 360);
    final result = await smallRenderer.render(
      media: original,
      overlay: const CommunityPhotoOverlay(
        dateText: '',
        timeText: ' ',
        workoutText: null,
      ),
    );

    expect(result, same(original));
    expect(result.bytes, same(original.bytes));
  });

  test(
    'posted photo contains selected labels and excludes editor controls',
    () async {
      final result = await const CanvasCommunityPhotoRenderer().render(
        media: _whitePhoto(),
        overlay: allOverlays,
      );
      final image = image_lib.decodeImage(result.bytes)!;
      final policy = UserImagePolicy.communityPost;

      expect(image.width, 1080);
      expect(image.height, 1080);
      expect(image.width, lessThanOrEqualTo(policy.maxDimension));
      expect(
        result.bytes.lengthInBytes,
        lessThanOrEqualTo(policy.maxOutputBytes),
      );
      expect(result.contentType, 'image/png');
      expect(result.fileName, endsWith('.png'));
      // Each label panel is baked into its corner of the actual image.
      expect(_red(image, 48, 84), lessThan(150));
      expect(_red(image, 1032, 84), lessThan(150));
      expect(_red(image, 48, 1002), lessThan(150));
      // The center has only the photo wash, never the '사진 변경' control.
      expect(_red(image, 540, 540), closeTo(224, 1));
    },
  );

  test(
    'each overlay selection independently controls uploaded pixels',
    () async {
      final choices = [
        const CommunityPhotoOverlay(dateText: '10월 18일'),
        const CommunityPhotoOverlay(timeText: '18:30'),
        const CommunityPhotoOverlay(workoutText: '오늘 운동 완료'),
      ];
      final panelPoints = [(16, 28), (344, 28), (16, 334)];
      final original = _whitePhoto();

      for (var selected = 0; selected < choices.length; selected++) {
        final media = await smallRenderer.render(
          media: original,
          overlay: choices[selected],
        );
        final image = image_lib.decodeImage(media.bytes)!;
        for (var corner = 0; corner < panelPoints.length; corner++) {
          final (x, y) = panelPoints[corner];
          expect(
            _red(image, x, y),
            corner == selected ? lessThan(150) : closeTo(224, 1),
            reason: 'selection $selected must only draw panel $selected',
          );
        }
      }
    },
  );

  for (final landscape in [true, false]) {
    test(
      'square upload center-crops ${landscape ? 'landscape' : 'portrait'} photo',
      () async {
        final source = image_lib.Image(
          width: landscape ? 720 : 360,
          height: landscape ? 360 : 720,
        );
        image_lib.fill(source, color: image_lib.ColorRgb8(0, 255, 0));
        image_lib.fillRect(
          source,
          x1: 0,
          y1: 0,
          x2: landscape ? 179 : 359,
          y2: landscape ? 359 : 179,
          color: image_lib.ColorRgb8(255, 0, 0),
        );
        image_lib.fillRect(
          source,
          x1: landscape ? 540 : 0,
          y1: landscape ? 0 : 540,
          x2: source.width - 1,
          y2: source.height - 1,
          color: image_lib.ColorRgb8(0, 0, 255),
        );

        final media = await smallRenderer.render(
          media: _media(image_lib.encodePng(source)),
          overlay: const CommunityPhotoOverlay(dateText: '10월 18일'),
        );
        final image = image_lib.decodeImage(media.bytes)!;
        expect(image.width, 360);
        expect(image.height, 360);
        for (final (x, y) in [(10, 180), (350, 180), (180, 10), (180, 350)]) {
          final pixel = image.getPixel(x, y);
          expect(pixel.r, closeTo(0, 1));
          expect(pixel.g, closeTo(224, 1));
          expect(pixel.b, closeTo(0, 1));
        }
      },
    );
  }

  test(
    'Korean labels use distinct Hangul glyphs in the posted photo',
    () async {
      final photo = _whitePhoto();
      final first = await smallRenderer.render(
        media: photo,
        overlay: const CommunityPhotoOverlay(workoutText: '가'),
      );
      final second = await smallRenderer.render(
        media: photo,
        overlay: const CommunityPhotoOverlay(workoutText: '나'),
      );

      // A missing font would draw the same replacement box for both syllables.
      expect(first.bytes, isNot(orderedEquals(second.bytes)));
    },
  );

  test(
    'damaged photo fails instead of posting an unmodified original',
    () async {
      await expectLater(
        smallRenderer.render(
          media: _media(Uint8List.fromList([1, 2, 3])),
          overlay: allOverlays,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            isNotEmpty,
          ),
        ),
      );
    },
  );
}

CommunityPostMedia _whitePhoto({int width = 360, int height = 360}) {
  final image = image_lib.Image(width: width, height: height);
  image_lib.fill(image, color: image_lib.ColorRgb8(255, 255, 255));
  return _media(image_lib.encodePng(image));
}

CommunityPostMedia _media(Uint8List bytes) => CommunityPostMedia(
  bytes: bytes,
  fileName: 'camera-photo.png',
  contentType: 'image/png',
);

num _red(image_lib.Image image, int x, int y) => image.getPixel(x, y).r;
