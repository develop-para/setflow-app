import 'dart:async';
import 'dart:math' as math;

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
        // Routine loading stays in the header. Exercise selection is the
        // primary action, so a non-empty day exposes it as a labelled FAB.
        actions: [
          IconButton(
            key: const Key('daily-load-routine'),
            tooltip: '루틴 불러오기',
            onPressed: () => _openRoutinePicker(context),
            icon: const Icon(SetflowIcons.routine),
          ),
          PopupMenuButton<String>(
            tooltip: '기록 메뉴',
            // 기본 위치는 버튼 '위'에 겹쳐 떠서, 앱바에서 열면 제목을 덮은 채
            // 허공에 뜬 것처럼 보였다. 메뉴는 연 버튼 아래에 붙어야 한다.
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'delete') _deleteWorkout(context);
              if (value == 'set-defaults') _showSetDefaultsSheet(context);
            },
            // 메모와 공유는 눌러도 토스트만 뜨고 아무것도 저장·공유하지 않아서 뺐다.
            // 만들어지면 그때 다시 넣는다 — 있는 척하는 메뉴가 없는 것보다 나쁘다.
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'set-defaults',
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded),
                    SizedBox(width: SetflowSpacing.sm2),
                    Text('세트 기본값'),
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
      floatingActionButton: session.exercises.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const Key('daily-add-exercise'),
              // 기록 탭으로 호스팅되면 커뮤니티 FAB와 같은 트리에 산다 —
              // 기본 히어로 태그가 겹치면 라우트 전환 때마다 터진다.
              heroTag: 'daily-add-exercise-fab',
              tooltip: '운동 선택',
              onPressed: _openExerciseFlow,
              icon: const Icon(SetflowIcons.addExercise),
              label: const Text('운동 선택'),
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
                        label: '운동 선택',
                        icon: SetflowIcons.addExercise,
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

class _WorkoutSummaryBar extends StatefulWidget {
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
  State<_WorkoutSummaryBar> createState() => _WorkoutSummaryBarState();
}

class _WorkoutSummaryBarState extends State<_WorkoutSummaryBar> {
  /// 경과 시간을 분 단위로 갱신하는 시계. 첫 세트가 완료된 뒤에만 돌고,
  /// 다 끝나면 멈춘다 — 그때부터는 숫자가 변하지 않는다.
  Timer? _ticker;

  WorkoutSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _WorkoutSummaryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final running =
        session.startedAt != null &&
        session.totalSets > 0 &&
        session.completedSets < session.totalSets;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String? get _elapsedLabel {
    final elapsed = session.elapsedUntil(DateTime.now());
    if (elapsed == null) return null;
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    return hours > 0 ? '$hours시간 $minutes분' : '$minutes분';
  }

  @override
  Widget build(BuildContext context) {
    final isCardioOnly = !session.hasResistance && session.hasCardio;
    final volume = isCardioOnly
        ? '${(session.cardioDurationSeconds / 60).round()}분'
        : session.volume >= 1000
        ? '${(session.volume / 1000).toStringAsFixed(1)}t'
        : '${session.volume.toStringAsFixed(0)}${widget.unit}';
    final elapsedLabel = _elapsedLabel;
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
          // 첫 세트를 완료한 순간부터의 시간. 시작 전에는 자리도 없다 —
          // "0분"은 정보가 아니다.
          if (elapsedLabel != null) ...[
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Flexible(
              child: _SummaryValue(
                key: const ValueKey('workout-elapsed'),
                label: '시간',
                value: elapsedLabel,
              ),
            ),
          ],
          const SizedBox(width: SetflowSpacing.sm),
          Semantics(
            label: '다음 운동 자동 추천',
            toggled: widget.recommendationEnabled,
            child: InkWell(
              key: const Key('auto-recommend-toggle'),
              borderRadius: BorderRadius.circular(SetflowRadii.full),
              onTap: () =>
                  widget.onRecommendationChanged(!widget.recommendationEnabled),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                decoration: BoxDecoration(
                  color: widget.recommendationEnabled
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
                      color: widget.recommendationEnabled
                          ? Theme.of(context).colorScheme.onSurface
                          : SetflowColors.disabled,
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Text(
                      '추천 ${widget.recommendationEnabled ? 'ON' : 'OFF'}',
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
  const _SummaryValue({required this.label, required this.value, super.key});

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
                        // 내 루틴 카드와 같은 문법: 식별색은 가는 선이다.
                        // 여기만 10px 알약이면 같은 루틴이 화면마다 다른
                        // 옷을 입는다.
                        Container(
                          width: 4,
                          height: 36,
                          decoration: BoxDecoration(
                            color: routine.color,
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.full,
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
                        Icon(
                          Icons.add_circle_outline_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
                                    measurement: exercise.template.measurement,
                                    onToggle: _isSetLive(exercise, set)
                                        ? () => _toggleSet(state, set)
                                        : null,
                                    onTypeChanged: (type) =>
                                        state.updateSet(set, type: type),
                                    onWeightChanged: (weight) =>
                                        state.updateSet(set, weight: weight),
                                    onRepsChanged: (reps) =>
                                        state.updateSet(set, reps: reps),
                                    onDurationChanged: (seconds) =>
                                        state.updateSet(
                                          set,
                                          durationSeconds: seconds,
                                        ),
                                    onRestChanged: (seconds) => state.updateSet(
                                      set,
                                      restSeconds: seconds,
                                    ),
                                    showRir: state.useRir,
                                    onRirChanged: (reserve) => state.updateSet(
                                      set,
                                      rir: reserve,
                                      clearRir: reserve == null,
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
    final result = await showNumberDial(
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

/// "몇 회 더 할 수 있었나". 0부터 5까지와 '기록 안 함' 하나.
///
/// 다이얼이 아니라 칩인 이유: 값이 여섯 개뿐이고 세트마다 반복되는 입력이라
/// 시트를 열었다 닫는 왕복이 무게·횟수보다 비싸다. 그리고 다이얼에는 "안 적음"을
/// 고를 자리가 없다 — 취소와 구별되지 않는다.
class _RirPicker extends StatelessWidget {
  const _RirPicker({
    required this.setNumber,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int setNumber;
  final int? value;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RIR · 몇 회 더 할 수 있었나요?',
          style: TextStyle(
            fontSize: SetflowFontSize.micro,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: SetflowWeight.medium,
          ),
        ),
        const SizedBox(height: SetflowSpacing.xxs),
        Wrap(
          spacing: SetflowSpacing.xs,
          runSpacing: SetflowSpacing.xxs,
          children: [
            for (var reserve = 0; reserve <= 5; reserve++)
              ChoiceChip(
                key: ValueKey('inline-set-rir-$setNumber-$reserve'),
                label: Text('$reserve'),
                selected: value == reserve,
                visualDensity: VisualDensity.compact,
                onSelected: enabled
                    // 이미 고른 값을 다시 누르면 해제된다 — 잘못 누른 것을
                    // 되돌릴 다른 길이 없다.
                    ? (_) => onChanged(value == reserve ? null : reserve)
                    : null,
              ),
            ChoiceChip(
              key: ValueKey('inline-set-rir-$setNumber-none'),
              label: const Text('기록 안 함'),
              selected: value == null,
              visualDensity: VisualDensity.compact,
              onSelected: enabled ? (_) => onChanged(null) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// A number the user picks, never types in place.
///
/// The box *is* the button: tapping it opens [showNumberDial], where the value
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
    required this.onDurationChanged,
    required this.onRestChanged,
    required this.onDelete,
    required this.onRirChanged,
    this.measurement = ExerciseMeasurement.weightReps,
    this.showRir = false,
  });

  final WorkoutSetEntry set;
  final String unit;
  final VoidCallback? onToggle;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<int> onRestChanged;
  final VoidCallback onDelete;

  /// null이면 "기록 안 함"으로 되돌린다. 0은 값이다 — 실패 직전까지 갔다는 뜻.
  final ValueChanged<int?> onRirChanged;

  /// 설정 > 운동 기록 환경설정의 'RIR 입력 필드'. 꺼 둔 사람에게는 행이 늘어날
  /// 이유가 없으므로 아예 그리지 않는다.
  final bool showRir;

  /// 이 종목이 세트를 무엇으로 재는가 — 무게 다이얼을 그릴지 말지가 여기서
  /// 갈린다. 푸시업에 무게 박스를 주면 0을 타이핑하는 일만 남는다.
  final ExerciseMeasurement measurement;

  @override
  State<_InlineSetRow> createState() => _InlineSetRowState();
}

class _InlineSetRowState extends State<_InlineSetRow> {
  late final TextEditingController weightController;
  late final TextEditingController repsController;
  late final TextEditingController durationController;
  late final TextEditingController restController;
  bool deleteRevealed = false;

  /// A logged set folds down to one line; tapping opens it again for editing.
  bool reopened = false;

  @override
  void initState() {
    super.initState();
    weightController = TextEditingController(text: _weightText());
    repsController = TextEditingController(text: '${widget.set.reps}');
    durationController = TextEditingController(
      text: '${widget.set.durationSeconds}',
    );
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
    if (oldWidget.set.durationSeconds != widget.set.durationSeconds) {
      durationController.text = '${widget.set.durationSeconds}';
    }
    if (oldWidget.set.restSeconds != widget.set.restSeconds) {
      restController.text = '${widget.set.restSeconds}';
    }
  }

  @override
  void dispose() {
    weightController.dispose();
    repsController.dispose();
    durationController.dispose();
    restController.dispose();
    super.dispose();
  }

  /// 접힌 줄에도 남긴다 — 적어 둔 값이 접히면서 사라지면 적을 이유가 없다.
  String _rirSuffix() {
    final rir = widget.set.rir;
    if (!_showsRir || rir == null) return '';
    return ' · RIR $rir';
  }

  String _weightText() =>
      widget.set.weight.toStringAsFixed(widget.set.weight % 1 == 0 ? 0 : 1);

  /// 버티는 종목에는 "몇 회 더"가 성립하지 않는다 — 남는 것은 시간이다.
  bool get _showsRir =>
      widget.showRir && widget.measurement != ExerciseMeasurement.duration;

  /// 95초보다 "1분 35초"가 읽힌다.
  static String _holdText(int seconds) {
    if (seconds < 60) return '$seconds초';
    final remainder = seconds % 60;
    return remainder == 0
        ? '${seconds ~/ 60}분'
        : '${seconds ~/ 60}분 $remainder초';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.set.completed && !reopened) {
      return _CompletedSetLine(
        key: ValueKey('inline-set-done-${widget.set.number}'),
        number: widget.set.number,
        label: '세트',
        summary: switch (widget.measurement) {
          ExerciseMeasurement.weightReps =>
            '${_weightText()}${widget.unit} × ${widget.set.reps}회${_rirSuffix()}',
          ExerciseMeasurement.repsOnly => '${widget.set.reps}회${_rirSuffix()}',
          ExerciseMeasurement.duration => _holdText(widget.set.durationSeconds),
        },
        onExpand: () => setState(() => reopened = true),
      );
    }
    // 1RM은 무게가 있어야 성립한다 — 맨몸 세트에는 계산할 것이 없다.
    final estimate = widget.measurement == ExerciseMeasurement.weightReps
        ? AppScope.of(
            context,
          ).estimateOneRepMax(widget.set.weight, widget.set.reps)
        : null;
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
                if (widget.measurement == ExerciseMeasurement.weightReps) ...[
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
                ],
                if (widget.measurement == ExerciseMeasurement.duration)
                  Expanded(
                    child: _numberField(
                      key: ValueKey('inline-set-duration-${widget.set.number}'),
                      label: '시간',
                      suffix: '초',
                      controller: durationController,
                      onDial: () => _pickSetValue(
                        title: '버티는 시간',
                        suffix: '초',
                        initialValue: widget.set.durationSeconds <= 0
                            ? 60
                            : widget.set.durationSeconds.toDouble(),
                        min: 5,
                        max: 600,
                        step: 5,
                        controller: durationController,
                        onChanged: (value) =>
                            widget.onDurationChanged(value.round()),
                      ),
                    ),
                  )
                else
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
                        onChanged: (value) =>
                            widget.onRepsChanged(value.round()),
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
            if (_showsRir) ...[
              const SizedBox(height: SetflowSpacing.xs),
              _RirPicker(
                setNumber: widget.set.number,
                value: widget.set.rir,
                enabled: !widget.set.completed,
                onChanged: widget.onRirChanged,
              ),
            ],
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
    final result = await showNumberDial(
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
  /// screen that says the row moves. The live row **rests slightly pushed
  /// aside**, and on the strip it uncovers two chevrons pulse in sequence —
  /// the way a navigation arrow marches along a route. A nudge that returns
  /// to flat taught nothing once it stopped; a row that visibly is not in its
  /// closed position keeps saying "this slides" until the first real swipe.
  /// 기기에서는 첫 스와이프가 올 때까지 계속 돈다 — 멈춘 힌트는 힌트가
  /// 아니라는 것이 실사용 피드백이었다. 테스트에서만 두 사이클로 유한하다:
  /// 무한 repeat는 pumpAndSettle을 영원히 돌리고, 토스트 3초보다 길게 돌면
  /// settle이 '되돌리기'를 누를 새를 통째로 삼킨다.
  // dart-define이 아니라 바인딩으로 판별한다 — FLUTTER_TEST define은 flutter
  // test가 항상 넣어 주지 않는다. 테스트 바인딩은 WidgetsFlutterBinding이
  // 아니므로 이 검사면 충분하고, 웹 빌드에서도 안전하다.
  static final _isTest = WidgetsBinding.instance is! WidgetsFlutterBinding;
  static const _cycles = 2;
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200 * _cycles),
  );

  /// 0..1 위상 — 사이클 하나 안에서의 위치.
  double get _phase => (_hint.value * _cycles) % 1;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The hint is for the row whose turn it is, until the first swipe lands.
  bool get _hinting => widget.showHint && widget.enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHint());
  }

  @override
  void didUpdateWidget(covariant _SwipeableSet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The turn moves down the list as sets are logged; the new live row picks
    // the hint up if the lesson still has not landed.
    _syncHint();
  }

  void _syncHint() {
    if (!mounted) return;
    if (_hinting && !_reduceMotion) {
      if (_isTest) {
        if (!_hint.isAnimating && !_hint.isCompleted) _hint.forward(from: 0);
      } else if (!_hint.isAnimating) {
        _hint.repeat();
      }
    } else if (!_hinting) {
      _hint.stop();
    }
    // 모션을 꺼도 밀려 있는 자세와 화살표는 남는다 — 움직임이 아니라 상태가
    // 가르치게 한다.
    setState(() {});
  }

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  /// How far the resting row sits open. Breathes a few pixels with the
  /// chevron cycle, and collapses the moment a real drag takes over.
  double get _hintShift {
    if (!_hinting) return 0;
    final drag = (1 - progress * 8).clamp(0.0, 1.0);
    final breath = _reduceMotion || _hint.isCompleted
        ? 0.0
        : math.sin(_phase * 2 * math.pi) * 4;
    return (12 + breath) * drag;
  }

  /// The chevrons light up one after the other, front first — a route arrow.
  /// 홀로그램은 은은해야 한다: 행 내용 위에 뜨므로 진하면 가독을 해친다.
  double _chevronOpacity(int index) {
    if (_reduceMotion || _hint.isCompleted) return .35;
    final t = (_phase - index * .22) % 1;
    final wave = t < .5 ? t * 2 : (1 - t) * 2;
    return .10 + .45 * Curves.easeInOut.transform(wave);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logging = !towardsEnd;
    // 칩 위 전경은 칩과 짝지어진 on색이어야 한다. onSurface를 쓰면 다크에서
    // 라임 칩 위 흰색(1.18:1)이 되고, error를 그대로 쓰면 빨강 칩 위 빨강이
    // 된다 — 실제로 삭제 칩이 글자 없는 빨간 알약으로 보였다.
    final fill = logging
        ? theme.colorScheme.primary
        : context.setflowColors.error;
    final accent = logging
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onError;
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
          // 오버레이 두 개를 조건부(`if`)로 넣으면 안 된다: 드래그가 시작돼
          // 힌트가 접히는 순간 Stack 자식 개수가 바뀌고, Transform이 다른
          // 슬롯으로 밀리며 Dismissible이 통째로 재생성된다 — 제스처가 그
          // 자리에서 죽어 **스와이프 자체가 불가능**했다(실기기 버그).
          // 항상 트리에 두고 투명도로만 숨긴다.
          builder: (context, child) => Stack(
            children: [
              // 밀린 행이 드러내는 트랙 — 실제 스와이프가 여는 것과 같은 면.
              Positioned.fill(
                child: Opacity(
                  opacity: _hintShift > 0 ? 1 : 0,
                  child: ColoredBox(
                    color: theme.colorScheme.primary.withValues(alpha: .16),
                  ),
                ),
              ),
              Transform.translate(offset: Offset(_hintShift, 0), child: child),
              // 화살표는 틈 안이 아니라 행 **위에** 홀로그램처럼 떠서 진행
              // 방향으로 순차로 깜빡인다. 틈에 넣으면 12px 안에서 잘리고,
              // 위에 띄우면 틈이 얼마나 열렸는지와 무관하다.
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _hintShift > 0 ? 1 : 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: SetflowSpacing.lg),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < 2; i++)
                              Opacity(
                                opacity: _chevronOpacity(i),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 26,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
              accent: theme.colorScheme.onError,
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

    // 트랙은 **행 밑으로 모서리 반경만큼 파고드는 둥근 패널**이다.
    // 전체를 채우는 워시는 행의 둥근 모서리 옆에 각진 색 조각을 남기고,
    // 드러난 폭과 정확히 같은 패널은 행의 곡선과 패널의 곡선 사이에 흰
    // 허리가 생겨 "행 뒤의 배경"이 아니라 따로 노는 조각으로 읽혔다
    // (둘 다 실기기 보고). 반경만큼 겹치면 패널의 안쪽 둥근 모서리가 행의
    // 곡선 뒤에 숨어, 완료 쪽 힌트처럼 행 뒤에 깔린 면으로 보인다.
    return LayoutBuilder(
      builder: (context, constraints) {
        final revealed = constraints.maxWidth * progress.clamp(0.0, 1.0);
        // 겹침은 반경의 절반: 반경 전체를 겹치면 안쪽 곡선이 행 밑에 다
        // 숨어 전면 워시와 같아지고(각진 조각), 겹침이 없으면 행과 패널의
        // 곡선 사이에 흰 허리가 생긴다. 절반이면 곡선의 바깥 절반이 이음새
        // 위로 드러나 둥글게 마감되면서 흰 틈도 남지 않는다.
        final width = revealed <= 0
            ? 0.0
            : (revealed + SetflowRadii.md / 2).clamp(0.0, constraints.maxWidth);
        return Align(
          alignment: logging ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            width: width,
            height: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: fill.withValues(alpha: .10 + .40 * strength),
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Align(
              alignment: logging ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                // 패널이 칩보다 좁은 초기 프레임에서 칩은 줄어들지 않고 패널의
                // 둥근 클립 밖으로 잘려 나간다 — fit.none이 오버플로 에러 없이
                // 자연 크기를 유지하게 한다.
                child: FittedBox(
                  fit: BoxFit.none,
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
                          borderRadius: BorderRadius.circular(
                            SetflowRadii.full,
                          ),
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
            ),
          ),
        );
      },
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
            // 완료는 회색이 아니라 브랜드다. primaryContainer는 라이트에선
            // 라임 틴트, 다크에선 어두운 라임 컨테이너라 양쪽에서 "우리 색으로
            // 끝냈다"로 읽힌다.
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(SetflowRadii.md),
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
                style: TextStyle(
                  fontSize: SetflowFontSize.caption,
                  fontWeight: SetflowWeight.medium,
                  color: theme.colorScheme.onPrimaryContainer,
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
                    color: theme.colorScheme.onPrimaryContainer,
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
  String? equipment;
  final selected = <String>{};

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final query = search.trim();
    final filtered = state.exercises.where((item) {
      final matchesSearch = item.matchesCatalogQuery(query);
      // The field promises a whole-catalog search. Typing from inside a body
      // part must therefore not leave the previous part as a hidden filter.
      final matchesMuscle =
          query.isNotEmpty ||
          muscle == null ||
          muscle == '전체' ||
          item.muscle == muscle;
      final matchesEquipment =
          equipment == null || item.resolvedEquipmentKey == equipment;
      return matchesSearch && matchesMuscle && matchesEquipment;
    }).toList();
    final equipmentFacets = <String, String>{
      for (final item in state.exercises)
        item.resolvedEquipmentKey: item.resolvedEquipmentName,
    }.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final showCategories = query.isEmpty && muscle == null && equipment == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('운동 선택'),
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
              prefixIcon: const Icon(SetflowIcons.exerciseSearch),
              hint: '운동명 · 부위 · 기구 검색 (한국어/영문)',
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              key: const Key('exercise-equipment-filter'),
              padding: const EdgeInsets.symmetric(
                horizontal: SetflowSpacing.gutter,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: equipmentFacets.length + 1,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: SetflowSpacing.xs),
              itemBuilder: (context, index) {
                final facet = index == 0 ? null : equipmentFacets[index - 1];
                return ChoiceChip(
                  label: Text(facet?.value ?? '전체 기구'),
                  selected: equipment == facet?.key,
                  onSelected: (_) => setState(() => equipment = facet?.key),
                );
              },
            ),
          ),
          if (state.exerciseCatalogLoading)
            const LinearProgressIndicator(
              key: Key('exercise-catalog-loading'),
              minHeight: SetflowSpacing.xs,
            )
          else if (state.exerciseCatalogError != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SetflowSpacing.gutter,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'DB 운동을 불러오지 못해 저장된 목록을 보여드려요.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: state.refreshExerciseCatalog,
                    child: const Text('다시 불러오기'),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: SetflowSpacing.xs),
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
                    message: '검색어 또는 부위·기구 필터를 바꿔보세요.',
                    actionLabel: '검색 초기화',
                    onAction: () => setState(() {
                      searchController.clear();
                      search = '';
                      muscle = null;
                      equipment = null;
                    }),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                searchController.clear();
                                setState(() {
                                  search = '';
                                  muscle = null;
                                  equipment = null;
                                });
                              },
                              icon: const Icon(
                                Icons.grid_view_rounded,
                                size: 17,
                              ),
                              label: const Text('부위 선택'),
                            ),
                            const Spacer(),
                            Text(
                              '${filtered.length}개 운동 · 전체 ${state.exercises.length}개',
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
                                  : '${exercise.muscle} · ${exercise.resolvedEquipmentName}',
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
    final created = AppScope.of(context).createCustomExercise(
      name: draft.name,
      muscle: draft.muscle,
      measurement: draft.measurement,
    );
    if (created == null) {
      AppSnackbar.error(context, '같은 이름의 운동이 있거나 입력값을 확인해주세요.');
      return;
    }
    setState(() {
      selected.add(created.id);
      muscle = created.muscle;
      equipment = null;
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
  // 복근·유산소도 색을 갖는다 — 달력 막대가 부위 색이라 회색이면 "한 것"이 안 보인다.
  _MuscleCategory(
    '복근',
    Icons.self_improvement_rounded,
    context.setflowColors.purple,
  ),
  _MuscleCategory(
    '유산소',
    Icons.directions_run_rounded,
    context.setflowColors.info,
  ),
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
  const _CustomExerciseDraft({
    required this.name,
    required this.muscle,
    required this.measurement,
  });

  final String name;
  final String muscle;
  final ExerciseMeasurement measurement;
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
  ExerciseMeasurement measurement = ExerciseMeasurement.weightReps;

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
      _CustomExerciseDraft(
        name: nameController.text.trim(),
        muscle: muscle,
        measurement: measurement,
      ),
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
            // 유산소는 자체 구간 기록이라 측정 방식을 고를 것이 없다.
            if (muscle != '유산소') ...[
              const SizedBox(height: SetflowSpacing.md),
              Text(
                '기록 방식',
                style: TextStyle(
                  fontSize: SetflowFontSize.small,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: SetflowSpacing.sm),
              Wrap(
                spacing: SetflowSpacing.sm,
                children: [
                  for (final (label, value) in const [
                    ('무게 × 횟수', ExerciseMeasurement.weightReps),
                    ('횟수만', ExerciseMeasurement.repsOnly),
                    ('시간 버티기', ExerciseMeasurement.duration),
                  ])
                    ChoiceChip(
                      key: ValueKey('measurement-${value.name}'),
                      label: Text(label),
                      selected: measurement == value,
                      onSelected: (_) => setState(() => measurement = value),
                    ),
                ],
              ),
            ],
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
    final measurement = exercise.template.measurement;
    final usesWeight = measurement == ExerciseMeasurement.weightReps;
    final holds = measurement == ExerciseMeasurement.duration;
    final previous = usesWeight
        ? state.performanceFor(
            exercise.template,
            before: state.dateOnly(widget.date),
          )
        : null;
    // 맨몸 세트에는 1RM이 없다. 지난 기록의 최고치가 그 자리의 기준선이다.
    final bodyweightBest = usesWeight
        ? null
        : _bodyweightBest(state, exercise.template, holds: holds);
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
                        !usesWeight
                            ? (bodyweightBest == null
                                  ? '첫 기록을 시작해보세요'
                                  : '최고 기록 $bodyweightBest')
                            : previous == null
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
                        !usesWeight
                            ? (bodyweightBest == null
                                  ? (holds
                                        ? '완료한 세트부터 최고 시간을 추적해요.'
                                        : '완료한 세트부터 최고 횟수를 추적해요.')
                                  : '완료한 세트에서 계산한 지난 최고치예요.')
                            : previous == null
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
              if (usesWeight)
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
                    holds ? '시간' : '횟수',
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
                            if (usesWeight) ...[
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
                            ],
                            Expanded(
                              child: holds
                                  ? _NumberStepper(
                                      value: '${set.durationSeconds}',
                                      suffix: '초',
                                      onMinus: () => state.updateSet(
                                        set,
                                        durationSeconds:
                                            set.durationSeconds - 15,
                                      ),
                                      onPlus: () => state.updateSet(
                                        set,
                                        durationSeconds:
                                            set.durationSeconds + 15,
                                      ),
                                      onValueTap: () => _editSetValue(
                                        context,
                                        state,
                                        set,
                                        editsWeight: false,
                                        editsDuration: true,
                                      ),
                                    )
                                  : _NumberStepper(
                                      value: '${set.reps}',
                                      suffix: '회',
                                      onMinus: () => state.updateSet(
                                        set,
                                        reps: set.reps - 1,
                                      ),
                                      onPlus: () => state.updateSet(
                                        set,
                                        reps: set.reps + 1,
                                      ),
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
                              if (state.estimateOneRepMax(set.weight, set.reps)
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

  /// 이 종목의 지난 완료 세트 중 최고치 — 횟수 또는 버틴 시간.
  String? _bodyweightBest(
    AppState state,
    ExerciseTemplate template, {
    required bool holds,
  }) {
    final today = state.dateOnly(widget.date);
    var best = 0;
    for (final entry in state.sessions.entries) {
      if (!entry.key.isBefore(today)) continue;
      for (final exercise in entry.value.exercises) {
        if (exercise.template.id != template.id) continue;
        for (final set in exercise.sets) {
          if (!set.completed) continue;
          final value = holds ? set.durationSeconds : set.reps;
          if (value > best) best = value;
        }
      }
    }
    if (best <= 0) return null;
    if (!holds) return '$best회';
    final remainder = best % 60;
    if (best < 60) return '$best초';
    return remainder == 0 ? '${best ~/ 60}분' : '${best ~/ 60}분 $remainder초';
  }

  Future<void> _editSetValue(
    BuildContext context,
    AppState state,
    WorkoutSetEntry set, {
    required bool editsWeight,
    bool editsDuration = false,
  }) async {
    final result = await showNumberDial(
      context,
      title: editsDuration
          ? '버티는 시간'
          : editsWeight
          ? '무게'
          : '횟수',
      suffix: editsDuration
          ? '초'
          : editsWeight
          ? state.weightUnit
          : '회',
      initialValue: editsDuration
          ? (set.durationSeconds <= 0 ? 60 : set.durationSeconds.toDouble())
          : editsWeight
          ? set.weight
          : set.reps.toDouble(),
      min: editsDuration ? 5 : 0,
      max: editsDuration
          ? 600
          : editsWeight
          ? 999
          : 100,
      step: editsDuration
          ? 5
          : editsWeight
          ? .5
          : 1,
    );
    if (result == null || !context.mounted) return;
    if (editsDuration) {
      state.updateSet(set, durationSeconds: result.round());
    } else if (editsWeight) {
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
/// 운동을 추가할 때 만들어질 세트의 기본값.
///
/// 값은 처방보다 앞서고 이전 기록 추천보다는 뒤선다 — 직접 정한 것이
/// 프로필 유추보다 명시적이지만, 지난번에 실제로 든 무게·횟수는 그보다도
/// 정확하다. 숫자는 타이핑하지 않는다: 스텝퍼만 있다.
void _showSetDefaultsSheet(BuildContext context) {
  final state = AppScope.of(context);
  var sets = state.defaultSetCount ?? 3;
  var reps = state.defaultRepCount ?? 10;
  var rest = state.restDefaultSeconds;
  showSetflowSheet<void>(
    context,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        final theme = Theme.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            SetflowSpacing.gutter,
            0,
            SetflowSpacing.gutter,
            SetflowSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('세트 기본값', style: theme.textTheme.titleLarge),
              const SizedBox(height: SetflowSpacing.xs),
              Text(
                '운동을 추가할 때 이 값으로 세트가 만들어져요. '
                '이전 기록이 있으면 그때의 무게·횟수를 따라가요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SetflowSpacing.lg),
              _DefaultStepperRow(
                label: '세트 수',
                value: '$sets세트',
                onMinus: sets > 1 ? () => setSheetState(() => sets -= 1) : null,
                onPlus: sets < 10 ? () => setSheetState(() => sets += 1) : null,
              ),
              _DefaultStepperRow(
                label: '횟수',
                value: '$reps회',
                onMinus: reps > 1 ? () => setSheetState(() => reps -= 1) : null,
                onPlus: reps < 50 ? () => setSheetState(() => reps += 1) : null,
              ),
              _DefaultStepperRow(
                label: '휴식',
                value: '$rest초',
                onMinus: rest > 30
                    ? () => setSheetState(() => rest -= 15)
                    : null,
                onPlus: rest < 600
                    ? () => setSheetState(() => rest += 15)
                    : null,
              ),
              const SizedBox(height: SetflowSpacing.lg),
              AppButton(
                key: const ValueKey('set-defaults-apply'),
                label: '적용',
                onPressed: () {
                  state.setDefaultSetPlan(sets: sets, reps: reps);
                  state.setRestDefaultSeconds(rest);
                  Navigator.of(sheetContext).pop();
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _DefaultStepperRow extends StatelessWidget {
  const _DefaultStepperRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: SetflowWeight.medium,
              ),
            ),
          ),
          IconButton(
            tooltip: '$label 줄이기',
            onPressed: onMinus,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(
            width: 64,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: SetflowWeight.strong,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            tooltip: '$label 늘리기',
            onPressed: onPlus,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

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

/// 숫자를 고치는 유일한 길(AGENTS.md 5). 기록 화면과 함께 방이 같은 시트를
/// 쓴다 — 방이 자체 편집기를 갖는 순간 "적용이 유일한 저장 지점"이 둘이 된다.
Future<double?> showNumberDial(
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
