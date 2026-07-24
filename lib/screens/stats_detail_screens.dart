import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// [RoutineManagerPage]에서 진입하는 루틴별 통계 상세 화면.
/// 조회수/저장수/적용수/상담 전환율과 최근 추이, 마켓 랭킹을 보여준다. 데모 더미 데이터.
class RoutineStatsPage extends StatelessWidget {
  const RoutineStatsPage({required this.routine, super.key});
  final RoutineData routine;

  int get _seed => routine.id.hashCode.abs();
  int get _views => 800 + _seed % 2200;
  int get _saves => 60 + _seed % 260;
  int get _applies => 30 + _seed % 140;
  int get _consultations => 8 + _seed % 60;
  double get _conversion => _views == 0 ? 0 : _consultations / _views * 100;
  int get _ranking => 1 + _seed % 40;

  List<int> get _trend => List.generate(7, (i) => 20 + (_seed + i * 37) % 80);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('${routine.name} 통계')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: routine.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Expanded(
                      child: Text(
                        '${routine.author} · ${routine.level}',
                        style: text.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.md),
                Text(
                  '조회수',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      NumberFormat('#,###').format(_views),
                      style: text.displayLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Text(
                      '회',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    Text(
                      NumberFormat('#,###').format(_saves),
                      style: text.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Text(
                      '저장',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.lg),
                _Sparkline(values: _trend, color: theme.colorScheme.primary),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          const SectionTitle('세부 지표'),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              MetricCard(
                label: '적용수',
                value: NumberFormat('#,###').format(_applies),
                icon: Icons.play_circle_outline,
                tint: context.setflowColors.teal,
              ),
              const SizedBox(width: SetflowSpacing.sm),
              MetricCard(
                label: '상담 전환율',
                value: _conversion.toStringAsFixed(1),
                suffix: '%',
                icon: Icons.trending_up,
                tint: context.setflowColors.success,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.md),
          _HairlineStat(
            icon: Icons.emoji_events_outlined,
            label: '마켓 노출 랭킹',
            value: '#$_ranking',
            tint: context.setflowColors.orange,
          ),
        ],
      ),
    );
  }
}

/// [TrainerManagementPage]에서 진입하는 트레이너별 성과 상세 화면.
/// 담당 회원 수/매출/상담 전환/평점 지표와 피드백 이행률, 최근 추이를 보여준다. 데모 더미 데이터.
class TrainerPerformancePage extends StatelessWidget {
  const TrainerPerformancePage({
    required this.name,
    required this.membersLabel,
    required this.feedbackRate,
    required this.rating,
    required this.accentColor,
    super.key,
  });

  final String name;
  final String membersLabel;
  final String feedbackRate;
  final double rating;
  final Color accentColor;

  int get _seed => name.hashCode.abs();
  int get _revenue => 1200000 + _seed % 4800000;
  int get _consultations => 10 + _seed % 50;
  double get _conversionRate => 20 + _seed % 60;
  double get _feedbackValue {
    final digits = RegExp(r'\d+').firstMatch(feedbackRate)?.group(0);
    return (int.tryParse(digits ?? '0') ?? 0) / 100;
  }

  List<int> get _trend => List.generate(6, (i) => 30 + (_seed + i * 53) % 70);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('$name 성과')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: accentColor.withValues(alpha: .16),
                      child: Text(
                        name.characters.first,
                        style: text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Expanded(
                      child: Text(
                        name,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    StatusChip(
                      label: '$rating',
                      icon: Icons.star_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.md),
                Text(
                  '상담 전환율',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _conversionRate.toStringAsFixed(1),
                      style: text.displayLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    Text(
                      '%',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    Text(
                      membersLabel,
                      style: text.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Text(
                      '담당',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.lg),
                _Sparkline(values: _trend, color: theme.colorScheme.primary),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          const SectionTitle('세부 지표'),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              MetricCard(
                label: '매출',
                value: NumberFormat('#,###').format(_revenue),
                suffix: '원',
                icon: Icons.payments_outlined,
                tint: context.setflowColors.success,
              ),
              const SizedBox(width: SetflowSpacing.sm),
              MetricCard(
                label: '상담 건수',
                value: '$_consultations',
                icon: Icons.forum_outlined,
                tint: context.setflowColors.purple,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.xl),
          const SectionTitle('피드백 이행률'),
          const SizedBox(height: SetflowSpacing.md),
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '회원 피드백 이행률',
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      feedbackRate,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.sm),
                LinearProgressIndicator(
                  value: _feedbackValue.clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(SetflowRadii.sm),
                  color: accentColor,
                  backgroundColor: accentColor.withValues(alpha: .12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Quiet aggregate row on a hairline top divider — mockup's weekly-total
/// pattern applied to a single stat instead of a boxed side column.
class _HairlineStat extends StatelessWidget {
  const _HairlineStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: SetflowSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini bar sparkline for hero stat blocks — full volt above 66% of the
/// series max, dimmed volt above 33%, quiet surface below that.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});
  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final quiet = context.setflowColors.surfaceContainerHigh;
    final maxValue = values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final value in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SetflowSpacing.xxs,
                ),
                child: _bar(value / maxValue, quiet),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double ratio, Color quiet) {
    final barColor = ratio >= .66
        ? color
        : ratio >= .33
        ? color.withValues(alpha: .45)
        : quiet;
    return FractionallySizedBox(
      heightFactor: ratio.clamp(.08, 1),
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SetflowRadii.xs),
          ),
        ),
      ),
    );
  }
}
