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
    return Scaffold(
      appBar: AppBar(title: Text('${routine.name} 통계')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          SetflowCard(
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 44,
                  decoration: BoxDecoration(
                    color: routine.color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routine.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${routine.author} · ${routine.level}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: SetflowColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('성과 지표'),
          const SizedBox(height: 10),
          Row(
            children: [
              MetricCard(
                label: '조회수',
                value: NumberFormat('#,###').format(_views),
                icon: Icons.visibility_outlined,
                tint: SetflowColors.blue,
              ),
              const SizedBox(width: 8),
              MetricCard(
                label: '저장수',
                value: NumberFormat('#,###').format(_saves),
                icon: Icons.bookmark_outline,
                tint: SetflowColors.purple,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              MetricCard(
                label: '적용수',
                value: NumberFormat('#,###').format(_applies),
                icon: Icons.play_circle_outline,
                tint: SetflowColors.teal,
              ),
              const SizedBox(width: 8),
              MetricCard(
                label: '상담 전환율',
                value: _conversion.toStringAsFixed(1),
                suffix: '%',
                icon: Icons.trending_up,
                tint: SetflowColors.green,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionTitle('최근 7일 조회 추이'),
          const SizedBox(height: 10),
          SetflowCard(
            child: _TrendChart(values: _trend, color: routine.color),
          ),
          const SizedBox(height: 20),
          const SectionTitle('마켓 노출 랭킹'),
          const SizedBox(height: 10),
          SetflowCard(
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_events_outlined,
                  color: SetflowColors.orange,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '현재 순위',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '#$_ranking',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
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
    return Scaffold(
      appBar: AppBar(title: Text('$name 성과')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          SetflowCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: accentColor.withValues(alpha: .16),
                  child: Text(
                    name.characters.first,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        '소속 코치 성과 리포트',
                        style: TextStyle(
                          fontSize: 11,
                          color: SetflowColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: SetflowColors.primary,
                      size: 20,
                    ),
                    Text(
                      '$rating',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('성과 지표'),
          const SizedBox(height: 10),
          Row(
            children: [
              MetricCard(
                label: '담당 회원',
                value: membersLabel,
                icon: Icons.groups_outlined,
                tint: SetflowColors.blue,
              ),
              const SizedBox(width: 8),
              MetricCard(
                label: '매출',
                value: NumberFormat('#,###').format(_revenue),
                suffix: '원',
                icon: Icons.payments_outlined,
                tint: SetflowColors.green,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              MetricCard(
                label: '상담 전환율',
                value: _conversionRate.toStringAsFixed(1),
                suffix: '%',
                icon: Icons.trending_up,
                tint: SetflowColors.teal,
              ),
              const SizedBox(width: 8),
              MetricCard(
                label: '상담 건수',
                value: '$_consultations',
                icon: Icons.forum_outlined,
                tint: SetflowColors.purple,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionTitle('피드백 이행률'),
          const SizedBox(height: 10),
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '회원 피드백 이행률',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      feedbackRate,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: _feedbackValue.clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: accentColor,
                  backgroundColor: accentColor.withValues(alpha: .12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionTitle('최근 상담 전환 추이'),
          const SizedBox(height: 10),
          SetflowCard(
            child: _TrendChart(values: _trend, color: accentColor),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values, required this.color});
  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: 84 * values[i] / maxValue,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .75),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
