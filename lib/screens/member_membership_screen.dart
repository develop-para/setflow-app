import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class MemberMembershipScreen extends StatelessWidget {
  const MemberMembershipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final memberships = state.memberMemberships;
    return Scaffold(
      appBar: AppBar(title: const Text('연결 센터 관리')),
      body: state.memberMembershipsError != null
          ? EmptyState(
              icon: Icons.sync_problem_rounded,
              title: '센터 연결 정보를 불러오지 못했어요',
              message: '서버 연결을 확인한 뒤 다시 시도해주세요.',
              actionLabel: '다시 시도',
              onAction: () async {
                try {
                  await state.refreshBusinessDashboard(UserRole.member);
                } catch (_) {
                  if (context.mounted) {
                    AppSnackbar.error(context, '센터 연결 정보를 불러오지 못했어요.');
                  }
                }
              },
            )
          : memberships.isEmpty
          ? const EmptyState(
              icon: Icons.apartment_outlined,
              title: '연결된 센터가 없어요',
              message: '센터 초대를 수락하면 담당 트레이너와 기록을 공유할 수 있어요.',
            )
          : ListView.separated(
              padding: SetflowInsets.pageList,
              itemCount: memberships.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final membership = memberships[index];
                final ending = state.isEndingBusinessMembership(membership.id);
                return SetflowCard(
                  key: ValueKey('member-membership-${membership.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            child: Icon(Icons.apartment_rounded),
                          ),
                          const SizedBox(width: SetflowSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  membership.gymName ?? '연결 센터',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '운동 기록 공유 및 담당 트레이너 연결 중',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SetflowSpacing.md),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: ValueKey(
                            'member-end-membership-${membership.id}',
                          ),
                          onPressed: ending
                              ? null
                              : () => _endMembership(context, membership.id),
                          icon: ending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.link_off_rounded),
                          label: Text(ending ? '종료 중...' : '센터 연결 종료'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _endMembership(BuildContext context, String memberId) async {
    final state = AppScope.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.link_off_rounded,
              color: Theme.of(dialogContext).colorScheme.error,
            ),
            title: const Text('센터 연결을 종료할까요?'),
            content: const Text('담당 트레이너 배정과 센터의 운동·체성분 기록 접근 권한이 즉시 종료됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: const Text('연결 종료'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await state.endBusinessMembership(memberId);
      if (!context.mounted) return;
      AppSnackbar.success(context, '센터 연결을 종료했어요.');
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '센터 연결을 종료하지 못했어요.');
      }
    }
  }
}
