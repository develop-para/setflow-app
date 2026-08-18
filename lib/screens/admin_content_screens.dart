import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// Pushed-screen header: back [AppIconButton] + big w900 title, athletic
/// pattern language item 6. Kept private per file (see spec: don't share).
class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.lg,
        SetflowSpacing.sm,
        SetflowSpacing.lg,
        SetflowSpacing.xs,
      ),
      child: Row(
        children: [
          AppIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '뒤로',
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: SetflowSpacing.md),
          Expanded(
            child: Text(
              title,
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero stat block (pattern language item 1, simplified): a screen's key
/// count leads as a huge volt tabular numeral instead of a small caption.
class _HeroCount extends StatelessWidget {
  const _HeroCount({required this.label, required this.count, this.unit});

  final String label;
  final int count;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SetflowSpacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$count',
              style: text.displayMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: colors.primary,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: SetflowSpacing.xs),
              Text(
                unit!,
                style: text.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 루틴 심사: 금지 키워드 탐지 게시물 승인/반려 큐 데모.
class AdminContentRoutinesScreen extends StatefulWidget {
  const AdminContentRoutinesScreen({super.key});

  @override
  State<AdminContentRoutinesScreen> createState() =>
      _AdminContentRoutinesScreenState();
}

class _AdminContentRoutinesScreenState
    extends State<AdminContentRoutinesScreen> {
  final _queue = [
    (
      id: 'r1',
      author: '운동광',
      createdAt: '2026-05-20 10:15',
      title: '스테로이드 없이 만드는 왕팔 루틴',
      description: '약물(스테로이드) 절대 없이 네츄럴로만 만드는 진짜 팔운동 루틴입니다.',
      keywords: ['스테로이드', '약물'],
    ),
    (
      id: 'r2',
      author: '헬린이',
      createdAt: '2026-05-20 09:30',
      title: '불법약물 판매합니다 텔레그램 연락주세요',
      description: '루틴은 개뿔 불법약물 팜 텔레그램 @diet123',
      keywords: ['불법약물', '텔레그램'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _AdminHeader(title: '키워드 탐지 컨텐츠 검토'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _HeroCount(
                    label: '대기 중인 검토',
                    count: _queue.length,
                    unit: '건',
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  SetflowCard(
                    color: context.setflowColors.orange.withValues(alpha: .08),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          color: context.setflowColors.orange,
                        ),
                        const SizedBox(width: SetflowSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('자동 탐지 시스템 작동 중', style: text.titleMedium),
                              const SizedBox(height: SetflowSpacing.xs),
                              Text(
                                '금지 키워드(불법, 약물, 광고 등)가 포함된 게시물이 임시 차단되었습니다. 문맥을 검토하여 처리해주세요.',
                                style: text.labelMedium?.copyWith(height: 1.45),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  if (_queue.isEmpty)
                    const EmptyState(
                      icon: Icons.search_off,
                      title: '모든 컨텐츠 검토가 완료되었습니다',
                      message: '대기 중인 키워드 탐지 게시물이 없습니다.',
                    )
                  else
                    for (final item in _queue)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.md,
                        ),
                        child: SetflowCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StatusChip(
                                label: '키워드 탐지: ${item.keywords.join(', ')}',
                                color: colors.error,
                              ),
                              const SizedBox(height: SetflowSpacing.md),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '작성자: ${item.author}',
                                    style: text.labelMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    item.createdAt,
                                    style: text.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: context.setflowColors.disabled,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: SetflowSpacing.sm),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  SetflowSpacing.md,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      context.setflowColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(
                                    SetflowRadii.md,
                                  ),
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.title, style: text.titleMedium),
                                    const SizedBox(height: SetflowSpacing.xs),
                                    Text(
                                      item.description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodyMedium?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.lg),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _reject(item.id),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: colors.error,
                                        side: BorderSide(color: colors.error),
                                      ),
                                      icon: const Icon(
                                        Icons.cancel_outlined,
                                        size: 18,
                                      ),
                                      label: const Text('게시물 삭제 (경고)'),
                                    ),
                                  ),
                                  const SizedBox(width: SetflowSpacing.sm),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => _approve(item.id),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: colors.inverseSurface,
                                        foregroundColor:
                                            colors.onInverseSurface,
                                      ),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 18,
                                      ),
                                      label: const Text('문맥상 정상 (승인)'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(String id) async {
    final confirmed = await _confirm(
      '금지 키워드가 포함되어 있지만, 문맥상 정상적인 글입니다.\n승인(통과) 처리하시겠습니까?',
    );
    if (confirmed == true && mounted) {
      setState(() => _queue.removeWhere((q) => q.id == id));
      showMessage(context, '정상 컨텐츠로 승인되었습니다.');
    }
  }

  Future<void> _reject(String id) async {
    final confirmed = await _confirm('부적절한 컨텐츠로 확인되어 삭제 및 작성자에게 경고를 발송하시겠습니까?');
    if (confirmed == true && mounted) {
      setState(() => _queue.removeWhere((q) => q.id == id));
      showMessage(context, '컨텐츠가 삭제되고 경고가 발송되었습니다.');
    }
  }

  Future<bool?> _confirm(String message) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

/// 신고 처리: 유저 신고 큐 + 등급/SLA 표시 + 삭제·기각 조치 데모.
class AdminContentReportsScreen extends StatefulWidget {
  const AdminContentReportsScreen({super.key});

  @override
  State<AdminContentReportsScreen> createState() =>
      _AdminContentReportsScreenState();
}

class _AdminContentReportsScreenState extends State<AdminContentReportsScreen> {
  final _queue = [
    (
      id: 'rep1',
      targetType: '게시글',
      targetTitle: '운동할 때 욕 나오네 XX',
      author: '화난근육',
      reportCount: 5,
      grade: 'Red',
      isAutoBlinded: true,
      reportedAt: '2026-05-20 10:00',
      slaHoursLeft: 1,
      reasons: ['욕설/혐오 발언', '스팸/도배'],
    ),
    (
      id: 'rep2',
      targetType: '댓글',
      targetTitle: '이 루틴 진짜 별로네요.',
      author: '불만유저',
      reportCount: 3,
      grade: 'Orange',
      isAutoBlinded: false,
      reportedAt: '2026-05-19 15:30',
      slaHoursLeft: 12,
      reasons: ['타인 비방'],
    ),
    (
      id: 'rep3',
      targetType: '게시글',
      targetTitle: '나만 아는 꿀팁 (사실 아님)',
      author: '어그로꾼',
      reportCount: 1,
      grade: 'Yellow',
      isAutoBlinded: false,
      reportedAt: '2026-05-18 09:00',
      slaHoursLeft: -5,
      reasons: ['잘못된 정보'],
    ),
  ];

  String? _expandedId;

  Color _gradeColor(BuildContext context, String grade) => switch (grade) {
    'Red' => Theme.of(context).colorScheme.error,
    'Orange' => context.setflowColors.orange,
    _ => Theme.of(context).colorScheme.primary,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _AdminHeader(title: '유저 신고 검토 대기'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _HeroCount(
                        label: '대기 중인 검토',
                        count: _queue.length,
                        unit: '건',
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: SetflowSpacing.xs,
                        children: [
                          for (final grade in const ['Red', 'Orange', 'Yellow'])
                            StatusChip(
                              label: grade,
                              color: _gradeColor(context, grade),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  if (_queue.isEmpty)
                    const EmptyState(
                      icon: Icons.search_off,
                      title: '모든 신고 처리 완료!',
                      message: '대기 중인 신고 건이 없습니다.',
                    )
                  else
                    for (final item in _queue)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.md,
                        ),
                        child: SetflowCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  StatusChip(
                                    label: '등급: ${item.grade}',
                                    color: _gradeColor(context, item.grade),
                                  ),
                                  if (item.isAutoBlinded) ...[
                                    const SizedBox(width: SetflowSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: SetflowSpacing.sm,
                                        vertical: SetflowSpacing.xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.inverseSurface,
                                        borderRadius: BorderRadius.circular(
                                          SetflowRadii.xs,
                                        ),
                                      ),
                                      child: Text(
                                        '자동 블라인드',
                                        style: text.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: colors.onInverseSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  Text(
                                    item.slaHoursLeft < 0
                                        ? 'SLA 초과 (H+${item.slaHoursLeft.abs()})'
                                        : 'SLA H-${item.slaHoursLeft}',
                                    style: text.labelMedium?.copyWith(
                                      color: item.slaHoursLeft < 0
                                          ? colors.error
                                          : item.slaHoursLeft <= 2
                                          ? context.setflowColors.orange
                                          : context.setflowColors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: SetflowSpacing.sm),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '[${item.targetType}] 작성자: ${item.author}',
                                      style: text.labelMedium?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '누적 신고: ${item.reportCount}회',
                                    style: text.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: colors.error,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  SetflowSpacing.md,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      context.setflowColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(
                                    SetflowRadii.sm,
                                  ),
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  '"${item.targetTitle}"',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              Wrap(
                                spacing: SetflowSpacing.xs,
                                runSpacing: SetflowSpacing.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '신고 사유:',
                                    style: text.labelMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  for (final reason in item.reasons)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: SetflowSpacing.sm,
                                        vertical: SetflowSpacing.xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context
                                            .setflowColors
                                            .surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(
                                          SetflowRadii.xs,
                                        ),
                                      ),
                                      child: Text(
                                        reason,
                                        style: text.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: SetflowSpacing.md),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: () => setState(
                                    () => _expandedId = _expandedId == item.id
                                        ? null
                                        : item.id,
                                  ),
                                  child: Text(
                                    _expandedId == item.id ? '상세 닫기' : '상세 검토',
                                  ),
                                ),
                              ),
                              if (_expandedId == item.id) ...[
                                const SizedBox(height: SetflowSpacing.sm),
                                const Divider(height: 1),
                                const SizedBox(height: SetflowSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            _act(item.id, delete: true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: colors.error,
                                        ),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                        ),
                                        label: const Text('삭제 처리'),
                                      ),
                                    ),
                                    const SizedBox(width: SetflowSpacing.sm),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _act(item.id, delete: false),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          size: 18,
                                        ),
                                        label: const Text('기각 (정상)'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _act(String id, {required bool delete}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(
          delete
              ? '부적절한 컨텐츠로 규정하여 완전히 삭제하시겠습니까?'
              : '문제가 없다고 판단하여 신고를 기각하시겠습니까? (블라인드 해제)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _queue.removeWhere((q) => q.id == id);
        _expandedId = null;
      });
      showMessage(
        context,
        delete ? '컨텐츠가 완전히 삭제되었습니다.' : '신고가 기각되고 정상 처리되었습니다.',
      );
    }
  }
}

/// 제재 이력: 유저 검색 + 누적 제재 단계 타임라인 데모.
class AdminUserSanctionHistoryScreen extends StatefulWidget {
  const AdminUserSanctionHistoryScreen({super.key});

  @override
  State<AdminUserSanctionHistoryScreen> createState() =>
      _AdminUserSanctionHistoryScreenState();
}

class _AdminUserSanctionHistoryScreenState
    extends State<AdminUserSanctionHistoryScreen> {
  final _controller = TextEditingController();

  static const _mockUsers = [
    (
      id: 'u1',
      nickname: '김근육',
      email: 'muscle@test.com',
      currentLevel: 1,
      history: [
        (
          id: 'h1',
          date: '2026.05.10 14:22',
          level: 1,
          title: '1차 제재 (경고)',
          reason: '게시판 도배',
          admin: 'Admin (admin1)',
        ),
      ],
    ),
    (
      id: 'u2',
      nickname: '상습범',
      email: 'badboy@test.com',
      currentLevel: 3,
      history: [
        (
          id: 'h4',
          date: '2026.05.18 09:12',
          level: 3,
          title: '3차 제재 (30일 정지)',
          reason: '타인 비방 및 욕설 반복',
          admin: 'Admin (admin2)',
        ),
        (
          id: 'h3',
          date: '2026.04.15 11:30',
          level: 2,
          title: '2차 제재 (7일 정지)',
          reason: '욕설',
          admin: 'Admin (admin1)',
        ),
        (
          id: 'h2',
          date: '2025.11.05 16:40',
          level: 1,
          title: '1차 제재 (경고)',
          reason: '광고성 게시글',
          admin: 'Admin (admin1)',
        ),
      ],
    ),
    (
      id: 'u3',
      nickname: '클린유저',
      email: 'clean@test.com',
      currentLevel: 0,
      history:
          <
            ({
              String id,
              String date,
              int level,
              String title,
              String reason,
              String admin,
            })
          >[],
    ),
  ];

  ({
    String id,
    String nickname,
    String email,
    int currentLevel,
    List<
      ({
        String id,
        String date,
        int level,
        String title,
        String reason,
        String admin,
      })
    >
    history,
  })?
  _selectedUser;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _levelColor(BuildContext context, int level) => switch (level) {
    1 => context.setflowColors.orange,
    2 || 3 => Theme.of(context).colorScheme.error,
    4 => Theme.of(context).colorScheme.onSurface,
    _ => context.setflowColors.disabled,
  };

  IconData _levelIcon(int level) => switch (level) {
    1 => Icons.report_gmailerrorred_outlined,
    2 || 3 => Icons.timer_outlined,
    4 => Icons.person_off_outlined,
    _ => Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final user = _selectedUser;
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _AdminHeader(title: '제재 이력 관리'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _controller,
                          onSubmitted: (_) => _search(),
                          prefixIcon: const Icon(Icons.search),
                          hint: '유저 닉네임 또는 이메일 검색',
                        ),
                      ),
                      const SizedBox(width: SetflowSpacing.sm),
                      FilledButton(
                        onPressed: _search,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.inverseSurface,
                          foregroundColor: colors.onInverseSurface,
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.md,
                            ),
                          ),
                        ),
                        child: const Text('검색'),
                      ),
                    ],
                  ),
                  if (user != null) ...[
                    const SizedBox(height: SetflowSpacing.xl),
                    SetflowCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color:
                                      context.setflowColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(
                                    SetflowRadii.full,
                                  ),
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: Icon(
                                  Icons.person_outline,
                                  color: context.setflowColors.disabled,
                                ),
                              ),
                              const SizedBox(width: SetflowSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.nickname,
                                      style: text.titleMedium,
                                    ),
                                    Text(
                                      user.email,
                                      style: text.labelMedium?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '현재 누적 단계',
                                    style: text.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: SetflowSpacing.xs),
                                  StatusChip(
                                    label: user.currentLevel > 0
                                        ? '${user.currentLevel}단계'
                                        : '정상 (클린)',
                                    color: _levelColor(
                                      context,
                                      user.currentLevel,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (user.currentLevel > 0) ...[
                            const SizedBox(height: SetflowSpacing.lg),
                            const Divider(height: 1),
                            const SizedBox(height: SetflowSpacing.md),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _resetLevel,
                                icon: const Icon(Icons.restart_alt, size: 18),
                                label: const Text('누적 단계 리셋 (12개월 경과 후)'),
                              ),
                            ),
                            const SizedBox(height: SetflowSpacing.xs),
                            Text(
                              '마지막 제재일로부터 12개월 경과 시 누적 단계 리셋 (이력은 남음)',
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(
                                color: context.setflowColors.disabled,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: SetflowSpacing.xl),
                    const SectionTitle('제재 이력 타임라인'),
                    const SizedBox(height: SetflowSpacing.md),
                    if (user.history.isEmpty)
                      const EmptyState(
                        icon: Icons.shield_outlined,
                        title: '제재 이력이 없는 클린 유저입니다',
                        message: '해당 유저에게 등록된 제재 이력이 없습니다.',
                      )
                    else
                      SetflowCard(
                        child: Column(
                          children: [
                            for (final hist in user.history)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: SetflowSpacing.md,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TintedIconBadge(
                                      icon: _levelIcon(hist.level),
                                      color: _levelColor(context, hist.level),
                                      size: 32,
                                      iconSize: 16,
                                    ),
                                    const SizedBox(width: SetflowSpacing.sm),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(
                                          SetflowSpacing.md,
                                        ),
                                        decoration: BoxDecoration(
                                          color: context
                                              .setflowColors
                                              .surfaceContainerLow,
                                          borderRadius: BorderRadius.circular(
                                            SetflowRadii.sm,
                                          ),
                                          border: Border.all(
                                            color: colors.outlineVariant,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  hist.title,
                                                  style: text.bodySmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: _levelColor(
                                                          context,
                                                          hist.level,
                                                        ),
                                                      ),
                                                ),
                                                Text(
                                                  hist.date,
                                                  style: text.bodySmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: context
                                                            .setflowColors
                                                            .disabled,
                                                      ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(
                                              height: SetflowSpacing.xs,
                                            ),
                                            Text(
                                              '사유: ${hist.reason}',
                                              style: text.labelMedium,
                                            ),
                                            const SizedBox(
                                              height: SetflowSpacing.sm,
                                            ),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Text(
                                                '처리자: ${hist.admin}',
                                                style: text.bodySmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _search() {
    final query = _controller.text.trim();
    final match = _mockUsers.where(
      (u) => u.nickname.contains(query) || u.email.contains(query),
    );
    if (match.isEmpty) {
      showMessage(context, '검색 결과가 없습니다.');
      setState(() => _selectedUser = null);
      return;
    }
    setState(() => _selectedUser = match.first);
  }

  Future<void> _resetLevel() async {
    final user = _selectedUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('12개월 경과 또는 소명 완료로 제재 누적 단계를 리셋하시겠습니까? (이력은 보존됨)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(
        () => _selectedUser = (
          id: user.id,
          nickname: user.nickname,
          email: user.email,
          currentLevel: 0,
          history: user.history,
        ),
      );
      showMessage(context, '제재 누적 단계가 리셋되었습니다.');
    }
  }
}

/// 미성년 알림: 위험 행동 감지 현황 리스트 + 경고/검토/오탐 조치 데모.
class AdminContentMinorAlertsScreen extends StatefulWidget {
  const AdminContentMinorAlertsScreen({super.key});

  @override
  State<AdminContentMinorAlertsScreen> createState() =>
      _AdminContentMinorAlertsScreenState();
}

class _AdminContentMinorAlertsScreenState
    extends State<AdminContentMinorAlertsScreen> {
  final _alerts = [
    (
      id: 'al1',
      user: '매크로충',
      severity: 'High',
      type: 'Abuse',
      detectedAt: '2026-05-20 11:30',
      description: '동일 기기에서 짧은 시간 내 다수 계정 가입 시도 감지 (IP: 192.168.0.1)',
    ),
    (
      id: 'al2',
      user: '도배러',
      severity: 'Medium',
      type: 'Spam',
      detectedAt: '2026-05-20 10:15',
      description: '1분 내에 10개 이상의 동일한 댓글 반복 작성 (어뷰징 의심)',
    ),
    (
      id: 'al3',
      user: '초보운동러',
      severity: 'Low',
      type: 'Minor',
      detectedAt: '2026-05-19 22:40',
      description: '하루 동안 루틴 완료 취소 20회 반복 (비정상적 앱 사용 패턴)',
    ),
  ];

  Color _severityColor(BuildContext context, String severity) =>
      switch (severity) {
        'High' => Theme.of(context).colorScheme.error,
        'Medium' => context.setflowColors.orange,
        _ => Theme.of(context).colorScheme.primary,
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _AdminHeader(title: '위험 행동 감지 현황'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  _HeroCount(
                    label: '신규 감지 알림',
                    count: _alerts.length,
                    unit: '건',
                  ),
                  const SizedBox(height: SetflowSpacing.lg),
                  if (_alerts.isEmpty)
                    const EmptyState(
                      icon: Icons.verified_user_outlined,
                      title: '감지된 위험 알림이 없습니다',
                      message: '현재 대기 중인 위험 행동 알림이 없습니다.',
                    )
                  else
                    for (final item in _alerts)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.md,
                        ),
                        child: SetflowCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  StatusChip(
                                    label: '심각도: ${item.severity}',
                                    color: _severityColor(
                                      context,
                                      item.severity,
                                    ),
                                  ),
                                  const SizedBox(width: SetflowSpacing.xs),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: SetflowSpacing.sm,
                                      vertical: SetflowSpacing.xs,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context
                                          .setflowColors
                                          .surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(
                                        SetflowRadii.xs,
                                      ),
                                    ),
                                    child: Text(
                                      item.type,
                                      style: text.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    item.detectedAt,
                                    style: text.labelMedium?.copyWith(
                                      color: context.setflowColors.disabled,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: SetflowSpacing.sm),
                              Text(
                                '감지 대상 유저: ${item.user}',
                                style: text.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  SetflowSpacing.md,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      context.setflowColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(
                                    SetflowRadii.md,
                                  ),
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: Text(
                                  item.description,
                                  style: text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.md),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _chooseAction(context, item.id),
                                  icon: const Icon(
                                    Icons.rule_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('조치 선택'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseAction(BuildContext context, String id) async {
    final action = await showAppActionSheet<String>(
      context,
      title: '이 알림에 대한 조치',
      actions: [
        SheetAction(
          icon: Icons.mail_outline,
          label: '앱내 경고 발송',
          value: '앱내 경고 발송',
        ),
        SheetAction(
          icon: Icons.person_search_outlined,
          label: '계정 집중 검토',
          value: '계정 집중 검토',
          destructive: true,
        ),
        SheetAction(
          icon: Icons.close_rounded,
          label: '오탐 처리 (닫기)',
          value: '오탐 처리',
        ),
      ],
    );
    if (action != null && mounted) _act(id, action);
  }

  void _act(String id, String action) {
    final message = switch (action) {
      '앱내 경고 발송' => '해당 유저에게 경고 팝업이 발송되었습니다.',
      '계정 집중 검토' => '계정 상세 검토 페이지로 이동합니다. (현재는 목록에서 숨김 처리)',
      _ => '위험 알림이 무시(오탐 처리)되었습니다.',
    };
    setState(() => _alerts.removeWhere((a) => a.id == id));
    showMessage(context, message);
  }
}
