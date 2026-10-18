import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../data/coaching_workout_repository.dart';
import '../theme.dart';
import '../theme/icons.dart';
import 'common.dart';

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

class TrainerDailyWork extends StatefulWidget {
  const TrainerDailyWork({
    required this.onSchedule,
    required this.onConsultation,
    required this.onWorkout,
    super.key,
  });

  final ValueChanged<BusinessCoachingSchedule> onSchedule;
  final ValueChanged<BusinessConsultation> onConsultation;
  final ValueChanged<CoachingWorkout> onWorkout;

  @override
  State<TrainerDailyWork> createState() => _TrainerDailyWorkState();
}

class _TrainerDailyWorkState extends State<TrainerDailyWork> {
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final state = AppScope.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    try {
      await Future.wait([
        state.refreshCoachingSchedules(from: today, to: today),
        if (state.coachingWorkoutRepository != null)
          state.refreshCoachingWorkouts(),
      ]);
    } catch (_) {
      if (mounted) _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final today = DateTime.now();
    final profile = state.businessWorkspace?.profile;
    final trainerId = profile is TrainerBusinessProfile
        ? profile.id
        : state.businessWorkspace?.access.trainer?.id ??
              state.businessAccess?.trainer?.id;
    final lessons =
        state.coachingSchedules
            .where(
              (item) =>
                  item.trainerId == trainerId &&
                  DateUtils.isSameDay(item.date, today) &&
                  !item.isCompleted,
            )
            .toList()
          ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final replies =
        state.businessConsultations
            .where(trainerConsultationNeedsReply)
            .toList()
          ..sort(
            (a, b) => (a.latestMessage?.createdAt ?? a.createdAt ?? today)
                .compareTo(b.latestMessage?.createdAt ?? b.createdAt ?? today),
          );
    final completed =
        state.coachingWorkouts
            .where(
              (item) =>
                  item.trainerId == trainerId &&
                  !item.isCancelled &&
                  item.status == CoachingWorkoutStatus.completed &&
                  item.session.completedSets > 0,
            )
            .toList()
          ..sort(
            (a, b) => (b.updatedAt ?? b.date).compareTo(a.updatedAt ?? a.date),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('오늘 할 일'),
        const SizedBox(height: SetflowSpacing.md),
        if (_loading) const LinearProgressIndicator(),
        if (_failed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('수업·운동 일부를 불러오지 못했어요'),
            trailing: TextButton(onPressed: _load, child: const Text('재시도')),
          ),
        Text(
          '오늘 수업 ${lessons.length}건 · 답변 대기 ${replies.length}건',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: SetflowSpacing.sm),
        for (final item in lessons)
          ListTile(
            key: ValueKey('trainer-today-lesson-${item.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${_clock(item.startMinutes)} · ${item.memberName ?? '회원 미지정'}',
            ),
            subtitle: Text(item.title),
            trailing: const Icon(SetflowIcons.forward),
            onTap: () => widget.onSchedule(item),
          ),
        for (final item in replies)
          ListTile(
            key: ValueKey('trainer-reply-${item.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text('${item.memberName ?? '회원'} · 답변 대기'),
            subtitle: Text(
              item.latestMessage?.text ?? item.question ?? '상담 내용을 확인해주세요.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(SetflowIcons.forward),
            onTap: () => widget.onConsultation(item),
          ),
        if (!_loading && !_failed && lessons.isEmpty && replies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SetflowSpacing.md),
            child: Text('오늘 남은 수업과 답변 대기가 없어요.'),
          ),
        if (completed.isNotEmpty) ...[
          const SizedBox(height: SetflowSpacing.lg),
          const SectionTitle('최근 완료한 코칭 운동'),
          const SizedBox(height: SetflowSpacing.sm),
          for (final item in completed.take(5))
            ListTile(
              key: ValueKey('trainer-completed-${item.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${item.memberName} · ${item.title}'),
              subtitle: Text(
                '${DateFormat('M월 d일').format(item.date)} · 실제 ${item.session.completedSets}세트',
              ),
              trailing: const Icon(SetflowIcons.forward),
              onTap: () => widget.onWorkout(item),
            ),
        ],
      ],
    );
  }
}

/// A member's follow-up returns the conversation to the reply queue even when
/// an earlier trainer reply exists. Reading a message alone does not resolve it.
bool trainerConsultationNeedsReply(BusinessConsultation item) {
  final latest = item.latestMessage;
  if (latest != null) return latest.sender == BusinessMessageSender.member;
  return item.status != BusinessConsultationStatus.answered &&
      item.status != BusinessConsultationStatus.replied;
}
