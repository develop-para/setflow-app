import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'post_media_picker.dart';
import 'user_image_optimizer.dart';

enum TrainerDocumentSource { camera, gallery }

class PickedTrainerDocument {
  const PickedTrainerDocument({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

abstract interface class TrainerDocumentPicker {
  Future<PickedTrainerDocument?> pick(TrainerDocumentSource source);
}

/// Uses XFile bytes instead of dart:io File so the same path works on Android,
/// iOS and web. Server-side Storage validation remains authoritative.
class ImagePickerTrainerDocumentPicker implements TrainerDocumentPicker {
  ImagePickerTrainerDocumentPicker({
    ImagePickerGateway? gateway,
    this._optimizer = const UserImageOptimizer(),
  }) : _gateway = gateway ?? PluginImagePickerGateway();

  static const maxDimension = 2400.0;
  static const imageQuality = 88;

  final ImagePickerGateway _gateway;
  final UserImageOptimizer _optimizer;

  @override
  Future<PickedTrainerDocument?> pick(TrainerDocumentSource source) async {
    final file = await _gateway.pickImage(
      source: source == TrainerDocumentSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: imageQuality,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final fileName = file.name.trim().isEmpty ? 'document.jpg' : file.name;
    final optimized = await _optimizer.optimize(
      bytes: bytes,
      fileName: fileName,
      reportedContentType: _reportedContentType(file.mimeType, fileName),
      purpose: UserImagePurpose.trainerDocument,
    );
    return PickedTrainerDocument(
      bytes: optimized.bytes,
      fileName: optimized.fileName,
      contentType: optimized.contentType,
    );
  }

  static String? _reportedContentType(String? reportedType, String fileName) {
    final normalized = reportedType?.trim().toLowerCase();
    if (normalized != null && normalized.isNotEmpty) return normalized;
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => null,
    };
  }
}
