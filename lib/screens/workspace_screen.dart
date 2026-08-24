import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 사업자(트레이너/헬스장) 전용 PC 데스크톱 워크스페이스.
///
/// 모바일 목업 폭에 갇히지 않고, 넓은 화면에서는 다단 그리드로
/// 요약 지표와 운영 패널을 한눈에 보여주는 데모 화면이다.
class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({required this.role, super.key});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final config = _workspaceConfig(context, role);
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: Text(config.title)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth - 48;
            final columns = contentWidth >= 1180
                ? 3
                : (contentWidth >= 760 ? 2 : 1);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.gutter,
                20,
                SetflowSpacing.gutter,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.subtitle,
                    style: const TextStyle(
                      fontSize: SetflowFontSize.headlineLarge,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    '주요 운영 지표를 한 화면에서 확인하세요.',
                    style: TextStyle(
                      fontSize: SetflowFontSize.caption,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: SetflowSpacing.xl),
                  _ResponsiveGrid(
                    width: contentWidth,
                    columns: columns,
                    children: config.stats,
                  ),
                  SizedBox(height: SetflowSpacing.xxl),
                  _ResponsiveGrid(
                    width: contentWidth,
                    columns: columns,
                    children: config.panels,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  ({String title, String subtitle, List<Widget> stats, List<Widget> panels})
  _workspaceConfig(BuildContext context, UserRole role) {
    return switch (role) {
      UserRole.gym => (
        title: 'PC 요약',
        subtitle: '모션짐 강남점 운영 현황',
        stats: [
          _StatTile(
            label: '전체 회원',
            value: '4',
            suffix: '명',
            icon: Icons.groups_outlined,
            tint: context.setflowColors.teal,
          ),
          _StatTile(
            label: '이번 달 매출',
            value: '18.4',
            suffix: '백만원',
            icon: Icons.trending_up,
            tint: context.setflowColors.success,
          ),
          _StatTile(
            label: '소속 트레이너',
            value: '4',
            suffix: '명',
            icon: Icons.badge_outlined,
            tint: context.setflowColors.purple,
          ),
          _StatTile(
            label: '신규 상담',
            value: '9',
            suffix: '건',
            icon: Icons.chat_bubble_outline,
            tint: context.setflowColors.orange,
          ),
        ],
        panels: [
          _panel(
            title: '소속 트레이너 현황',
            child: Column(
              children: [
                _EntryRow(
                  name: '김코치',
                  subtitle: '회원 18명 · 피드백 98%',
                  trailing: '4.9',
                  trailingColor: context.setflowColors.blue,
                  avatarColor: context.setflowColors.blue,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '박트레이너',
                  subtitle: '회원 15명 · 피드백 94%',
                  trailing: '4.8',
                  trailingColor: context.setflowColors.teal,
                  avatarColor: context.setflowColors.teal,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '이코치',
                  subtitle: '회원 12명 · 피드백 78%',
                  trailing: '4.6',
                  trailingColor: context.setflowColors.orange,
                  avatarColor: context.setflowColors.orange,
                ),
              ],
            ),
          ),
          _panel(
            title: '신규 상담 대기',
            child: Column(
              children: [
                _EntryRow(
                  name: '이수진',
                  subtitle: '근육 증가 · 운동 경력 3개월',
                  trailing: '미답변',
                  trailingColor: context.setflowColors.error,
                  avatarColor: SetflowColors.primary,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '김도윤',
                  subtitle: '체중 감량 · 무릎 통증 있음',
                  trailing: '미답변',
                  trailingColor: context.setflowColors.error,
                  avatarColor: SetflowColors.primary,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '정민아',
                  subtitle: '체력 향상 · 러닝 병행 희망',
                  trailing: '답변 완료',
                  trailingColor: context.setflowColors.success,
                  avatarColor: SetflowColors.primary,
                ),
              ],
            ),
          ),
          _panel(
            title: '정산 현황',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이번 달 정산 예정',
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: SetflowSpacing.xs),
                Text(
                  '14,280,000원',
                  style: TextStyle(
                    fontSize: SetflowFontSize.headlineLarge,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: SetflowSpacing.lg),
                Divider(height: 1),
                SizedBox(height: SetflowSpacing.lg),
                _EntryRow(
                  name: '장기 코칭',
                  subtitle: '박트레이너 · 이준호',
                  trailing: '680,000원',
                  trailingColor: SetflowColors.ink,
                  avatarColor: context.setflowColors.success,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '환불 보류',
                  subtitle: '이코치 · 최서연',
                  trailing: '120,000원',
                  trailingColor: context.setflowColors.error,
                  avatarColor: context.setflowColors.error,
                ),
              ],
            ),
          ),
          _panel(
            title: '운영 알림',
            child: Column(
              children: [
                _EntryRow(
                  name: '신규 회원 배정 필요',
                  subtitle: '상담 완료 회원 3명',
                  trailing: '배정',
                  trailingColor: context.setflowColors.purple,
                  avatarColor: context.setflowColors.purple,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '피드백 이행률 확인',
                  subtitle: '이행률 80% 미만 트레이너 1명',
                  trailing: '보기',
                  trailingColor: context.setflowColors.orange,
                  avatarColor: context.setflowColors.orange,
                ),
              ],
            ),
          ),
        ],
      ),
      UserRole.admin => (
        title: '운영 워크스페이스',
        subtitle: 'Setflow 운영 현황',
        stats: [
          _StatTile(
            label: '전체 사용자',
            value: '8,420',
            suffix: '명',
            icon: Icons.groups_outlined,
            tint: context.setflowColors.blue,
          ),
          _StatTile(
            label: '활성 코칭',
            value: '284',
            suffix: '건',
            icon: Icons.handshake_outlined,
            tint: context.setflowColors.teal,
          ),
          _StatTile(
            label: '심사 대기',
            value: '14',
            suffix: '건',
            icon: Icons.fact_check_outlined,
            tint: context.setflowColors.orange,
          ),
          _StatTile(
            label: '신고 큐',
            value: '6',
            suffix: '건',
            icon: Icons.report_outlined,
            tint: context.setflowColors.error,
          ),
        ],
        panels: [
          _panel(
            title: 'SLA 처리 현황',
            child: Column(
              children: [
                _ProgressEntry(
                  label: 'Red 신고 · 1시간',
                  value: .82,
                  color: context.setflowColors.error,
                ),
                SizedBox(height: SetflowSpacing.xl),
                _ProgressEntry(
                  label: 'Orange 신고 · 24시간',
                  value: .94,
                  color: context.setflowColors.orange,
                ),
                SizedBox(height: SetflowSpacing.xl),
                _ProgressEntry(
                  label: '인증 심사 · 3영업일',
                  value: .97,
                  color: context.setflowColors.success,
                ),
              ],
            ),
          ),
          _panel(
            title: '시스템 상태',
            child: Column(
              children: [
                _EntryRow(
                  name: 'API',
                  subtitle: '정상',
                  trailing: '정상',
                  trailingColor: context.setflowColors.success,
                  avatarColor: context.setflowColors.success,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: 'OCR 서비스',
                  subtitle: '정상',
                  trailing: '정상',
                  trailingColor: context.setflowColors.success,
                  avatarColor: context.setflowColors.success,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '정산 배치',
                  subtitle: '대기 2건',
                  trailing: '대기',
                  trailingColor: context.setflowColors.orange,
                  avatarColor: context.setflowColors.orange,
                ),
              ],
            ),
          ),
        ],
      ),
      _ => (
        title: '트레이너 워크스페이스',
        subtitle: '안녕하세요, 김코치님',
        stats: [
          _StatTile(
            label: '이번 달 예상수익',
            value: '2,480,000',
            suffix: '원',
            icon: Icons.payments_outlined,
            tint: SetflowColors.primary,
          ),
          _StatTile(
            label: '관리 회원',
            value: '12',
            suffix: '/ 50명',
            icon: Icons.people_outline,
            tint: context.setflowColors.purple,
          ),
          _StatTile(
            label: '피드백 대기',
            value: '3',
            suffix: '건',
            icon: Icons.mark_chat_unread_outlined,
            tint: context.setflowColors.orange,
          ),
          _StatTile(
            label: '루틴 조회수',
            value: '1,284',
            suffix: '회',
            icon: Icons.bar_chart_rounded,
            tint: context.setflowColors.blue,
          ),
        ],
        panels: [
          _panel(
            title: '담당 회원 현황',
            child: Column(
              children: [
                _EntryRow(
                  name: '박민지',
                  subtitle: '근육 증가 · 마지막 기록 오늘',
                  trailing: '92%',
                  trailingColor: context.setflowColors.success,
                  avatarColor: SetflowColors.primary,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '이준호',
                  subtitle: '체중 감량 · 마지막 기록 어제',
                  trailing: '78%',
                  trailingColor: context.setflowColors.orange,
                  avatarColor: context.setflowColors.teal,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '정하늘',
                  subtitle: '건강 유지 · 마지막 기록 오늘',
                  trailing: '88%',
                  trailingColor: context.setflowColors.success,
                  avatarColor: context.setflowColors.blue,
                ),
              ],
            ),
          ),
          _panel(
            title: '상담 대기',
            child: Column(
              children: [
                _EntryRow(
                  name: '이수진',
                  subtitle: '근육 증가 · 운동 경력 3개월',
                  trailing: '미답변',
                  trailingColor: context.setflowColors.error,
                  avatarColor: SetflowColors.primary,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '김도윤',
                  subtitle: '체중 감량 · 무릎 통증 있음',
                  trailing: '미답변',
                  trailingColor: context.setflowColors.error,
                  avatarColor: SetflowColors.primary,
                ),
              ],
            ),
          ),
          _panel(
            title: '이번 달 정산',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이번 달 정산 예정',
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: SetflowSpacing.xs),
                Text(
                  '2,480,000원',
                  style: TextStyle(
                    fontSize: SetflowFontSize.headlineLarge,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: SetflowSpacing.lg),
                Divider(height: 1),
                SizedBox(height: SetflowSpacing.lg),
                _EntryRow(
                  name: '단기 코칭',
                  subtitle: '김코치 · 박민지',
                  trailing: '350,000원',
                  trailingColor: SetflowColors.ink,
                  avatarColor: context.setflowColors.success,
                ),
              ],
            ),
          ),
          _panel(
            title: '루틴 성과',
            child: Column(
              children: [
                _EntryRow(
                  name: '루틴 조회수',
                  subtitle: '지난달 대비',
                  trailing: '+18%',
                  trailingColor: context.setflowColors.success,
                  avatarColor: context.setflowColors.blue,
                ),
                Divider(height: 22),
                _EntryRow(
                  name: '상담 전환',
                  subtitle: '지난달 대비',
                  trailing: '+2.1%',
                  trailingColor: context.setflowColors.success,
                  avatarColor: context.setflowColors.purple,
                ),
              ],
            ),
          ),
        ],
      ),
    };
  }

  static Widget _panel({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(title),
        const SizedBox(height: SetflowSpacing.sm2),
        SetflowCard(child: child),
      ],
    );
  }
}

/// 넓은 화면에선 [columns]개의 열로, 좁은 화면에선 단일 열로 배치하는 그리드.
class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.width,
    required this.columns,
    required this.children,
  });
  final double width;
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        children: [
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: child),
        ],
      );
    }
    const gap = 16.0;
    final itemWidth = (width - gap * (columns - 1)) / columns;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final child in children) SizedBox(width: itemWidth, child: child),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    this.suffix,
  });
  final String label;
  final String value;
  final String? suffix;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => SetflowCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tint, size: 22),
        const SizedBox(height: SetflowSpacing.md2),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: SetflowFontSize.caption,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: SetflowSpacing.xs),
        RichText(
          text: TextSpan(
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: SetflowFontSize.headlineLarge,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (suffix != null)
                TextSpan(
                  text: ' $suffix',
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.name,
    required this.subtitle,
    required this.trailing,
    required this.trailingColor,
    required this.avatarColor,
  });
  final String name;
  final String subtitle;
  final String trailing;
  final Color trailingColor;
  final Color avatarColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        backgroundColor: avatarColor.withValues(alpha: .18),
        child: Text(
          name.characters.first,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      const SizedBox(width: SetflowSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: SetflowSpacing.xxs),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: SetflowFontSize.small,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: SetflowSpacing.sm),
      Text(
        trailing,
        style: TextStyle(fontWeight: FontWeight.w900, color: trailingColor),
      ),
    ],
  );
}

class _ProgressEntry extends StatelessWidget {
  const _ProgressEntry({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${(value * 100).toInt()}%',
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
      const SizedBox(height: SetflowSpacing.sm),
      LinearProgressIndicator(
        value: value,
        minHeight: 8,
        borderRadius: BorderRadius.circular(SetflowRadii.xs),
        color: color,
        backgroundColor: color.withValues(alpha: .12),
      ),
    ],
  );
}
