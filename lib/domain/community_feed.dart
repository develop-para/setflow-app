import '../models.dart';

enum CommunityFeedOrder {
  latest,
  popular;

  int compare(CommunityPost a, CommunityPost b) {
    if (this == popular) {
      final likes = b.likes.compareTo(a.likes);
      if (likes != 0) return likes;
    }
    final date = b.createdAt.compareTo(a.createdAt);
    return date != 0 ? date : b.id.compareTo(a.id);
  }
}

enum CommunityFeedMedia {
  all,
  photos,
  textOnly;

  bool includes(CommunityPost post) {
    final hasPhoto = post.imageUrl?.trim().isNotEmpty ?? false;
    return switch (this) {
      all => true,
      photos => hasPhoto,
      textOnly => !hasPhoto,
    };
  }
}

class CommunityFeedPage {
  const CommunityFeedPage({
    required this.posts,
    required this.hasMore,
    this.isCached = false,
  });

  /// Applies the same query to a complete local collection, before paging.
  factory CommunityFeedPage.fromAllPosts(
    Iterable<CommunityPost> posts, {
    required CommunityFeedOrder order,
    required CommunityFeedMedia media,
    required int limit,
    required int offset,
  }) {
    final sorted = posts.where(media.includes).toList()..sort(order.compare);
    final page = sorted.skip(offset).take(limit).toList(growable: false);
    return CommunityFeedPage(
      posts: page,
      hasMore: offset + page.length < sorted.length,
    );
  }

  final List<CommunityPost> posts;
  final bool hasMore;
  final bool isCached;
}
