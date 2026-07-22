import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// 운영자 시스템 관리 허브. 랭킹/OCR/요금제/금칙어/로그 개별 화면으로 진입한다.
class AdminSystemScreen extends StatelessWidget {
  const AdminSystemScreen({super.key});

  static const _items = [
    (
      Icons.leaderboard_outlined,
      SetflowColors.blue,
      '랭킹 관리',
      '트렌딩 알고리즘 가중치 및 현재 순위',
    ),
    (
      Icons.document_scanner_outlined,
      SetflowColors.teal,
      'OCR 검수',
      '자동 인식 결과 검수 대기열',
    ),
    (
      Icons.workspace_premium_outlined,
      SetflowColors.purple,
      '요금제 관리',
      '구독 플랜 등록/수정/삭제',
    ),
    (Icons.block_outlined, SetflowColors.red, '금칙어 관리', '자동 블라인드 키워드 목록'),
    (
      Icons.monitor_heart_outlined,
      SetflowColors.orange,
      '시스템 로그',
      '서버 상태 및 에러 로그',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('시스템 관리')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _items[index];
          return SetflowCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _screenFor(index)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: item.$2.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.$1, color: item.$2),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$3,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$4,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SetflowColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: SetflowColors.disabled),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _screenFor(int index) => switch (index) {
    0 => const AdminSystemRankingScreen(),
    1 => const AdminSystemOcrScreen(),
    2 => const AdminSystemPlansScreen(),
    3 => const AdminSystemKeywordsScreen(),
    _ => const AdminSystemLogsScreen(),
  };
}

/// 랭킹 관리: 현재 순위 리스트 + 알고리즘 가중치 데모.
class AdminSystemRankingScreen extends StatefulWidget {
  const AdminSystemRankingScreen({super.key});

  @override
  State<AdminSystemRankingScreen> createState() =>
      _AdminSystemRankingScreenState();
}

class _AdminSystemRankingScreenState extends State<AdminSystemRankingScreen> {
  double _viewWeight = 1;
  double _commentWeight = 3;
  double _consultWeight = 10;
  double _purchaseWeight = 50;
  double _gravity = 1.8;

  static const _ranking = [
    (1, '12주 근성장 루틴', '트레이너 김코치', 982),
    (2, '체지방 감량 4주 챌린지', '트레이너 박헬스', 861),
    (3, '초보자 홈트레이닝', '트레이너 이지은', 744),
    (4, '바디프로필 8주 완성', '트레이너 최민준', 703),
    (5, '유산소 서킷 트레이닝', '트레이너 정하늘', 612),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('랭킹 관리')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          const SectionTitle('현재 트렌딩 순위'),
          const SizedBox(height: 10),
          SetflowCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final item in _ranking)
                  ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: item.$1 <= 3
                          ? SetflowColors.primary
                          : SetflowColors.soft,
                      child: Text(
                        '${item.$1}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    title: Text(
                      item.$2,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(item.$3),
                    trailing: Text(
                      '${item.$4}점',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: SetflowColors.blue,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('가중치 파라미터'),
          const SizedBox(height: 10),
          SetflowCard(
            child: Column(
              children: [
                _WeightSlider(
                  label: '조회수 (W_view)',
                  value: _viewWeight,
                  max: 10,
                  onChanged: (value) => setState(() => _viewWeight = value),
                ),
                const SizedBox(height: 16),
                _WeightSlider(
                  label: '댓글수 (W_comment)',
                  value: _commentWeight,
                  max: 20,
                  onChanged: (value) => setState(() => _commentWeight = value),
                ),
                const SizedBox(height: 16),
                _WeightSlider(
                  label: '상담요청 (W_consult)',
                  value: _consultWeight,
                  max: 50,
                  onChanged: (value) => setState(() => _consultWeight = value),
                ),
                const SizedBox(height: 16),
                _WeightSlider(
                  label: '코칭결제 (W_purchase)',
                  value: _purchaseWeight,
                  max: 200,
                  onChanged: (value) =>
                      setState(() => _purchaseWeight = value),
                ),
                const SizedBox(height: 16),
                _WeightSlider(
                  label: 'Time Decay (Gravity)',
                  value: _gravity,
                  max: 3,
                  onChanged: (value) => setState(() => _gravity = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: '파라미터 저장',
            icon: Icons.save_outlined,
            onPressed: () =>
                showMessage(context, '랭킹 가중치를 저장하고 재계산을 예약했습니다. (데모)'),
          ),
        ],
      ),
    );
  }
}

class _WeightSlider extends StatelessWidget {
  const _WeightSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              value.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: SetflowColors.blue,
              ),
            ),
          ],
        ),
        Slider(value: value, max: max, onChanged: onChanged),
      ],
    );
  }
}

/// OCR 검수: 자동 인식 결과 검수 대기열 데모.
class AdminSystemOcrScreen extends StatefulWidget {
  const AdminSystemOcrScreen({super.key});

  @override
  State<AdminSystemOcrScreen> createState() => _AdminSystemOcrScreenState();
}

class _AdminSystemOcrScreenState extends State<AdminSystemOcrScreen> {
  final _queue = [
    (id: 'q1', type: '인바디', member: '박민지', confidence: 62),
    (id: 'q2', type: 'PT 영수증', member: '이준호', confidence: 48),
    (id: 'q3', type: '체력장 기록지', member: '최서연', confidence: 71),
    (id: 'q4', type: '인바디', member: '정하늘', confidence: 55),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR 검수')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Row(
            children: [
              MetricCard(
                label: '검수 대기',
                value: '${_queue.length}',
                suffix: '건',
                icon: Icons.hourglass_empty,
                tint: SetflowColors.orange,
              ),
              const SizedBox(width: 10),
              const MetricCard(
                label: '이번주 처리',
                value: '132',
                suffix: '건',
                icon: Icons.task_alt,
                tint: SetflowColors.green,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionTitle('낮은 신뢰도 검수 대기열'),
          const SizedBox(height: 10),
          if (_queue.isEmpty)
            const EmptyState(
              icon: Icons.done_all,
              title: '검수할 항목이 없습니다',
              message: '신뢰도가 낮은 OCR 인식 결과가 접수되면 이곳에 표시됩니다.',
            )
          else
            for (final item in _queue)
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: SetflowCard(
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: SetflowColors.teal.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.image_search,
                          color: SetflowColors.teal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.type} · ${item.member}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '인식 신뢰도 ${item.confidence}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: item.confidence < 60
                                    ? SetflowColors.red
                                    : SetflowColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '승인',
                        onPressed: () => _resolve(item.id, '승인'),
                        icon: const Icon(
                          Icons.check_circle_outline,
                          color: SetflowColors.green,
                        ),
                      ),
                      IconButton(
                        tooltip: '반려',
                        onPressed: () => _resolve(item.id, '반려'),
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: SetflowColors.red,
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

  void _resolve(String id, String action) {
    setState(() => _queue.removeWhere((item) => item.id == id));
    showMessage(context, '검수 항목을 $action 처리했습니다. (데모)');
  }
}

/// 요금제 관리: 구독 플랜 CRUD 데모.
class AdminSystemPlansScreen extends StatefulWidget {
  const AdminSystemPlansScreen({super.key});

  @override
  State<AdminSystemPlansScreen> createState() =>
      _AdminSystemPlansScreenState();
}

class _AdminSystemPlansScreenState extends State<AdminSystemPlansScreen> {
  final _plans = [
    (id: 'free', name: '일반 무료', price: '0원', desc: '루틴 저장 4개 · OCR 5건/월'),
    (
      id: 'premium',
      name: '일반 프리미엄',
      price: '4,900원',
      desc: '루틴 저장 무제한 · OCR 50건/월',
    ),
    (id: 'trainer-pro', name: '트레이너 프로', price: '29,000원', desc: '회원 관리 50명'),
    (
      id: 'enterprise',
      name: '엔터프라이즈',
      price: '99,000원',
      desc: '회원 관리 무제한 · 수수료 5%',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('요금제 관리')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          for (final plan in _plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: SetflowCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${plan.price} · ${plan.desc}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SetflowColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '편집',
                      onPressed: () => _openEditor(plan: plan),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '삭제',
                      onPressed: () => _confirmDelete(plan.id),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: SetflowColors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: '새 플랜 추가',
            icon: Icons.add,
            onPressed: () => _openEditor(),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('플랜을 삭제하시겠습니까?'),
        content: const Text('삭제된 플랜은 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제', style: TextStyle(color: SetflowColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _plans.removeWhere((plan) => plan.id == id));
      showMessage(context, '플랜을 삭제했습니다. (데모)');
    }
  }

  Future<void> _openEditor({
    ({String id, String name, String price, String desc})? plan,
  }) async {
    final nameController = TextEditingController(text: plan?.name);
    final priceController = TextEditingController(text: plan?.price);
    final descController = TextEditingController(text: plan?.desc);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(plan == null ? '새 플랜 추가' : '플랜 편집'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '플랜 이름'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceController,
              decoration: const InputDecoration(labelText: '가격'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: '설명'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (saved == true &&
        nameController.text.trim().isNotEmpty &&
        mounted) {
      final entry = (
        id: plan?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameController.text.trim(),
        price: priceController.text.trim().isEmpty
            ? '0원'
            : priceController.text.trim(),
        desc: descController.text.trim(),
      );
      setState(() {
        if (plan == null) {
          _plans.add(entry);
        } else {
          final index = _plans.indexWhere((item) => item.id == plan.id);
          if (index != -1) _plans[index] = entry;
        }
      });
      showMessage(context, plan == null ? '플랜을 추가했습니다. (데모)' : '플랜을 수정했습니다. (데모)');
    }
    nameController.dispose();
    priceController.dispose();
    descController.dispose();
  }
}

/// 금칙어 관리: 키워드 리스트 + 추가/삭제 데모.
class AdminSystemKeywordsScreen extends StatefulWidget {
  const AdminSystemKeywordsScreen({super.key});

  @override
  State<AdminSystemKeywordsScreen> createState() =>
      _AdminSystemKeywordsScreenState();
}

class _AdminSystemKeywordsScreenState
    extends State<AdminSystemKeywordsScreen> {
  final _controller = TextEditingController();
  final _keywords = ['불법약물', '스테로이드', '텔레그램', '대리결제', '카톡상담'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('금칙어 관리')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          SetflowCard(
            color: SetflowColors.red.withValues(alpha: .06),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: SetflowColors.red),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '등록된 키워드가 포함된 게시글/댓글은 작성 즉시 자동 블라인드 처리됩니다.',
                    style: TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.add),
                    hintText: '추가할 금지 키워드 입력',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _add,
                style: FilledButton.styleFrom(
                  backgroundColor: SetflowColors.ink,
                  minimumSize: const Size(0, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('추가'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '등록된 키워드 ${_keywords.length}개',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: SetflowColors.secondaryText,
            ),
          ),
          const SizedBox(height: 10),
          if (_keywords.isEmpty)
            const EmptyState(
              icon: Icons.block_outlined,
              title: '등록된 금지 키워드가 없습니다',
              message: '위 입력창에서 새 키워드를 추가해 보세요.',
            )
          else
            SetflowCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final keyword in _keywords)
                    ListTile(
                      title: Text(
                        keyword,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      trailing: IconButton(
                        tooltip: '삭제',
                        onPressed: () => _remove(keyword),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: SetflowColors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _add() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    if (_keywords.contains(value)) {
      showMessage(context, '이미 등록된 키워드입니다.');
      return;
    }
    setState(() => _keywords.insert(0, value));
    _controller.clear();
  }

  void _remove(String keyword) {
    setState(() => _keywords.remove(keyword));
    showMessage(context, '"$keyword" 키워드를 삭제했습니다. (데모)');
  }
}

/// 시스템 로그: 로그 라인 리스트 + 레벨/기간 필터 데모.
class AdminSystemLogsScreen extends StatefulWidget {
  const AdminSystemLogsScreen({super.key});

  @override
  State<AdminSystemLogsScreen> createState() => _AdminSystemLogsScreenState();
}

class _AdminSystemLogsScreenState extends State<AdminSystemLogsScreen> {
  String _levelFilter = '전체';

  static const _levels = ['전체', 'INFO', 'WARN', 'ERROR'];

  static const _logs = [
    ('11:45:02', 'ERROR', 'payment-api', 'PG사 결제 웹훅 수신 타임아웃'),
    ('09:12:33', 'WARN', 'image-storage', 'S3 버킷 처리 지연 감지 (1.5초 초과)'),
    ('08:21:32', 'INFO', 'settlement-batch', '정산 배치 완료 · 284건'),
    ('08:18:05', 'WARN', 'ocr-service', 'OCR 응답 지연 · 1.8초'),
    ('08:02:44', 'INFO', 'ranking-job', '랭킹 재계산 완료'),
    ('전일 23:55:10', 'ERROR', 'auth-server', 'Redis 세션 저장소 연결 실패'),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _levelFilter == '전체'
        ? _logs
        : _logs.where((log) => log.$2 == _levelFilter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('시스템 로그')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          const Row(
            children: [
              MetricCard(
                label: '업타임',
                value: '99.98',
                suffix: '%',
                icon: Icons.cloud_done_outlined,
                tint: SetflowColors.green,
              ),
              SizedBox(width: 10),
              MetricCard(
                label: '오류율',
                value: '0.02',
                suffix: '%',
                icon: Icons.error_outline,
                tint: SetflowColors.red,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            children: [
              for (final level in _levels)
                FilterChip(
                  label: Text(level),
                  selected: _levelFilter == level,
                  onSelected: (_) => setState(() => _levelFilter = level),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            const EmptyState(
              icon: Icons.check_circle_outline,
              title: '해당 레벨의 로그가 없습니다',
              message: '다른 필터를 선택해 보세요.',
            )
          else
            for (final log in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: SetflowCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _logColor(log.$2).withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              log.$2,
                              style: TextStyle(
                                color: _logColor(log.$2),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            log.$3,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: SetflowColors.secondaryText,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            log.$1,
                            style: const TextStyle(
                              fontSize: 10,
                              color: SetflowColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        log.$4,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Color _logColor(String level) => switch (level) {
    'ERROR' => SetflowColors.red,
    'WARN' => SetflowColors.orange,
    _ => SetflowColors.green,
  };
}
