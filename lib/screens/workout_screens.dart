import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'member_goal_screen.dart';

class DailyWorkoutScreen extends StatelessWidget {
  const DailyWorkoutScreen({required this.date, super.key});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = state.sessionFor(date);
    final coachFeedbacks = state.memberSessionFeedbackForDate(date);
    final recommendation = state.recommendationForDate(date);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${date.month}월 ${date.day}일 (${['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1]})',
        ),
        actions: [
          IconButton(
            onPressed: () => showMessage(context, '운동 메모를 저장할 수 있습니다.'),
            icon: const Icon(Icons.note_alt_outlined),
          ),
          IconButton(
            onPressed: () => showMessage(context, '오늘 기록 공유 링크를 준비했습니다.'),
            icon: const Icon(Icons.ios_share_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '기록 메뉴',
            onSelected: (value) {
              if (value == 'delete') _deleteWorkout(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      color: SetflowColors.red,
                    ),
                    SizedBox(width: 10),
                    Text(
                      '이 날짜 기록 삭제',
                      style: TextStyle(color: SetflowColors.red),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Row(
              children: [
                MetricCard(
                  label: session.hasResistance ? '총 볼륨' : '유산소 시간',
                  value: !session.hasResistance && session.hasCardio
                      ? '${(session.cardioDurationSeconds / 60).round()}'
                      : session.volume > 1000
                      ? (session.volume / 1000).toStringAsFixed(1)
                      : session.volume.toStringAsFixed(0),
                  suffix: !session.hasResistance && session.hasCardio
                      ? '분'
                      : session.volume > 1000
                      ? 't'
                      : state.weightUnit,
                  icon: session.hasResistance
                      ? Icons.monitor_weight_outlined
                      : Icons.timer_outlined,
                  tint: SetflowColors.teal,
                ),
                const SizedBox(width: 10),
                MetricCard(
                  label: '완료 세트',
                  value: '${session.completedSets}',
                  suffix: '/ ${session.totalSets}',
                  icon: Icons.check_circle_outline_rounded,
                  tint: SetflowColors.orange,
                ),
              ],
            ),
          ),
          if (state.persistenceError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: _PersistenceNotice(
                onRetry: () {
                  state.retryPersistence();
                  AppSnackbar.info(context, '운동 기록 저장을 다시 시도했어요.');
                },
              ),
            ),
          if (state.role == UserRole.member &&
              state.memberSessionFeedbackError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: _CoachFeedbackErrorCard(
                loading: state.memberSessionFeedbackLoading,
                onRetry: () async {
                  try {
                    await state.refreshMemberSessionFeedback(
                      from: DateTime(date.year, date.month, date.day - 30),
                      to: DateTime(date.year, date.month, date.day + 30),
                    );
                  } catch (_) {
                    if (context.mounted) {
                      AppSnackbar.error(context, '코치 피드백을 불러오지 못했어요.');
                    }
                  }
                },
              ),
            ),
          if (coachFeedbacks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: _CoachFeedbackCard(feedbacks: coachFeedbacks),
            ),
          if (!state.hasTrainingGoal)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: _GoalRequiredRecommendationCard(
                onApply: () async {
                  final hasGoals = await ensureMemberTrainingGoals(context);
                  if (!hasGoals || !context.mounted) return;
                  final refreshed = state.recommendationForDate(date);
                  if (refreshed == null) {
                    AppSnackbar.info(context, '운동 기록을 완료하면 추천 세트를 계산해요.');
                    return;
                  }
                  state.applyRecommendation(date, refreshed);
                  AppSnackbar.success(
                    context,
                    '${refreshed.template.name} 추천 세트를 적용했어요.',
                  );
                },
              ),
            )
          else if (recommendation != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: _NextSessionCard(
                recommendation: recommendation,
                unit: state.weightUnit,
                hasGoal: state.hasTrainingGoal,
                onApply: () async {
                  final hasGoals = await ensureMemberTrainingGoals(context);
                  if (!hasGoals || !context.mounted) return;
                  final refreshed = state.recommendationForDate(date);
                  if (refreshed == null) return;
                  state.applyRecommendation(date, refreshed);
                  AppSnackbar.success(
                    context,
                    '${refreshed.template.name} 추천 세트를 적용했어요.',
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Column(
              children: [
                AppButton(
                  label: '운동 추가',
                  icon: Icons.add_rounded,
                  onPressed: () => _openLibrary(context),
                ),
                const SizedBox(height: SetflowSpacing.sm),
                AppButton(
                  label: '루틴 불러오기',
                  icon: Icons.playlist_add_check_rounded,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => _openRoutinePicker(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: session.exercises.isEmpty
                ? EmptyState(
                    icon: Icons.fitness_center_rounded,
                    title: '오늘은 어떤 운동을 할까요?',
                    message: '운동을 직접 추가하거나 저장한 루틴을 불러와보세요.',
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 100),
                    itemCount: session.exercises.length,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, _) => Transform.scale(
                          scale: 1 + animation.value * .025,
                          child: Material(
                            color: Colors.transparent,
                            elevation: 14 * animation.value,
                            borderRadius: BorderRadius.circular(22),
                            child: child,
                          ),
                        ),
                      );
                    },
                    onReorderItem: (oldIndex, newIndex) =>
                        state.reorderExercise(session, oldIndex, newIndex),
                    itemBuilder: (_, index) {
                      final exercise = session.exercises[index];
                      return Padding(
                        key: ValueKey(exercise.id),
                        padding: const EdgeInsets.only(bottom: 13),
                        child: _ExerciseCard(
                          date: date,
                          exercise: exercise,
                          index: index,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExerciseLibraryScreen(date: date)),
    );
  }

  Future<void> _openRoutinePicker(BuildContext context) async {
    final state = AppScope.of(context);
    if (state.routines.isEmpty) {
      AppSnackbar.info(context, '저장된 루틴이 없어요. 내 루틴에서 먼저 만들어주세요.');
      return;
    }
    final routine = await showModalBottomSheet<RoutineData>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RoutinePickerSheet(routines: state.routines),
    );
    if (routine == null || !context.mounted) return;
    final added = state.applyRoutine(routine, date);
    if (added == 0) {
      AppSnackbar.info(context, '이 날짜에 루틴 운동이 이미 모두 있어요.');
    } else {
      AppSnackbar.success(context, '${routine.name}에서 운동 $added개를 적용했어요.');
    }
  }

  Future<void> _deleteWorkout(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: SetflowColors.red,
            ),
            title: const Text('운동 기록을 삭제할까요?'),
            content: Text('${date.month}월 ${date.day}일의 운동과 세트 기록이 모두 삭제됩니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: SetflowColors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    AppScope.of(context).deleteSession(date);
    AppSnackbar.success(context, '운동 기록을 삭제했어요.');
    Navigator.of(context).pop();
  }
}

class _CoachFeedbackCard extends StatelessWidget {
  const _CoachFeedbackCard({required this.feedbacks});

  final List<MemberSessionFeedback> feedbacks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = feedbacks.first;
    return Semantics(
      label: '코치 피드백 ${feedbacks.length}개',
      child: SetflowCard(
        key: const ValueKey('member-session-feedback-card'),
        padding: const EdgeInsets.all(SetflowSpacing.md),
        onTap: () => _showAll(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(SetflowRadii.md),
              ),
              child: Icon(
                Icons.forum_rounded,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: SetflowSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '코치 피드백',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (feedbacks.length > 1)
                        Text(
                          '${feedbacks.length}개',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    latest.authorName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    latest.text,
                    key: ValueKey('member-session-feedback-${latest.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: SetflowSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAll(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: feedbacks.length + 1,
            separatorBuilder: (_, index) => index == 0
                ? const SizedBox(height: SetflowSpacing.sm)
                : const Divider(height: SetflowSpacing.xl),
            itemBuilder: (_, index) {
              if (index == 0) {
                return Text(
                  '코치 피드백',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                );
              }
              final feedback = feedbacks[index - 1];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${feedback.authorName} · ${_feedbackTimestamp(feedback.createdAt)}',
                    style: Theme.of(sheetContext).textTheme.labelLarge
                        ?.copyWith(
                          color: Theme.of(
                            sheetContext,
                          ).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  SelectableText(feedback.text),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CoachFeedbackErrorCard extends StatelessWidget {
  const _CoachFeedbackErrorCard({required this.loading, required this.onRetry});

  final bool loading;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SetflowCard(
      key: const ValueKey('member-session-feedback-error'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, color: theme.colorScheme.error),
          const SizedBox(width: SetflowSpacing.sm),
          const Expanded(child: Text('코치 피드백을 불러오지 못했어요.')),
          TextButton(
            onPressed: loading ? null : onRetry,
            child: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

String _feedbackTimestamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}월 ${local.day}일 $hour:$minute';
}

class _RoutinePickerSheet extends StatelessWidget {
  const _RoutinePickerSheet({required this.routines});

  final List<RoutineData> routines;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '루틴 불러오기',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '선택한 루틴의 운동이 이 날짜에 바로 추가됩니다.',
                    style: TextStyle(color: SetflowColors.secondaryText),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                itemCount: routines.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final routine = routines[index];
                  return SetflowCard(
                    onTap: routine.exercises.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(routine),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 48,
                          decoration: BoxDecoration(
                            color: routine.color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                routine.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${routine.exercises.length}개 운동 · ${routine.exercises.map((item) => item.muscle).toSet().join(', ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SetflowColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.add_circle_rounded),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatefulWidget {
  const _ExerciseCard({
    required this.date,
    required this.exercise,
    required this.index,
  });

  final DateTime date;
  final WorkoutExercise exercise;
  final int index;

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  bool recommendationShown = false;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final exercise = widget.exercise;
    return SetflowCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        children: [
          ReorderableDelayedDragStartListener(
            index: widget.index,
            child: Semantics(
              label: '${exercise.template.name} 순서 이동, 길게 누르기',
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: SetflowColors.primary.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          exercise.template.icon,
                          color: SetflowColors.orange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exercise.template.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${exercise.template.muscle} · 상단을 길게 눌러 순서 이동',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: SetflowColors.secondaryText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.drag_indicator_rounded,
                        color: SetflowColors.disabled,
                        size: 20,
                      ),
                      PopupMenuButton<String>(
                        tooltip: '운동 메뉴',
                        onSelected: (value) {
                          if (value == 'delete') {
                            _confirmDeleteExercise(context, state);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  color: SetflowColors.red,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  '운동 삭제',
                                  style: TextStyle(color: SetflowColors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          color: SetflowColors.disabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          for (final set in exercise.sets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: exercise.template.isCardio
                  ? _InlineCardioRow(
                      key: ObjectKey(set),
                      template: exercise.template,
                      set: set,
                      onToggle: () => _toggleSet(state, set),
                      onDurationChanged: (seconds) =>
                          state.updateSet(set, durationSeconds: seconds),
                      onDistanceChanged: (distance) =>
                          state.updateSet(set, distanceKm: distance),
                      onRpeChanged: (rpe) =>
                          state.updateSet(set, intensityRpe: rpe),
                      onDelete: () => _confirmDeleteSet(context, state, set),
                    )
                  : _InlineSetRow(
                      key: ObjectKey(set),
                      set: set,
                      unit: state.weightUnit,
                      onToggle: () => _toggleSet(state, set),
                      onTypeChanged: (type) => state.updateSet(set, type: type),
                      onWeightChanged: (weight) =>
                          state.updateSet(set, weight: weight),
                      onRepsChanged: (reps) => state.updateSet(set, reps: reps),
                      onRestChanged: (seconds) =>
                          state.updateSet(set, restSeconds: seconds),
                      onDelete: () => _confirmDeleteSet(context, state, set),
                    ),
            ),
          TextButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add, size: 18),
            label: Text(exercise.template.isCardio ? '구간 추가' : '세트 추가'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSet(AppState state, WorkoutSetEntry set) async {
    final prs = set.completed
        ? <PerformancePrType>{}
        : state.prTypesForCandidate(widget.exercise.template, set);
    state.toggleSet(set, startRest: !widget.exercise.template.isCardio);
    if (!set.completed) {
      recommendationShown = false;
      return;
    }
    final labels = prs.map((type) => type.label).join(' · ');
    AppSnackbar.success(
      context,
      labels.isEmpty
          ? '${set.number}${widget.exercise.template.isCardio ? '구간' : '세트'}을 저장했어요.'
          : '🏆 $labels을 달성했어요!',
    );
    final allCompleted =
        widget.exercise.sets.isNotEmpty &&
        widget.exercise.sets.every((item) => item.completed);
    if (!allCompleted || recommendationShown) return;
    recommendationShown = true;
    await _offerNextExercise(state);
  }

  Future<void> _offerNextExercise(AppState state) async {
    final session = state.sessionFor(widget.date);
    final currentIndex = session.exercises.indexOf(widget.exercise);
    if (currentIndex >= 0 && currentIndex < session.exercises.length - 1) {
      final next = session.exercises[currentIndex + 1];
      if (next.sets.any((set) => !set.completed)) {
        AppSnackbar.info(context, '다음 운동은 ${next.template.name}입니다.');
        return;
      }
    }
    final hasGoals = await ensureMemberTrainingGoals(context);
    if (!hasGoals || !mounted) return;
    final recommendation = ExerciseRecommendationEngine.recommendNext(
      catalog: state.exercises,
      session: session,
      completedExercise: widget.exercise,
      goals: state.goals,
      weeklyHistory: state.sessions.values,
    );
    if (recommendation == null) {
      AppSnackbar.info(context, '추천 가능한 운동이 이미 오늘 계획에 모두 있어요.');
      return;
    }
    final shouldAdd = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NextExerciseRecommendationSheet(
        recommendation: recommendation,
        unit: state.weightUnit,
      ),
    );
    if (shouldAdd != true || !mounted) return;
    final added = state.addRecommendedExercise(widget.date, recommendation);
    if (added) {
      AppSnackbar.success(
        context,
        '${recommendation.template.name}을 다음 운동으로 추가했어요.',
      );
    }
  }

  Future<void> _confirmDeleteSet(
    BuildContext context,
    AppState state,
    WorkoutSetEntry set,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              '${set.number}${widget.exercise.template.isCardio ? '구간' : '세트'}을 삭제할까요?',
            ),
            content: Text(
              '삭제한 ${widget.exercise.template.isCardio ? '구간' : '세트'}은 복구할 수 없습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: SetflowColors.red,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    state.removeSet(widget.exercise, set);
  }

  Future<void> _confirmDeleteExercise(
    BuildContext context,
    AppState state,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('운동을 삭제할까요?'),
            content: Text(
              '${widget.exercise.template.name}의 '
              '${widget.exercise.template.isCardio ? '구간' : '세트'} 기록이 모두 삭제됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: SetflowColors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    final session = state.sessionFor(widget.date);
    state.removeExercise(session, widget.exercise);
    AppSnackbar.success(context, '운동을 삭제했어요.');
  }
}

class _InlineCardioRow extends StatefulWidget {
  const _InlineCardioRow({
    required this.template,
    required this.set,
    required this.onToggle,
    required this.onDurationChanged,
    required this.onDistanceChanged,
    required this.onRpeChanged,
    required this.onDelete,
    super.key,
  });

  final ExerciseTemplate template;
  final WorkoutSetEntry set;
  final VoidCallback onToggle;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<double> onDistanceChanged;
  final ValueChanged<double> onRpeChanged;
  final VoidCallback onDelete;

  @override
  State<_InlineCardioRow> createState() => _InlineCardioRowState();
}

class _InlineCardioRowState extends State<_InlineCardioRow> {
  late final TextEditingController durationController;
  late final TextEditingController distanceController;
  late final TextEditingController rpeController;
  final durationFocus = FocusNode();
  final distanceFocus = FocusNode();
  final rpeFocus = FocusNode();

  CardioExerciseDefinition? get definition =>
      cardioDefinitionForExercise(widget.template.id);

  bool get supportsDistance =>
      definition?.metrics.contains(CardioMetric.distance) == true;

  @override
  void initState() {
    super.initState();
    durationController = TextEditingController(text: _durationText());
    distanceController = TextEditingController(text: _distanceText());
    rpeController = TextEditingController(text: _rpeText());
  }

  @override
  void didUpdateWidget(covariant _InlineCardioRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!durationFocus.hasFocus &&
        oldWidget.set.durationSeconds != widget.set.durationSeconds) {
      durationController.text = _durationText();
    }
    if (!distanceFocus.hasFocus &&
        oldWidget.set.distanceKm != widget.set.distanceKm) {
      distanceController.text = _distanceText();
    }
    if (!rpeFocus.hasFocus &&
        oldWidget.set.intensityRpe != widget.set.intensityRpe) {
      rpeController.text = _rpeText();
    }
  }

  @override
  void dispose() {
    durationController.dispose();
    distanceController.dispose();
    rpeController.dispose();
    durationFocus.dispose();
    distanceFocus.dispose();
    rpeFocus.dispose();
    super.dispose();
  }

  String _durationText() => _decimalText(widget.set.durationSeconds / 60);
  String _distanceText() =>
      widget.set.distanceKm <= 0 ? '' : _decimalText(widget.set.distanceKm);
  String _rpeText() =>
      widget.set.intensityRpe <= 0 ? '' : _decimalText(widget.set.intensityRpe);

  void _commitDuration() {
    final minutes = double.tryParse(durationController.text.trim());
    if (minutes == null || minutes <= 0 || minutes > 1440) {
      durationController.text = _durationText();
      return;
    }
    widget.onDurationChanged((minutes * 60).round());
  }

  void _commitDistance() {
    final raw = distanceController.text.trim();
    final distance = raw.isEmpty ? 0.0 : double.tryParse(raw);
    if (distance == null || distance < 0 || distance > 999.99) {
      distanceController.text = _distanceText();
      return;
    }
    widget.onDistanceChanged(distance);
  }

  void _commitRpe() {
    final rpe = double.tryParse(rpeController.text.trim());
    if (rpe == null || rpe < 1 || rpe > 10) {
      rpeController.text = _rpeText();
      return;
    }
    widget.onRpeChanged(rpe);
  }

  String get _summary {
    if (widget.set.durationSeconds <= 0) return '시간을 입력해주세요';
    final duration = Duration(seconds: widget.set.durationSeconds);
    final time = duration.inHours > 0
        ? '${duration.inHours}시간 ${duration.inMinutes.remainder(60)}분'
        : '${duration.inMinutes}분';
    if (!supportsDistance || widget.set.distanceKm <= 0) return time;
    if (definition?.modality == CardioModality.rowingErgometer) {
      final secondsPer500m =
          widget.set.durationSeconds / (widget.set.distanceKm * 2);
      final minutes = secondsPer500m ~/ 60;
      final seconds = secondsPer500m
          .round()
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '$time · $minutes:$seconds/500m';
    }
    if (definition?.metrics.contains(CardioMetric.pace) == true) {
      final secondsPerKm = widget.set.durationSeconds / widget.set.distanceKm;
      final minutes = secondsPerKm ~/ 60;
      final seconds = secondsPerKm
          .round()
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      return '$time · $minutes:$seconds/km';
    }
    final speed = widget.set.distanceKm / (widget.set.durationSeconds / 3600);
    return '$time · ${speed.toStringAsFixed(1)}km/h';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: SetflowMotion.standard,
      padding: const EdgeInsets.fromLTRB(9, 7, 7, 9),
      decoration: BoxDecoration(
        color: widget.set.completed
            ? SetflowColors.teal.withValues(alpha: .09)
            : context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        border: Border.all(
          color: widget.set.completed
              ? SetflowColors.teal.withValues(alpha: .35)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                ),
                child: Text(
                  '${widget.set.number}구간',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: SetflowColors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '구간 삭제',
                onPressed: widget.set.completed ? null : widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
              _SetCompletionButton(
                key: ValueKey('inline-set-complete-${widget.set.number}'),
                setNumber: widget.set.number,
                unitLabel: '구간',
                completed: widget.set.completed,
                onPressed: widget.onToggle,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _cardioField(
                  key: ValueKey('cardio-duration-${widget.set.number}'),
                  label: '시간',
                  suffix: '분',
                  controller: durationController,
                  focusNode: durationFocus,
                  onCommit: _commitDuration,
                ),
              ),
              if (supportsDistance) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _cardioField(
                    key: ValueKey('cardio-distance-${widget.set.number}'),
                    label: '거리',
                    suffix: 'km',
                    controller: distanceController,
                    focusNode: distanceFocus,
                    onCommit: _commitDistance,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: _cardioField(
                  key: ValueKey('cardio-rpe-${widget.set.number}'),
                  label: '강도',
                  suffix: 'RPE',
                  controller: rpeController,
                  focusNode: rpeFocus,
                  onCommit: _commitRpe,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'RPE 3–4 중강도 · 7–9 고강도 · 1–2는 가벼운 활동',
              style: TextStyle(
                fontSize: 9,
                color: SetflowColors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardioField({
    required Key key,
    required String label,
    required String suffix,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onCommit,
  }) {
    return TextField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: !widget.set.completed,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onSubmitted: (_) => onCommit(),
      onTapOutside: (_) {
        onCommit();
        focusNode.unfocus();
      },
    );
  }
}

String _decimalText(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

class _InlineSetRow extends StatefulWidget {
  const _InlineSetRow({
    required this.set,
    required this.unit,
    required this.onToggle,
    required this.onTypeChanged,
    required this.onWeightChanged,
    required this.onRepsChanged,
    required this.onRestChanged,
    required this.onDelete,
    super.key,
  });

  final WorkoutSetEntry set;
  final String unit;
  final VoidCallback onToggle;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int> onRestChanged;
  final VoidCallback onDelete;

  @override
  State<_InlineSetRow> createState() => _InlineSetRowState();
}

class _InlineSetRowState extends State<_InlineSetRow> {
  late final TextEditingController weightController;
  late final TextEditingController repsController;
  late final TextEditingController restController;
  final weightFocus = FocusNode();
  final repsFocus = FocusNode();
  final restFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    weightController = TextEditingController(text: _weightText());
    repsController = TextEditingController(text: '${widget.set.reps}');
    restController = TextEditingController(text: '${widget.set.restSeconds}');
  }

  @override
  void didUpdateWidget(covariant _InlineSetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!weightFocus.hasFocus && oldWidget.set.weight != widget.set.weight) {
      weightController.text = _weightText();
    }
    if (!repsFocus.hasFocus && oldWidget.set.reps != widget.set.reps) {
      repsController.text = '${widget.set.reps}';
    }
    if (!restFocus.hasFocus &&
        oldWidget.set.restSeconds != widget.set.restSeconds) {
      restController.text = '${widget.set.restSeconds}';
    }
  }

  @override
  void dispose() {
    weightController.dispose();
    repsController.dispose();
    restController.dispose();
    weightFocus.dispose();
    repsFocus.dispose();
    restFocus.dispose();
    super.dispose();
  }

  String _weightText() =>
      widget.set.weight.toStringAsFixed(widget.set.weight % 1 == 0 ? 0 : 1);

  void _commitWeight() {
    final value = double.tryParse(weightController.text.trim());
    if (value == null || value < 0 || value > 999) {
      weightController.text = _weightText();
      return;
    }
    widget.onWeightChanged(value);
  }

  void _commitReps() {
    final value = int.tryParse(repsController.text.trim());
    if (value == null || value < 0 || value > 999) {
      repsController.text = '${widget.set.reps}';
      return;
    }
    widget.onRepsChanged(value);
  }

  void _commitRest() {
    final value = int.tryParse(restController.text.trim());
    if (value == null || value < 15 || value > 600) {
      restController.text = '${widget.set.restSeconds}';
      return;
    }
    widget.onRestChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final estimate = PerformanceEngine.estimate(
      widget.set.weight,
      widget.set.reps,
    );
    return AnimatedContainer(
      duration: SetflowMotion.standard,
      padding: const EdgeInsets.fromLTRB(9, 7, 7, 9),
      decoration: BoxDecoration(
        color: widget.set.completed
            ? SetflowColors.teal.withValues(alpha: .09)
            : context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        border: Border.all(
          color: widget.set.completed
              ? SetflowColors.teal.withValues(alpha: .35)
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                ),
                child: Text(
                  '${widget.set.number}세트',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  estimate == null
                      ? 'e1RM 계산 제외'
                      : 'e1RM ${estimate.value.toStringAsFixed(1)} · ${estimate.quality.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: SetflowColors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '세트 종류 변경',
                onSelected: (value) {
                  if (value == 'delete') {
                    widget.onDelete();
                  } else {
                    widget.onTypeChanged(value);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: '일반', child: Text('일반 세트')),
                  PopupMenuItem(value: '웜업', child: Text('웜업 세트')),
                  PopupMenuItem(value: '드랍', child: Text('드랍 세트')),
                  PopupMenuItem(value: '실패', child: Text('실패 세트')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '세트 삭제',
                      style: TextStyle(color: SetflowColors.red),
                    ),
                  ),
                ],
                child: Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _typeColor(widget.set.type).withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(SetflowRadii.sm),
                  ),
                  child: Text(
                    widget.set.type,
                    style: TextStyle(
                      fontSize: 10,
                      color: _typeColor(widget.set.type),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _SetCompletionButton(
                key: ValueKey('inline-set-complete-${widget.set.number}'),
                setNumber: widget.set.number,
                completed: widget.set.completed,
                onPressed: widget.onToggle,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  label: '무게',
                  suffix: widget.unit,
                  controller: weightController,
                  focusNode: weightFocus,
                  decimal: true,
                  onCommit: _commitWeight,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField(
                  label: '횟수',
                  suffix: '회',
                  controller: repsController,
                  focusNode: repsFocus,
                  onCommit: _commitReps,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numberField(
                  label: '휴식',
                  suffix: '초',
                  controller: restController,
                  focusNode: restFocus,
                  onCommit: _commitRest,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required String label,
    required String suffix,
    required TextEditingController controller,
    required FocusNode focusNode,
    required VoidCallback onCommit,
    bool decimal = false,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: !widget.set.completed,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      onSubmitted: (_) => onCommit(),
      onTapOutside: (_) {
        onCommit();
        focusNode.unfocus();
      },
    );
  }

  Color _typeColor(String type) => switch (type) {
    '웜업' => SetflowColors.orange,
    '드랍' => SetflowColors.blue,
    '실패' => SetflowColors.red,
    _ => SetflowColors.teal,
  };
}

class _SetCompletionButton extends StatelessWidget {
  const _SetCompletionButton({
    required this.setNumber,
    required this.completed,
    required this.onPressed,
    this.unitLabel = '세트',
    super.key,
  });

  final int setNumber;
  final String unitLabel;
  final bool completed;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = completed
        ? Colors.white
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '$setNumber$unitLabel 완료',
      button: true,
      selected: completed,
      child: SizedBox(
        width: 72,
        height: 44,
        child: AnimatedContainer(
          duration: SetflowMotion.micro,
          decoration: BoxDecoration(
            color: completed ? SetflowColors.teal : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
            border: Border.all(
              color: completed
                  ? SetflowColors.teal
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      completed
                          ? Icons.check_circle_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 16,
                      color: foreground,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '완료',
                      style: TextStyle(
                        fontSize: 11,
                        color: foreground,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NextExerciseRecommendationSheet extends StatelessWidget {
  const _NextExerciseRecommendationSheet({
    required this.recommendation,
    required this.unit,
  });

  final NextExerciseRecommendation recommendation;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final cardio = recommendation.cardioPrescription;
    final prescriptionText = cardio == null
        ? '${PerformanceEngine.formatWeight(recommendation.startingWeight)}$unit · '
              '${recommendation.minReps}–${recommendation.maxReps}회 · '
              '${recommendation.sets}세트 · 휴식 ${recommendation.restSeconds}초'
        : '${cardio.durationMinutes}분'
              '${cardio.targetDistanceKm == null ? '' : ' · ${cardio.targetDistanceKm!.toStringAsFixed(1)}km'}'
              ' · RPE ${cardio.minimumRpe}–${cardio.maximumRpe}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: SetflowColors.orange,
                ),
                const SizedBox(width: 9),
                const Text(
                  '다음 운동 추천',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Chip(label: Text(recommendation.goalLabel)),
              ],
            ),
            const SizedBox(height: 14),
            SetflowCard(
              color: SetflowColors.primary.withValues(alpha: .14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recommendation.template.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    prescriptionText,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    recommendation.reason,
                    style: const TextStyle(
                      height: 1.45,
                      color: SetflowColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              cardio == null
                  ? '근거 적용 · 논문이 특정 다음 운동 하나를 최적이라고 정한 것은 아니며, 목표·주간 볼륨·오늘 미완료 패턴을 규칙으로 반영합니다.'
                  : '근거 적용 · 유산소는 중량이 아니라 시간·거리·RPE로 처방하며, 첫 기록의 거리는 임의로 만들지 않습니다.',
              style: const TextStyle(
                fontSize: 10,
                height: 1.4,
                color: SetflowColors.secondaryText,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('나중에'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('추천 운동 추가'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({required this.date, super.key});
  final DateTime date;

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final searchController = TextEditingController();
  String search = '';
  String muscle = '전체';
  final selected = <String>{};

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final filtered = state.exercises.where((item) {
      final matchesSearch =
          item.name.toLowerCase().contains(search.toLowerCase()) ||
          item.muscle.contains(search);
      final matchesMuscle = muscle == '전체' || item.muscle == muscle;
      return matchesSearch && matchesMuscle;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('운동 선택'),
        actions: [
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => _addSelected(context),
              child: Text('${selected.length}개 추가'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: AppTextField(
              controller: searchController,
              onChanged: (value) => setState(() => search = value),
              prefixIcon: const Icon(Icons.search),
              hint: '어떤 운동을 할까요? (한국어/영문)',
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: ['전체', '가슴', '등', '어깨', '하체', '팔', '복근', '유산소']
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item),
                        selected: muscle == item,
                        onSelected: (_) => setState(() => muscle = item),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 14),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '검색 결과가 없어요',
                    message: '검색어를 바꾸거나 전체 부위에서 다시 찾아보세요.',
                    actionLabel: '검색 초기화',
                    onAction: () => setState(() {
                      searchController.clear();
                      search = '';
                      muscle = '전체';
                    }),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                    itemCount: filtered.length + 1,
                    itemBuilder: (_, index) {
                      if (index == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.all(8),
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                showMessage(context, '커스텀 운동 입력 폼을 준비했습니다.'),
                            icon: const Icon(Icons.add),
                            label: const Text('새로운 운동 만들기'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        );
                      }
                      final exercise = filtered[index];
                      final isSelected = selected.contains(exercise.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: SetflowColors.soft,
                          child: Icon(
                            exercise.icon,
                            color: SetflowColors.secondaryText,
                          ),
                        ),
                        title: Text(
                          exercise.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(exercise.muscle),
                        trailing: IconButton(
                          onPressed: () => setState(
                            () => isSelected
                                ? selected.remove(exercise.id)
                                : selected.add(exercise.id),
                          ),
                          icon: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: isSelected
                                ? SetflowColors.primary
                                : SetflowColors.disabled,
                          ),
                        ),
                        onTap: () => setState(
                          () => isSelected
                              ? selected.remove(exercise.id)
                              : selected.add(exercise.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addSelected(context),
              backgroundColor: SetflowColors.primary,
              foregroundColor: SetflowColors.ink,
              icon: const Icon(Icons.check),
              label: Text('${selected.length}개 운동 추가'),
            ),
    );
  }

  void _addSelected(BuildContext context) {
    final state = AppScope.of(context);
    for (final template in state.exercises.where(
      (item) => selected.contains(item.id),
    )) {
      state.addExercise(widget.date, template);
    }
    AppSnackbar.success(context, '${selected.length}개 운동을 추가했어요.');
    Navigator.of(context).pop();
  }
}

class _GoalRequiredRecommendationCard extends StatelessWidget {
  const _GoalRequiredRecommendationCard({required this.onApply});

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return SetflowCard(
      key: const Key('goal-required-recommendation'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.track_changes_rounded,
                size: 18,
                color: SetflowColors.orange,
              ),
              SizedBox(width: 7),
              Text(
                '맞춤 추천 준비',
                style: TextStyle(
                  fontSize: 11,
                  color: SetflowColors.secondaryText,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            '운동 목표를 먼저 선택해주세요',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            '근력·근육 증가·감량·체력·건강 유지에 따라 중량, 반복수, 세트수와 휴식시간이 달라집니다.',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: SetflowColors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('추천 세트 적용'),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({
    required this.recommendation,
    required this.unit,
    required this.hasGoal,
    required this.onApply,
  });

  final WorkoutRecommendation recommendation;
  final String unit;
  final bool hasGoal;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return SetflowCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.track_changes_rounded,
                size: 18,
                color: SetflowColors.orange,
              ),
              const SizedBox(width: 7),
              const Text(
                'NEXT SESSION',
                style: TextStyle(
                  fontSize: 11,
                  color: SetflowColors.secondaryText,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasGoal ? recommendation.goal.label : '목표 설정 필요',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SetflowColors.teal,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            recommendation.template.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            hasGoal
                ? recommendation.prescriptionSummary(unit)
                : '목표를 설정하면 추천 세트를 계산해요',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            hasGoal
                ? '${recommendation.reason} · '
                      '${recommendation.progressionCondition(unit)}'
                : '추천 세트 적용을 누르면 목표 작성 화면으로 안내합니다.',
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: SetflowColors.secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
              label: const Text('추천 세트 적용'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersistenceNotice extends StatelessWidget {
  const _PersistenceNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SetflowColors.red.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(SetflowRadii.md),
      child: ListTile(
        leading: const Icon(Icons.cloud_off_rounded, color: SetflowColors.red),
        title: const Text('기록을 기기에 저장하지 못했어요.'),
        trailing: TextButton(onPressed: onRetry, child: const Text('재시도')),
      ),
    );
  }
}

class ExerciseSetScreen extends StatefulWidget {
  const ExerciseSetScreen({
    required this.date,
    required this.exercise,
    super.key,
  });
  final DateTime date;
  final WorkoutExercise exercise;

  @override
  State<ExerciseSetScreen> createState() => _ExerciseSetScreenState();
}

class _ExerciseSetScreenState extends State<ExerciseSetScreen> {
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final exercise = widget.exercise;
    if (exercise.template.isCardio) {
      return _buildCardioScreen(context, state, exercise);
    }
    final previous = state.performanceFor(
      exercise.template,
      before: state.dateOnly(widget.date),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.template.name),
        actions: [
          IconButton(
            onPressed: () => showMessage(context, '운동 기록 히스토리를 불러왔습니다.'),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SetflowColors.primary.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.trending_up_rounded,
                  color: SetflowColors.orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PERFORMANCE',
                        style: TextStyle(
                          fontSize: 11,
                          color: SetflowColors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        previous == null
                            ? '첫 기록을 시작해보세요'
                            : '예상 1RM '
                                  '${previous.currentE1rm.toStringAsFixed(1)} '
                                  '${state.weightUnit}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        previous == null
                            ? '완료한 세트부터 PR과 추천 중량을 계산해요.'
                            : '최근 최고 '
                                  '${PerformanceEngine.formatWeight(previous.latestSessionBest.set.weight)}'
                                  '${state.weightUnit} × '
                                  '${previous.latestSessionBest.set.reps}회 · '
                                  '추정 품질 ${previous.quality.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: SetflowColors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (previous?.changeFromPrevious case final change?)
                  Text(
                    '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}'
                    '${state.weightUnit}',
                    style: TextStyle(
                      color: change >= 0
                          ? SetflowColors.green
                          : SetflowColors.orange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              SizedBox(
                width: 44,
                child: Center(
                  child: Text(
                    '세트',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '무게',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '횟수',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 50,
                child: Center(
                  child: Text(
                    '완료',
                    style: TextStyle(
                      fontSize: 11,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final set in exercise.sets)
            Dismissible(
              key: ObjectKey(set),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => _confirmDeleteSet(context, set),
              onDismissed: (_) {
                state.removeSet(exercise, set);
                AppSnackbar.success(context, '세트를 삭제했어요.');
              },
              background: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.only(right: SetflowSpacing.xl),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: SetflowColors.red,
                  borderRadius: BorderRadius.circular(SetflowRadii.lg),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SetflowCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  color: set.completed
                      ? SetflowColors.teal.withValues(alpha: .1)
                      : null,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Center(
                              child: Text(
                                '${set.number}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _NumberStepper(
                              value: set.weight.toStringAsFixed(
                                set.weight % 1 == 0 ? 0 : 1,
                              ),
                              suffix: state.weightUnit,
                              onMinus: () => state.updateSet(
                                set,
                                weight: set.weight - 2.5,
                              ),
                              onPlus: () => state.updateSet(
                                set,
                                weight: set.weight + 2.5,
                              ),
                              onValueTap: () => _editSetValue(
                                context,
                                state,
                                set,
                                editsWeight: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: _NumberStepper(
                              value: '${set.reps}',
                              suffix: '회',
                              onMinus: () =>
                                  state.updateSet(set, reps: set.reps - 1),
                              onPlus: () =>
                                  state.updateSet(set, reps: set.reps + 1),
                              onValueTap: () => _editSetValue(
                                context,
                                state,
                                set,
                                editsWeight: false,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 50,
                            child: Checkbox(
                              value: set.completed,
                              activeColor: SetflowColors.teal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                              onChanged: (_) {
                                final prs = set.completed
                                    ? <PerformancePrType>{}
                                    : state.prTypesForCandidate(
                                        exercise.template,
                                        set,
                                      );
                                state.toggleSet(set);
                                if (set.completed) {
                                  final labels = prs
                                      .map((type) => type.label)
                                      .join(' · ');
                                  AppSnackbar.success(
                                    context,
                                    labels.isEmpty
                                        ? '${set.number}세트를 저장했어요.'
                                        : '🏆 $labels을 달성했어요!',
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 36),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [
                                  for (final type in ['일반', '웜업', '드랍', '실패'])
                                    ChoiceChip(
                                      label: Text(
                                        type,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      selected: set.type == type,
                                      visualDensity: VisualDensity.compact,
                                      onSelected: (_) =>
                                          state.updateSet(set, type: type),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (PerformanceEngine.estimate(set.weight, set.reps)
                                case final estimate?)
                              Text(
                                'e1RM ${estimate.value.toStringAsFixed(1)} · '
                                '${estimate.quality.label}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: SetflowColors.secondaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else
                              const Text(
                                'e1RM 계산 제외',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: SetflowColors.secondaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add),
            label: const Text('세트 추가'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const SetflowCard(
            child: Row(
              children: [
                Icon(Icons.info_outline, color: SetflowColors.blue),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '완료 체크 한 번으로 기록 저장, 볼륨 계산, 휴식 타이머가 동시에 시작됩니다.',
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      fontSize: 12,
                      height: 1.45,
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

  Widget _buildCardioScreen(
    BuildContext context,
    AppState state,
    WorkoutExercise exercise,
  ) {
    return Scaffold(
      appBar: AppBar(title: Text(exercise.template.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          SetflowCard(
            color: SetflowColors.blue.withValues(alpha: .08),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.directions_run_rounded, color: SetflowColors.blue),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '유산소는 무게나 반복 횟수 대신 시간·거리·자각 강도(RPE)를 기록합니다. 거리 측정이 어울리지 않는 종목은 시간과 RPE만 표시해요.',
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final set in exercise.sets) ...[
            _InlineCardioRow(
              key: ValueKey('cardio-detail-segment-${set.number}'),
              template: exercise.template,
              set: set,
              onToggle: () => state.toggleSet(set, startRest: false),
              onDurationChanged: (value) =>
                  state.updateSet(set, durationSeconds: value),
              onDistanceChanged: (value) =>
                  state.updateSet(set, distanceKm: value),
              onRpeChanged: (value) =>
                  state.updateSet(set, intensityRpe: value),
              onDelete: () async {
                final confirmed = await _confirmDeleteCardioSegment(
                  context,
                  set,
                );
                if (!confirmed || !context.mounted) return;
                state.removeSet(exercise, set);
                AppSnackbar.success(context, '구간을 삭제했어요.');
              },
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add),
            label: const Text('구간 추가'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDeleteCardioSegment(
    BuildContext context,
    WorkoutSetEntry set,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('${set.number}구간을 삭제할까요?'),
            content: const Text('삭제한 유산소 구간은 복구할 수 없습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: SetflowColors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editSetValue(
    BuildContext context,
    AppState state,
    WorkoutSetEntry set, {
    required bool editsWeight,
  }) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _SetValueDialog(
        editsWeight: editsWeight,
        initialValue: editsWeight
            ? set.weight.toStringAsFixed(set.weight % 1 == 0 ? 0 : 1)
            : '${set.reps}',
      ),
    );
    if (result == null || !context.mounted) return;
    if (editsWeight) {
      state.updateSet(set, weight: result);
    } else {
      state.updateSet(set, reps: result.round());
    }
    AppSnackbar.success(context, '세트 값을 저장했어요.');
  }

  Future<bool> _confirmDeleteSet(
    BuildContext context,
    WorkoutSetEntry set,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('${set.number}세트를 삭제할까요?'),
            content: const Text('삭제한 세트 기록은 복구할 수 없습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: FilledButton.styleFrom(
                  backgroundColor: SetflowColors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
  }
}

class _SetValueDialog extends StatefulWidget {
  const _SetValueDialog({
    required this.editsWeight,
    required this.initialValue,
  });

  final bool editsWeight;
  final String initialValue;

  @override
  State<_SetValueDialog> createState() => _SetValueDialogState();
}

class _SetValueDialogState extends State<_SetValueDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _save() {
    if (formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, double.parse(controller.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editsWeight ? '무게 직접 입력' : '횟수 직접 입력'),
      content: Form(
        key: formKey,
        child: AppTextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(
            decimal: widget.editsWeight,
          ),
          inputFormatters: [
            if (widget.editsWeight)
              FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}\.?\d{0,1}'))
            else
              FilteringTextInputFormatter.digitsOnly,
          ],
          hint: widget.editsWeight ? '0~999' : '0~999회',
          validator: (value) {
            final number = double.tryParse(value?.trim() ?? '');
            if (number == null) return '숫자를 입력해주세요.';
            if (number < 0 || number > 999) {
              return '0~999 범위로 입력해주세요.';
            }
            return null;
          },
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.value,
    required this.suffix,
    required this.onMinus,
    required this.onPlus,
    required this.onValueTap,
  });
  final String value;
  final String suffix;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onValueTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : SetflowColors.soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onMinus,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.remove, size: 15),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onValueTap,
              borderRadius: BorderRadius.circular(SetflowRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      suffix,
                      style: const TextStyle(
                        fontSize: 8,
                        color: SetflowColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onPlus,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.add, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}
