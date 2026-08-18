import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../data/community_repository.dart';
import 'user_image_optimizer.dart';

enum PostMediaSource { camera, gallery }

/// Injectable boundary used by AppState and widget tests.
abstract interface class PostMediaPicker {
  Future<CommunityPostMedia?> pick(PostMediaSource source);

  /// Recovers an image after Android recreates the app while the picker is
  /// open. Returns null on platforms that do not implement lost-data recovery.
  Future<CommunityPostMedia?> recoverLostImage();
}

/// Narrow adapter around the plugin so lost-data behavior can be faked in unit
/// tests without a platform channel.
abstract interface class ImagePickerGateway {
  Future<XFile?> pickImage({
    required ImageSource source,
    required double maxWidth,
    required double maxHeight,
    required int imageQuality,
    required bool requestFullMetadata,
  });

  Future<LostDataResponse> retrieveLostData();
}

class PluginImagePickerGateway implements ImagePickerGateway {
  PluginImagePickerGateway([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    required double maxWidth,
    required double maxHeight,
    required int imageQuality,
    required bool requestFullMetadata,
  }) {
    return _picker.pickImage(
      source: source,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
      requestFullMetadata: requestFullMetadata,
    );
  }

  @override
  Future<LostDataResponse> retrieveLostData() => _picker.retrieveLostData();
}

class ImagePickerPostMediaPicker implements PostMediaPicker {
  ImagePickerPostMediaPicker({
    ImagePickerGateway? gateway,
    this._optimizer = const UserImageOptimizer(),
  }) : _gateway = gateway ?? PluginImagePickerGateway();

  static const maxDimension = 1600.0;
  static const imageQuality = 82;

  final ImagePickerGateway _gateway;
  final UserImageOptimizer _optimizer;

  @override
  Future<CommunityPostMedia?> pick(PostMediaSource source) async {
    final file = await _gateway.pickImage(
      source: source == PostMediaSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: imageQuality,
      requestFullMetadata: false,
    );
    return file == null ? null : _read(file);
  }

  @override
  Future<CommunityPostMedia?> recoverLostImage() async {
    if (kIsWeb) return null;
    LostDataResponse response;
    try {
      response = await _gateway.retrieveLostData();
    } on UnimplementedError {
      return null;
    }
    if (response.isEmpty) return null;
    if (response.exception != null) throw response.exception!;
    if (response.type == RetrieveType.video) return null;

    final file =
        response.file ??
        ((response.files?.isNotEmpty ?? false) ? response.files!.first : null);
    return file == null ? null : _read(file);
  }

  Future<CommunityPostMedia> _read(XFile file) async {
    final Uint8List bytes = await file.readAsBytes();
    final fileName = file.name.trim().isEmpty ? 'post-image.jpg' : file.name;
    final optimized = await _optimizer.optimize(
      bytes: bytes,
      fileName: fileName,
      reportedContentType: _imageContentType(file.mimeType, fileName),
      purpose: UserImagePurpose.communityPost,
    );
    return CommunityPostMedia(
      bytes: optimized.bytes,
      fileName: optimized.fileName,
      contentType: optimized.contentType,
    );
  }

  static String _imageContentType(String? reportedType, String fileName) {
    final normalizedType = reportedType?.trim().toLowerCase();
    if (normalizedType != null && normalizedType.startsWith('image/')) {
      return normalizedType;
    }

    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }
}
