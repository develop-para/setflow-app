import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/evidence_catalog.dart';
import '../theme.dart';
import '../widgets/common.dart';

typedef EvidenceLinkLauncher = Future<bool> Function(Uri uri);

class EvidenceLibraryScreen extends StatelessWidget {
  const EvidenceLibraryScreen({this.linkLauncher, super.key});

  final EvidenceLinkLauncher? linkLauncher;

  Future<void> _openReference(
    BuildContext context,
    EvidenceReference reference,
  ) async {
    try {
      final opened = await (linkLauncher ?? _launchExternal)(
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
    final referencesByCategory = {
      for (final category in EvidenceCategory.values)
        category: evidenceCatalog
            .where((reference) => reference.category == category)
            .toList(growable: false),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('관련 논문')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            key: const ValueKey('evidence-library-list'),
            padding: const EdgeInsets.fromLTRB(
              SetflowSpacing.gutter,
              SetflowSpacing.sm,
              SetflowSpacing.gutter,
              SetflowSpacing.section,
            ),
            children: [
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
                            '예상 1RM, 목표별 세트 구성, 휴식시간과 다음 운동 순서에 참고한 자료입니다. '
                            '추천값은 연구의 집단 평균을 단순화한 보조 정보이며 의료 진단이나 개인 처방을 대신하지 않습니다.',
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
              for (final category in EvidenceCategory.values) ...[
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
                for (final reference in referencesByCategory[category]!) ...[
                  _EvidenceCard(
                    reference: reference,
                    onOpen: () => _openReference(context, reference),
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                ],
              ],
              const SizedBox(height: SetflowSpacing.sm),
              Text(
                '최종 검토: 2026년 8월 17일 · 논문 내용과 앱 규칙이 바뀌면 이 목록도 함께 갱신합니다.',
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
          reference.title,
          style: theme.textTheme.titleMedium?.copyWith(height: 1.35),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: SetflowSpacing.sm),
          child: Wrap(
            spacing: SetflowSpacing.sm,
            runSpacing: SetflowSpacing.xs,
            children: [
              _EvidenceTag(label: '${reference.year}'),
              _EvidenceTag(label: reference.evidenceType),
            ],
          ),
        ),
        children: [
          const Divider(height: SetflowSpacing.lg),
          _MetadataRow(label: '저자', value: reference.authors),
          _MetadataRow(label: '저널/기관', value: reference.source),
          if (reference.doi case final String doi)
            _MetadataRow(label: 'DOI', value: doi),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(),
            ),
          ),
          Expanded(child: Text(value, style: valueStyle)),
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
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: SetflowSpacing.sm),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontSize: SetflowFontSize.body),
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
                color: Theme.of(context).colorScheme.primary,
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
