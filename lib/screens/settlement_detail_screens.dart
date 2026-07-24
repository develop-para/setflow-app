import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// [SettlementPage]에서 진입하는 환불 내역 상세 화면.
/// 역할(trainer/gym/admin)에 따라 안내 문구와 더미 데이터가 달라진다.
class SettlementRefundsPage extends StatelessWidget {
  const SettlementRefundsPage({required this.role, super.key});
  final UserRole role;

  bool get _admin => role == UserRole.admin;

  List<_RefundItem> get _items => switch (role) {
    UserRole.admin => const [
      _RefundItem(
        date: '05.18',
        member: '박이탈',
        detail: '김동현 코치 · 1개월 밀착 코칭',
        amount: 150000,
        status: _RefundStatus.pending,
        reason: '코치님이 연락이 3일째 안 됩니다. 환불해주세요.',
      ),
      _RefundItem(
        date: '05.19',
        member: '최변심',
        detail: '이민수 코치 · 원데이 식단 피드백',
        amount: 35000,
        status: _RefundStatus.pending,
        reason: '다리 부상으로 당분간 운동이 어렵습니다.',
      ),
      _RefundItem(
        date: '05.10',
        member: '정환불',
        detail: '박지은 코치 · PT 10회권',
        amount: 420000,
        status: _RefundStatus.completed,
        reason: '단순 변심',
      ),
    ],
    UserRole.gym => const [
      _RefundItem(
        date: '05.19',
        member: '박소현',
        detail: 'PT 10회권 (잔여 7회)',
        amount: 420000,
        status: _RefundStatus.completed,
        reason: '이사에 따른 환불',
      ),
      _RefundItem(
        date: '05.14',
        member: '김철수',
        detail: '루틴 1개월 구독',
        amount: 30000,
        status: _RefundStatus.pending,
        reason: '단순 변심',
      ),
      _RefundItem(
        date: '05.02',
        member: '이영희',
        detail: 'PT 20회권 (잔여 20회)',
        amount: 1100000,
        status: _RefundStatus.completed,
        reason: '건강상 이유',
      ),
    ],
    _ => const [
      _RefundItem(
        date: '10.28',
        member: '김헬린',
        detail: '4주 완성 직장인 다이어트 풀코스',
        amount: 38000,
        status: _RefundStatus.completed,
        reason: '단순 변심',
      ),
      _RefundItem(
        date: '10.29',
        member: '바프도전기',
        detail: '바디프로필 D-30 극한의 컷팅',
        amount: 150000,
        status: _RefundStatus.pending,
        reason: '코칭 피드백 지연',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    final pendingTotal = items
        .where((item) => item.status == _RefundStatus.pending)
        .fold<int>(0, (sum, item) => sum + item.amount);
    final pendingCount = items
        .where((item) => item.status == _RefundStatus.pending)
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(_admin ? '환불 및 분쟁 관리' : '환불 및 미정산 내역')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          _DarkStatBanner(
            caption: '심사·처리 대기 중인 환불 금액',
            value: _formatAmount(pendingTotal),
            unit: '원',
            note: _admin
                ? '승인/거절 처리에 따라 담당 코치 정산액이 조정됩니다.'
                : '환불 통보일로부터 7일 이내 이의 제기가 가능합니다.',
            badge: pendingCount > 0
                ? StatusChip(
                    label: '$pendingCount건 대기',
                    color: context.setflowColors.orange,
                  )
                : null,
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('환불 접수 내역'),
          const SizedBox(height: SetflowSpacing.md),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
              child: SetflowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: SetflowColors.red.withValues(
                            alpha: .12,
                          ),
                          child: Text(
                            item.date,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: SetflowColors.red,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: SetflowSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.member} 님',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                item.detail,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _refundStatusChip(context, item.status),
                      ],
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(SetflowSpacing.md),
                      decoration: BoxDecoration(
                        color: context.setflowColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(SetflowRadii.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '사유: ${item.reason}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: SetflowSpacing.sm),
                          Text(
                            '-${_formatAmount(item.amount)}원',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: SetflowColors.red,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.status == _RefundStatus.pending) ...[
                      const SizedBox(height: SetflowSpacing.md),
                      if (_admin)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => showMessage(
                                  context,
                                  '${item.member} 님의 환불 요청을 거절했습니다.',
                                ),
                                child: const Text('환불 거절'),
                              ),
                            ),
                            const SizedBox(width: SetflowSpacing.sm),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => showMessage(
                                  context,
                                  '${item.member} 님의 환불을 승인했습니다.',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: SetflowColors.green,
                                ),
                                child: const Text('전액 환불 승인'),
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => showMessage(
                              context,
                              '${item.member} 님 환불 건에 이의를 제기했습니다.',
                            ),
                            child: const Text('이의(분쟁) 제기 신청'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _RefundStatus { pending, completed, disputed }

class _RefundItem {
  const _RefundItem({
    required this.date,
    required this.member,
    required this.detail,
    required this.amount,
    required this.status,
    required this.reason,
  });

  final String date;
  final String member;
  final String detail;
  final int amount;
  final _RefundStatus status;
  final String reason;
}

StatusChip _refundStatusChip(BuildContext context, _RefundStatus status) =>
    switch (status) {
      _RefundStatus.pending => StatusChip(
        label: '심사 대기',
        color: context.setflowColors.orange,
      ),
      _RefundStatus.completed => StatusChip(
        label: '처리 완료',
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      _RefundStatus.disputed => const StatusChip(
        label: '분쟁 중',
        color: SetflowColors.red,
      ),
    };

/// [SettlementPage]에서 진입하는 트레이너별 정산 분배 상세 화면 (gym/admin 전용).
class TrainerSettlementBreakdownPage extends StatelessWidget {
  const TrainerSettlementBreakdownPage({required this.role, super.key});
  final UserRole role;

  static const _grades = [
    ('수석 코치', 70),
    ('시니어 코치', 60),
    ('일반 코치', 50),
    ('파트타임', 40),
  ];

  static const _trainers = [
    _TrainerSettlement(
      name: '김동현',
      grade: '수석 코치',
      ratio: 70,
      generated: 4000000,
      share: 2800000,
    ),
    _TrainerSettlement(
      name: '박지은',
      grade: '시니어 코치',
      ratio: 60,
      generated: 3000000,
      share: 1800000,
    ),
    _TrainerSettlement(
      name: '이민수',
      grade: '일반 코치',
      ratio: 50,
      generated: 2000000,
      share: 1000000,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalShare = _trainers.fold<int>(0, (sum, t) => sum + t.share);

    return Scaffold(
      appBar: AppBar(
        title: Text(role == UserRole.admin ? '트레이너별 정산 현황' : '트레이너별 정산'),
      ),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          _DarkStatBanner(
            caption: '이번 달 코치 총 분배액',
            value: _formatAmount(totalShare),
            unit: '원',
            badge: StatusChip(
              label: '${_trainers.length}명',
              color: context.setflowColors.blue,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('직급별 수수료 배분 비율'),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              for (final grade in _grades) ...[
                Expanded(
                  child: SetflowCard(
                    padding: const EdgeInsets.symmetric(
                      vertical: SetflowSpacing.md,
                      horizontal: SetflowSpacing.sm,
                    ),
                    child: Column(
                      children: [
                        Text(
                          grade.$1,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: SetflowSpacing.xs),
                        Text(
                          '${grade.$2}%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (grade != _grades.last) const SizedBox(width: SetflowSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('소속 코치 분배 내역'),
          const SizedBox(height: SetflowSpacing.md),
          for (final trainer in _trainers)
            Padding(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
              child: SetflowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: context.setflowColors.blue
                              .withValues(alpha: .15),
                          child: Text(
                            trainer.name.characters.first,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: SetflowSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${trainer.name} 코치',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              Text(
                                '${trainer.grade} · 배분율 ${trainer.ratio}%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(SetflowSpacing.md),
                      decoration: BoxDecoration(
                        color: context.setflowColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(SetflowRadii.md),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '발생 매출',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${_formatAmount(trainer.generated)}원',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: SetflowSpacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '최종 분배액',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: context.setflowColors.blue,
                                ),
                              ),
                              Text(
                                '${_formatAmount(trainer.share)}원',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: context.setflowColors.blue,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
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

class _TrainerSettlement {
  const _TrainerSettlement({
    required this.name,
    required this.grade,
    required this.ratio,
    required this.generated,
    required this.share,
  });

  final String name;
  final String grade;
  final int ratio;
  final int generated;
  final int share;
}

String _formatAmount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Athletic hero-stat block (pattern 1): muted label row with an optional
/// [StatusChip]/count badge, then a huge volt tabular numeral with a small
/// dim unit beside it, and an optional note line. Used in place of
/// [HeroStatBanner]'s solid brand fill so every settlement page reads
/// consistently on the dark-athletic elevated card surface.
class _DarkStatBanner extends StatelessWidget {
  const _DarkStatBanner({
    required this.caption,
    required this.value,
    this.unit,
    this.note,
    this.badge,
  });

  final String caption;
  final String value;
  final String? unit;
  final String? note;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      color: context.setflowColors.surfaceContainerHigh,
      padding: const EdgeInsets.all(SetflowSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                caption,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: SetflowSpacing.sm),
                badge!,
              ],
            ],
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.displayMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: SetflowSpacing.xs),
                Text(
                  unit!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              note!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// [SettlementPage]에서 진입하는 수수료 정산 상세 화면 (admin 전용).
/// 사업자/트레이너별 매출·수수료율·수수료액 리스트와 합계를 보여준다.
class SettlementCommissionPage extends StatelessWidget {
  const SettlementCommissionPage({required this.role, super.key});
  final UserRole role;

  static const _items = [
    _CommissionItem(type: '트레이너', name: '김동현 코치', revenue: 4000000, rate: 15),
    _CommissionItem(type: '트레이너', name: '이민수 코치', revenue: 2000000, rate: 20),
    _CommissionItem(type: '사업자', name: '이지짐 강남점', revenue: 12500000, rate: 8),
    _CommissionItem(type: '사업자', name: '헬스원 송파점', revenue: 8300000, rate: 8),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalRevenue = _items.fold<int>(0, (sum, i) => sum + i.revenue);
    final totalCommission = _items.fold<int>(0, (sum, i) => sum + i.commission);

    return Scaffold(
      appBar: AppBar(title: const Text('수수료 정산')),
      body: ListView(
        padding: SetflowInsets.pageList,
        children: [
          _DarkStatBanner(
            caption: '이번 달 플랫폼 수수료 합계',
            value: _formatAmount(totalCommission),
            unit: '원',
            note: '총 매출 ${_formatAmount(totalRevenue)}원 기준 산정',
            badge: StatusChip(
              label: '${_items.length}건',
              color: context.setflowColors.purple,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('사업자·트레이너별 수수료 내역'),
          const SizedBox(height: SetflowSpacing.md),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
              child: SetflowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                          label: item.type,
                          color: item.type == '트레이너'
                              ? context.setflowColors.blue
                              : context.setflowColors.purple,
                        ),
                        const SizedBox(width: SetflowSpacing.sm),
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          '수수료율 ${item.rate}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(SetflowSpacing.md),
                      decoration: BoxDecoration(
                        color: context.setflowColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(SetflowRadii.md),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '발생 매출',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${_formatAmount(item.revenue)}원',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '플랫폼 수수료',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${_formatAmount(item.commission)}원',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('합계'),
          const SizedBox(height: SetflowSpacing.md),
          SetflowCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '총 매출',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${_formatAmount(totalRevenue)}원',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SetflowSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '총 플랫폼 수수료',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${_formatAmount(totalCommission)}원',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommissionItem {
  const _CommissionItem({
    required this.type,
    required this.name,
    required this.revenue,
    required this.rate,
  });

  final String type;
  final String name;
  final int revenue;
  final int rate;

  int get commission => (revenue * rate / 100).round();
}

/// [SettlementPage]에서 진입하는 최종 정산 확정 화면 (admin 전용).
/// 지급 대상 리스트와 "확정" 액션(데모 상태 토글)을 제공한다.
///
/// Athletic patterns 3 + 5: rows stay quiet until they're the next
/// actionable item (surface-2 highlight); a single sticky volt CTA at the
/// bottom drives that item through its two steps, with a confirmation
/// dialog before the irreversible final step and a success snackbar after.
class SettlementFinalConfirmPage extends StatefulWidget {
  const SettlementFinalConfirmPage({required this.role, super.key});
  final UserRole role;

  @override
  State<SettlementFinalConfirmPage> createState() =>
      _SettlementFinalConfirmPageState();
}

class _SettlementFinalConfirmPageState
    extends State<SettlementFinalConfirmPage> {
  final _items = [
    _PayoutItem(name: '박은지 코치', account: '국민 123456-78-901234', amount: 345000),
    _PayoutItem(name: '정근육 코치', account: '신한 110-123-456789', amount: 85000),
    _PayoutItem(
      name: '이지짐 강남점',
      account: '우리 1002-345-678901',
      amount: 1250000,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingCount = _items
        .where((item) => item.status != _PayoutStatus.confirmed)
        .length;
    final pendingAmount = _items
        .where((item) => item.status != _PayoutStatus.confirmed)
        .fold<int>(0, (sum, item) => sum + item.amount);
    final nextIndex = _items.indexWhere(
      (item) => item.status != _PayoutStatus.confirmed,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('최종 정산 확정')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: SetflowInsets.pageList,
              children: [
                _DarkStatBanner(
                  caption: '확정 대기 중인 지급액',
                  value: _formatAmount(pendingAmount),
                  unit: '원',
                  badge: pendingCount > 0
                      ? StatusChip(
                          label: '$pendingCount건 대기',
                          color: context.setflowColors.orange,
                        )
                      : null,
                ),
                const SizedBox(height: SetflowSpacing.xxl),
                const SectionTitle('지급 대상 목록'),
                const SizedBox(height: SetflowSpacing.md),
                for (var i = 0; i < _items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                    child: SetflowCard(
                      color: i == nextIndex
                          ? context.setflowColors.surfaceContainer
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _items[i].name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              _payoutStatusChip(context, _items[i].status),
                            ],
                          ),
                          const SizedBox(height: SetflowSpacing.md),
                          Container(
                            padding: const EdgeInsets.all(SetflowSpacing.md),
                            decoration: BoxDecoration(
                              color: context.setflowColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(
                                SetflowRadii.md,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '지급 계좌: ${_items[i].account}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: SetflowSpacing.sm),
                                Text(
                                  '${_formatAmount(_items[i].amount)}원',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_items[i].status == _PayoutStatus.confirmed) ...[
                            const SizedBox(height: SetflowSpacing.md),
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: SetflowColors.green,
                                ),
                                const SizedBox(width: SetflowSpacing.sm),
                                Text(
                                  '최종 정산이 확정되었습니다.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: SetflowColors.green,
                                    fontWeight: FontWeight.w800,
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
          if (nextIndex != -1)
            Padding(
              padding: SetflowInsets.bottomAction,
              child: PrimaryButton(
                label: _items[nextIndex].status == _PayoutStatus.pending
                    ? '${_items[nextIndex].name} 입금 처리 시작'
                    : '${_items[nextIndex].name} 최종 정산 확정',
                onPressed: () => _advance(nextIndex),
              ),
            )
          else
            Padding(
              padding: SetflowInsets.bottomAction,
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: SetflowColors.green),
                  const SizedBox(width: SetflowSpacing.sm),
                  Text(
                    '전체 정산이 확정되었습니다.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: SetflowColors.green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _advance(int index) async {
    final item = _items[index];
    if (item.status == _PayoutStatus.pending) {
      setState(() => item.status = _PayoutStatus.processing);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('최종 정산을 확정할까요?'),
        content: Text(
          '${item.name}님에게 ${_formatAmount(item.amount)}원을 지급 처리합니다. '
          '확정 후에는 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              '확정',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => item.status = _PayoutStatus.confirmed);
      if (context.mounted) {
        AppSnackbar.success(context, '${item.name}님 정산을 확정했어요.');
      }
    }
  }
}

enum _PayoutStatus { pending, processing, confirmed }

class _PayoutItem {
  _PayoutItem({
    required this.name,
    required this.account,
    required this.amount,
  });

  final String name;
  final String account;
  final int amount;
  _PayoutStatus status = _PayoutStatus.pending;
}

StatusChip _payoutStatusChip(BuildContext context, _PayoutStatus status) =>
    switch (status) {
      _PayoutStatus.pending => StatusChip(
        label: '확정 대기',
        color: context.setflowColors.orange,
      ),
      _PayoutStatus.processing => StatusChip(
        label: '처리 중',
        color: context.setflowColors.blue,
      ),
      _PayoutStatus.confirmed => const StatusChip(
        label: '확정 완료',
        color: SetflowColors.green,
      ),
    };
