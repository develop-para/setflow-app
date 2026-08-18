import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:setflow/services/post_media_picker.dart';
import 'package:setflow/services/user_image_optimizer.dart';

void main() {
  const optimizer = UserImageOptimizer();

  test('small valid image passes through without changing its bytes', () async {
    final source = image_lib.Image(width: 64, height: 48);
    image_lib.fill(source, color: image_lib.ColorRgb8(16, 206, 189));
    final bytes = image_lib.encodePng(source);

    final result = await optimizer.optimize(
      bytes: bytes,
      fileName: r'C:\camera\workout.png',
      reportedContentType: 'image/png',
      purpose: UserImagePurpose.communityPost,
    );

    expect(result.bytes, orderedEquals(bytes));
    expect(result.fileName, 'workout.png');
    expect(result.contentType, 'image/png');
    expect(result.width, 64);
    expect(result.height, 48);
    expect(result.wasOptimized, isFalse);
  });

  test(
    'large community image is deterministically downsized to policy',
    () async {
      final source = image_lib.Image(width: 2400, height: 1800);
      image_lib.fill(source, color: image_lib.ColorRgb8(245, 180, 32));
      final bytes = image_lib.encodePng(source);

      final first = await optimizer.optimize(
        bytes: bytes,
        fileName: 'large-workout.png',
        reportedContentType: 'image/png',
        purpose: UserImagePurpose.communityPost,
      );
      final second = await optimizer.optimize(
        bytes: bytes,
        fileName: 'large-workout.png',
        reportedContentType: 'image/png',
        purpose: UserImagePurpose.communityPost,
      );
      final decoded = image_lib.decodeJpg(first.bytes);

      expect(first.wasOptimized, isTrue);
      expect(first.contentType, 'image/jpeg');
      expect(first.fileName, 'large-workout.jpg');
      expect(max(first.width, first.height), lessThanOrEqualTo(1600));
      expect(first.bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
      expect(decoded, isNotNull);
      expect(decoded!.width, first.width);
      expect(decoded.height, first.height);
      expect(second.bytes, orderedEquals(first.bytes));
    },
  );

  test(
    'oversized encoded bytes are compressed even within pixel bounds',
    () async {
      var source = image_lib.Image(width: 1200, height: 1200);
      source = image_lib.noise(
        source,
        255,
        type: image_lib.NoiseType.uniform,
        random: Random(8275),
      );
      final bytes = image_lib.encodePng(source, level: 0);
      expect(bytes.length, greaterThan(2 * 1024 * 1024));

      final result = await optimizer.optimize(
        bytes: bytes,
        fileName: 'noisy.png',
        reportedContentType: 'image/png',
        purpose: UserImagePurpose.communityPost,
      );

      expect(result.wasOptimized, isTrue);
      expect(result.contentType, 'image/jpeg');
      expect(result.bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
    },
  );

  test('trainer documents keep the higher legibility resolution', () async {
    final source = image_lib.Image(width: 3000, height: 2000);
    image_lib.fill(source, color: image_lib.ColorRgb8(252, 252, 252));
    final bytes = image_lib.encodePng(source);

    final result = await optimizer.optimize(
      bytes: bytes,
      fileName: 'certificate.png',
      reportedContentType: 'image/png',
      purpose: UserImagePurpose.trainerDocument,
    );

    expect(result.width, 2400);
    expect(result.height, 1600);
    expect(result.bytes.length, lessThanOrEqualTo(4 * 1024 * 1024));
    expect(result.contentType, 'image/jpeg');
  });

  test('actual signature corrects a forged MIME and extension', () async {
    final source = image_lib.Image(width: 20, height: 20);
    final bytes = image_lib.encodePng(source);

    final result = await optimizer.optimize(
      bytes: bytes,
      fileName: 'not-really-a-jpeg.jpg',
      reportedContentType: 'image/jpeg',
      purpose: UserImagePurpose.communityPost,
    );

    expect(result.bytes, orderedEquals(bytes));
    expect(result.contentType, 'image/png');
    expect(result.fileName, 'not-really-a-jpeg.png');
    expect(result.wasOptimized, isTrue);
  });

  test('invalid image bytes are rejected before upload', () async {
    await expectLater(
      optimizer.optimize(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        fileName: 'broken.jpg',
        reportedContentType: 'image/jpeg',
        purpose: UserImagePurpose.communityPost,
      ),
      throwsA(isA<UserImageOptimizationException>()),
    );
  });

  test('post picker exposes optimized bytes to the composer preview', () async {
    final source = image_lib.Image(width: 2200, height: 1800);
    image_lib.fill(source, color: image_lib.ColorRgb8(30, 40, 50));
    final original = image_lib.encodePng(source);
    final picker = ImagePickerPostMediaPicker(
      gateway: _StaticImageGateway(
        XFile.fromData(original, name: 'camera.png', mimeType: 'image/png'),
      ),
    );

    final media = await picker.pick(PostMediaSource.gallery);
    final previewImage = image_lib.decodeImage(media!.bytes);

    expect(media.contentType, 'image/jpeg');
    expect(media.fileName, endsWith('.jpg'));
    expect(media.bytes.length, lessThanOrEqualTo(2 * 1024 * 1024));
    expect(previewImage, isNotNull);
    expect(
      max(previewImage!.width, previewImage.height),
      lessThanOrEqualTo(1600),
    );
  });
}

class _StaticImageGateway implements ImagePickerGateway {
  const _StaticImageGateway(this.file);

  final XFile file;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    required double maxWidth,
    required double maxHeight,
    required int imageQuality,
    required bool requestFullMetadata,
  }) async => file;

  @override
  Future<LostDataResponse> retrieveLostData() => throw UnimplementedError();
}
