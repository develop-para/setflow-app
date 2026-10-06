import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../domain/gym_directory.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/auth_gate.dart';
import '../widgets/common.dart';

/// Browsing and saving a public place work before signing in.
class GymDirectoryScreen extends StatefulWidget {
  const GymDirectoryScreen({super.key});

  @override
  State<GymDirectoryScreen> createState() => _GymDirectoryScreenState();
}

class _GymDirectoryScreenState extends State<GymDirectoryScreen> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Future<GymDirectoryCatalog>? _catalog;
  String? _region;
  int _limit = 60;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog ??= AppScope.of(context).loadGymDirectory();
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _searchChanged() {
    setState(() => _limit = 60);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _save(GymPlace gym) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await AppScope.of(context).savePublicGymPlace(gym);
      if (mounted) Navigator.of(context).pop(gym);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '운동 장소를 저장하지 못했어요. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addMissingPlace() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GymDirectoryRequestScreen(
          kind: GymDirectoryRequestKind.add,
          initialGymName: _query.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('헬스장 찾기'),
        actions: [
          IconButton(
            tooltip: '내 헬스장 제안',
            icon: const Icon(SetflowIcons.pastDays),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const GymDirectoryRequestsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<GymDirectoryCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              padding: SetflowInsets.pageList,
              children: [
                ErrorState(
                  message: '헬스장 목록을 불러오지 못했어요.',
                  onRetry: () => setState(() {
                    _catalog = AppScope.of(context).loadGymDirectory();
                  }),
                ),
                AppButton(
                  label: '목록에 없는 헬스장',
                  variant: AppButtonVariant.outlined,
                  onPressed: _addMissingPlace,
                ),
              ],
            );
          }
          final catalog = snapshot.data;
          if (catalog == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final matches = catalog.search(
            _query.text,
            region: _region,
            limit: _limit + 1,
          );
          final hasMore = matches.length > _limit;
          final visible = hasMore ? matches.take(_limit).toList() : matches;
          final regions = catalog.gyms.map((gym) => gym.region).toSet().toList()
            ..sort();
          return CustomScrollView(
            key: const ValueKey('gym-directory-results'),
            controller: _scroll,
            slivers: [
              SliverPadding(
                padding: SetflowInsets.pageHeader,
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('gym-directory-search'),
                        controller: _query,
                        onChanged: (_) => _searchChanged(),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: '헬스장 이름 또는 주소',
                          hintText: '예: 강남 피트니스',
                          prefixIcon: const Icon(SetflowIcons.exerciseSearch),
                          suffixIcon: _query.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '검색어 지우기',
                                  icon: const Icon(SetflowIcons.close),
                                  onPressed: () {
                                    _query.clear();
                                    _searchChanged();
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('gym-directory-region'),
                        initialValue: _region ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '지역'),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('전국')),
                          for (final region in regions)
                            DropdownMenuItem(
                              value: region,
                              child: Text(region),
                            ),
                        ],
                        onChanged: (value) {
                          _region = value == null || value.isEmpty
                              ? null
                              : value;
                          _searchChanged();
                        },
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      Text(
                        '제공 목록 · 사업주 확인 전',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        '헬스장을 누르면 오늘의 운동 장소로 저장해요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_saving) ...[
                        const SizedBox(height: SetflowSpacing.sm),
                        const LinearProgressIndicator(),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: SetflowInsets.pageList,
                sliver: SliverList.builder(
                  itemCount: visible.length + (hasMore ? 1 : 0) + 1,
                  itemBuilder: (context, index) {
                    if (index < visible.length) {
                      final gym = visible[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.sm,
                        ),
                        child: SetflowCard(
                          key: ValueKey('gym-directory-place-${gym.id}'),
                          onTap: _saving ? null : () => _save(gym),
                          padding: const EdgeInsets.all(SetflowSpacing.md),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      gym.name,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: SetflowSpacing.xs),
                                    Text(
                                      gym.address,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '헬스장 정보',
                                icon: const Icon(SetflowIcons.openSource),
                                onPressed: () =>
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => GymPlaceDetailScreen(
                                          gym: gym,
                                          source: catalog.source,
                                        ),
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (hasMore && index == visible.length) {
                      return TextButton(
                        key: const ValueKey('gym-directory-more'),
                        onPressed: () => setState(() => _limit += 60),
                        child: const Text('헬스장 더 보기'),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (visible.isEmpty) ...[
                          const SizedBox(height: SetflowSpacing.lg),
                          const Text('검색 결과가 없어요. 이름이나 지역을 바꿔보세요.'),
                          const SizedBox(height: SetflowSpacing.lg),
                        ],
                        AppButton(
                          key: const ValueKey('gym-directory-missing'),
                          label: '목록에 없는 헬스장',
                          variant: AppButtonVariant.outlined,
                          onPressed: _addMissingPlace,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class GymPlaceDetailScreen extends StatefulWidget {
  const GymPlaceDetailScreen({required this.gym, this.source, super.key});

  final GymPlace gym;
  final GymDirectorySource? source;

  @override
  State<GymPlaceDetailScreen> createState() => _GymPlaceDetailScreenState();
}

class _GymPlaceDetailScreenState extends State<GymPlaceDetailScreen> {
  Future<GymDirectoryCatalog>? _catalog;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.source == null) {
      _catalog ??= AppScope.of(context).loadGymDirectory();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppScope.of(context).savePublicGymPlace(widget.gym);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '운동 장소를 저장하지 못했어요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _suggest(GymDirectoryRequestKind kind) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => GymDirectoryRequestScreen(kind: kind, gym: widget.gym),
      ),
    );
  }

  Future<void> _openSource(String value) async {
    final uri = Uri.tryParse(value);
    try {
      if (uri == null ||
          !{'https', 'http'}.contains(uri.scheme) ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('원본 자료를 열 수 없어요.');
      }
    } catch (_) {
      if (mounted) AppSnackbar.error(context, '원본 자료를 열지 못했어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('헬스장 정보')),
      body: FutureBuilder<GymDirectoryCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          final source = widget.source ?? snapshot.data?.source;
          return ListView(
            padding: SetflowInsets.pageForm,
            children: [
              Text(widget.gym.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: SetflowSpacing.sm),
              Text(widget.gym.address, style: theme.textTheme.bodyLarge),
              const SizedBox(height: SetflowSpacing.xxl),
              const Text('제공 목록 · 사업주 확인 전'),
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                '공개 목록에 있는 기본 정보예요. 제휴나 실제 영업 여부는 확인하지 않았어요.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SetflowSpacing.lg),
              if (source != null) ...[
                Text('출처: ${source.label}'),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  source.sourceDataDate == null
                      ? '자료 기준일 미등록'
                      : '자료 기준일: ${source.sourceDataDate}',
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  source.verifiedAt == null
                      ? '자료 확인일 미등록'
                      : '자료 확인일: ${_dateLabel(source.verifiedAt!)}',
                ),
                if (source.sourceUrl != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _openSource(source.sourceUrl!),
                      child: const Text('원본 자료'),
                    ),
                  ),
              ] else if (snapshot.hasError) ...[
                const Text('자료 출처를 불러오지 못했어요.'),
                TextButton(
                  onPressed: () => setState(() {
                    _catalog = AppScope.of(context).loadGymDirectory();
                  }),
                  child: const Text('다시 불러오기'),
                ),
              ] else
                const Text('자료 출처를 확인하고 있어요.'),
              const SizedBox(height: SetflowSpacing.xxl),
              AppButton(
                label: '운동 장소 저장',
                isLoading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                '이 기기에 저장하고 오늘의 운동 장소로 선택해요. 센터 회원 연결은 별도로 진행해요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SetflowSpacing.xxl),
              AppButton(
                label: '정보 수정 제안',
                variant: AppButtonVariant.outlined,
                onPressed: () => _suggest(GymDirectoryRequestKind.correction),
              ),
              const SizedBox(height: SetflowSpacing.sm),
              AppButton(
                label: '사업주 확인 신청',
                variant: AppButtonVariant.outlined,
                onPressed: () => _suggest(GymDirectoryRequestKind.claim),
              ),
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                '사업주 신청은 운영 권한을 확인하는 검토 요청이에요. 신청이나 가입만으로 정보 수정 권한이 생기지 않아요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class GymDirectoryRequestScreen extends StatefulWidget {
  const GymDirectoryRequestScreen({
    required this.kind,
    this.gym,
    this.initialGymName = '',
    super.key,
  });

  final GymDirectoryRequestKind kind;
  final GymPlace? gym;
  final String initialGymName;

  @override
  State<GymDirectoryRequestScreen> createState() =>
      _GymDirectoryRequestScreenState();
}

class _GymDirectoryRequestScreenState extends State<GymDirectoryRequestScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.gym?.name ?? widget.initialGymName,
  );
  late final _address = TextEditingController(text: widget.gym?.address ?? '');
  final _note = TextEditingController();
  bool _checkedAvailability = false;
  bool? _available;
  bool _busy = false;
  String? _error;
  GymDirectoryRequest? _saved;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedAvailability) {
      _checkedAvailability = true;
      _checkAvailability();
    }
  }

  Future<void> _checkAvailability() async {
    var available = false;
    try {
      available = await AppScope.of(context).canSendGymDirectoryRequests();
    } catch (_) {
      // A device draft remains available even when the server cannot be reached.
    }
    if (mounted) setState(() => _available = available);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _saveAndMaybeSend() async {
    if (_busy || _available == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await AppScope.of(context).saveGymDirectorySuggestion(
        kind: widget.kind,
        gymName: _name.text.trim(),
        address: _address.text.trim(),
        note: _note.text.trim(),
        facilityId: widget.gym?.id,
      );
      if (!mounted) return;
      setState(() => _saved = request);
      if (_available == true) await _sendSaved(request.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '제안을 기기에 보관하지 못했어요. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendSaved(String id) async {
    if (!await requireSignIn(context, reason: AuthReason.gymDirectoryRequest)) {
      return;
    }
    if (!mounted) return;
    try {
      await AppScope.of(context).submitSavedGymDirectoryRequest(id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '전송하지 못했어요. 제안은 이 기기에 남아 있어요. 다시 보내주세요.');
      }
    }
  }

  Future<void> _retrySend(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await AppScope.of(context).canSendGymDirectoryRequests()) {
        if (mounted) {
          setState(() => _error = '현재 제안을 보낼 수 없어요. 이 기기에 계속 보관하고 있어요.');
        }
        return;
      }
      if (mounted) await _sendSaved(id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '전송하지 못했어요. 제안은 기기에 남아 있어요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final saved = _saved == null
        ? null
        : state.gymDirectoryRequests
              .where((request) => request.id == _saved!.id)
              .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(_kindTitle(widget.kind))),
      body: ListView(
        padding: SetflowInsets.pageForm,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              key: const ValueKey('gym-directory-request-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.setflowColors.error,
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
          if (saved != null) ...[
            _RequestSummary(request: saved),
            const SizedBox(height: SetflowSpacing.lg),
            if (saved.submittedAt == null &&
                state.gymDirectoryRequestRepository != null) ...[
              AppButton(
                key: const ValueKey('gym-directory-request-retry'),
                label: '다시 보내기',
                isLoading: _busy,
                onPressed: () => _retrySend(saved.id),
              ),
              const SizedBox(height: SetflowSpacing.sm),
            ],
            AppButton(
              label: '내 제안 확인',
              variant: AppButtonVariant.outlined,
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pushReplacement<void, void>(
                      MaterialPageRoute(
                        builder: (_) => const GymDirectoryRequestsScreen(),
                      ),
                    ),
            ),
          ] else
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_kindExplanation(widget.kind)),
                  const SizedBox(height: SetflowSpacing.xl),
                  TextFormField(
                    key: const ValueKey('gym-directory-request-name'),
                    controller: _name,
                    maxLength: 150,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '헬스장 이름'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '헬스장 이름을 입력해주세요.'
                        : null,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  TextFormField(
                    key: const ValueKey('gym-directory-request-address'),
                    controller: _address,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '주소'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '헬스장을 구분할 수 있는 주소를 입력해주세요.'
                        : null,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  TextFormField(
                    key: const ValueKey('gym-directory-request-note'),
                    controller: _note,
                    maxLength: 2000,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: widget.kind == GymDirectoryRequestKind.claim
                          ? '운영 권한 확인에 도움이 되는 내용'
                          : '추가로 알려줄 내용',
                      hintText: widget.kind == GymDirectoryRequestKind.claim
                          ? '공개 홈페이지 주소나 해당 지점과의 관계를 적어주세요.'
                          : '수정할 정보나 참고할 수 있는 링크를 적어주세요.',
                    ),
                    validator: (value) =>
                        widget.kind != GymDirectoryRequestKind.add &&
                            (value == null || value.trim().isEmpty)
                        ? '확인할 내용을 입력해주세요.'
                        : null,
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  Text(
                    _available == true
                        ? '보내는 순간 로그인이 필요해요. 먼저 기기에 보관하고 운영팀으로 보내요.'
                        : _available == null
                        ? '제안을 보낼 수 있는지 확인하고 있어요.'
                        : '현재 운영팀으로 보낼 수 없어 이 기기에 보관해요. 내 제안에서 다시 확인할 수 있어요.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  AppButton(
                    key: const ValueKey('gym-directory-request-save'),
                    label: _available == true ? '제안 보내기' : '기기에 제안 보관',
                    isLoading: _busy,
                    onPressed: _available == null ? null : _saveAndMaybeSend,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class GymDirectoryRequestsScreen extends StatefulWidget {
  const GymDirectoryRequestsScreen({super.key});

  @override
  State<GymDirectoryRequestsScreen> createState() =>
      _GymDirectoryRequestsScreenState();
}

class _GymDirectoryRequestsScreenState
    extends State<GymDirectoryRequestsScreen> {
  String? _sendingId;
  String? _error;

  Future<void> _send(GymDirectoryRequest request) async {
    if (_sendingId != null) return;
    setState(() {
      _sendingId = request.id;
      _error = null;
    });
    try {
      if (!await AppScope.of(context).canSendGymDirectoryRequests()) {
        if (mounted) {
          setState(() => _error = '현재 제안을 보낼 수 없어요. 기기에 계속 보관해요.');
        }
        return;
      }
      if (!mounted ||
          !await requireSignIn(
            context,
            reason: AuthReason.gymDirectoryRequest,
          )) {
        return;
      }
      if (!mounted) return;
      await AppScope.of(context).submitSavedGymDirectoryRequest(request.id);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '전송하지 못했어요. 제안은 기기에 남아 있어요.');
      }
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final requests = state.gymDirectoryRequests.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('내 헬스장 제안')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          const Text('기기에 보관한 제안과 운영팀에 보낸 제안을 확인해요.'),
          const SizedBox(height: SetflowSpacing.lg),
          if (_error != null) ...[
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.setflowColors.error,
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
          if (requests.isEmpty) const Text('아직 보관하거나 보낸 제안이 없어요.'),
          for (final request in requests) ...[
            _RequestSummary(request: request),
            if (request.submittedAt == null &&
                state.gymDirectoryRequestRepository != null) ...[
              const SizedBox(height: SetflowSpacing.sm),
              AppButton(
                key: ValueKey('gym-directory-send-${request.id}'),
                label: '제안 보내기',
                variant: AppButtonVariant.outlined,
                isLoading: _sendingId == request.id,
                onPressed: _sendingId == null ? () => _send(request) : null,
              ),
            ],
            const SizedBox(height: SetflowSpacing.xl),
          ],
        ],
      ),
    );
  }
}

class _RequestSummary extends StatelessWidget {
  const _RequestSummary({required this.request});

  final GymDirectoryRequest request;

  @override
  Widget build(BuildContext context) {
    final submitted = request.submittedAt != null;
    final theme = Theme.of(context);
    return SetflowCard(
      key: ValueKey('gym-directory-request-${request.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_kindTitle(request.kind), style: theme.textTheme.labelMedium),
          const SizedBox(height: SetflowSpacing.sm),
          Text(request.gymName, style: theme.textTheme.titleMedium),
          const SizedBox(height: SetflowSpacing.xs),
          Text(request.address),
          if (request.note.isNotEmpty) ...[
            const SizedBox(height: SetflowSpacing.sm),
            Text(request.note),
          ],
          const SizedBox(height: SetflowSpacing.md),
          Text(
            submitted ? '운영팀에 접수됨' : '기기에 보관됨 · 아직 보내지 않음',
            style: theme.textTheme.labelMedium?.copyWith(
              color: submitted
                  ? context.setflowColors.success
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Text(
            submitted
                ? '접수일: ${_dateLabel(request.submittedAt!)}'
                : '보관일: ${_dateLabel(request.createdAt)}',
            style: theme.textTheme.bodySmall,
          ),
          if (request.kind == GymDirectoryRequestKind.claim) ...[
            const SizedBox(height: SetflowSpacing.sm),
            const Text('사업주 권한은 확인과 승인 후에 부여돼요.'),
          ],
        ],
      ),
    );
  }
}

String _kindTitle(GymDirectoryRequestKind kind) => switch (kind) {
  GymDirectoryRequestKind.add => '헬스장 추가 제안',
  GymDirectoryRequestKind.correction => '정보 수정 제안',
  GymDirectoryRequestKind.claim => '사업주 확인 신청',
};

String _kindExplanation(GymDirectoryRequestKind kind) => switch (kind) {
  GymDirectoryRequestKind.add => '목록에 없는 헬스장의 이름과 주소를 알려주세요.',
  GymDirectoryRequestKind.correction => '잘못된 정보와 바꿔야 할 내용을 알려주세요. 확인 후 반영해요.',
  GymDirectoryRequestKind.claim =>
    '이 헬스장의 사업주 또는 관리자인가요? 운영 권한 확인을 신청해주세요. 가입만으로 정보를 수정할 수는 없어요.',
};

String _dateLabel(DateTime value) {
  final date = value.toLocal();
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}
