import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Constrains a pilot screen to a comfortable reading width on wide
/// viewports while staying edge-to-edge on phones.
class _CenteredContent extends StatelessWidget {
  const _CenteredContent({required this.child});

  static const _wideBreakpoint = 600.0;
  static const _contentMaxWidth = 560.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= _wideBreakpoint) return child;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

void _toggleSet(BuildContext context, AppState state, WorkoutSetEntry set) {
  HapticFeedback.lightImpact();
  state.toggleSet(set);
  if (set.completed) {
    AppSnackbar.success(context, '${set.number}세트를 저장했어요.');
  }
}

/// Opens the athletic completion summary sheet fired by the sticky "운동
/// 완료" CTA — shows the day's totals, then confirms with a snackbar.
Future<void> _showCompletionSheet(
  BuildContext context,
  WorkoutSession session,
  String weightUnit,
) {
  final volumeValue = session.volume > 1000
      ? (session.volume / 1000).toStringAsFixed(1)
      : session.volume.toStringAsFixed(0);
  final volumeUnit = session.volume > 1000 ? 't' : weightUnit;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final text = theme.textTheme;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            SetflowSpacing.xl,
            SetflowSpacing.sm,
            SetflowSpacing.xl,
            SetflowSpacing.xl + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: theme.colorScheme.primary,
                size: 32,
              ),
              const SizedBox(height: SetflowSpacing.md),
              Text(
                '오늘 운동을 완료했어요',
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: SetflowSpacing.xs),
              Text(
                '${session.completedSets}세트 · $volumeValue$volumeUnit 을 기록했어요.',
                style: text.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SetflowSpacing.xxl),
              PrimaryButton(
                label: '확인',
                onPressed: () {
                  Navigator.pop(sheetContext);
                  AppSnackbar.success(context, '오늘 운동 기록을 저장했어요.');
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class DailyWorkoutScreen extends StatelessWidget {
  const DailyWorkoutScreen({required this.date, super.key});
  final DateTime date;

  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = state.sessionFor(date);
    final theme = Theme.of(context);
    final text = theme.textTheme;

    // Mockup subtitle reads "가슴 · 1시간 12분" (muscle groups · duration).
    // We don't track elapsed workout time anywhere in AppState, so showing a
    // duration would mean fabricating data — the subtitle only carries the
    // muscle groups actually touched today, and hides entirely on a blank day.
    final muscleGroups = <String>{
      for (final exercise in session.exercises) exercise.template.muscle,
    };
    final subtitle = muscleGroups.isEmpty ? null : muscleGroups.join(' · ');

    return Scaffold(
      body: SafeArea(
        child: _CenteredContent(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SetflowSpacing.xl,
                  SetflowSpacing.md,
                  SetflowSpacing.xl,
                  0,
                ),
                child: Row(
                  children: [
                    AppIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '뒤로',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: SetflowSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${date.month}월 ${date.day}일 ${_weekdayLabels[date.weekday - 1]}요일',
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: text.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.note_alt_outlined,
                      tooltip: '메모',
                      onTap: () => showMessage(context, '운동 메모를 저장할 수 있습니다.'),
                    ),
                    const SizedBox(width: SetflowSpacing.sm),
                    AppIconButton(
                      icon: Icons.ios_share_outlined,
                      tooltip: '공유',
                      onTap: () =>
                          showMessage(context, '오늘 기록 공유 링크를 준비했습니다.'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SetflowSpacing.xl,
                  SetflowSpacing.lg,
                  SetflowSpacing.xl,
                  0,
                ),
                child: _DayStatsPanel(
                  session: session,
                  weightUnit: state.weightUnit,
                ),
              ),
              if (state.persistenceError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    SetflowSpacing.xl,
                    SetflowSpacing.md,
                    SetflowSpacing.xl,
                    0,
                  ),
                  child: _PersistenceNotice(
                    onRetry: () {
                      state.retryPersistence();
                      AppSnackbar.info(context, '운동 기록 저장을 다시 시도했어요.');
                    },
                  ),
                ),
              Expanded(
                child: session.exercises.isEmpty
                    ? EmptyState(
                        icon: Icons.fitness_center_rounded,
                        title: '오늘은 어떤 운동을 할까요?',
                        message: '운동을 추가하면 세트와 볼륨을 바로 기록할 수 있어요.',
                        actionLabel: '운동 추가',
                        onAction: () => _openLibrary(context),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          SetflowSpacing.lg,
                          SetflowSpacing.md,
                          SetflowSpacing.lg,
                          SetflowSpacing.section,
                        ),
                        itemCount: session.exercises.length,
                        // The auto-generated desktop handle floats at the
                        // card's vertical center; use an explicit grip in
                        // the card header instead.
                        buildDefaultDragHandles: false,
                        proxyDecorator: (child, index, animation) =>
                            AnimatedBuilder(
                              animation: animation,
                              builder: (context, _) => Transform.scale(
                                scale: 1 + animation.value * .02,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      SetflowRadii.lg,
                                    ),
                                    boxShadow: SetflowShadows.level3,
                                  ),
                                  child: child,
                                ),
                              ),
                            ),
                        onReorderItem: (oldIndex, newIndex) =>
                            state.reorderExercise(session, oldIndex, newIndex),
                        itemBuilder: (_, index) {
                          final exercise = session.exercises[index];
                          return Padding(
                            key: ValueKey(exercise.id),
                            padding: const EdgeInsets.only(
                              bottom: SetflowSpacing.md,
                            ),
                            child: _ExerciseCard(
                              date: date,
                              exercise: exercise,
                              reorderIndex: index,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      // Adding an exercise stays a persistent FAB (the header already carries
      // 메모/공유; a 3rd icon there felt crowded) — the sticky CTA below is a
      // distinct action ("finish today's workout"), not "add more".
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openLibrary(context),
        tooltip: '운동 추가',
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      bottomNavigationBar: session.exercises.isEmpty
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(
                SetflowSpacing.xl,
                0,
                SetflowSpacing.xl,
                SetflowSpacing.md,
              ),
              child: PrimaryButton(
                label: '운동 완료',
                onPressed: () =>
                    _showCompletionSheet(context, session, state.weightUnit),
              ),
            ),
    );
  }

  void _openLibrary(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExerciseLibraryScreen(date: date)),
    );
  }
}

/// Single stat panel replacing the old two-MetricCard row: 총 볼륨 | 완료 세트
/// as huge tabular numerals over a thin volt progress bar + caption.
class _DayStatsPanel extends StatelessWidget {
  const _DayStatsPanel({required this.session, required this.weightUnit});

  final WorkoutSession session;
  final String weightUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final volumeValue = session.volume > 1000
        ? (session.volume / 1000).toStringAsFixed(1)
        : session.volume.toStringAsFixed(0);
    final volumeUnit = session.volume > 1000 ? 't' : weightUnit;
    final caption = session.totalSets == 0
        ? '오늘은 아직 등록한 세트가 없어요'
        : session.completedSets == session.totalSets
        ? '오늘 계획한 세트를 모두 완료했어요'
        : '${session.totalSets - session.completedSets}세트 남았어요';

    return SetflowCard(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.xl,
        SetflowSpacing.lg,
        SetflowSpacing.xl,
        SetflowSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _DayStat(
                    label: '총 볼륨',
                    value: volumeValue,
                    unit: volumeUnit,
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(
                    horizontal: SetflowSpacing.lg,
                  ),
                  color: theme.colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _DayStat(
                    label: '완료 세트',
                    value: '${session.completedSets}',
                    unit: '/ ${session.totalSets}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(SetflowRadii.full),
            child: LinearProgressIndicator(
              value: session.completion,
              minHeight: 4,
              color: theme.colorScheme.primary,
              backgroundColor: context.setflowColors.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Text(
            caption,
            style: text.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayStat extends StatelessWidget {
  const _DayStat({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: SetflowSpacing.xs),
        Text.rich(
          TextSpan(
            style: text.displayMedium?.copyWith(fontWeight: FontWeight.w900),
            children: [
              TextSpan(text: value),
              TextSpan(
                text: ' $unit',
                style: text.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quiet neutral pill for an exercise's muscle group (mockup `.chip`).
class _MuscleChip extends StatelessWidget {
  const _MuscleChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.sm,
        vertical: SetflowSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(SetflowRadii.full),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.date,
    required this.exercise,
    this.reorderIndex,
  });
  final DateTime date;
  final WorkoutExercise exercise;

  /// Index inside the reorderable exercise list; shows the drag grip when set.
  final int? reorderIndex;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final nextIndex = exercise.sets.indexWhere((set) => !set.completed);

    return SetflowCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SetflowRadii.lg),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ExerciseSetScreen(date: date, exercise: exercise),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.lg,
                SetflowSpacing.md,
                SetflowSpacing.sm,
                SetflowSpacing.md,
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      exercise.template.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  _MuscleChip(exercise.template.muscle),
                  const Spacer(),
                  IconButton(
                    tooltip: '운동 메뉴',
                    onPressed: () => _openExerciseMenu(context, state),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: context.setflowColors.disabled,
                    ),
                  ),
                  if (reorderIndex != null)
                    ReorderableDragStartListener(
                      index: reorderIndex!,
                      child: Tooltip(
                        message: '길게 눌러 순서 변경',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: const EdgeInsets.all(SetflowSpacing.sm),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 22,
                              color: context.setflowColors.disabled,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < exercise.sets.length; i++) ...[
            const Divider(height: 1),
            _SetRow(
              number: '${exercise.sets[i].number}',
              weight: exercise.sets[i].weight,
              weightUnit: state.weightUnit,
              reps: exercise.sets[i].reps,
              isDone: exercise.sets[i].completed,
              isNext: i == nextIndex,
              restSeconds: exercise.sets[i].completed
                  ? state.restDefaultSeconds
                  : null,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) => _SetEditorSheet(
                  exercise: exercise,
                  set: exercise.sets[i],
                ),
              ),
              onToggle: () => _toggleSet(context, state, exercise.sets[i]),
            ),
          ],
          const Divider(height: 1),
          InkWell(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(SetflowRadii.lg),
            ),
            onTap: () {
              HapticFeedback.selectionClick();
              state.addSet(exercise);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.md),
              child: Center(
                child: Text(
                  '＋ 세트 추가',
                  style: text.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExerciseMenu(BuildContext context, AppState state) async {
    final action = await showAppActionSheet<String>(
      context,
      title: exercise.template.name,
      actions: const [
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: '운동 삭제',
          value: 'delete',
          destructive: true,
        ),
      ],
    );
    if (action == 'delete' && context.mounted) {
      await _confirmDeleteExercise(context, state);
    }
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
            content: Text('${exercise.template.name}의 세트 기록이 모두 삭제됩니다.'),
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
    final session = state.sessionFor(date);
    state.removeExercise(session, exercise);
    AppSnackbar.success(context, '운동을 삭제했어요.');
  }
}

/// One thumb-sized set row (mockup pattern 3): number circle, bold
/// weight×reps, a rest caption once done, and a trailing check control.
/// The next actionable (first incomplete) row gets a surface-2 highlight.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.number,
    required this.weight,
    required this.weightUnit,
    required this.reps,
    required this.isDone,
    required this.isNext,
    required this.onTap,
    required this.onToggle,
    this.restSeconds,
  });

  final String number;
  final double weight;
  final String weightUnit;
  final int reps;
  final bool isDone;
  final bool isNext;
  final int? restSeconds;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final weightLabel = weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1);
    return ColoredBox(
      color: isNext
          ? context.setflowColors.surfaceContainer
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SetflowSpacing.lg,
            vertical: SetflowSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? theme.colorScheme.primary.withValues(alpha: .14)
                      : context.setflowColors.surfaceContainerHigh,
                ),
                child: Text(
                  number,
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isDone
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Text.rich(
                TextSpan(
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                  children: [
                    TextSpan(text: weightLabel),
                    TextSpan(
                      text: weightUnit,
                      style: text.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SetflowSpacing.sm,
                ),
                child: Text(
                  '×',
                  style: text.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text.rich(
                TextSpan(
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                  children: [
                    TextSpan(text: '$reps'),
                    TextSpan(
                      text: '회',
                      style: text.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (isDone && restSeconds != null) ...[
                Text(
                  '휴식 $restSeconds초',
                  style: text.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: SetflowSpacing.md),
              ],
              _SetCheck(done: isDone, onTap: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trailing 26px check control: teal fill + dark check when done, a
/// 1.6px outline ring while pending.
class _SetCheck extends StatelessWidget {
  const _SetCheck({required this.done, required this.onTap});

  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(SetflowRadii.xs),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? context.setflowColors.teal : Colors.transparent,
            borderRadius: BorderRadius.circular(SetflowRadii.xs),
            border: done
                ? null
                : Border.all(color: theme.colorScheme.outlineVariant, width: 1.6),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.black)
              : null,
        ),
      ),
    );
  }
}

/// Bottom sheet set editor — steppers + set-type pills + a destructive
/// delete row. Replaces the old inline steppers; every mutation still goes
/// through [AppState.updateSet]/[AppState.removeSet], so it rebuilds live
/// via the ambient [AppScope] the same way the rest of the app does.
class _SetEditorSheet extends StatelessWidget {
  const _SetEditorSheet({required this.exercise, required this.set});

  final WorkoutExercise exercise;
  final WorkoutSetEntry set;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SetflowSpacing.xl,
          0,
          SetflowSpacing.xl,
          SetflowSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${exercise.template.name} · ${set.number}번째 세트',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: SetflowSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: _NumberStepper(
                    value: set.weight.toStringAsFixed(
                      set.weight % 1 == 0 ? 0 : 1,
                    ),
                    suffix: state.weightUnit,
                    onMinus: () => state.updateSet(set, weight: set.weight - 2.5),
                    onPlus: () => state.updateSet(set, weight: set.weight + 2.5),
                    onValueTap: () => _editValue(context, state, editsWeight: true),
                  ),
                ),
                const SizedBox(width: SetflowSpacing.sm),
                Expanded(
                  child: _NumberStepper(
                    value: '${set.reps}',
                    suffix: '회',
                    onMinus: () => state.updateSet(set, reps: set.reps - 1),
                    onPlus: () => state.updateSet(set, reps: set.reps + 1),
                    onValueTap: () =>
                        _editValue(context, state, editsWeight: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.lg),
            Text(
              '세트 타입',
              style: text.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: SetflowSpacing.sm),
            Wrap(
              spacing: SetflowSpacing.sm,
              runSpacing: SetflowSpacing.sm,
              children: [
                for (final type in ['일반', '웜업', '드랍', '실패'])
                  ChoiceChip(
                    label: Text(type),
                    selected: set.type == type,
                    onSelected: (_) => state.updateSet(set, type: type),
                  ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _delete(context, state),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                ),
                label: Text(
                  '세트 삭제',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editValue(
    BuildContext context,
    AppState state, {
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

  Future<void> _delete(BuildContext context, AppState state) async {
    final confirmed =
        await showDialog<bool>(
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
    if (!confirmed || !context.mounted) return;
    state.removeSet(exercise, set);
    AppSnackbar.success(context, '세트를 삭제했어요.');
    Navigator.pop(context);
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
    final theme = Theme.of(context);
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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
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
              padding: const EdgeInsets.symmetric(
                horizontal: SetflowSpacing.xl,
              ),
              children: ['전체', '가슴', '등', '어깨', '하체', '팔', '복근', '유산소']
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(right: SetflowSpacing.sm),
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
                    padding: const EdgeInsets.fromLTRB(
                      SetflowSpacing.lg,
                      0,
                      SetflowSpacing.lg,
                      100,
                    ),
                    itemCount: filtered.length + 1,
                    itemBuilder: (_, index) {
                      if (index == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.all(SetflowSpacing.sm),
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                showMessage(context, '커스텀 운동 입력 폼을 준비했습니다.'),
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
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: SetflowSpacing.sm,
                          vertical: SetflowSpacing.xs,
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              context.setflowColors.surfaceContainer,
                          child: Icon(
                            exercise.icon,
                            color: theme.colorScheme.onSurfaceVariant,
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
                                : context.setflowColors.disabled,
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
              foregroundColor: theme.colorScheme.onPrimary,
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
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final exercise = widget.exercise;
    final best = exercise.sets.fold<double>(
      0,
      (value, set) => set.weight > value ? set.weight : value,
    );
    final nextIndex = exercise.sets.indexWhere((set) => !set.completed);
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
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.lg,
          SetflowSpacing.xs,
          SetflowSpacing.lg,
          100,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(SetflowSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(SetflowRadii.lg),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '이전 최고 기록',
                        style: text.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        '${best.toStringAsFixed(0)} ${state.weightUnit} × 10회',
                        style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '+5.0kg',
                  style: text.labelLarge?.copyWith(
                    color: context.setflowColors.success,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          SetflowCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < exercise.sets.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _SetRow(
                    number: '${exercise.sets[i].number}',
                    weight: exercise.sets[i].weight,
                    weightUnit: state.weightUnit,
                    reps: exercise.sets[i].reps,
                    isDone: exercise.sets[i].completed,
                    isNext: i == nextIndex,
                    restSeconds: exercise.sets[i].completed
                        ? state.restDefaultSeconds
                        : null,
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => _SetEditorSheet(
                        exercise: exercise,
                        set: exercise.sets[i],
                      ),
                    ),
                    onToggle: () =>
                        _toggleSet(context, state, exercise.sets[i]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => state.addSet(exercise),
            icon: const Icon(Icons.add),
            label: const Text('세트 추가'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SetflowRadii.md),
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xl),
          const InfoBanner(
            message: '완료 체크 한 번으로 기록 저장, 볼륨 계산, 휴식 타이머가 동시에 시작됩니다.',
            icon: Icons.info_outline,
            color: SetflowColors.blue,
          ),
        ],
      ),
    );
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
    final theme = Theme.of(context);
    final text = theme.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xs),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainer,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onMinus,
            borderRadius: BorderRadius.circular(SetflowRadii.xs),
            child: const Padding(
              padding: EdgeInsets.all(SetflowSpacing.xs),
              child: Icon(Icons.remove, size: 15),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onValueTap,
              borderRadius: BorderRadius.circular(SetflowRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SetflowSpacing.xxs,
                ),
                child: Column(
                  children: [
                    Text(
                      value,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      suffix,
                      style: text.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
              padding: EdgeInsets.all(SetflowSpacing.xs),
              child: Icon(Icons.add, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}
