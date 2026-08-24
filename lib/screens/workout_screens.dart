import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data/business_repository.dart';
import '../data/exercise_guides.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import 'evidence_library_screen.dart';
import 'member_goal_screen.dart';
import 'recommendation_profile_screen.dart';

class DailyWorkoutScreen extends StatefulWidget {
  const DailyWorkoutScreen({required this.date, super.key});
  final DateTime date;

  @override
  State<DailyWorkoutScreen> createState() => _DailyWorkoutScreenState();
}

class _DailyWorkoutScreenState extends State<DailyWorkoutScreen> {
  bool emptyDayRecommendationDismissed = false;

  DateTime get date => widget.date;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = state.sessionFor(date);
    final coachFeedbacks = state.memberSessionFeedbackForDate(date);
    // Everything that sits above the exercises. Horizontal padding belongs to
    // whoever places this, so the same blocks fit the empty column and the
    // list's header without doubling up.
    final statusBlocks = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _WorkoutSummaryBar(
          session: session,
          unit: state.weightUnit,
          recommendationEnabled: state.autoRecommendNextExercise,
          onRecommendationChanged: state.setAutoRecommendNextExercise,
        ),
      ),
      if (state.persistenceError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PersistenceNotice(
            onRetry: () {
              state.retryPersistence();
              AppSnackbar.info(context, '운동 기록 저장을 다시 시도했어요.');
            },
          ),
        ),
      if (state.persistenceError == null && state.persistenceSyncError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PersistenceSyncNotice(
            onRetry: () async {
              try {
                await state.syncPersistenceToServer();
                if (context.mounted) {
                  AppSnackbar.success(context, '서버 동기화를 완료했어요.');
                }
              } catch (_) {
                if (context.mounted) {
                  AppSnackbar.info(context, '기기에는 저장되어 있어요. 연결되면 다시 동기화합니다.');
                }
              }
            },
          ),
        ),
      if (state.role == UserRole.member &&
          state.memberSessionFeedbackError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
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
          padding: const EdgeInsets.only(bottom: 14),
          child: _CoachFeedbackCard(feedbacks: coachFeedbacks),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        // The date is this screen's name, so it sits where a name sits: at the
        // start, on the same 18px line as the cards under it. It used to be
        // pushed inward by two icons parked in `leading`, a slot meant for one
        // control, which left the title floating at neither margin.
        titleSpacing: 18,
        title: Text(
          '${date.month}월 ${date.day}일 (${['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1]})',
        ),
        // Adding an exercise and loading a routine live here and nowhere else.
        // They used to be two full-width buttons pinned above the list, which
        // cost a third of the screen on every day that already had exercises.
        actions: [
          IconButton(
            key: const Key('daily-add-exercise'),
            tooltip: '운동 추가',
            onPressed: _openExerciseFlow,
            icon: const Icon(SetflowIcons.addExercise),
          ),
          IconButton(
            key: const Key('daily-load-routine'),
            tooltip: '루틴 불러오기',
            onPressed: () => _openRoutinePicker(context),
            icon: const Icon(SetflowIcons.routine),
          ),
          PopupMenuButton<String>(
            tooltip: '기록 메뉴',
            onSelected: (value) {
              if (value == 'delete') _deleteWorkout(context);
            },
            // 메모와 공유는 눌러도 토스트만 뜨고 아무것도 저장·공유하지 않아서 뺐다.
            // 만들어지면 그때 다시 넣는다 — 있는 척하는 메뉴가 없는 것보다 나쁘다.
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      color: context.setflowColors.error,
                    ),
                    SizedBox(width: SetflowSpacing.sm2),
                    Text(
                      '이 날짜 기록 삭제',
                      style: TextStyle(color: context.setflowColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: session.exercises.isEmpty
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                  child: Column(children: statusBlocks),
                ),
                // The two big buttons are a first-run affordance, nothing more.
                // Once the day has an exercise the header icons carry them.
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Column(
                    children: [
                      AppButton(
                        label: '운동 추가',
                        icon: Icons.add_rounded,
                        onPressed: _openExerciseFlow,
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
                const Expanded(
                  child: EmptyState(
                    icon: Icons.fitness_center_rounded,
                    title: '오늘은 어떤 운동을 할까요?',
                    message: '운동을 직접 추가하거나 저장한 루틴을 불러와보세요.',
                  ),
                ),
              ],
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.gutter,
                2,
                SetflowSpacing.gutter,
                100,
              ),
              // Volume, warnings and coach notes ride the list instead of
              // sitting on top of it: pinned, they ate the space the sets need.
              header: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(children: statusBlocks),
              ),
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
                      borderRadius: BorderRadius.circular(SetflowRadii.xl),
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
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ExerciseCard(
                    date: date,
                    exercise: exercise,
                    index: index,
                  ),
                );
              },
            ),
    );
  }

  Future<void> _openExerciseFlow() async {
    final state = AppScope.of(context);
    final session = state.sessionFor(date);
    if (session.exercises.isNotEmpty ||
        !state.autoRecommendNextExercise ||
        emptyDayRecommendationDismissed) {
      _openLibrary();
      return;
    }
    final hasGoals = await ensureMemberTrainingGoals(context);
    if (!mounted) return;
    if (!hasGoals) {
      _openLibrary();
      return;
    }
    await ensurePrecisionRecommendationSurvey(context);
    if (!mounted) return;
    if (state.recommendationProfile?.shouldPauseAutomaticRecommendation ??
        false) {
      AppSnackbar.info(
        context,
        '통증이 7/10 이상이라 자동 추천을 중단했어요. 의료 전문가의 평가를 먼저 받아주세요.',
      );
      _openLibrary();
      return;
    }

    final unavailableEquipment = <String>{};
    while (mounted) {
      final recommendation = state.firstExerciseRecommendationForDate(
        date,
        excludedTemplateIds: unavailableEquipment,
      );
      if (recommendation == null) {
        AppSnackbar.info(
          context,
          state.recommendationProfile == null
              ? '사용 가능한 기구에 맞는 다른 추천이 없어요. 직접 선택해주세요.'
              : '입력한 장비·숙련도·제외 동작에 맞는 추천이 없어요. 직접 선택하거나 설문을 수정해주세요.',
        );
        setState(() => emptyDayRecommendationDismissed = true);
        _openLibrary();
        return;
      }

      final action = await showSetflowSheet<_RecommendationAction>(
        context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _NextExerciseRecommendationSheet(
          recommendation: recommendation,
          unit: state.weightUnit,
          title: '오늘의 첫 운동 추천',
        ),
      );
      if (!mounted) return;
      if (action == _RecommendationAction.noEquipment) {
        unavailableEquipment.add(recommendation.template.id);
        continue;
      }
      if (action == _RecommendationAction.add) {
        final added = state.addRecommendedExercise(date, recommendation);
        if (added) {
          AppSnackbar.success(
            context,
            '${recommendation.template.name}을 첫 운동으로 추가했어요.',
          );
        }
        return;
      }

      setState(() => emptyDayRecommendationDismissed = true);
      _openLibrary();
      return;
    }
  }

  void _openLibrary() {
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
    final routine = await showSetflowSheet<RoutineData>(
      context,
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
                  backgroundColor: context.setflowColors.error,
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
    // Hosted as the 기록 tab this screen is the root route, so only a pushed
    // copy (a past date opened from the calendar) may close itself.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }
}

class _WorkoutSummaryBar extends StatelessWidget {
  const _WorkoutSummaryBar({
    required this.session,
    required this.unit,
    required this.recommendationEnabled,
    required this.onRecommendationChanged,
  });

  final WorkoutSession session;
  final String unit;
  final bool recommendationEnabled;
  final ValueChanged<bool> onRecommendationChanged;

  @override
  Widget build(BuildContext context) {
    final isCardioOnly = !session.hasResistance && session.hasCardio;
    final volume = isCardioOnly
        ? '${(session.cardioDurationSeconds / 60).round()}분'
        : session.volume >= 1000
        ? '${(session.volume / 1000).toStringAsFixed(1)}t'
        : '${session.volume.toStringAsFixed(0)}$unit';
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          // 글자 크기를 키운 사용자에게 이 줄이 가장 먼저 넘쳤다. 토글은 눌러야
          // 하므로 크기를 지키고, 두 수치가 남는 폭을 나눠 갖는다.
          Flexible(
            child: _SummaryValue(
              label: isCardioOnly ? '시간' : '볼륨',
              value: volume,
            ),
          ),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Flexible(
            child: _SummaryValue(
              label: '완료 세트',
              value: '${session.completedSets}/${session.totalSets}',
            ),
          ),
          const SizedBox(width: SetflowSpacing.sm),
          Semantics(
            label: '다음 운동 자동 추천',
            toggled: recommendationEnabled,
            child: InkWell(
              key: const Key('auto-recommend-toggle'),
              borderRadius: BorderRadius.circular(SetflowRadii.full),
              onTap: () => onRecommendationChanged(!recommendationEnabled),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                decoration: BoxDecoration(
                  color: recommendationEnabled
                      ? SetflowColors.primary.withValues(alpha: .2)
                      : Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: recommendationEnabled
                          ? Theme.of(context).colorScheme.onSurface
                          : SetflowColors.disabled,
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Text(
                      '추천 ${recommendationEnabled ? 'ON' : 'OFF'}',
                      style: const TextStyle(
                        fontSize: SetflowFontSize.tiny,
                        fontWeight: SetflowWeight.medium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 라벨이 먼저 줄어든다 — '볼륨'은 문맥으로 알 수 있지만 숫자는 아니다.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: SetflowFontSize.micro,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: SetflowWeight.strong,
            ),
          ),
        ),
        const SizedBox(width: SetflowSpacing.xs),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: SetflowFontSize.caption,
              fontWeight: SetflowWeight.medium,
            ),
          ),
        ),
      ],
    );
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
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    latest.authorName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
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
    return showSetflowSheet<void>(
      context,
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
                  ).textTheme.titleLarge?.copyWith(),
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
            Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '루틴 불러오기',
                    style: TextStyle(
                      fontSize: SetflowFontSize.headline,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: SetflowSpacing.xs),
                  Text(
                    '선택한 루틴의 운동이 이 날짜에 바로 추가됩니다.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                itemCount: routines.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SetflowSpacing.sm2),
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
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.xs,
                            ),
                          ),
                        ),
                        const SizedBox(width: SetflowSpacing.md),
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
                              const SizedBox(height: SetflowSpacing.xs),
                              Text(
                                '${routine.exercises.length}개 운동 · ${routine.exercises.map((item) => item.muscle).toSet().join(', ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: SetflowFontSize.caption,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
  late bool collapsed;

  @override
  void initState() {
    super.initState();
    collapsed =
        widget.exercise.sets.isNotEmpty &&
        widget.exercise.sets.every((set) => set.completed);
  }

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
                      // 판도 없고 색도 없다. 라임 사각형 위의 주황 아이콘은
                      // 이 화면에서 가장 먼저 눈에 들어오는 요소였는데, 정작
                      // 아무 의미도 없는 장식이었다 — 봐야 할 것은 종목 이름과
                      // 세트다.
                      Icon(
                        exercise.template.icon,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(width: SetflowSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exercise.template.name,
                              style: const TextStyle(
                                fontSize: SetflowFontSize.title,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              exercise.sets.isNotEmpty &&
                                      exercise.sets.every(
                                        (set) => set.completed,
                                      )
                                  ? '${exercise.template.muscle} · 완료 ${exercise.sets.length}/${exercise.sets.length}'
                                  : '${exercise.template.muscle} · 상단을 길게 눌러 순서 이동',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: SetflowFontSize.tiny,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: ValueKey('collapse-exercise-${exercise.id}'),
                        tooltip: collapsed ? '세트 펼치기' : '세트 접기',
                        onPressed: () => setState(() => collapsed = !collapsed),
                        icon: AnimatedRotation(
                          turns: collapsed ? 0 : .5,
                          duration: SetflowMotion.micro,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: '운동 메뉴',
                        onSelected: (value) {
                          if (value == 'guide') {
                            _showExerciseGuide(context, exercise.template);
                          } else if (value == 'delete') {
                            _confirmDeleteExercise(context, state);
                          }
                        },
                        itemBuilder: (_) => [
                          if (exerciseGuides.containsKey(exercise.template.id))
                            const PopupMenuItem(
                              value: 'guide',
                              child: Row(
                                children: [
                                  Icon(SetflowIcons.guide),
                                  SizedBox(width: SetflowSpacing.sm2),
                                  Text('수행 방법'),
                                ],
                              ),
                            ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  color: context.setflowColors.error,
                                ),
                                SizedBox(width: SetflowSpacing.sm2),
                                Text(
                                  '운동 삭제',
                                  style: TextStyle(
                                    color: context.setflowColors.error,
                                  ),
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
          AnimatedSize(
            duration: SetflowMotion.standard,
            curve: SetflowMotion.emphasisCurve,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      for (final set in exercise.sets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SwipeableSet(
                            set: set,
                            enabled: _isSetLive(exercise, set),
                            showHint:
                                !state.hasSwipedSet &&
                                !set.completed &&
                                _isSetLive(exercise, set),
                            onToggle: () => _toggleSet(state, set),
                            onDelete: () =>
                                _confirmDeleteSet(context, state, set),
                            child: exercise.template.isCardio
                                ? _InlineCardioRow(
                                    template: exercise.template,
                                    set: set,
                                    onToggle: _isSetLive(exercise, set)
                                        ? () => _toggleSet(state, set)
                                        : null,
                                    onDurationChanged: (seconds) =>
                                        state.updateSet(
                                          set,
                                          durationSeconds: seconds,
                                        ),
                                    onDistanceChanged: (distance) => state
                                        .updateSet(set, distanceKm: distance),
                                    onRpeChanged: (rpe) =>
                                        state.updateSet(set, intensityRpe: rpe),
                                    onDelete: () =>
                                        _confirmDeleteSet(context, state, set),
                                  )
                                : _InlineSetRow(
                                    set: set,
                                    unit: state.weightUnit,
                                    onToggle: _isSetLive(exercise, set)
                                        ? () => _toggleSet(state, set)
                                        : null,
                                    onTypeChanged: (type) =>
                                        state.updateSet(set, type: type),
                                    onWeightChanged: (weight) =>
                                        state.updateSet(set, weight: weight),
                                    onRepsChanged: (reps) =>
                                        state.updateSet(set, reps: reps),
                                    onRestChanged: (seconds) => state.updateSet(
                                      set,
                                      restSeconds: seconds,
                                    ),
                                    onDelete: () =>
                                        _confirmDeleteSet(context, state, set),
                                  ),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: () => state.addSet(exercise),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          exercise.template.isCardio ? '구간 추가' : '세트 추가',
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Whether [set] is the one being worked on right now.
  ///
  /// Sets are done in order, so that is the first one not logged yet. Anything
  /// after it stays inert: logging a third set while the first was still open
  /// also restarted a rest that belonged to a different set. A logged set stays
  /// live so a mistake can be taken back.
  bool _isSetLive(WorkoutExercise exercise, WorkoutSetEntry set) {
    if (set.completed) return true;
    for (final item in exercise.sets) {
      if (!item.completed) return identical(item, set);
    }
    return false;
  }

  Future<void> _toggleSet(AppState state, WorkoutSetEntry set) async {
    final prs = set.completed
        ? <PerformancePrType>{}
        : state.prTypesForCandidate(widget.exercise.template, set);
    try {
      await state.toggleSet(set, startRest: !widget.exercise.template.isCardio);
    } catch (_) {
      if (mounted) {
        AppSnackbar.info(context, '기기 저장에 실패했어요. 상단의 다시 시도를 눌러주세요.');
      }
      return;
    }
    unawaited(state.syncPersistenceToServer().catchError((_) {}));
    if (!mounted) return;
    if (!set.completed) {
      recommendationShown = false;
      return;
    }
    final labels = prs.map((type) => type.label).join(' · ');
    final unit = widget.exercise.template.isCardio ? '구간' : '세트';
    // What was actually lifted becomes the plan for the sets still ahead. The
    // snapshot is taken first so the toast can hand it straight back.
    // 휴식 화면이 "무엇을 하다 쉬는지"를 말하려면 지금 찍어 둬야 한다.
    if (set.completed) {
      final session = state.sessions[state.dateOnly(widget.date)];
      if (session != null) state.noteRestFocus(session, widget.exercise);
    }
    final undo = AppState.snapshotPendingSets(widget.exercise, set);
    final adopted = state.adoptActualIntoPendingSets(widget.exercise, set);
    // The undo has to survive a PR: the first set of an exercise is very often
    // a record, and that is exactly the set whose numbers get propagated.
    // Announcing the record instead of the change would leave the guess
    // standing with no way back.
    final headline = labels.isEmpty ? '${set.number}$unit 저장' : '🏆 $labels 달성';
    if (adopted > 0) {
      AppSnackbar.undoable(
        context,
        '$headline · 남은 $adopted$unit도 같은 값으로 맞췄어요.',
        actionLabel: '되돌리기',
        onAction: () => state.restorePendingSets(undo),
      );
    } else if (labels.isNotEmpty) {
      AppSnackbar.success(context, '🏆 $labels을 달성했어요!');
    }
    // No toast for an ordinary logged set. The row folding to one line is the
    // confirmation, and a message in the middle of the screen every set — this
    // loop runs fifteen times a session — sits on top of the next set's button
    // and eats the tap meant for it.
    final allCompleted =
        widget.exercise.sets.isNotEmpty &&
        widget.exercise.sets.every((item) => item.completed);
    if (!allCompleted || recommendationShown) return;
    setState(() => collapsed = true);
    if (!state.autoRecommendNextExercise) return;
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
    await ensurePrecisionRecommendationSurvey(context);
    if (!mounted) return;
    if (state.recommendationProfile?.shouldPauseAutomaticRecommendation ??
        false) {
      AppSnackbar.info(
        context,
        '통증이 7/10 이상이라 자동 추천을 중단했어요. 의료 전문가의 평가를 먼저 받아주세요.',
      );
      return;
    }
    final unavailableEquipment = <String>{};
    while (mounted) {
      final recommendation = ExerciseRecommendationEngine.recommendNext(
        catalog: state.exercises,
        session: session,
        completedExercise: widget.exercise,
        goals: state.goals,
        weeklyHistory: state.sessions.values,
        excludedTemplateIds: unavailableEquipment,
        recommendationProfile: state.recommendationProfile,
      );
      if (recommendation == null) {
        AppSnackbar.info(
          context,
          state.recommendationProfile == null
              ? '사용 가능한 기구에 맞는 다른 추천이 없어요.'
              : '입력한 장비·숙련도·제외 동작에 맞는 다른 추천이 없어요.',
        );
        return;
      }
      final action = await showSetflowSheet<_RecommendationAction>(
        context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _NextExerciseRecommendationSheet(
          recommendation: recommendation,
          unit: state.weightUnit,
        ),
      );
      if (!mounted) return;
      if (action == _RecommendationAction.noEquipment) {
        unavailableEquipment.add(recommendation.template.id);
        continue;
      }
      if (action != _RecommendationAction.add) return;
      final added = state.addRecommendedExercise(widget.date, recommendation);
      if (added) {
        AppSnackbar.success(
          context,
          '${recommendation.template.name}을 다음 운동으로 추가했어요.',
        );
      }
      return;
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
                  backgroundColor: context.setflowColors.error,
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
                  backgroundColor: context.setflowColors.error,
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
  final VoidCallback? onToggle;
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
  bool deleteRevealed = false;

  /// A logged set folds down to one line; tapping opens it again for editing.
  bool reopened = false;

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
    // Un-completing reopens the card: a set that is no longer logged has to
    // show its dials again.
    if (oldWidget.set.completed && !widget.set.completed) reopened = false;
    if (oldWidget.set.durationSeconds != widget.set.durationSeconds) {
      durationController.text = _durationText();
    }
    if (oldWidget.set.distanceKm != widget.set.distanceKm) {
      distanceController.text = _distanceText();
    }
    if (oldWidget.set.intensityRpe != widget.set.intensityRpe) {
      rpeController.text = _rpeText();
    }
  }

  @override
  void dispose() {
    durationController.dispose();
    distanceController.dispose();
    rpeController.dispose();
    super.dispose();
  }

  String _durationText() => _decimalText(widget.set.durationSeconds / 60);
  String _distanceText() =>
      widget.set.distanceKm <= 0 ? '' : _decimalText(widget.set.distanceKm);
  String _rpeText() =>
      widget.set.intensityRpe <= 0 ? '' : _decimalText(widget.set.intensityRpe);

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
    if (widget.set.completed && !reopened) {
      return _CompletedSetLine(
        key: ValueKey('inline-cardio-done-${widget.set.number}'),
        number: widget.set.number,
        label: '구간',
        summary: _summary,
        onExpand: () => setState(() => reopened = true),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        setState(() => deleteRevealed = true);
      },
      child: AnimatedContainer(
        duration: SetflowMotion.standard,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
        decoration: BoxDecoration(
          color: widget.set.completed
              ? context.setflowColors.teal.withValues(alpha: .09)
              : context.setflowColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          border: Border.all(
            color: widget.set.completed
                ? context.setflowColors.teal.withValues(alpha: .35)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(SetflowRadii.full),
                  ),
                  child: Text(
                    '${widget.set.number}구간',
                    style: const TextStyle(
                      fontSize: SetflowFontSize.small,
                      fontWeight: SetflowWeight.medium,
                    ),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: Text(
                    _summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: SetflowFontSize.tiny,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _cardioField(
                    key: ValueKey('cardio-duration-${widget.set.number}'),
                    label: '시간',
                    suffix: '분',
                    controller: durationController,
                    onDial: () => _pickCardioValue(
                      title: '운동 시간',
                      suffix: '분',
                      initialValue: widget.set.durationSeconds / 60,
                      min: 1,
                      max: 180,
                      step: 1,
                      controller: durationController,
                      onChanged: (value) =>
                          widget.onDurationChanged((value * 60).round()),
                    ),
                  ),
                ),
                if (supportsDistance) ...[
                  const SizedBox(width: SetflowSpacing.xs2),
                  Expanded(
                    child: _cardioField(
                      key: ValueKey('cardio-distance-${widget.set.number}'),
                      label: '거리',
                      suffix: 'km',
                      controller: distanceController,
                      onDial: () => _pickCardioValue(
                        title: '운동 거리',
                        suffix: 'km',
                        initialValue: widget.set.distanceKm,
                        min: 0,
                        max: 100,
                        step: .1,
                        controller: distanceController,
                        onChanged: widget.onDistanceChanged,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: SetflowSpacing.xs2),
                Expanded(
                  child: _cardioField(
                    key: ValueKey('cardio-rpe-${widget.set.number}'),
                    label: '강도',
                    suffix: 'RPE',
                    controller: rpeController,
                    onDial: () => _pickCardioValue(
                      title: '운동 강도',
                      suffix: 'RPE',
                      initialValue: widget.set.intensityRpe <= 0
                          ? 3
                          : widget.set.intensityRpe,
                      min: 1,
                      max: 10,
                      step: .5,
                      controller: rpeController,
                      onChanged: widget.onRpeChanged,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.xs2),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'RPE 3–4 중강도 · 7–9 고강도 · 1–2는 가벼운 활동',
                style: TextStyle(
                  fontSize: SetflowFontSize.micro,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            AnimatedSize(
              duration: SetflowMotion.micro,
              child: deleteRevealed
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '길게 눌러 삭제 메뉴를 열었어요.',
                              style: TextStyle(
                                fontSize: SetflowFontSize.micro,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => deleteRevealed = false),
                            child: const Text('닫기'),
                          ),
                          TextButton.icon(
                            onPressed: widget.onDelete,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('구간 삭제'),
                            style: TextButton.styleFrom(
                              foregroundColor: context.setflowColors.error,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCardioValue({
    required String title,
    required String suffix,
    required double initialValue,
    required double min,
    required double max,
    required double step,
    required TextEditingController controller,
    required ValueChanged<double> onChanged,
  }) async {
    final result = await _showNumberDial(
      context,
      title: title,
      suffix: suffix,
      initialValue: initialValue,
      min: min,
      max: max,
      step: step,
    );
    if (result == null || !mounted) return;
    controller.text = _decimalText(result);
    onChanged(result);
  }

  Widget _cardioField({
    required Key key,
    required String label,
    required String suffix,
    required TextEditingController controller,
    required VoidCallback onDial,
  }) {
    return _DialValueField(
      key: key,
      label: label,
      suffix: suffix,
      controller: controller,
      enabled: !widget.set.completed,
      onDial: onDial,
    );
  }
}

/// A number the user picks, never types in place.
///
/// The box *is* the button: tapping it opens [_showNumberDial], where the value
/// is dialled or typed and then applied. It used to be an editable field with a
/// tune icon hanging off its right edge — two hit targets for one number, and
/// the icon ate the width the number needed.
///
/// Read-only on purpose, and it refuses focus so no keyboard ever races the
/// sheet. That also means there is no half-typed number sitting in the
/// controller when the screen locks mid-lift: the dial's 적용 is the only
/// commit, and it writes straight through to the session.
class _DialValueField extends StatelessWidget {
  const _DialValueField({
    required this.label,
    required this.suffix,
    required this.controller,
    required this.enabled,
    required this.onDial,
    super.key,
  });

  final String label;
  final String suffix;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onDial;

  @override
  Widget build(BuildContext context) {
    // The TextField is here for its decoration only — the box is a button, not
    // an input (AGENTS.md 5). Its own gestures are switched off because the
    // selection drag wins the arena against the row's swipe, and the three
    // boxes cover most of the row: the set's own numbers would swallow the
    // gesture that logs it.
    return Semantics(
      button: enabled,
      label: '$label ${controller.text}$suffix',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onDial : null,
        child: IgnorePointer(
          child: TextField(
            controller: controller,
            enabled: enabled,
            readOnly: true,
            canRequestFocus: false,
            mouseCursor: SystemMouseCursors.click,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: SetflowFontSize.body,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
            ),
          ),
        ),
      ),
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
  });

  final WorkoutSetEntry set;
  final String unit;
  final VoidCallback? onToggle;
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
  bool deleteRevealed = false;

  /// A logged set folds down to one line; tapping opens it again for editing.
  bool reopened = false;

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
    // Un-completing reopens the card: a set that is no longer logged has to
    // show its dials again.
    if (oldWidget.set.completed && !widget.set.completed) reopened = false;
    if (oldWidget.set.weight != widget.set.weight) {
      weightController.text = _weightText();
    }
    if (oldWidget.set.reps != widget.set.reps) {
      repsController.text = '${widget.set.reps}';
    }
    if (oldWidget.set.restSeconds != widget.set.restSeconds) {
      restController.text = '${widget.set.restSeconds}';
    }
  }

  @override
  void dispose() {
    weightController.dispose();
    repsController.dispose();
    restController.dispose();
    super.dispose();
  }

  String _weightText() =>
      widget.set.weight.toStringAsFixed(widget.set.weight % 1 == 0 ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    if (widget.set.completed && !reopened) {
      return _CompletedSetLine(
        key: ValueKey('inline-set-done-${widget.set.number}'),
        number: widget.set.number,
        label: '세트',
        summary: '${_weightText()}${widget.unit} × ${widget.set.reps}회',
        onExpand: () => setState(() => reopened = true),
      );
    }
    final estimate = PerformanceEngine.estimate(
      widget.set.weight,
      widget.set.reps,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        setState(() => deleteRevealed = true);
      },
      child: AnimatedContainer(
        duration: SetflowMotion.standard,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
        decoration: BoxDecoration(
          color: widget.set.completed
              ? context.setflowColors.teal.withValues(alpha: .09)
              : context.setflowColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          border: Border.all(
            color: widget.set.completed
                ? context.setflowColors.teal.withValues(alpha: .35)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(SetflowRadii.full),
                  ),
                  child: Text(
                    '${widget.set.number}세트',
                    style: const TextStyle(
                      fontSize: SetflowFontSize.small,
                      fontWeight: SetflowWeight.medium,
                    ),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  // 추정치가 없을 때는 비운다. 갓 만든 기록에서는 모든 세트가
                  // 계산 제외라, 여섯 줄이 전부 같은 전문 용어를 반복하면서
                  // 정작 무게·횟수보다 먼저 읽혔다. 숫자가 생기면 그때 뜬다.
                  child: estimate == null
                      ? const SizedBox.shrink()
                      : Text(
                          'e1RM ${estimate.value.toStringAsFixed(1)} · ${estimate.quality.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: SetflowFontSize.micro,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                  itemBuilder: (_) => [
                    PopupMenuItem(value: '일반', child: Text('일반 세트')),
                    PopupMenuItem(value: '웜업', child: Text('웜업 세트')),
                    PopupMenuItem(value: '드랍', child: Text('드랍 세트')),
                    PopupMenuItem(value: '실패', child: Text('실패 세트')),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        '세트 삭제',
                        style: TextStyle(color: context.setflowColors.error),
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
                        fontSize: SetflowFontSize.tiny,
                        color: _typeColor(widget.set.type),
                        fontWeight: SetflowWeight.medium,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.xs),
              ],
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    key: ValueKey('inline-set-weight-${widget.set.number}'),
                    label: '무게',
                    suffix: widget.unit,
                    controller: weightController,
                    onDial: () => _pickSetValue(
                      title: '무게',
                      suffix: widget.unit,
                      initialValue: widget.set.weight,
                      min: 0,
                      max: 999,
                      step: .5,
                      controller: weightController,
                      onChanged: widget.onWeightChanged,
                    ),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.xs2),
                Expanded(
                  child: _numberField(
                    key: ValueKey('inline-set-reps-${widget.set.number}'),
                    label: '횟수',
                    suffix: '회',
                    controller: repsController,
                    onDial: () => _pickSetValue(
                      title: '횟수',
                      suffix: '회',
                      initialValue: widget.set.reps.toDouble(),
                      min: 0,
                      max: 100,
                      step: 1,
                      controller: repsController,
                      onChanged: (value) => widget.onRepsChanged(value.round()),
                    ),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.xs2),
                Expanded(
                  child: _numberField(
                    key: ValueKey('inline-set-rest-${widget.set.number}'),
                    label: '휴식',
                    suffix: '초',
                    controller: restController,
                    onDial: () => _pickSetValue(
                      title: '휴식 시간',
                      suffix: '초',
                      initialValue: widget.set.restSeconds.toDouble(),
                      min: 15,
                      max: 600,
                      step: 5,
                      controller: restController,
                      onChanged: (value) => widget.onRestChanged(value.round()),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: SetflowMotion.micro,
              child: deleteRevealed
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '길게 눌러 삭제 메뉴를 열었어요.',
                              style: TextStyle(
                                fontSize: SetflowFontSize.micro,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => deleteRevealed = false),
                            child: const Text('닫기'),
                          ),
                          TextButton.icon(
                            onPressed: widget.onDelete,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('세트 삭제'),
                            style: TextButton.styleFrom(
                              foregroundColor: context.setflowColors.error,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSetValue({
    required String title,
    required String suffix,
    required double initialValue,
    required double min,
    required double max,
    required double step,
    required TextEditingController controller,
    required ValueChanged<double> onChanged,
  }) async {
    final result = await _showNumberDial(
      context,
      title: title,
      suffix: suffix,
      initialValue: initialValue,
      min: min,
      max: max,
      step: step,
    );
    if (result == null || !mounted) return;
    controller.text = _decimalText(result);
    onChanged(result);
  }

  Widget _numberField({
    required Key key,
    required String label,
    required String suffix,
    required TextEditingController controller,
    required VoidCallback onDial,
  }) {
    return _DialValueField(
      key: key,
      label: label,
      suffix: suffix,
      controller: controller,
      enabled: !widget.set.completed,
      onDial: onDial,
    );
  }

  /// Colour marks the set types that are *not* ordinary. A plain set gets the
  /// neutral label — tinting it too made every row look like it meant something.
  Color _typeColor(String type) => switch (type) {
    '웜업' => context.setflowColors.orange,
    '드랍' => context.setflowColors.blue,
    '실패' => context.setflowColors.error,
    _ => SetflowColors.steel,
  };
}

/// The one control the whole product turns on: completing a set saves the
/// record, updates volume and starts the rest timer.
///
/// It used to be a grey box reading "완료". The word was doing no work — the
/// row is a set, there is nothing else to finish — and a filled grey pill next
/// to three grey number boxes read as one more field. So it is a circle with a
/// check, and the state is carried the way this app carries every state:
/// **by density**. Empty outline = not done, black fill = done.
/// Right to log the set, left to delete it.
///
/// The set loop is the same three moves over and over — lift, log, rest — and a
/// 48px circle is a small target for a shaking hand. Swiping makes the whole row
/// the target. The circle stays inside the row: a gesture is the only way to
/// reach a control that has no other affordance, and that leaves a screen reader
/// with nothing to press.
///
/// Neither direction removes the row here. Completing collapses it (the numbers
/// stay on screen as history), and deleting goes through the confirm dialog that
/// owns the removal — so `confirmDismiss` always answers false and the row
/// springs back while the real work happens behind it.
/// Right to log the set, left to delete it.
///
/// The set loop is the same three moves over and over — lift, log, rest — and a
/// 48px circle is a small target for a shaking hand. Swiping makes the whole row
/// the target. The circle stays inside the row: a gesture is the only way to
/// reach a control that has no other affordance, and that leaves a screen reader
/// with nothing to press.
///
/// Only [enabled] rows answer the log gesture. Sets are done in order, so the
/// one being worked on is the first that is not logged yet; letting a later one
/// be swiped meant a third set could be logged while the first was still open,
/// and it restarted a rest that belonged to a different set.
///
/// Neither direction removes the row. Logging folds it (the numbers stay on
/// screen as history) and deleting goes through the confirm dialog that owns the
/// removal, so `confirmDismiss` always answers false and the row springs back
/// while the real work happens behind it.
class _SwipeableSet extends StatefulWidget {
  const _SwipeableSet({
    required this.set,
    required this.enabled,
    required this.showHint,
    required this.onToggle,
    required this.onDelete,
    required this.child,
  });

  final WorkoutSetEntry set;
  final bool enabled;

  /// 아직 밀어본 적 없는 사용자에게, 차례인 행 하나만 움직여 보인다.
  final bool showHint;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<_SwipeableSet> createState() => _SwipeableSetState();
}

class _SwipeableSetState extends State<_SwipeableSet>
    with SingleTickerProviderStateMixin {
  /// How far the row has travelled, 0..1 of its own width.
  double progress = 0;
  bool towardsEnd = false;

  /// A swipe has no handle, so before anyone has done one there is nothing on
  /// screen that says the row moves. The live row nudges itself a few pixels
  /// and settles back — enough to read as "this slides", not enough to look
  /// like a glitch. It runs twice and never again once a set has been logged
  /// this way.
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeHint());
  }

  @override
  void didUpdateWidget(covariant _SwipeableSet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The turn moves down the list as sets are logged; the new live row gets
    // the hint if the lesson still has not landed.
    if (!oldWidget.enabled && widget.enabled) _maybeHint();
  }

  void _maybeHint() {
    if (!mounted || !widget.showHint) return;
    // Someone who turned animations off is not being taught with motion.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _hint.forward(from: 0);
  }

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  /// Two soft pushes to the right, each returning to rest.
  double get _nudge {
    final t = _hint.value;
    if (t >= 1) return 0;
    final cycle = (t * 2) % 1;
    final wave = Curves.easeInOut.transform(
      cycle < .5 ? cycle * 2 : (1 - cycle) * 2,
    );
    return wave * 14;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logging = !towardsEnd;
    // The wash is the brand; the glyph on top of it is not. Lime on a lime
    // wash disappears, which is the same 1.18:1 trap the rule warns about.
    final fill = logging
        ? theme.colorScheme.primary
        : context.setflowColors.error;
    final accent = logging
        ? theme.colorScheme.onSurface
        : context.setflowColors.error;
    final radius = BorderRadius.circular(SetflowRadii.md);

    return ClipRRect(
      // The row and the track behind it have to share one rounded box, or the
      // square corners of the track show through the moment the row starts to
      // travel.
      borderRadius: radius,
      child: Semantics(
        // The circle is gone, so the gesture is the only way in — and a swipe
        // is not something assistive tech can perform. This is the way back:
        // TalkBack and VoiceOver list it as an action on the row itself,
        // without putting a control on screen.
        customSemanticsActions: {
          if (widget.enabled)
            CustomSemanticsAction(label: widget.set.completed ? '완료 취소' : '완료'):
                widget.onToggle,
          CustomSemanticsAction(label: '세트 삭제'): widget.onDelete,
        },
        child: AnimatedBuilder(
          animation: _hint,
          builder: (context, child) =>
              Transform.translate(offset: Offset(_nudge, 0), child: child),
          child: Dismissible(
            key: ObjectKey(widget.set),
            direction: widget.enabled
                ? DismissDirection.horizontal
                : DismissDirection.endToStart,
            // Generous on purpose: the row lives inside a vertical scroll, and an
            // accidental log also starts the rest timer.
            dismissThresholds: const {
              DismissDirection.startToEnd: .4,
              DismissDirection.endToStart: .4,
            },
            onUpdate: (details) {
              if (details.reached && !details.previousReached) {
                HapticFeedback.mediumImpact();
              }
              setState(() {
                progress = details.progress;
                towardsEnd = details.direction == DismissDirection.endToStart;
              });
            },
            background: _track(fill: fill, accent: accent, logging: true),
            secondaryBackground: _track(
              fill: context.setflowColors.error,
              accent: context.setflowColors.error,
              logging: false,
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                widget.onToggle();
              } else {
                widget.onDelete();
              }
              return false;
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }

  /// The track the row slides over — a wash that deepens with the drag rather
  /// than a panel being uncovered, so the gesture reads as "slide to unlock".
  ///
  /// The label rides a solid chip, not the wash. Against the wash no foreground
  /// survives the whole drag in dark: ink needs the wash bright, white needs it
  /// dim, and the wash passes through both. On the chip the pairing is fixed —
  /// ink on lime is 16:1 wherever the drag happens to be.
  Widget _track({
    required Color fill,
    required Color accent,
    required bool logging,
  }) {
    // Ramped, not linear: the wash should be unmistakable by the time the
    // threshold is near, and barely there for a stray sideways scroll.
    final strength = Curves.easeIn.transform(progress.clamp(0, 1).toDouble());
    final passed = progress >= .4;
    final label = logging ? (widget.set.completed ? '되돌리기' : '완료') : '삭제';
    final icon = logging
        ? (widget.set.completed ? SetflowIcons.undo : SetflowIcons.setComplete)
        : Icons.delete_outline_rounded;

    return ColoredBox(
      color: fill.withValues(alpha: .10 + .40 * strength),
      child: Align(
        alignment: logging ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: AnimatedScale(
            // A small kick at the threshold: the row has to say "let go now"
            // without the thumb leaving the glass to look for a label.
            scale: passed ? 1.08 : 1,
            duration: SetflowMotion.micro,
            child: Opacity(
              opacity: (.45 + .55 * strength).clamp(0.0, 1.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: accent),
                    const SizedBox(width: SetflowSpacing.xs2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: SetflowFontSize.caption,
                        fontWeight: SetflowWeight.medium,
                        color: accent,
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

/// Tapping opens it again — a logged set is still editable.
class _CompletedSetLine extends StatelessWidget {
  const _CompletedSetLine({
    required this.number,
    required this.summary,
    required this.label,
    required this.onExpand,
    super.key,
  });

  final int number;
  final String summary;
  final String label;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$number$label $summary, 눌러서 펼치기',
      excludeSemantics: true,
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(SetflowRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.setflowColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(SetflowRadii.md),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(
                SetflowIcons.setComplete,
                size: 17,
                // Success, not the brand. Lime is a fill — as a glyph on white
                // it sits at 1.18:1 and simply is not there.
                color: context.setflowColors.success,
              ),
              const SizedBox(width: SetflowSpacing.sm2),
              Text(
                '$number$label',
                style: const TextStyle(
                  fontSize: SetflowFontSize.caption,
                  fontWeight: SetflowWeight.medium,
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm2),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RecommendationAction { chooseManually, noEquipment, add }

class _NextExerciseRecommendationSheet extends StatelessWidget {
  const _NextExerciseRecommendationSheet({
    required this.recommendation,
    required this.unit,
    this.title = '다음 운동 추천',
  });

  final NextExerciseRecommendation recommendation;
  final String unit;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cardio = recommendation.cardioPrescription;
    final prescriptionText = cardio == null
        ? '${recommendation.startingWeight > 0 ? '${PerformanceEngine.formatWeight(recommendation.startingWeight)}$unit' : '중량 직접 선택'} · '
              '${recommendation.minReps}–${recommendation.maxReps}회 · '
              '${recommendation.sets}세트 · 휴식 ${recommendation.restSeconds}초'
        : '${cardio.durationMinutes}분'
              '${cardio.targetDistanceKm == null ? '' : ' · ${cardio.targetDistanceKm!.toStringAsFixed(1)}km'}'
              ' · RPE ${cardio.minimumRpe}–${cardio.maximumRpe}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  color: context.setflowColors.orange,
                ),
                const SizedBox(width: SetflowSpacing.sm2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: SetflowFontSize.headline,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Chip(label: Text(recommendation.goalLabel)),
              ],
            ),
            const SizedBox(height: SetflowSpacing.md2),
            SetflowCard(
              color: SetflowColors.primary.withValues(alpha: .14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recommendation.template.name,
                    style: const TextStyle(
                      fontSize: SetflowFontSize.titleLarge,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs2),
                  Text(
                    prescriptionText,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: SetflowSpacing.sm2),
                  Text(
                    recommendation.reason,
                    style: TextStyle(
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm2),
            Text(
              recommendation.evidenceNote.isNotEmpty
                  ? recommendation.evidenceNote
                  : cardio == null
                  ? '논문이 특정 다음 운동 하나를 최적이라고 정한 것은 아닙니다. 목표·주간 기록을 근거 원칙에 대입한 앱 규칙입니다.'
                  : '유산소는 시간·거리·RPE로 제안하며 첫 기록의 거리를 임의로 만들지 않습니다.',
              style: TextStyle(
                fontSize: SetflowFontSize.tiny,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (recommendation.evidenceIds.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EvidenceLibraryScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: Text('근거 논문 ${recommendation.evidenceIds.length}건 보기'),
                ),
              ),
            const SizedBox(height: SetflowSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('recommendation-no-equipment'),
                onPressed: () =>
                    Navigator.pop(context, _RecommendationAction.noEquipment),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('기구 없음 · 다른 운동 추천'),
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _RecommendationAction.chooseManually,
                    ),
                    child: const Text('직접 선택'),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, _RecommendationAction.add),
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
  String? muscle;
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
    final showCategories = search.trim().isEmpty && muscle == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(muscle == null ? '운동 선택' : '$muscle 운동'),
        actions: [
          IconButton(
            tooltip: '새 운동 만들기',
            onPressed: () => _createExercise(context),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
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
              hint: '전체 운동 검색 (한국어/영문)',
            ),
          ),
          Expanded(
            child: showCategories
                ? GridView.builder(
                    key: const Key('exercise-muscle-grid'),
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 110),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.18,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _muscleCategories(context).length,
                    itemBuilder: (_, index) {
                      final category = _muscleCategories(context)[index];
                      final count = category.name == '전체'
                          ? state.exercises.length
                          : state.exercises
                                .where(
                                  (exercise) =>
                                      exercise.muscle == category.name,
                                )
                                .length;
                      return _MuscleCategoryCard(
                        category: category,
                        exerciseCount: count,
                        onTap: () => setState(() => muscle = category.name),
                      );
                    },
                  )
                : filtered.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: '검색 결과가 없어요',
                    message: '검색어를 바꾸거나 전체 부위에서 다시 찾아보세요.',
                    actionLabel: '검색 초기화',
                    onAction: () => setState(() {
                      searchController.clear();
                      search = '';
                      muscle = null;
                    }),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() => muscle = null),
                              icon: const Icon(
                                Icons.grid_view_rounded,
                                size: 17,
                              ),
                              label: const Text('부위 선택'),
                            ),
                            const Spacer(),
                            Text(
                              '${filtered.length}개 운동',
                              style: TextStyle(
                                fontSize: SetflowFontSize.small,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            SetflowSpacing.gutter,
                            0,
                            SetflowSpacing.gutter,
                            100,
                          ),
                          itemCount: filtered.length + 1,
                          itemBuilder: (_, index) {
                            if (index == filtered.length) {
                              return Padding(
                                padding: const EdgeInsets.all(8),
                                child: OutlinedButton.icon(
                                  key: const Key('create-custom-exercise'),
                                  onPressed: () => _createExercise(context),
                                  icon: const Icon(Icons.add),
                                  label: const Text('새로운 운동 만들기'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        SetflowRadii.md,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }
                            final exercise = filtered[index];
                            final isSelected = selected.contains(exercise.id);
                            final previous = state.performanceFor(
                              exercise,
                              before: state.dateOnly(widget.date),
                            );
                            final recommendation = state.recommendationFor(
                              exercise,
                              before: state.dateOnly(widget.date),
                            );
                            final existingCount =
                                state
                                    .sessions[state.dateOnly(widget.date)]
                                    ?.exercises
                                    .where(
                                      (item) => item.template.id == exercise.id,
                                    )
                                    .length ??
                                0;
                            final suggestedWeight =
                                recommendation?.weight ??
                                previous?.latestSessionBest.set.weight;
                            final suggestedReps =
                                recommendation?.minReps ??
                                previous?.latestSessionBest.set.reps;
                            final subtitleParts = <String>[
                              exercise.id.startsWith('custom_')
                                  ? '${exercise.muscle} · 내가 만든 운동'
                                  : exercise.muscle,
                              if (existingCount > 0) '오늘 $existingCount회 추가됨',
                              if (suggestedWeight != null &&
                                  suggestedWeight > 0 &&
                                  suggestedReps != null)
                                '이전 기록 추천 ${PerformanceEngine.formatWeight(suggestedWeight)}${state.weightUnit} × $suggestedReps회',
                            ];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              leading: Icon(
                                exercise.icon,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                exercise.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(subtitleParts.join(' · ')),
                              trailing: IconButton(
                                tooltip: isSelected ? '선택 해제' : '선택',
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
          ),
        ],
      ),
      floatingActionButton: selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addSelected(context),
              icon: const Icon(Icons.check),
              label: Text('${selected.length}개 운동 추가'),
            ),
    );
  }

  Future<void> _createExercise(BuildContext context) async {
    final draft = await showSetflowSheet<_CustomExerciseDraft>(
      context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateExerciseSheet(initialMuscle: muscle),
    );
    if (draft == null || !context.mounted) return;
    final created = AppScope.of(
      context,
    ).createCustomExercise(name: draft.name, muscle: draft.muscle);
    if (created == null) {
      AppSnackbar.error(context, '같은 이름의 운동이 있거나 입력값을 확인해주세요.');
      return;
    }
    setState(() {
      selected.add(created.id);
      muscle = created.muscle;
      searchController.clear();
      search = '';
    });
    AppSnackbar.success(context, '${created.name}을 만들고 선택했어요.');
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

class _MuscleCategory {
  _MuscleCategory(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

/// 부위별 색은 테마를 따라야 해서 const 리스트에서 함수가 됐다.
List<_MuscleCategory> _muscleCategories(BuildContext context) => [
  _MuscleCategory('전체', Icons.apps_rounded, context.setflowColors.orange),
  _MuscleCategory(
    '가슴',
    Icons.fitness_center_rounded,
    context.setflowColors.error,
  ),
  _MuscleCategory('등', Icons.rowing_rounded, context.setflowColors.blue),
  _MuscleCategory(
    '어깨',
    Icons.accessibility_new_rounded,
    context.setflowColors.teal,
  ),
  _MuscleCategory(
    '하체',
    Icons.directions_walk_rounded,
    context.setflowColors.success,
  ),
  _MuscleCategory(
    '팔',
    Icons.sports_gymnastics_rounded,
    context.setflowColors.orange,
  ),
  _MuscleCategory('복근', Icons.self_improvement_rounded, SetflowNeutral.n600),
  _MuscleCategory('유산소', Icons.directions_run_rounded, SetflowNeutral.n600),
];

class _MuscleCategoryCard extends StatelessWidget {
  const _MuscleCategoryCard({
    required this.category,
    required this.exerciseCount,
    required this.onTap,
  });

  final _MuscleCategory category;
  final int exerciseCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${category.name}, 운동 $exerciseCount개',
      child: Material(
        color: category.color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                right: -8,
                bottom: -12,
                child: Icon(
                  category.icon,
                  size: 92,
                  color: category.color.withValues(alpha: .2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(category.icon, color: category.color),
                    const Spacer(),
                    Text(
                      category.name,
                      style: const TextStyle(
                        fontSize: SetflowFontSize.titleLarge,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$exerciseCount개 운동 보기',
                      style: TextStyle(
                        fontSize: SetflowFontSize.tiny,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    );
  }
}

class _CustomExerciseDraft {
  const _CustomExerciseDraft({required this.name, required this.muscle});

  final String name;
  final String muscle;
}

class _CreateExerciseSheet extends StatefulWidget {
  const _CreateExerciseSheet({this.initialMuscle});

  final String? initialMuscle;

  @override
  State<_CreateExerciseSheet> createState() => _CreateExerciseSheetState();
}

class _CreateExerciseSheetState extends State<_CreateExerciseSheet> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  late String muscle;

  @override
  void initState() {
    super.initState();
    muscle = widget.initialMuscle == null || widget.initialMuscle == '전체'
        ? '가슴'
        : widget.initialMuscle!;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (!(formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _CustomExerciseDraft(name: nameController.text.trim(), muscle: muscle),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '새로운 운동 만들기',
              style: TextStyle(
                fontSize: SetflowFontSize.headline,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xs2),
            Text(
              '만든 운동은 내 운동 목록에 저장되고 다른 기기에도 동기화됩니다.',
              style: TextStyle(
                fontSize: SetflowFontSize.small,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            AppTextField(
              key: const Key('custom-exercise-name'),
              controller: nameController,
              autofocus: true,
              label: '운동 이름',
              hint: '예: 인클라인 스미스 머신 프레스',
              textInputAction: TextInputAction.next,
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return '운동 이름을 입력해주세요.';
                if (name.length > 50) return '운동 이름은 50자 이내로 입력해주세요.';
                return null;
              },
            ),
            const SizedBox(height: SetflowSpacing.md),
            DropdownButtonFormField<String>(
              key: const Key('custom-exercise-muscle'),
              initialValue: muscle,
              decoration: const InputDecoration(
                labelText: '운동 부위',
                prefixIcon: Icon(Icons.accessibility_new_rounded),
              ),
              items: _muscleCategories(context)
                  .where((category) => category.name != '전체')
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.name,
                      child: Text(category.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => muscle = value);
              },
            ),
            const SizedBox(height: SetflowSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('save-custom-exercise'),
                onPressed: _save,
                icon: const Icon(Icons.add_rounded),
                label: const Text('운동 만들기'),
              ),
            ),
          ],
        ),
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
      color: context.setflowColors.error.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(SetflowRadii.md),
      child: ListTile(
        leading: Icon(
          Icons.cloud_off_rounded,
          color: context.setflowColors.error,
        ),
        title: const Text('기록을 기기에 저장하지 못했어요.'),
        trailing: TextButton(onPressed: onRetry, child: const Text('재시도')),
      ),
    );
  }
}

class _PersistenceSyncNotice extends StatelessWidget {
  const _PersistenceSyncNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.setflowColors.orange.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(SetflowRadii.md),
      child: ListTile(
        leading: Icon(
          Icons.cloud_sync_outlined,
          color: context.setflowColors.orange,
        ),
        title: const Text('기기에 저장됨 · 서버 동기화 대기 중'),
        trailing: TextButton(onPressed: onRetry, child: const Text('지금 동기화')),
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
            key: const ValueKey('exercise-history'),
            tooltip: '지난 기록',
            onPressed: () =>
                _showExerciseHistory(context, state, exercise.template),
            icon: const Icon(SetflowIcons.pastDays),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          4,
          SetflowSpacing.gutter,
          100,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SetflowColors.primary.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(SetflowRadii.lg),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  color: context.setflowColors.orange,
                ),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PERFORMANCE',
                        style: TextStyle(
                          fontSize: SetflowFontSize.small,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        previous == null
                            ? '첫 기록을 시작해보세요'
                            : '예상 1RM '
                                  '${previous.currentE1rm.toStringAsFixed(1)} '
                                  '${state.weightUnit}',
                        style: const TextStyle(
                          fontSize: SetflowFontSize.titleLarge,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        previous == null
                            ? '완료한 세트부터 PR과 추천 중량을 계산해요.'
                            : '최근 최고 '
                                  '${PerformanceEngine.formatWeight(previous.latestSessionBest.set.weight)}'
                                  '${state.weightUnit} × '
                                  '${previous.latestSessionBest.set.reps}회 · '
                                  '추정 품질 ${previous.quality.label}',
                        style: TextStyle(
                          fontSize: SetflowFontSize.small,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                          ? context.setflowColors.success
                          : context.setflowColors.orange,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          Row(
            children: [
              SizedBox(
                width: 44,
                child: Center(
                  child: Text(
                    '세트',
                    style: TextStyle(
                      fontSize: SetflowFontSize.small,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      fontSize: SetflowFontSize.small,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      fontSize: SetflowFontSize.small,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                      fontSize: SetflowFontSize.small,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
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
                  color: context.setflowColors.error,
                  borderRadius: BorderRadius.circular(SetflowRadii.lg),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () async {
                    HapticFeedback.mediumImpact();
                    final confirmed = await _confirmDeleteSet(context, set);
                    if (!confirmed || !context.mounted) return;
                    state.removeSet(exercise, set);
                    AppSnackbar.success(context, '세트를 삭제했어요.');
                  },
                  child: SetflowCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    color: set.completed
                        ? context.setflowColors.teal.withValues(alpha: .1)
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
                                    fontSize: SetflowFontSize.title,
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
                            const SizedBox(width: SetflowSpacing.sm),
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
                                activeColor: context.setflowColors.teal,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    SetflowRadii.xs,
                                  ),
                                ),
                                onChanged: (_) async {
                                  final prs = set.completed
                                      ? <PerformancePrType>{}
                                      : state.prTypesForCandidate(
                                          exercise.template,
                                          set,
                                        );
                                  try {
                                    await state.toggleSet(set);
                                  } catch (_) {
                                    if (context.mounted) {
                                      AppSnackbar.info(
                                        context,
                                        '기기 저장에 실패했어요. 다시 시도해주세요.',
                                      );
                                    }
                                    return;
                                  }
                                  unawaited(
                                    state.syncPersistenceToServer().catchError(
                                      (_) {},
                                    ),
                                  );
                                  if (!context.mounted) return;
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
                        const SizedBox(height: SetflowSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.only(left: 40),
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
                                          style: const TextStyle(
                                            fontSize: SetflowFontSize.tiny,
                                          ),
                                        ),
                                        selected: set.type == type,
                                        visualDensity: VisualDensity.compact,
                                        onSelected: (_) =>
                                            state.updateSet(set, type: type),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              if (PerformanceEngine.estimate(
                                    set.weight,
                                    set.reps,
                                  )
                                  case final estimate?)
                                Text(
                                  'e1RM ${estimate.value.toStringAsFixed(1)} · '
                                  '${estimate.quality.label}',
                                  style: TextStyle(
                                    fontSize: SetflowFontSize.tiny,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else
                                Text(
                                  'e1RM 계산 제외',
                                  style: TextStyle(
                                    fontSize: SetflowFontSize.tiny,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
            ),
          OutlinedButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add),
            label: const Text('세트 추가'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          SetflowCard(
            child: Row(
              children: [
                Icon(Icons.info_outline, color: context.setflowColors.blue),
                SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Text(
                    '완료 체크 한 번으로 기록 저장, 볼륨 계산, 휴식 타이머가 동시에 시작됩니다.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: SetflowFontSize.caption,
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
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          4,
          SetflowSpacing.gutter,
          100,
        ),
        children: [
          SetflowCard(
            color: context.setflowColors.blue.withValues(alpha: .08),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.directions_run_rounded,
                  color: context.setflowColors.blue,
                ),
                SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Text(
                    '유산소는 무게나 반복 횟수 대신 시간·거리·자각 강도(RPE)를 기록합니다. 거리 측정이 어울리지 않는 종목은 시간과 RPE만 표시해요.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: SetflowFontSize.caption,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.md2),
          for (final set in exercise.sets) ...[
            _InlineCardioRow(
              key: ValueKey('cardio-detail-segment-${set.number}'),
              template: exercise.template,
              set: set,
              onToggle: () async {
                try {
                  await state.toggleSet(set, startRest: false);
                } catch (_) {
                  if (context.mounted) {
                    AppSnackbar.info(context, '기기 저장에 실패했어요. 다시 시도해주세요.');
                  }
                  return;
                }
                unawaited(state.syncPersistenceToServer().catchError((_) {}));
              },
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
            const SizedBox(height: SetflowSpacing.sm2),
          ],
          OutlinedButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add),
            label: const Text('구간 추가'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SetflowRadii.lg),
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
                  backgroundColor: context.setflowColors.error,
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
    final result = await _showNumberDial(
      context,
      title: editsWeight ? '무게' : '횟수',
      suffix: editsWeight ? state.weightUnit : '회',
      initialValue: editsWeight ? set.weight : set.reps.toDouble(),
      min: 0,
      max: editsWeight ? 999 : 100,
      step: editsWeight ? .5 : 1,
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
                  backgroundColor: context.setflowColors.error,
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

/// 이 종목을 지금까지 어떻게 해 왔는지.
///
/// 예전엔 이 버튼이 "히스토리를 불러왔습니다" 토스트만 띄우고 아무것도 안 했다.
/// 기록은 이미 `state.sessions`에 다 있었다 — 보여 주기만 하면 되는 일이었다.
void _showExerciseHistory(
  BuildContext context,
  AppState state,
  ExerciseTemplate template,
) {
  final entries = <(DateTime, List<WorkoutSetEntry>)>[];
  for (final entry in state.sessions.entries) {
    for (final exercise in entry.value.exercises) {
      if (exercise.template.id != template.id) continue;
      final done = exercise.sets.where((set) => set.completed).toList();
      if (done.isNotEmpty) entries.add((entry.key, done));
    }
  }
  // 최근이 위로. 날짜가 곧 순서다.
  entries.sort((a, b) => b.$1.compareTo(a.$1));

  showSetflowSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          0,
          SetflowSpacing.gutter,
          SetflowSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(template.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.xxs),
            Text(
              entries.isEmpty ? '아직 기록이 없어요' : '${entries.length}일치 기록',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            if (entries.isEmpty)
              Text(
                '이 종목의 세트를 완료하면 여기에 쌓입니다.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final (date, sets) in entries.take(20))
                Padding(
                  padding: const EdgeInsets.only(bottom: SetflowSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${date.month}월 ${date.day}일',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        // 한 줄에 그날 한 세트를 전부 — 무게가 오른 날이 눈에 띈다.
                        sets
                            .map(
                              (set) =>
                                  '${_decimalText(set.weight)}${state.weightUnit}'
                                  ' × ${set.reps}',
                            )
                            .join('   '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
    },
  );
}

/// 이 동작을 어떻게 하는지. 글자로 된 종목명만 보고는 초보자가 알 수 없다.
///
/// 사진이 아니라 글인 이유: 이 문장들의 출처인 데이터셋은 텍스트만 MIT이고 GIF는
/// Gym visual 소유라 우리가 쓸 권리가 없다. 자세히는 docs/exercise-guides.md.
void _showExerciseGuide(BuildContext context, ExerciseTemplate template) {
  final steps = exerciseGuides[template.id];
  if (steps == null) return;
  showSetflowSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.gutter,
          0,
          SetflowSpacing.gutter,
          SetflowSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(template.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: SetflowSpacing.xxs),
            Text(
              '${template.muscle} · ${steps.length}단계',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: SetflowSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 번호는 순서가 정보라서 붙인다 — 이 문장들은 따라 하는 차례다.
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(steps[i], style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

Future<double?> _showNumberDial(
  BuildContext context, {
  required String title,
  required String suffix,
  required double initialValue,
  required double min,
  required double max,
  required double step,
}) {
  return showSetflowSheet<double>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NumberDialSheet(
      title: title,
      suffix: suffix,
      initialValue: initialValue,
      min: min,
      max: max,
      step: step,
    ),
  );
}

class _NumberDialSheet extends StatefulWidget {
  const _NumberDialSheet({
    required this.title,
    required this.suffix,
    required this.initialValue,
    required this.min,
    required this.max,
    required this.step,
  });

  final String title;
  final String suffix;
  final double initialValue;
  final double min;
  final double max;
  final double step;

  @override
  State<_NumberDialSheet> createState() => _NumberDialSheetState();
}

class _NumberDialSheetState extends State<_NumberDialSheet> {
  late final TextEditingController inputController;
  late final FixedExtentScrollController dialController;
  late double selectedValue;

  int get itemCount => ((widget.max - widget.min) / widget.step).floor() + 1;

  int _indexFor(double value) =>
      ((value.clamp(widget.min, widget.max) - widget.min) / widget.step)
          .round()
          .clamp(0, itemCount - 1);

  double _valueFor(int index) => widget.min + (index * widget.step);

  @override
  void initState() {
    super.initState();
    final initialIndex = _indexFor(widget.initialValue);
    selectedValue = _valueFor(initialIndex);
    inputController = TextEditingController(text: _decimalText(selectedValue));
    dialController = FixedExtentScrollController(initialItem: initialIndex);
  }

  @override
  void dispose() {
    inputController.dispose();
    dialController.dispose();
    super.dispose();
  }

  void _syncInputToDial() {
    final value = double.tryParse(inputController.text.trim());
    if (value == null || value < widget.min || value > widget.max) return;
    final index = _indexFor(value);
    selectedValue = _valueFor(index);
    dialController.animateToItem(
      index,
      duration: SetflowMotion.standard,
      curve: SetflowMotion.emphasisCurve,
    );
  }

  void _save() {
    final typed = double.tryParse(inputController.text.trim());
    if (typed == null || typed < widget.min || typed > widget.max) {
      AppSnackbar.error(
        context,
        '${_decimalText(widget.min)}~${_decimalText(widget.max)} 범위로 입력해주세요.',
      );
      return;
    }
    Navigator.pop(context, typed);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.title} 선택',
            style: const TextStyle(
              fontSize: SetflowFontSize.headline,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Text(
            '다이얼을 돌리거나 아래에 숫자를 직접 입력하세요.',
            style: TextStyle(
              fontSize: SetflowFontSize.small,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(
            height: 188,
            child: CupertinoPicker.builder(
              scrollController: dialController,
              itemExtent: 42,
              useMagnifier: true,
              magnification: 1.12,
              onSelectedItemChanged: (index) {
                HapticFeedback.selectionClick();
                selectedValue = _valueFor(index);
                inputController.text = _decimalText(selectedValue);
              },
              childCount: itemCount,
              itemBuilder: (_, index) => Center(
                child: Text(
                  '${_decimalText(_valueFor(index))} ${widget.suffix}',
                  style: const TextStyle(
                    fontSize: SetflowFontSize.titleLarge,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          TextField(
            key: const Key('number-dial-direct-input'),
            controller: inputController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: '직접 입력',
              suffixText: widget.suffix,
              prefixIcon: const Icon(Icons.keyboard_rounded),
            ),
            onEditingComplete: _syncInputToDial,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: SetflowSpacing.md2),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm2),
              Expanded(
                child: FilledButton(onPressed: _save, child: const Text('적용')),
              ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : SetflowColors.soft,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onMinus,
            borderRadius: BorderRadius.circular(SetflowRadii.xs),
            child: const Padding(
              padding: EdgeInsets.all(6),
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
                        fontSize: SetflowFontSize.bodyLarge,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      suffix,
                      style: TextStyle(
                        fontSize: SetflowFontSize.micro,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onPlus,
            borderRadius: BorderRadius.circular(SetflowRadii.xs),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.add, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}
