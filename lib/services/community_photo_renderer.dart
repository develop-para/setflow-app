import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/community_repository.dart';
import '../theme/tokens.dart';
import 'user_image_optimizer.dart';

/// The exact text visible in the draft, captured before asynchronous rendering.
@immutable
class CommunityPhotoOverlay {
  const CommunityPhotoOverlay({this.dateText, this.timeText, this.workoutText});

  final String? dateText;
  final String? timeText;
  final String? workoutText;

  bool get isEmpty =>
      !_hasText(dateText) && !_hasText(timeText) && !_hasText(workoutText);

  static bool _hasText(String? text) => text?.trim().isNotEmpty ?? false;
}

abstract interface class CommunityPhotoRenderer {
  Future<CommunityPostMedia> render({
    required CommunityPostMedia media,
    required CommunityPhotoOverlay overlay,
  });
}

/// Bakes the preview's crop and labels into upload bytes on the device.
///
/// This does not capture the widget tree: the preview may be outside the scroll
/// viewport, and editing controls must never become part of the posted photo.
class CanvasCommunityPhotoRenderer implements CommunityPhotoRenderer {
  const CanvasCommunityPhotoRenderer({this.outputDimension = 1080})
    : assert(outputDimension > 0 && outputDimension <= 1600);

  final int outputDimension;

  @override
  Future<CommunityPostMedia> render({
    required CommunityPostMedia media,
    required CommunityPhotoOverlay overlay,
  }) async {
    // With every overlay disabled, preserve the user's original photo.
    if (overlay.isEmpty) return media;
    if (outputDimension <= 0 ||
        outputDimension > UserImagePolicy.communityPost.maxDimension) {
      throw const FormatException('사진 크기가 올바르지 않습니다. 다시 시도해주세요.');
    }

    ui.Codec? codec;
    ui.Image? sourceImage;
    ui.PictureRecorder? recorder;
    ui.Picture? picture;
    ui.Image? renderedImage;
    try {
      const optimizer = UserImageOptimizer();
      final source = await optimizer.optimize(
        bytes: media.bytes,
        fileName: media.fileName,
        reportedContentType: media.contentType,
        purpose: UserImagePurpose.communityPost,
      );
      codec = await ui.instantiateImageCodec(source.bytes);
      sourceImage = (await codec.getNextFrame()).image;
      final size = Size.square(outputDimension.toDouble());
      recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final rect = Offset.zero & size;
      canvas.drawRect(rect, Paint()..color = Colors.white);
      paintImage(
        canvas: canvas,
        rect: rect,
        image: sourceImage,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      CommunityPhotoOverlayPainter(overlay).paint(canvas, size);
      picture = recorder.endRecording();
      renderedImage = await picture.toImage(outputDimension, outputDimension);
      final encoded = await renderedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (encoded == null) {
        throw const FormatException('사진에 오버레이를 저장하지 못했어요. 다시 시도해주세요.');
      }
      final optimized = await optimizer.optimize(
        bytes: encoded.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
        fileName: 'community-photo.png',
        reportedContentType: 'image/png',
        purpose: UserImagePurpose.communityPost,
      );
      return CommunityPostMedia(
        bytes: optimized.bytes,
        fileName: optimized.fileName,
        contentType: optimized.contentType,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('사진에 오버레이를 저장하지 못했어요. 사진을 다시 선택한 뒤 시도해주세요.');
    } finally {
      renderedImage?.dispose();
      picture?.dispose();
      if (recorder?.isRecording ?? false) {
        recorder!.endRecording().dispose();
      }
      sourceImage?.dispose();
      codec?.dispose();
    }
  }
}

/// Shared by the on-screen preview and exported photo. Scaling a fixed design
/// square keeps positions, glyph sizes and rounded panels identical in both.
class CommunityPhotoOverlayPainter extends CustomPainter {
  const CommunityPhotoOverlayPainter(this.overlay);

  static const _designSide = 360.0;
  final CommunityPhotoOverlay overlay;

  @override
  void paint(Canvas canvas, Size size) {
    if (overlay.isEmpty || size.isEmpty) return;
    canvas.save();
    try {
      canvas.scale(size.width / _designSide, size.height / _designSide);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _designSide, _designSide),
        Paint()..color = Colors.black.withValues(alpha: .12),
      );
      _paintLabel(canvas, overlay.dateText, Alignment.topLeft);
      _paintLabel(canvas, overlay.timeText, Alignment.topRight);
      _paintLabel(canvas, overlay.workoutText, Alignment.bottomLeft);
    } finally {
      canvas.restore();
    }
  }

  void _paintLabel(Canvas canvas, String? text, Alignment alignment) {
    if (!CommunityPhotoOverlay._hasText(text)) return;
    const margin = SetflowSpacing.md;
    const horizontalPadding = SetflowSpacing.sm;
    const verticalPadding = SetflowSpacing.xs2;
    final maxPanelWidth = alignment == Alignment.bottomLeft
        ? _designSide - 2 * margin
        : (_designSide - 3 * margin) / 2;
    final painter = TextPainter(
      text: TextSpan(
        text: text!.trim(),
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: SetflowFontSize.small,
          fontWeight: SetflowWeight.strong,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    try {
      painter.layout(maxWidth: maxPanelWidth - 2 * horizontalPadding);
      final panelSize = Size(
        painter.width + 2 * horizontalPadding,
        painter.height + 2 * verticalPadding,
      );
      final panelRect = alignment.inscribe(
        panelSize,
        const Rect.fromLTWH(
          margin,
          margin,
          _designSide - 2 * margin,
          _designSide - 2 * margin,
        ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          panelRect,
          const Radius.circular(SetflowRadii.sm),
        ),
        Paint()..color = Colors.black54,
      );
      painter.paint(
        canvas,
        panelRect.topLeft + const Offset(horizontalPadding, verticalPadding),
      );
    } finally {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(CommunityPhotoOverlayPainter oldDelegate) =>
      overlay.dateText != oldDelegate.overlay.dateText ||
      overlay.timeText != oldDelegate.overlay.timeText ||
      overlay.workoutText != oldDelegate.overlay.workoutText;
}
