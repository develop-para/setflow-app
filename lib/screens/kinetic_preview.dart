import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/kinetic.dart';
import '../widgets/motion.dart';

/// Internal design-QA gallery for the Kinetic language. Reachable on web via
/// `?preview=kinetic`. Not part of the shipping navigation.
class KineticPreviewScreen extends StatefulWidget {
  const KineticPreviewScreen({super.key});

  @override
  State<KineticPreviewScreen> createState() => _KineticPreviewScreenState();
}

class _KineticPreviewScreenState extends State<KineticPreviewScreen> {
  int _seg = 0;
  int _nav = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: Reveal.list(stagger: const Duration(milliseconds: 45), [
            Row(
              children: [
                const SetflowWordmark(),
                const Spacer(),
                AppIconButton(icon: Icons.notifications_none_rounded, onTap: () {}),
              ],
            ),
            const SizedBox(height: SetflowSpacing.section),
            const KineticScreenHeader(
              kicker: '이번 주',
              title: '오늘도\n밀어붙이자',
            ),
            const SizedBox(height: SetflowSpacing.xl),
            const TrainingHeroCard(
              kicker: '이번 주 트레이닝',
              value: '12,480',
              unit: 'kg',
              delta: '8%',
              deltaUp: true,
              streak: '3주 연속',
              spark: [6.2, 5.4, 7.1, 6.8, 8.4, 7.9, 9.2, 8.6, 10.1, 12.4],
              weekValues: [8, 0, 6.5, 9.2, 0, 5.3, 3.1],
              weekLabels: ['월', '화', '수', '목', '금', '토', '일'],
              weekHighlight: 5,
              ringValue: 0.86,
              ringTop: '86%',
              ringBottom: '목표',
            ),
            const SizedBox(height: SetflowSpacing.md),
            const Row(
              children: [
                Expanded(
                  child: KineticStatBlock(
                    label: '연속 기록',
                    value: '14',
                    unit: '일',
                    style: KineticStatStyle.brand,
                  ),
                ),
                SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: KineticStatBlock(
                    label: '완료 세트',
                    value: '186',
                    style: KineticStatStyle.plain,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.md),
            const KineticStatStrip(
              stats: [
                KineticStat('벤치 1RM', '92.5', unit: 'kg'),
                KineticStat('스쿼트', '140', unit: 'kg'),
                KineticStat('데드', '175', unit: 'kg'),
              ],
            ),
            const SizedBox(height: SetflowSpacing.section),
            const KineticLabel('훈련 기록 · 최근 10주', tick: true),
            const SizedBox(height: SetflowSpacing.md),
            SetflowCard(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ContributionGrid(
                  color: theme.colorScheme.primary,
                  emptyColor: context.setflowColors.surfaceContainerHigh,
                  intensities: const [
                    [0.4, 0, 0.8, 0, 0.6, 0.3, 0],
                    [0.7, 0.5, 0, 0.9, 0, 0.4, 0.2],
                    [0, 0.6, 0.5, 0.7, 0.3, 0, 0.8],
                    [0.5, 0, 0.9, 0.4, 0.6, 0.7, 0],
                    [0.8, 0.3, 0, 0.5, 0.9, 0, 0.4],
                    [0.6, 0.7, 0.4, 0, 0.5, 0.8, 0.3],
                    [0, 0.9, 0.6, 0.7, 0, 0.4, 0.5],
                    [0.7, 0.5, 0.8, 0.3, 0.6, 0, 0.9],
                    [0.4, 0, 0.6, 0.9, 0.5, 0.7, 0],
                    [0.9, 0.6, 0.4, 0.5, 0.8, 0.3, 0.7],
                  ],
                ),
              ),
            ),
            const SizedBox(height: SetflowSpacing.section),
            const KineticLabel('부위별 볼륨 · 이번 주', tick: true),
            const SizedBox(height: SetflowSpacing.md),
            SetflowCard(
              child: Column(
                children: [
                  SplitBar(
                    label: '등',
                    value: '6.1t',
                    fraction: 1.0,
                    color: theme.colorScheme.primary,
                    trackColor: context.setflowColors.surfaceContainerHigh,
                  ),
                  SplitBar(
                    label: '하체',
                    value: '4.2t',
                    fraction: 0.69,
                    color: context.setflowColors.blue,
                    trackColor: context.setflowColors.surfaceContainerHigh,
                  ),
                  SplitBar(
                    label: '가슴',
                    value: '3.6t',
                    fraction: 0.59,
                    color: context.setflowColors.purple,
                    trackColor: context.setflowColors.surfaceContainerHigh,
                  ),
                  SplitBar(
                    label: '어깨',
                    value: '2.1t',
                    fraction: 0.34,
                    color: context.setflowColors.teal,
                    trackColor: context.setflowColors.surfaceContainerHigh,
                  ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.section),
            const KineticLabel('빠른 지표', tick: true),
            const SizedBox(height: SetflowSpacing.md),
            const Row(
              children: [
                MetricCard(
                  label: '주간 운동',
                  value: '5',
                  suffix: '회',
                  icon: Icons.bolt_rounded,
                  tint: SetflowColors.primary,
                ),
                SizedBox(width: SetflowSpacing.md),
                MetricCard(
                  label: '평균 시간',
                  value: '58',
                  suffix: '분',
                  icon: Icons.timer_outlined,
                  tint: SetflowColors.teal,
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.section),
            const KineticLabel('오늘의 루틴', tick: true),
            const SizedBox(height: SetflowSpacing.md),
            SetflowCard(
              onTap: () {},
              child: Row(
                children: [
                  const TintedIconBadge(
                    icon: Icons.fitness_center_rounded,
                    color: SetflowColors.primary,
                    square: true,
                  ),
                  const SizedBox(width: SetflowSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('하체 파워 데이', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          '스쿼트 · 레그프레스 · 런지 · 6종',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const StatusChip(label: '진행중', color: SetflowColors.green),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.section),
            const KineticLabel('컨트롤', tick: true),
            const SizedBox(height: SetflowSpacing.md),
            SegPills(
              items: const ['내 루틴', '최근', '보관함'],
              selectedIndex: _seg,
              onChanged: (i) => setState(() => _seg = i),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Wrap(
              spacing: SetflowSpacing.sm,
              runSpacing: SetflowSpacing.sm,
              children: const [
                StatusChip(label: '초급', color: SetflowColors.blue),
                StatusChip(label: '근력', color: SetflowColors.purple),
                StatusChip(
                  label: '완료',
                  color: SetflowColors.green,
                  icon: Icons.check_rounded,
                ),
                StatusChip(label: '주의', color: SetflowColors.warning),
              ],
            ),
            const SizedBox(height: SetflowSpacing.section),
            const KineticLabel('컬러 시스템 · 웜 중립 램프', tick: true),
            const SizedBox(height: SetflowSpacing.md),
            SetflowCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SetflowRadii.sm),
                    child: Row(
                      children: const [
                        Expanded(child: ColoredBox(color: SetflowNeutral.n0, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n50, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n100, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n200, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n300, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n400, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n500, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n600, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n700, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n800, child: SizedBox(height: 34))),
                        Expanded(child: ColoredBox(color: SetflowNeutral.n900, child: SizedBox(height: 34))),
                      ],
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  const KineticLabel('브랜드 · 액센트'),
                  const SizedBox(height: SetflowSpacing.sm),
                  Wrap(
                    spacing: SetflowSpacing.sm,
                    runSpacing: SetflowSpacing.sm,
                    children: [
                      _swatch(context, SetflowColors.primary, 'Supernova'),
                      _swatch(context, SetflowColors.ink, 'Ink'),
                      _swatch(context, context.setflowColors.teal, 'Teal'),
                      _swatch(context, context.setflowColors.blue, 'Blue'),
                      _swatch(context, context.setflowColors.purple, 'Purple'),
                      _swatch(context, context.setflowColors.success, 'Green'),
                      _swatch(context, context.setflowColors.orange, 'Orange'),
                      _swatch(context, SetflowColors.red, 'Red'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            PrimaryButton(label: '운동 시작하기', icon: Icons.play_arrow_rounded, onPressed: () {}),
            const SizedBox(height: SetflowSpacing.md),
            AppButton(
              label: '루틴 편집',
              variant: AppButtonVariant.outlined,
              onPressed: () {},
            ),
          ]),
        ),
      ),
      bottomNavigationBar: SetflowNavBar(
        selectedIndex: _nav,
        onSelected: (i) => setState(() => _nav = i),
        items: const [
          SetflowNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: '홈',
          ),
          SetflowNavItem(
            icon: Icons.fitness_center_outlined,
            selectedIcon: Icons.fitness_center_rounded,
            label: '운동',
          ),
          SetflowNavItem(
            icon: Icons.leaderboard_outlined,
            selectedIcon: Icons.leaderboard_rounded,
            label: '랭킹',
          ),
          SetflowNavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: '프로필',
          ),
        ],
      ),
    );
  }
}

Widget _swatch(BuildContext context, Color color, String label) {
  final theme = Theme.of(context);
  return Container(
    padding: const EdgeInsets.fromLTRB(6, 5, 11, 5),
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(SetflowRadii.full),
      border: Border.all(color: theme.colorScheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    ),
  );
}
