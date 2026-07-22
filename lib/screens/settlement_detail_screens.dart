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
    final items = _items;
    final pendingTotal = items
        .where((item) => item.status == _RefundStatus.pending)
        .fold<int>(0, (sum, item) => sum + item.amount);

    return Scaffold(
      appBar: AppBar(title: Text(_admin ? '환불 및 분쟁 관리' : '환불 및 미정산 내역')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SetflowColors.red,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '심사·처리 대기 중인 환불 금액',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatAmount(pendingTotal)}원',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _admin
                      ? '승인/거절 처리에 따라 담당 코치 정산액이 조정됩니다.'
                      : '환불 통보일로부터 7일 이내 이의 제기가 가능합니다.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('환불 접수 내역'),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: SetflowColors.red,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
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
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: SetflowColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusChip(status: item.status),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: SetflowColors.soft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '사유: ${item.reason}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: SetflowColors.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '-${_formatAmount(item.amount)}원',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: SetflowColors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.status == _RefundStatus.pending) ...[
                      const SizedBox(height: 10),
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
                            const SizedBox(width: 8),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final _RefundStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      _RefundStatus.pending => ('심사 대기', SetflowColors.orange),
      _RefundStatus.completed => ('처리 완료', SetflowColors.secondaryText),
      _RefundStatus.disputed => ('분쟁 중', SetflowColors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

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
    final totalShare = _trainers.fold<int>(0, (sum, t) => sum + t.share);

    return Scaffold(
      appBar: AppBar(
        title: Text(role == UserRole.admin ? '트레이너별 정산 현황' : '트레이너별 정산'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SetflowColors.blue,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '이번 달 코치 총 분배액',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatAmount(totalShare)}원',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('직급별 수수료 배분 비율'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final grade in _grades) ...[
                Expanded(
                  child: SetflowCard(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 6,
                    ),
                    child: Column(
                      children: [
                        Text(
                          grade.$1,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: SetflowColors.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${grade.$2}%',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (grade != _grades.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 22),
          const SectionTitle('소속 코치 분배 내역'),
          const SizedBox(height: 10),
          for (final trainer in _trainers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetflowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: SetflowColors.blue.withValues(
                            alpha: .15,
                          ),
                          child: Text(
                            trainer.name.characters.first,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 11),
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
                              const SizedBox(height: 3),
                              Text(
                                '${trainer.grade} · 배분율 ${trainer.ratio}%',
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
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SetflowColors.soft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '발생 매출',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: SetflowColors.secondaryText,
                                ),
                              ),
                              Text(
                                '${_formatAmount(trainer.generated)}원',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '최종 분배액',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: SetflowColors.blue,
                                ),
                              ),
                              Text(
                                '${_formatAmount(trainer.share)}원',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: SetflowColors.blue,
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
