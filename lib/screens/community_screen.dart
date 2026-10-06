import 'package:flutter/material.dart';

import '../app_state.dart';
import '../domain/community_feed.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';
import 'member_social_detail_screens.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({this.textOnly = false, super.key});

  final bool textOnly;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  static const _pageSize = 24;
  final _scroll = ScrollController();
  final List<CommunityPost> _posts = [];
  AppState? _state;
  int? _accountVersion;
  int _request = 0;
  int _offset = 0;
  bool _loading = true;
  bool _hasMore = false;
  bool _failed = false;
  bool _cached = false;
  bool _retryReset = true;
  CommunityFeedOrder _order = CommunityFeedOrder.latest;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_state == state &&
        _accountVersion == state.communityFeedAccountVersion) {
      return;
    }
    _state = state;
    _accountVersion = state.communityFeedAccountVersion;
    _request++;
    _posts.clear();
    _loading = true;
    _failed = false;
    _cached = false;
    _hasMore = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _request++;
    _scroll.dispose();
    super.dispose();
  }

  void _loadNearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 600 &&
        !_loading &&
        !_failed &&
        _hasMore) {
      _load(reset: false);
    }
  }

  Future<void> _load({bool reset = true, bool clear = false}) async {
    if (!mounted || _state == null || (!reset && _loading)) return;
    final request = ++_request;
    final account = _accountVersion;
    final state = _state!;
    setState(() {
      _loading = true;
      _failed = false;
      _retryReset = reset;
      if (clear) {
        _posts.clear();
        _cached = false;
        _hasMore = false;
      }
    });
    try {
      final page = await state.listCommunityFeed(
        order: _order,
        media: widget.textOnly
            ? CommunityFeedMedia.textOnly
            : CommunityFeedMedia.photos,
        limit: _pageSize,
        offset: reset ? 0 : _offset,
      );
      if (!mounted ||
          request != _request ||
          account != state.communityFeedAccountVersion) {
        return;
      }
      setState(() {
        if (reset) _posts.clear();
        final existing = _posts.map((post) => post.id).toSet();
        _posts.addAll(page.posts.where((post) => existing.add(post.id)));
        _offset = (reset ? 0 : _offset) + page.posts.length;
        _hasMore = page.hasMore && page.posts.isNotEmpty;
        _cached = reset ? page.isCached : _cached || page.isCached;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && request == _request) _loadNearEnd();
      });
    } catch (_) {
      if (!mounted ||
          request != _request ||
          account != state.communityFeedAccountVersion) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
        _retryReset = reset;
      });
    }
  }

  void _changeOrder(CommunityFeedOrder order) {
    if (_order == order) return;
    setState(() => _order = order);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(clear: true);
  }

  Future<void> _openPost(CommunityPost post) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CommunityPostDetailScreen(post: post)),
    );
    // Reactions already update this post. Keep the loaded pages and browsing
    // position on return; pull-to-refresh reloads the whole server ranking.
    if (mounted) {
      setState(() {
        _posts.removeWhere((post) => post.isDeleted);
        _posts.sort(_order.compare);
      });
    }
  }

  Future<void> _openTextPosts() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CommunityScreen(textOnly: true)),
    );
    if (mounted) await _load();
  }

  Future<void> _compose() async {
    if (!await requireSignIn(context, reason: AuthReason.community)) return;
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SocialPostComposerScreen()),
    );
    if (created == true && mounted) {
      AppSnackbar.success(context, '게시물을 등록했어요.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.textOnly ? '사진 없는 글' : '커뮤니티')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 240).floor().clamp(2, 6);
            return RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                key: ValueKey(
                  widget.textOnly
                      ? 'community-text-feed'
                      : 'community-photo-feed',
                ),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: SetflowInsets.pageHeader,
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        spacing: SetflowSpacing.sm,
                        runSpacing: SetflowSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final order in [
                            CommunityFeedOrder.popular,
                            CommunityFeedOrder.latest,
                          ])
                            ChoiceChip(
                              key: ValueKey('community-order-${order.name}'),
                              label: Text(
                                order == CommunityFeedOrder.popular
                                    ? '인기순'
                                    : '최신순',
                              ),
                              selected: _order == order,
                              onSelected: (_) => _changeOrder(order),
                            ),
                          if (!widget.textOnly)
                            TextButton(
                              key: const ValueKey('community-text-posts'),
                              onPressed: _openTextPosts,
                              child: const Text('사진 없는 글'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_loading && (_posts.isEmpty || _retryReset))
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (_posts.isNotEmpty &&
                      ((_cached && !_failed) || (_failed && _retryReset)))
                    SliverPadding(
                      padding: SetflowInsets.pageHeader,
                      sliver: SliverToBoxAdapter(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: SetflowSpacing.sm,
                          children: [
                            Text(
                              _cached
                                  ? '저장된 게시물을 보여드리고 있어요.'
                                  : '게시물을 더 불러오지 못했어요.',
                              style: theme.textTheme.bodySmall,
                            ),
                            TextButton(
                              onPressed: _loading ? null : _load,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_posts.isEmpty && !_loading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: _failed
                            ? SetflowIcons.cloudUnavailable
                            : SetflowIcons.gallery,
                        title: _failed
                            ? '게시물을 불러오지 못했어요'
                            : widget.textOnly
                            ? '아직 글이 없어요'
                            : '아직 사진이 없어요',
                        message: _failed
                            ? '연결을 확인하고 다시 시도해주세요.'
                            : widget.textOnly
                            ? '사진 없이 남긴 운동 이야기는 여기에 모여요.'
                            : '운동 사진을 공유해보세요. 사진 없는 글은 위에서 따로 볼 수 있어요.',
                        actionLabel: _failed ? '다시 시도' : '게시물 작성',
                        onAction: _failed ? _load : _compose,
                      ),
                    ),
                  if (_posts.isNotEmpty)
                    SliverPadding(
                      padding: SetflowInsets.pageHeader,
                      sliver: widget.textOnly
                          ? SliverList.builder(
                              itemCount: _posts.length,
                              itemBuilder: (_, index) {
                                final post = _posts[index];
                                return ListTile(
                                  key: ValueKey('community-text-${post.id}'),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: SetflowSpacing.sm,
                                  ),
                                  title: Text(
                                    post.content,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '${post.author} · 좋아요 ${post.likes}',
                                  ),
                                  onTap: () => _openPost(post),
                                );
                              },
                            )
                          : SliverGrid.builder(
                              itemCount: _posts.length,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: SetflowSpacing.xs,
                                    mainAxisSpacing: SetflowSpacing.xs,
                                    childAspectRatio: 3 / 4,
                                  ),
                              itemBuilder: (_, index) => _PhotoTile(
                                post: _posts[index],
                                onTap: () => _openPost(_posts[index]),
                              ),
                            ),
                    ),
                  if (_loading && !_retryReset)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (_posts.isNotEmpty && _failed && !_retryReset)
                    SliverPadding(
                      padding: SetflowInsets.pageHeader,
                      sliver: SliverToBoxAdapter(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: SetflowSpacing.sm,
                          children: [
                            Text(
                              '게시물을 더 불러오지 못했어요.',
                              style: theme.textTheme.bodySmall,
                            ),
                            TextButton(
                              onPressed: () => _load(reset: false),
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(
                      height: SetflowSpacing.page + SetflowSpacing.huge,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('community-compose'),
        heroTag: widget.textOnly
            ? 'community-text-compose-fab'
            : 'community-compose-fab',
        tooltip: '게시물 작성',
        onPressed: _compose,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(
          side: BorderSide(color: theme.colorScheme.onSurface),
        ),
        child: const Icon(SetflowIcons.addExercise),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.post, required this.onTap});

  final CommunityPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Semantics(
        key: ValueKey('community-photo-${post.id}'),
        button: true,
        label: '${post.author}의 사진 게시물, 좋아요 ${post.likes}개, 상세 보기',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SetflowRadii.xs),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: context.setflowColors.surfaceContainer),
              Image.network(
                post.imageUrl?.trim() ?? '',
                fit: BoxFit.cover,
                cacheWidth:
                    (constraints.maxWidth *
                            MediaQuery.devicePixelRatioOf(context))
                        .ceil(),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => Center(
                  child: Tooltip(
                    message: '사진을 불러오지 못했어요. 눌러서 게시물 보기',
                    child: Icon(
                      SetflowIcons.imageUnavailable,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
