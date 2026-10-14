import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/evidence_catalog.dart';
import '../domain/workout_design_rule.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';

typedef EvidenceLinkLauncher = Future<bool> Function(Uri uri);

class EvidenceLibraryScreen extends StatefulWidget {
  const EvidenceLibraryScreen({
    this.linkLauncher,
    this.referenceIds,
    super.key,
  });

  final EvidenceLinkLauncher? linkLauncher;
  final Set<String>? referenceIds;

  @override
  State<EvidenceLibraryScreen> createState() => _EvidenceLibraryScreenState();
}

class _EvidenceLibraryScreenState extends State<EvidenceLibraryScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _search(String value) {
    setState(() => _query = value.trim().toLowerCase());
    // 결과와 설명의 높이가 바뀐 뒤 검색 입력으로 돌아간다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _search('');
  }

  Widget _buildSearch(BuildContext context) => AppTextField(
    key: const ValueKey('evidence-search'),
    controller: _searchController,
    label: '주제·논문·저자 검색',
    hint: '휴식, RIR, 근비대',
    prefixIcon: const Icon(SetflowIcons.exerciseSearch),
    suffixIcon: _query.isEmpty
        ? null
        : IconButton(
            tooltip: '검색 지우기',
            icon: const Icon(SetflowIcons.close),
            onPressed: _clearSearch,
          ),
    textInputAction: TextInputAction.search,
    onChanged: _search,
    onSubmitted: (_) => FocusScope.of(context).unfocus(),
  );

  Future<void> _openReference(
    BuildContext context,
    EvidenceReference reference,
  ) async {
    try {
      final opened = await (widget.linkLauncher ?? _launchExternal)(
        reference.officialUrl,
      );
      if (!opened && context.mounted) {
        AppSnackbar.error(context, '공식 논문 페이지를 열지 못했어요.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '공식 논문 페이지를 열지 못했어요.');
      }
    }
  }

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final designRules = WorkoutDesignRule.values.where(
      (rule) =>
          widget.referenceIds == null ||
          rule.evidenceIds.any(widget.referenceIds!.contains),
    );
    final references = evidenceCatalog
        .where(
          (reference) =>
              (widget.referenceIds == null ||
                  widget.referenceIds!.contains(reference.id)) &&
              (_query.isEmpty || reference.searchableText.contains(_query)),
        )
        .toList(growable: false);
    final referencesByCategory = {
      for (final category in EvidenceCategory.values)
        category: references
            .where((reference) => reference.category == category)
            .toList(growable: false),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('관련 논문')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SetflowSpacing.gutter,
                  SetflowSpacing.sm,
                  SetflowSpacing.gutter,
                  SetflowSpacing.sm,
                ),
                child: _buildSearch(context),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('evidence-library-list'),
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    SetflowSpacing.gutter,
                    SetflowSpacing.sm,
                    SetflowSpacing.gutter,
                    SetflowSpacing.section,
                  ),
                  children: [
                    if (_query.isNotEmpty)
                      Text(
                        '${references.length}건의 논문',
                        key: const ValueKey('evidence-search-count'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (_query.isEmpty)
                      SetflowCard(
                        color: context.setflowColors.surfaceContainer,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.science_outlined,
                              color: context.setflowColors.teal,
                            ),
                            SizedBox(width: SetflowSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Setflow의 추천 근거',
                                    style: TextStyle(
                                      fontSize: SetflowFontSize.titleLarge,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  SizedBox(height: SetflowSpacing.xs),
                                  Text(
                                    '연구에서 확인한 원칙과 앱에서 정한 수치·기록 방식의 이유를 함께 확인할 수 있어요. '
                                    '앱 기본값은 개인의 최적량이나 안전 상한을 뜻하지 않습니다.',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: SetflowSpacing.lg),
                    if (_query.isEmpty && designRules.isNotEmpty) ...[
                      SetflowCard(
                        key: const ValueKey('workout-design-rules'),
                        padding: EdgeInsets.zero,
                        child: ExpansionTile(
                          title: Text(
                            '운동 기록·추천의 설계 이유',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: const Text('연구 원칙 · 앱 기본값 · 기록 보존'),
                          tilePadding: const EdgeInsets.all(SetflowSpacing.md),
                          childrenPadding: const EdgeInsets.all(
                            SetflowSpacing.sm,
                          ),
                          children: [
                            for (final rule in designRules) ...[
                              _DesignRuleCard(rule: rule),
                              const SizedBox(height: SetflowSpacing.sm),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                    ],
                    if (references.isEmpty)
                      SetflowCard(
                        key: const ValueKey('evidence-search-empty'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '검색 결과가 없어요',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: SetflowSpacing.sm),
                            const Text('휴식·RIR·근비대 같은 주제나 저자 이름으로 검색해보세요.'),
                            TextButton(
                              onPressed: _clearSearch,
                              child: const Text('검색 초기화'),
                            ),
                          ],
                        ),
                      ),
                    for (final category in EvidenceCategory.values.where(
                      (category) => referencesByCategory[category]!.isNotEmpty,
                    )) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          SetflowSpacing.xs,
                          SetflowSpacing.md,
                          SetflowSpacing.xs,
                          SetflowSpacing.sm,
                        ),
                        child: Text(
                          category.label,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      for (final reference
                          in referencesByCategory[category]!) ...[
                        _EvidenceCard(
                          reference: reference,
                          onOpen: () => _openReference(context, reference),
                        ),
                        const SizedBox(height: SetflowSpacing.md),
                      ],
                    ],
                    const SizedBox(height: SetflowSpacing.sm),
                    Text(
                      '근거·설계 검토: ${WorkoutDesignRule.reviewedOn} · 논문이 뒷받침하는 범위와 앱 선택을 구분합니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: SetflowFontSize.caption,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesignRuleCard extends StatelessWidget {
  const _DesignRuleCard({required this.rule});

  final WorkoutDesignRule rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      key: ValueKey('workout-rule-${rule.name}'),
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        title: Text(rule.title, style: theme.textTheme.titleMedium),
        subtitle: Text(rule.basis.label, style: theme.textTheme.bodySmall),
        tilePadding: const EdgeInsets.all(SetflowSpacing.md),
        childrenPadding: const EdgeInsets.fromLTRB(
          SetflowSpacing.md,
          0,
          SetflowSpacing.md,
          SetflowSpacing.md,
        ),
        children: [
          if (rule.principle.isNotEmpty)
            _MetadataRow(label: '연구에서 참고한 원칙', value: rule.principle),
          _MetadataRow(label: '앱에서 적용하는 방식', value: rule.implementation),
          _MetadataRow(label: '이렇게 정한 이유', value: rule.rationale),
          _MetadataRow(label: '해석할 때의 한계', value: rule.limitations),
          for (final id in rule.evidenceIds)
            _MetadataRow(
              label: '참고 논문',
              value:
                  '${evidenceCatalogById[id]!.authors} (${evidenceCatalogById[id]!.year})',
            ),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({required this.reference, required this.onOpen});

  final EvidenceReference reference;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      key: ValueKey('evidence-${reference.id}'),
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(
          SetflowSpacing.lg,
          SetflowSpacing.md,
          SetflowSpacing.md,
          SetflowSpacing.md,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          SetflowSpacing.lg,
          0,
          SetflowSpacing.lg,
          SetflowSpacing.lg,
        ),
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        title: Text(
          reference.koreanTitle,
          style: theme.textTheme.titleMedium?.copyWith(height: 1.35),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: SetflowSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reference.takeaway, style: theme.textTheme.bodySmall),
              const SizedBox(height: SetflowSpacing.sm),
              Wrap(
                spacing: SetflowSpacing.sm,
                runSpacing: SetflowSpacing.xs,
                children: [
                  _EvidenceTag(label: '${reference.year}'),
                  _EvidenceTag(label: reference.evidenceType),
                ],
              ),
            ],
          ),
        ),
        children: [
          const Divider(height: SetflowSpacing.lg),
          _MetadataRow(label: '공식 논문 제목', value: reference.title),
          _MetadataRow(label: '저자', value: reference.authors),
          _MetadataRow(label: '저널/기관', value: reference.source),
          if (reference.doi case final String doi)
            _MetadataRow(label: 'DOI', value: doi),
          _MetadataRow(
            label: '검토일 · 확인 범위',
            value: '${reference.reviewedOn} · ${reference.reviewScope}',
          ),
          const SizedBox(height: SetflowSpacing.lg),
          const _EvidenceSubheading(
            icon: Icons.rule_rounded,
            title: '앱에서 참조한 규칙',
          ),
          const SizedBox(height: SetflowSpacing.sm),
          for (final rule in reference.appRules) _RuleBullet(text: rule),
          const SizedBox(height: SetflowSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SetflowSpacing.md),
            decoration: BoxDecoration(
              color: context.setflowColors.surfaceContainer,
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _EvidenceSubheading(
                  icon: Icons.info_outline_rounded,
                  title: '근거의 한계',
                ),
                const SizedBox(height: SetflowSpacing.sm),
                Text(
                  reference.limitations,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          AppButton(
            key: ValueKey('evidence-link-${reference.id}'),
            label: 'DOI · 공식 페이지 열기',
            icon: Icons.open_in_new_rounded,
            variant: AppButtonVariant.outlined,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}

class _EvidenceTag extends StatelessWidget {
  const _EvidenceTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.sm,
        vertical: SetflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainer,
        borderRadius: BorderRadius.circular(SetflowRadii.full),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: SetflowSpacing.xs),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _EvidenceSubheading extends StatelessWidget {
  const _EvidenceSubheading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 라임은 흰 배경에서 사라진다 — 아이콘·점 같은 전경은 읽는 브랜드.
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: SetflowSpacing.sm),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _RuleBullet extends StatelessWidget {
  const _RuleBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SetflowSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: SetflowSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
