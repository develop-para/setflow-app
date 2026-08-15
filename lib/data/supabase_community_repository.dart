import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'community_repository.dart';

class SupabaseCommunityRepository implements CommunityRepository {
  SupabaseCommunityRepository(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _postsTable = 'posts';
  static const _commentsTable = 'comments';
  static const _likesTable = 'post_likes';
  static const _imageBucket = 'post-images';
  static const _maxImageBytes = 6 * 1024 * 1024;
  static const _allowedImageTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
    'image/heif',
  };
  static const _postColumns =
      'id,user_id,author_name,content,metric,visual_key,image_url,'
      'image_color,location,routine_name,active_overlays,likes_count,created_at';

  final SupabaseClient _client;
  final DateTime Function() _now;
  int _uploadSequence = 0;

  @override
  Future<List<CommunityPostRecord>> fetchPosts({
    int limit = 50,
    int offset = 0,
  }) async {
    final safeLimit = limit.clamp(1, 100);
    final safeOffset = offset < 0 ? 0 : offset;
    final user = _requireUser();
    final postRows = await _client
        .from(_postsTable)
        .select(_postColumns)
        .order('created_at', ascending: false)
        .range(safeOffset, safeOffset + safeLimit - 1);

    if (postRows.isEmpty) return const [];

    final postIds = postRows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList(growable: false);

    final commentRows = await _client
        .from(_commentsTable)
        .select('id,post_id,user_id,author_name,text,created_at')
        .inFilter('post_id', postIds)
        .order('created_at', ascending: true);

    final likeRows = await _client
        .from(_likesTable)
        .select('post_id')
        .eq('user_id', user.id)
        .inFilter('post_id', postIds);
    final likedPostIds = likeRows
        .map((row) => row['post_id']?.toString())
        .whereType<String>()
        .toSet();

    final commentsByPost = <String, List<PostComment>>{};
    for (final row in commentRows) {
      final postId = row['post_id']?.toString();
      if (postId == null) continue;
      final commentUserId = row['user_id']?.toString();
      final authorName = _displayName(
        row['author_name'],
        isMine: commentUserId == user.id,
        currentUser: user,
      );
      commentsByPost
          .putIfAbsent(postId, () => [])
          .add(
            PostComment(
              id: row['id']?.toString() ?? '',
              author: authorName,
              content: row['text']?.toString() ?? '',
              createdAt: _dateTime(row['created_at']),
            ),
          );
    }

    return postRows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          final authorUserId = row['user_id']?.toString() ?? '';
          final isMine = authorUserId == user.id;
          final imageUrl = _nullableText(row['image_url']);
          final colorValue = _parseColorValue(row['image_color']);
          final overlays = _stringList(row['active_overlays']);

          return CommunityPostRecord(
            post: CommunityPost(
              id: id,
              author: _displayName(
                row['author_name'],
                isMine: isMine,
                currentUser: user,
              ),
              content: row['content']?.toString() ?? '',
              metric: _nullableText(row['metric']) ?? '일상 기록',
              createdAt: _dateTime(row['created_at']),
              visualKey: _nullableText(row['visual_key']) ?? 'strength',
              color: Color(colorValue),
              likes: _integer(row['likes_count']),
              isLiked: likedPostIds.contains(id),
              isMine: isMine,
              imageUrl: imageUrl,
              location: _nullableText(row['location']),
              routineName: _nullableText(row['routine_name']),
              activeOverlays: overlays,
              comments: commentsByPost[id] ?? const [],
            ),
            authorUserId: authorUserId,
            imageUrl: imageUrl,
            imageStoragePath: _storagePathFromPublicUrl(imageUrl),
            location: _nullableText(row['location']),
            routineName: _nullableText(row['routine_name']),
            activeOverlays: overlays,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<CommunityPostRecord> createPost(CreateCommunityPostInput input) async {
    final user = _requireUser();
    final content = input.content.trim();
    if (content.isEmpty && input.media == null) {
      throw const CommunityValidationException('글 또는 사진을 추가해 주세요.');
    }

    final uploadedImage = input.media == null
        ? null
        : await _uploadPostImage(user.id, input.media!);
    final authorName = await _currentAuthorName(user);
    late final Map<String, dynamic> row;
    try {
      row = await _client
          .from(_postsTable)
          .insert({
            'user_id': user.id,
            'author_name': authorName,
            'content': content.isEmpty ? null : content,
            'metric': input.metric.trim().isEmpty
                ? '일상 기록'
                : input.metric.trim(),
            'visual_key': input.visualKey.trim().isEmpty
                ? 'strength'
                : input.visualKey.trim(),
            'image_url': uploadedImage?.publicUrl,
            'image_color': _colorHex(input.colorValue),
            'location': _nullableTrimmed(input.location),
            'routine_name': _nullableTrimmed(input.routineName),
            'active_overlays': input.activeOverlays,
          })
          .select(_postColumns)
          .single();
    } catch (error, stackTrace) {
      if (uploadedImage != null) {
        try {
          await _client.storage.from(_imageBucket).remove([
            uploadedImage.storagePath,
          ]);
        } catch (_) {
          // Preserve the database failure; orphan cleanup can be retried by an
          // operational job without hiding the cause shown to the user.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    return _recordFromCreatedRow(
      row,
      currentUser: user,
      imageStoragePath: uploadedImage?.storagePath,
    );
  }

  @override
  Future<CommunityLikeResult> toggleLike(String postId) async {
    final user = _requireUser();
    final normalizedPostId = postId.trim();
    if (normalizedPostId.isEmpty) {
      throw const CommunityValidationException('게시물을 찾을 수 없습니다.');
    }

    final existing = await _client
        .from(_likesTable)
        .select('post_id')
        .eq('post_id', normalizedPostId)
        .eq('user_id', user.id)
        .maybeSingle();

    final isLiked = existing == null;
    if (isLiked) {
      try {
        await _client.from(_likesTable).insert({
          'post_id': normalizedPostId,
          'user_id': user.id,
        });
      } on PostgrestException catch (error) {
        // A repeated tap can race with the first INSERT. The unique key means
        // the desired final state (liked) is already present.
        if (error.code != '23505') rethrow;
      }
    } else {
      await _client
          .from(_likesTable)
          .delete()
          .eq('post_id', normalizedPostId)
          .eq('user_id', user.id);
    }

    final post = await _client
        .from(_postsTable)
        .select('likes_count')
        .eq('id', normalizedPostId)
        .maybeSingle();
    return CommunityLikeResult(
      isLiked: isLiked,
      likesCount: _integer(post?['likes_count']),
    );
  }

  @override
  Future<PostComment> addComment({
    required String postId,
    required String content,
  }) async {
    final user = _requireUser();
    final normalizedPostId = postId.trim();
    final normalizedContent = content.trim();
    if (normalizedPostId.isEmpty || normalizedContent.isEmpty) {
      throw const CommunityValidationException('댓글 내용을 입력해 주세요.');
    }

    final row = await _client
        .from(_commentsTable)
        .insert({
          'post_id': normalizedPostId,
          'user_id': user.id,
          'author_name': await _currentAuthorName(user),
          'text': normalizedContent,
        })
        .select('id,author_name,text,created_at')
        .single();

    return PostComment(
      id: row['id']?.toString() ?? '',
      author: _displayName(row['author_name'], isMine: true, currentUser: user),
      content: row['text']?.toString() ?? normalizedContent,
      createdAt: _dateTime(row['created_at']),
    );
  }

  Future<UploadedPostImage> _uploadPostImage(
    String userId,
    CommunityPostMedia media,
  ) async {
    if (media.bytes.isEmpty) {
      throw const CommunityValidationException('선택한 사진이 비어 있습니다.');
    }
    if (media.bytes.lengthInBytes > _maxImageBytes) {
      throw const CommunityValidationException('사진은 6MB 이하만 업로드할 수 있습니다.');
    }
    final contentType = media.contentType.trim().toLowerCase();
    if (!_allowedImageTypes.contains(contentType)) {
      throw const CommunityValidationException(
        'JPG, PNG, WebP, HEIC 이미지만 업로드할 수 있습니다.',
      );
    }

    final extension = _safeExtension(contentType);
    final timestamp = _now().toUtc().microsecondsSinceEpoch;
    final sequence = _uploadSequence++;
    final storagePath = '$userId/${timestamp}_$sequence.$extension';
    final bucket = _client.storage.from(_imageBucket);
    await bucket.uploadBinary(
      storagePath,
      media.bytes,
      fileOptions: FileOptions(
        cacheControl: '3600',
        upsert: false,
        contentType: contentType,
      ),
    );

    return UploadedPostImage(
      storagePath: storagePath,
      publicUrl: bucket.getPublicUrl(storagePath),
    );
  }

  CommunityPostRecord _recordFromCreatedRow(
    Map<String, dynamic> row, {
    required User currentUser,
    String? imageStoragePath,
  }) {
    final imageUrl = _nullableText(row['image_url']);
    return CommunityPostRecord(
      post: CommunityPost(
        id: row['id']?.toString() ?? '',
        author: _displayName(
          row['author_name'],
          isMine: true,
          currentUser: currentUser,
        ),
        content: row['content']?.toString() ?? '',
        metric: _nullableText(row['metric']) ?? '일상 기록',
        createdAt: _dateTime(row['created_at']),
        visualKey: _nullableText(row['visual_key']) ?? 'strength',
        color: Color(_parseColorValue(row['image_color'])),
        likes: _integer(row['likes_count']),
        isMine: true,
        imageUrl: imageUrl,
        location: _nullableText(row['location']),
        routineName: _nullableText(row['routine_name']),
        activeOverlays: _stringList(row['active_overlays']),
      ),
      authorUserId: currentUser.id,
      imageUrl: imageUrl,
      imageStoragePath: imageStoragePath ?? _storagePathFromPublicUrl(imageUrl),
      location: _nullableText(row['location']),
      routineName: _nullableText(row['routine_name']),
      activeOverlays: _stringList(row['active_overlays']),
    );
  }

  User _requireUser() {
    final user = _client.auth.currentUser;
    if (user == null) throw const CommunityAuthenticationRequired();
    return user;
  }

  Future<String> _currentAuthorName(User user) async {
    final metadataName = _firstNonEmpty([
      user.userMetadata?['nickname'],
      user.userMetadata?['name'],
      user.userMetadata?['full_name'],
    ]);
    if (metadataName != null) return metadataName;

    try {
      final row = await _client
          .from('users')
          .select('nickname')
          .eq('id', user.id)
          .maybeSingle();
      final nickname = _nullableText(row?['nickname']);
      if (nickname != null) return nickname;
    } catch (_) {
      // A missing optional profile must not prevent a user from posting.
    }
    return '회원';
  }

  static String _displayName(
    dynamic storedName, {
    required bool isMine,
    required User? currentUser,
  }) {
    final stored = _nullableText(storedName);
    if (stored != null) return stored;
    if (isMine && currentUser != null) {
      return _firstNonEmpty([
            currentUser.userMetadata?['nickname'],
            currentUser.userMetadata?['name'],
            currentUser.userMetadata?['full_name'],
          ]) ??
          '회원';
    }
    return '회원';
  }

  static String? _storagePathFromPublicUrl(String? url) {
    if (url == null) return null;
    const marker = '/object/public/$_imageBucket/';
    final markerIndex = url.indexOf(marker);
    if (markerIndex < 0) return null;
    final encodedPath = url
        .substring(markerIndex + marker.length)
        .split('?')
        .first;
    if (encodedPath.isEmpty) return null;
    return encodedPath.split('/').map(Uri.decodeComponent).join('/');
  }

  static String _safeExtension(String contentType) {
    // Content-Type is validated before this method, so derive the stored
    // extension from it rather than trusting a user-controlled file name.
    return switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
  }

  static int _parseColorValue(dynamic raw) {
    final value = _nullableText(raw);
    if (value == null) return 0xFF10CEBD;
    var normalized = value.replaceFirst('#', '').replaceFirst('0x', '');
    if (normalized.length == 6) normalized = 'FF$normalized';
    return int.tryParse(normalized, radix: 16) ?? 0xFF10CEBD;
  }

  static String _colorHex(int value) =>
      '#${value.toUnsigned(32).toRadixString(16).padLeft(8, '0').toUpperCase()}';

  static int _integer(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static DateTime _dateTime(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return (parsed ?? DateTime.now()).toLocal();
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString().trim())
        .whereType<String>()
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String? _nullableText(dynamic raw) {
    final value = raw?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? _nullableTrimmed(String? raw) => _nullableText(raw);

  static String? _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final normalized = _nullableText(value);
      if (normalized != null) return normalized;
    }
    return null;
  }
}

class UploadedPostImage {
  const UploadedPostImage({required this.storagePath, required this.publicUrl});

  final String storagePath;
  final String publicUrl;
}
