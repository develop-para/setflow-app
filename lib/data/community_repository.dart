import 'dart:typed_data';

import '../models.dart';

/// A byte-based image selected for a community post.
///
/// Keeping media in memory lets the same flow work on mobile and web without
/// depending on `dart:io` paths that may disappear between app launches.
class CommunityPostMedia {
  const CommunityPostMedia({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

class CreateCommunityPostInput {
  const CreateCommunityPostInput({
    required this.content,
    this.metric = '일상 기록',
    this.visualKey = 'strength',
    this.colorValue = 0xFF10CEBD,
    this.media,
    this.location,
    this.routineName,
    this.activeOverlays = const [],
  });

  final String content;
  final String metric;
  final String visualKey;

  /// ARGB color value used by [CommunityPost.color].
  final int colorValue;
  final CommunityPostMedia? media;
  final String? location;
  final String? routineName;
  final List<String> activeOverlays;
}

/// Community-specific fields that are intentionally not part of the legacy
/// [CommunityPost] snapshot model yet.
class CommunityPostRecord {
  const CommunityPostRecord({
    required this.post,
    required this.authorUserId,
    this.imageUrl,
    this.imageStoragePath,
    this.location,
    this.routineName,
    this.activeOverlays = const [],
  });

  final CommunityPost post;
  final String authorUserId;
  final String? imageUrl;

  /// Present for a newly uploaded image (and when a public URL can be decoded).
  /// The database stores the public URL; this path is retained for cleanup.
  final String? imageStoragePath;
  final String? location;
  final String? routineName;
  final List<String> activeOverlays;
}

class CommunityLikeResult {
  const CommunityLikeResult({required this.isLiked, required this.likesCount});

  final bool isLiked;
  final int likesCount;
}

class CommunityAuthenticationRequired implements Exception {
  const CommunityAuthenticationRequired();

  @override
  String toString() => '커뮤니티 기능은 로그인 후 이용할 수 있습니다.';
}

class CommunityValidationException implements Exception {
  const CommunityValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class CommunityRepository {
  /// Loads shared posts/comments, plus the caller's own like rows when there
  /// is a session. Readable without an account — the feed is a browse surface,
  /// not an account feature, so a guest gets the posts with the "liked by me"
  /// overlay left off.
  Future<List<CommunityPostRecord>> fetchPosts({
    int limit = 50,
    int offset = 0,
  });

  /// Uploads [CreateCommunityPostInput.media], when present, and inserts the
  /// post. An uploaded object is removed if the database insert fails.
  Future<CommunityPostRecord> createPost(CreateCommunityPostInput input);

  /// Toggles only the authenticated user's like for [postId].
  Future<CommunityLikeResult> toggleLike(String postId);

  Future<PostComment> addComment({
    required String postId,
    required String content,
  });
}
