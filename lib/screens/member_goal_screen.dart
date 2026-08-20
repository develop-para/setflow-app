import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<bool> ensureMemberTrainingGoals(BuildContext context) async {
  final state = AppScope.of(context);
  if (state.hasTrainingGoal) return true;
  final shouldOpen =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.track_changes_rounded,
            color: SetflowColors.orange,
          ),
          title: const Text('운동 목표가 필요해요'),
          content: const Text('목표를 작성해야 합니다. 작성창으로 이동하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('나중에'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('목표 작성하기'),
            ),
          ],
        ),
      ) ??
      false;
  if (!shouldOpen || !context.mounted) return false;
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const MemberGoalScreen()),
      ) ??
      false;
}

class MemberGoalScreen extends StatefulWidget {
  const MemberGoalScreen({super.key});

  @override
  State<MemberGoalScreen> createState() => _MemberGoalScreenState();
}

class _MemberGoalScreenState extends State<MemberGoalScreen> {
  static const options = [
    ('🏋️', '근력 향상', '낮은 반복과 충분한 휴식으로 주요 중량을 높여요'),
    ('🔥', '체중 감량', '큰 근육군 중심으로 훈련 밀도를 높여요'),
    ('💪', '근육 증가', '근육군별 다중 세트와 점진적 과부하를 적용해요'),
    ('🏃', '체력 향상', '전신 근지구력과 기초 체력을 함께 키워요'),
    ('🌱', '건강 유지', '밀기·당기기·하체 움직임을 균형 있게 구성해요'),
  ];

  Set<String>? selected;
  bool isSaving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    selected ??= Set.of(AppScope.of(context).goals);
  }

  void _toggle(String goal) {
    if (isSaving) return;
    setState(() {
      if (!selected!.remove(goal) && selected!.length < 2) {
        selected!.add(goal);
      }
    });
  }

  Future<void> _save() async {
    if (selected!.isEmpty) {
      AppSnackbar.info(context, '운동 목표를 하나 이상 선택해주세요.');
      return;
    }
    if (isSaving) return;
    setState(() => isSaving = true);
    final state = AppScope.of(context);
    state.setMemberProfile(
      goals: selected!,
      heightCm: state.heightCm,
      weight: state.weight,
      age: state.age,
      gender: state.gender,
    );
    try {
      await state.syncPersistenceToServer();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      if (state.persistenceError != null) {
        setState(() => isSaving = false);
        AppSnackbar.error(context, '목표를 기기에 저장하지 못했어요. 다시 시도해주세요.');
        return;
      }
      AppSnackbar.info(context, '목표는 기기에 저장됐어요. 클라우드는 연결되는 즉시 다시 동기화합니다.');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운동 목표 설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
        children: [
          const Text(
            '어떤 목표로 운동하시나요?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            '먼저 선택한 목표 하나를 추천 기준으로 사용하며, 최대 2개까지 프로필에 저장할 수 있습니다.',
            style: TextStyle(color: SetflowColors.secondaryText, height: 1.45),
          ),
          const SizedBox(height: 22),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetflowCard(
                onTap: () => _toggle(option.$2),
                color: selected!.contains(option.$2)
                    ? SetflowColors.primary.withValues(alpha: .16)
                    : null,
                child: Row(
                  children: [
                    Text(option.$1, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.$2,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (selected!.isNotEmpty &&
                              selected!.first == option.$2) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SetflowColors.orange.withValues(
                                  alpha: .14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                '주 목표',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: SetflowColors.orange,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            option.$3,
                            style: const TextStyle(
                              fontSize: 11,
                              color: SetflowColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      selected!.contains(option.$2)
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: selected!.contains(option.$2)
                          ? SetflowColors.teal
                          : SetflowColors.disabled,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(18),
        child: AppButton(
          label: '목표 저장',
          icon: Icons.check_rounded,
          isLoading: isSaving,
          onPressed: isSaving ? null : _save,
        ),
      ),
    );
  }
}
