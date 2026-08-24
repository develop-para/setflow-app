import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class RecommendationProfileSummary extends StatelessWidget {
  const RecommendationProfileSummary({
    required this.profile,
    this.compact = false,
    super.key,
  });

  final RecommendationProfile profile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final equipment = profile.availableEquipment
        .map((item) => item.label)
        .join(' · ');
    final pain = profile.painRegions.isEmpty
        ? '현재 등록한 부위 없음'
        : '${profile.painRegions.map((item) => item.label).join(' · ')} · ${profile.painLevel}/10';
    final restrictions = profile.restrictedMovements.isEmpty
        ? '직접 지정한 제외 동작 없음'
        : profile.restrictedMovements.map((item) => item.label).join(' · ');
    final recoveryDate = profile.recoveryRecordedAt.toLocal();
    final recovery =
        '${profile.recoveryStatus.label} · ${recoveryDate.year}.${_two(recoveryDate.month)}.${_two(recoveryDate.day)} 기록';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryRow(
          icon: Icons.signal_cellular_alt_rounded,
          label: '숙련도',
          value: profile.experienceLevel.label,
          compact: compact,
        ),
        _SummaryRow(
          icon: Icons.fitness_center_rounded,
          label: '사용 장비',
          value: equipment,
          compact: compact,
        ),
        _SummaryRow(
          icon: Icons.healing_outlined,
          label: '부상 · 통증',
          value: pain,
          compact: compact,
        ),
        _SummaryRow(
          icon: Icons.block_rounded,
          label: '피할 동작',
          value: restrictions,
          compact: compact,
        ),
        _SummaryRow(
          icon: Icons.bedtime_outlined,
          label: '회복 상태',
          value: recovery,
          compact: compact,
        ),
        if (profile.injuryNote.isNotEmpty)
          _SummaryRow(
            icon: Icons.notes_rounded,
            label: '추가 메모',
            value: profile.injuryNote,
            compact: compact,
          ),
      ],
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.compact,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: compact ? 17 : 19,
            color: context.setflowColors.teal,
          ),
          const SizedBox(width: SetflowSpacing.sm2),
          SizedBox(
            width: compact ? 70 : 82,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
