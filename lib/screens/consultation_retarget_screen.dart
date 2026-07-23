import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// [ConsultationQueuePage]에서 진입하는 상담 리타겟 화면.
/// 상담 후 미등록/미전환 회원 목록을 경과일 기준으로 필터링하고,
/// 개별 또는 일괄로 재접근(재상담 안내 메시지 발송) 액션을 데모로 제공한다.
/// 더미 데이터, 로컬 상태만 사용하며 실제 메시지 발송은 이루어지지 않는다.
class ConsultationRetargetScreen extends StatefulWidget {
  const ConsultationRetargetScreen({required this.role, super.key});
  final UserRole role;

  @override
  State<ConsultationRetargetScreen> createState() =>
      _ConsultationRetargetScreenState();
}

class _RetargetTarget {
  _RetargetTarget({
    required this.name,
    required this.daysSince,
    required this.optIn,
  });
  final String name;
  final int daysSince;
  final bool optIn;
  bool selected = false;
}

enum _DaysFilter { all, sevenPlus, fourteenPlus, thirtyPlus }

class _ConsultationRetargetScreenState
    extends State<ConsultationRetargetScreen> {
  final _messageController = TextEditingController(
    text: '회원님, 지난 상담 이후 궁금하신 점은 없으셨나요? 지금 등록하시면 특별 혜택을 드려요! 💪',
  );
  _DaysFilter _filter = _DaysFilter.all;
  final _quotaTotal = 30;
  final _quotaUsed = 12;

  late final _targets = <_RetargetTarget>[
    _RetargetTarget(name: '김헬린', daysSince: 5, optIn: true),
    _RetargetTarget(name: '바프도전기', daysSince: 9, optIn: true),
    _RetargetTarget(name: '이초보', daysSince: 15, optIn: false),
    _RetargetTarget(name: '득근득근', daysSince: 22, optIn: true),
    _RetargetTarget(name: '정유미', daysSince: 34, optIn: true),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  bool _matchesFilter(_RetargetTarget target) => switch (_filter) {
    _DaysFilter.all => true,
    _DaysFilter.sevenPlus => target.daysSince >= 7,
    _DaysFilter.fourteenPlus => target.daysSince >= 14,
    _DaysFilter.thirtyPlus => target.daysSince >= 30,
  };

  List<_RetargetTarget> get _visible => _targets.where(_matchesFilter).toList();

  int get _selectedCount => _targets.where((t) => t.selected).length;

  @override
  Widget build(BuildContext context) {
    final gym = widget.role == UserRole.gym;
    final visible = _visible;
    final selectableVisible = visible.where((t) => t.optIn).toList();
    final allSelected =
        selectableVisible.isNotEmpty &&
        selectableVisible.every((t) => t.selected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('상담 리타겟'),
        actions: [
          TextButton(
            onPressed: selectableVisible.isEmpty
                ? null
                : () => setState(() {
                    for (final target in selectableVisible) {
                      target.selected = !allSelected;
                    }
                  }),
            child: Text(allSelected ? '선택 해제' : '전체 선택'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 120),
        children: [
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      color: SetflowColors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${gym ? '짐' : '트레이너'} 이번 달 발송 현황',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$_quotaUsed / $_quotaTotal건',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _quotaUsed / _quotaTotal,
                    minHeight: 8,
                    backgroundColor: SetflowColors.elevated,
                    color: SetflowColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionTitle('상담 후 미등록 회원'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children:
                [
                      ('전체', _DaysFilter.all),
                      ('7일 경과', _DaysFilter.sevenPlus),
                      ('14일 경과', _DaysFilter.fourteenPlus),
                      ('30일 경과', _DaysFilter.thirtyPlus),
                    ]
                    .map(
                      (option) => FilterChip(
                        label: Text(option.$1),
                        selected: _filter == option.$2,
                        onSelected: (_) => setState(() => _filter = option.$2),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: EmptyState(
                icon: Icons.filter_alt_off_outlined,
                title: '대상 회원이 없어요',
                message: '선택한 조건에 해당하는 미등록 회원이 없습니다.',
              ),
            )
          else
            ...visible.map(
              (target) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SetflowCard(
                  onTap: target.optIn
                      ? () => setState(() => target.selected = !target.selected)
                      : null,
                  child: Row(
                    children: [
                      Checkbox(
                        value: target.selected,
                        onChanged: target.optIn
                            ? (value) => setState(
                                () => target.selected = value ?? false,
                              )
                            : null,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  target.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (!target.optIn) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SetflowColors.red.withValues(
                                        alpha: .12,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      '수신 거부',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: SetflowColors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '상담 후 ${target.daysSince}일 경과',
                              style: const TextStyle(
                                fontSize: 12,
                                color: SetflowColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '개별 재접근',
                        onPressed: target.optIn
                            ? () => _sendTo([target])
                            : null,
                        icon: const Icon(
                          Icons.send_outlined,
                          color: SetflowColors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: SetflowInsets.bottomAction,
          child: PrimaryButton(
            label: _selectedCount > 0
                ? '선택한 $_selectedCount명에게 재접근 메시지 발송'
                : '재접근 대상을 선택하세요',
            icon: Icons.send_rounded,
            onPressed: _selectedCount == 0
                ? null
                : () =>
                      _openComposer(_targets.where((t) => t.selected).toList()),
          ),
        ),
      ),
    );
  }

  void _openComposer(List<_RetargetTarget> recipients) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          SetflowSpacing.xxl,
          4,
          SetflowSpacing.xxl,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${recipients.length}명에게 재상담 안내',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              recipients.map((t) => t.name).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: SetflowColors.secondaryText),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '발송 메시지'),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: '발송하기',
              onPressed: () => _sendTo(recipients, sheetContext: sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  void _sendTo(List<_RetargetTarget> recipients, {BuildContext? sheetContext}) {
    if (sheetContext != null) Navigator.pop(sheetContext);
    setState(() {
      for (final target in recipients) {
        target.selected = false;
      }
    });
    showMessage(context, '${recipients.length}명에게 재상담 메시지를 발송했습니다.');
  }
}
