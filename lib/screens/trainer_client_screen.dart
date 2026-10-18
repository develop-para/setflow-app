import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/pro_access_gate.dart';
import '../widgets/trainer_daily_work.dart';
import 'coaching_management_screen.dart';
import 'coaching_workout_screens.dart';
import 'consultation_chat_screen.dart';

/// Personal coaching keeps its own consent and record source; a center member
/// identifier is never synthesized from a coaching connection.
class TrainerClientScreen extends StatelessWidget {
  const TrainerClientScreen({required this.connection, super.key});

  final CoachingConnection connection;

  @override
  Widget build(BuildContext context) => CoachingAccountBoundary(
    requiredRole: UserRole.trainer,
    child: _TrainerClientPage(connection: connection),
  );
}

class _TrainerClientPage extends StatelessWidget {
  const _TrainerClientPage({required this.connection});

  final CoachingConnection connection;

  Future<void> _refresh(BuildContext context) async {
    try {
      await AppScope.of(context).refreshBusinessDashboard(UserRole.trainer);
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '회원 정보를 새로고침하지 못했어요. 다시 시도해주세요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final records =
        state.coachingSessionRecords
            .where((record) => record.coachingId == connection.id)
            .toList()
          ..sort((a, b) => b.sessionDate.compareTo(a.sessionDate));
    final conversations =
        state.businessConsultations
            .where((item) => item.userId == connection.memberUserId)
            .toList()
          ..sort((a, b) {
            final priority = (trainerConsultationNeedsReply(b) ? 1 : 0)
                .compareTo(trainerConsultationNeedsReply(a) ? 1 : 0);
            if (priority != 0) return priority;
            return (b.latestMessage?.createdAt ?? b.createdAt ?? DateTime(0))
                .compareTo(
                  a.latestMessage?.createdAt ?? a.createdAt ?? DateTime(0),
                );
          });
    final chatRepository = state.businessRepository;
    return Scaffold(
      appBar: AppBar(title: Text(connection.memberName)),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: SetflowInsets.pageList,
          children: [
            Text(
              connection.memberGoal ?? '목표 미등록',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: SetflowSpacing.xs),
            Text(
              '개인 코칭 ${connection.sessionCount}회',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Wrap(
              spacing: SetflowSpacing.sm,
              runSpacing: SetflowSpacing.sm,
              children: [
                if (managementRepository(context) != null)
                  FilledButton.icon(
                    key: const ValueKey('trainer-client-records'),
                    onPressed: () => openTrainerMemberRecords(
                      context,
                      memberUserId: connection.memberUserId,
                      memberName: connection.memberName,
                    ),
                    icon: const Icon(SetflowIcons.calendar),
                    label: const Text('운동 기록'),
                  ),
                if (state.coachingWorkoutRepository != null)
                  OutlinedButton.icon(
                    key: const ValueKey('trainer-client-assignments'),
                    onPressed: () async {
                      if (!await requireProAccess(context)) return;
                      if (!context.mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CoachingAssignmentsScreen(
                            memberUserId: connection.memberUserId,
                            memberName: connection.memberName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(SetflowIcons.record),
                    label: const Text('운동 과제 관리'),
                  ),
                if (conversations.isNotEmpty &&
                    chatRepository is ConsultationChatRepository)
                  OutlinedButton.icon(
                    key: const ValueKey('trainer-client-chat'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ConsultationChatScreen(
                          consultationId: conversations.first.id,
                          role: UserRole.trainer,
                          initialConsultation: conversations.first,
                        ),
                      ),
                    ),
                    icon: const Icon(SetflowIcons.coaching),
                    label: const Text('상담 대화'),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.xl),
            const SectionTitle('공유한 수업 기록'),
            const SizedBox(height: SetflowSpacing.md),
            if (records.isEmpty)
              const EmptyState(
                icon: SetflowIcons.calendar,
                title: '아직 공유한 수업이 없어요',
                message: '개인 운동 기록은 위의 운동 기록에서 공유 상태를 확인할 수 있어요.',
              ),
            for (final record in records) ...[
              SetflowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: SetflowSpacing.xs),
                    Text(
                      '${DateFormat('M월 d일').format(record.sessionDate)} · ${record.gymName}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: SetflowSpacing.sm),
                    Text(record.sessionSummary),
                    if (record.routineSummary?.isNotEmpty ?? false) ...[
                      const SizedBox(height: SetflowSpacing.sm),
                      Text(record.routineSummary!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: SetflowSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}
