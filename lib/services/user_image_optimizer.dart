import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image_lib;

/// Upload-specific limits. Pickers and repositories use the same policy so a
/// forged or stale picker result cannot bypass validation at the Storage edge.
enum UserImagePurpose { communityPost, trainerDocument }

class UserImagePolicy {
  const UserImagePolicy({
    required this.maxDimension,
    required this.maxOutputBytes,
    required this.maxSourceBytes,
    required this.maxSourcePixels,
    required this.startQuality,
    required this.minimumQuality,
    required this.minimumDimension,
    required this.preserveChromaDetail,
  });

  static const communityPost = UserImagePolicy(
    maxDimension: 1600,
    maxOutputBytes: 2 * 1024 * 1024,
    maxSourceBytes: 24 * 1024 * 1024,
    maxSourcePixels: 40 * 1000 * 1000,
    startQuality: 82,
    minimumQuality: 68,
    minimumDimension: 720,
    preserveChromaDetail: false,
  );

  /// Documents retain more pixels and a higher JPEG floor so small print and
  /// certificate numbers remain readable after upload.
  static const trainerDocument = UserImagePolicy(
    maxDimension: 2400,
    maxOutputBytes: 4 * 1024 * 1024,
    maxSourceBytes: 32 * 1024 * 1024,
    maxSourcePixels: 50 * 1000 * 1000,
    startQuality: 90,
    minimumQuality: 76,
    minimumDimension: 1400,
    preserveChromaDetail: true,
  );

  final int maxDimension;
  final int maxOutputBytes;
  final int maxSourceBytes;
  final int maxSourcePixels;
  final int startQuality;
  final int minimumQuality;
  final int minimumDimension;
  final bool preserveChromaDetail;

  static UserImagePolicy forPurpose(UserImagePurpose purpose) =>
      switch (purpose) {
        UserImagePurpose.communityPost => communityPost,
        UserImagePurpose.trainerDocument => trainerDocument,
      };
}

class OptimizedUserImage {
  const OptimizedUserImage({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.width,
    required this.height,
    required this.wasOptimized,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final int width;
  final int height;
  final bool wasOptimized;
}

class UserImageOptimizationException implements FormatException {
  const UserImageOptimizationException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => message;
}

class UserImageOptimizer {
  const UserImageOptimizer();

  /// Runs the CPU-heavy codec work outside the UI isolate where supported.
  /// Flutter web executes [compute] on the main event loop, but uses the same
  /// pure-Dart codec and therefore produces the same validated bytes.
  Future<OptimizedUserImage> optimize({
    required Uint8List bytes,
    required String fileName,
    required String? reportedContentType,
    required UserImagePurpose purpose,
  }) => compute(
    _optimizeUserImage,
    _OptimizationRequest(
      bytes: bytes,
      fileName: fileName,
      reportedContentType: reportedContentType,
      policy: UserImagePolicy.forPurpose(purpose),
    ),
  );
}

class _OptimizationRequest {
  const _OptimizationRequest({
    required this.bytes,
    required this.fileName,
    required this.reportedContentType,
    required this.policy,
  });

  final Uint8List bytes;
  final String fileName;
  final String? reportedContentType;
  final UserImagePolicy policy;
}

OptimizedUserImage _optimizeUserImage(_OptimizationRequest request) {
  final bytes = request.bytes;
  final policy = request.policy;
  if (bytes.isEmpty) {
    throw const UserImageOptimizationException('선택한 이미지가 비어 있습니다.');
  }
  if (bytes.lengthInBytes > policy.maxSourceBytes) {
    throw UserImageOptimizationException(
      '원본 이미지는 ${policy.maxSourceBytes ~/ (1024 * 1024)}MB 이하여야 합니다.',
    );
  }

  image_lib.Decoder? decoder;
  try {
    decoder = image_lib.findDecoderForData(bytes);
  } catch (_) {
    decoder = null;
  }
  final detected = decoder == null ? null : _detectedType(decoder.format);
  if (decoder == null || detected == null) {
    throw const UserImageOptimizationException(
      '손상되지 않은 JPG, PNG 또는 WebP 이미지만 사용할 수 있습니다.',
    );
  }

  image_lib.DecodeInfo? info;
  try {
    info = decoder.startDecode(bytes);
  } catch (_) {
    info = null;
  }
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const UserImageOptimizationException('이미지 크기를 확인할 수 없습니다.');
  }
  if (info.width * info.height > policy.maxSourcePixels) {
    throw UserImageOptimizationException(
      '이미지 해상도가 너무 큽니다. '
      '${policy.maxSourcePixels ~/ 1000000}MP 이하 이미지를 선택해주세요.',
    );
  }

  image_lib.Image? decoded;
  try {
    decoded = decoder.decode(bytes, frame: 0);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    throw const UserImageOptimizationException('이미지가 손상되어 열 수 없습니다.');
  }

  final safeOriginalName = _safeFileName(request.fileName, detected.extension);
  final reported = request.reportedContentType?.trim().toLowerCase();
  final withinDimension =
      decoded.width <= policy.maxDimension &&
      decoded.height <= policy.maxDimension;
  final withinBytes = bytes.lengthInBytes <= policy.maxOutputBytes;

  // Preserve already-small images byte-for-byte. MIME and extension still
  // come from the decoded signature, never from a user-controlled filename.
  if (withinDimension && withinBytes) {
    return OptimizedUserImage(
      bytes: bytes,
      fileName: safeOriginalName,
      contentType: detected.contentType,
      width: decoded.width,
      height: decoded.height,
      wasOptimized:
          reported != null &&
          reported.isNotEmpty &&
          reported != detected.contentType,
    );
  }

  var working = decoded;
  final longestSide = math.max(working.width, working.height);
  if (longestSide > policy.maxDimension) {
    final scale = policy.maxDimension / longestSide;
    working = image_lib.copyResize(
      working,
      width: math.max(1, (working.width * scale).round()),
      height: math.max(1, (working.height * scale).round()),
      interpolation: image_lib.Interpolation.average,
    );
  }
  working = _flattenTransparency(working);

  while (true) {
    for (
      var quality = policy.startQuality;
      quality >= policy.minimumQuality;
      quality -= 4
    ) {
      final encoded = image_lib.encodeJpg(
        working,
        quality: quality,
        chroma: policy.preserveChromaDetail
            ? image_lib.JpegChroma.yuv444
            : image_lib.JpegChroma.yuv420,
      );
      if (encoded.lengthInBytes <= policy.maxOutputBytes) {
        return OptimizedUserImage(
          bytes: encoded,
          fileName: _safeFileName(request.fileName, 'jpg'),
          contentType: 'image/jpeg',
          width: working.width,
          height: working.height,
          wasOptimized: true,
        );
      }
    }

    final longest = math.max(working.width, working.height);
    if (longest <= policy.minimumDimension) break;
    final nextLongest = math.max(
      policy.minimumDimension,
      (longest * .85).floor(),
    );
    final scale = nextLongest / longest;
    final nextWidth = math.max(1, (working.width * scale).round());
    final nextHeight = math.max(1, (working.height * scale).round());
    if (nextWidth == working.width && nextHeight == working.height) break;
    working = image_lib.copyResize(
      working,
      width: nextWidth,
      height: nextHeight,
      interpolation: image_lib.Interpolation.average,
    );
  }

  throw UserImageOptimizationException(
    '이미지를 ${policy.maxOutputBytes ~/ (1024 * 1024)}MB 이하로 줄일 수 없습니다.',
  );
}

image_lib.Image _flattenTransparency(image_lib.Image source) {
  if (!source.hasAlpha) return source;
  final background = image_lib.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  );
  image_lib.fill(background, color: image_lib.ColorRgb8(255, 255, 255));
  return image_lib.compositeImage(background, source);
}

({String contentType, String extension})? _detectedType(
  image_lib.ImageFormat format,
) => switch (format) {
  // image_picker receives maxWidth/maxHeight/imageQuality in every app path;
  // its iOS/Android implementations convert HEIC/HEIF to JPEG before this
  // byte-level boundary. Raw HEIC that bypasses the picker stays fail-closed
  // because the cross-platform Dart codec cannot validate its pixels safely.
  image_lib.ImageFormat.jpg => (contentType: 'image/jpeg', extension: 'jpg'),
  image_lib.ImageFormat.png => (contentType: 'image/png', extension: 'png'),
  image_lib.ImageFormat.webp => (contentType: 'image/webp', extension: 'webp'),
  _ => null,
};

String _safeFileName(String raw, String extension) {
  var name = raw.trim().replaceAll('\\', '/').split('/').last;
  if (name.isEmpty) name = 'image';
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name
      .replaceAll(RegExp(r'[^a-zA-Z0-9가-힣_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  if (name.isEmpty) name = 'image';
  if (name.length > 72) name = name.substring(0, 72);
  return '$name.$extension';
}
