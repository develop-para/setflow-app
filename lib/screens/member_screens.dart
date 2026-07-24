import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/kinetic.dart';
import '../widgets/motion.dart';
import 'detail_screens.dart';
import 'member_social_detail_screens.dart';
import 'workout_screens.dart';

class MemberShell extends StatefulWidget {
  const MemberShell({super.key});

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int index = 0;

  static const destinations = [
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, '캘린더'),
    (Icons.playlist_add_outlined, Icons.playlist_add_rounded, '루틴'),
    (Icons.fitness_center_outlined, Icons.fitness_center_rounded, '전문가 루틴'),
    (Icons.group_outlined, Icons.group_rounded, '동기부여'),
    (Icons.chat_bubble_outline, Icons.chat_bubble_rounded, '코칭'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      const CalendarScreen(),
      const RoutinesScreen(),
      const MarketScreen(),
      const CommunityScreen(),
      const CoachingScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: SetflowNavBar(
        selectedIndex: index,
        onSelected: (value) => setState(() => index = value),
        items: [
          for (final d in destinations)
            SetflowNavItem(icon: d.$1, selectedIcon: d.$2, label: d.$3),
        ],
      ),
    );
  }
}

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

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? copySource;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final days = _calendarDays(month);
    final weeks = List.generate(
      6,
      (index) => days.sublist(index * 7, index * 7 + 7),
    );
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;

    return SafeArea(
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
                  InkWell(
                    borderRadius: BorderRadius.circular(SetflowRadii.sm),
                    onTap: () => _showMonthPicker(context),
                    child: Padding(
                      padding: const EdgeInsets.all(SetflowSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('${month.month}월', style: text.displayMedium),
                          const SizedBox(width: SetflowSpacing.sm),
                          Text(
                            '${month.year}',
                            style: text.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.setflowColors.disabled,
                            ),
                          ),
                          const SizedBox(width: SetflowSpacing.xs),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: context.setflowColors.disabled,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  AppIconButton(
                    icon: Icons.bar_chart_rounded,
                    tooltip: '운동 통계',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DashboardScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  AppIconButton(
                    icon: Icons.menu_rounded,
                    tooltip: '설정',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            _WeekHero(weeks: weeks),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.lg,
                SetflowSpacing.xl,
                SetflowSpacing.lg,
                SetflowSpacing.sm,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Center(
                        child: Text(
                          ['일', '월', '화', '수', '목', '금', '토'][i],
                          style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: i == 0
                                ? scheme.error.withValues(alpha: .55)
                                : i == 6
                                ? context.setflowColors.blue.withValues(
                                    alpha: .55,
                                  )
                                : context.setflowColors.disabled,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 6 week rows + 5 hairline total rows between them.
                  const hairlineHeight = 18.0;
                  final height =
                      (constraints.maxHeight -
                          5 * hairlineHeight -
                          SetflowSpacing.sm) /
                      6;
                  return GestureDetector(
                    onVerticalDragEnd: (details) {
                      // Require a deliberate fling; otherwise ordinary taps that
                      // drift a few pixels get misread as month navigation.
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity.abs() < 300) return;
                      final forward = velocity < 0;
                      setState(
                        () => month = DateTime(
                          month.year,
                          month.month + (forward ? 1 : -1),
                        ),
                      );
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: Padding(
                        key: ValueKey('${month.year}-${month.month}'),
                        padding: const EdgeInsets.fromLTRB(
                          SetflowSpacing.lg,
                          0,
                          SetflowSpacing.lg,
                          SetflowSpacing.sm,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < weeks.length; i++) ...[
                              SizedBox(
                                height: height,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final day in weeks[i])
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(
                                            SetflowSpacing.xxs,
                                          ),
                                          child: _CalendarCell(
                                            date: day,
                                            session: state
                                                .sessions[state.dateOnly(day)],
                                            inMonth: day.month == month.month,
                                            isToday: DateUtils.isSameDay(
                                              day,
                                              DateTime.now(),
                                            ),
                                            onTap: () =>
                                                _handleDayTap(context, day),
                                            onLongPress: () =>
                                                _showDayMenu(context, day),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (i < weeks.length - 1)
                                SizedBox(
                                  height: hairlineHeight,
                                  child: _WeekHairline(week: weeks[i]),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (copySource != null)
              Container(
                margin: const EdgeInsets.fromLTRB(
                  SetflowSpacing.lg,
                  0,
                  SetflowSpacing.lg,
                  SetflowSpacing.sm,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: SetflowSpacing.lg,
                  vertical: SetflowSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: scheme.inverseSurface,
                  borderRadius: BorderRadius.circular(SetflowRadii.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, color: scheme.primary, size: 18),
                    const SizedBox(width: SetflowSpacing.sm),
                    Expanded(
                      child: Text(
                        '복사할 날짜를 선택해주세요',
                        style: text.labelMedium?.copyWith(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => copySource = null),
                      child: Icon(
                        Icons.close,
                        color: scheme.onInverseSurface,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMonthPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MonthPickerSheet(initial: month),
    );
    if (selected != null) setState(() => month = selected);
  }

  void _handleDayTap(BuildContext context, DateTime day) {
    if (copySource != null) {
      AppScope.of(context).copySession(copySource!, day);
      setState(() => copySource = null);
      AppSnackbar.success(context, '${day.month}월 ${day.day}일로 운동을 복사했습니다.');
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DailyWorkoutScreen(date: day)));
  }

  Future<void> _showDayMenu(BuildContext context, DateTime day) async {
    final state = AppScope.of(context);
    final session = state.sessions[state.dateOnly(day)];
    if (session == null || session.exercises.isEmpty) return;
    final action = await showAppActionSheet<String>(
      context,
      title: '${day.month}월 ${day.day}일 운동',
      actions: const [
        SheetAction(icon: Icons.copy_rounded, label: '루틴 복사', value: 'copy'),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: '기록 삭제',
          value: 'delete',
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'copy') {
      setState(() => copySource = day);
    } else if (action == 'delete') {
      final confirmed = await _confirmDeleteDay(context, day);
      if (!confirmed || !context.mounted) return;
      state.deleteSession(day);
      AppSnackbar.success(context, '운동 기록을 삭제했어요.');
    }
  }

  Future<bool> _confirmDeleteDay(BuildContext context, DateTime day) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final scheme = Theme.of(dialogContext).colorScheme;
            return AlertDialog(
              icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: const Text('운동 기록을 삭제할까요?'),
              content: Text('${day.month}월 ${day.day}일의 운동과 세트 기록이 모두 삭제됩니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  child: const Text('삭제'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  List<DateTime> _calendarDays(DateTime target) {
    final first = DateTime(target.year, target.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (index) => start.add(Duration(days: index)));
  }
}

class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final now = DateTime.now();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SetflowSpacing.xl,
          0,
          SetflowSpacing.xl,
          SetflowSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => setState(() => year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SetflowSpacing.lg,
                  ),
                  child: Text(
                    '$year년',
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => year++),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: SetflowSpacing.md),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: SetflowSpacing.sm,
              crossAxisSpacing: SetflowSpacing.sm,
              childAspectRatio: 1.9,
              children: [
                for (var m = 1; m <= 12; m++)
                  _monthCell(context, m, text, scheme, now),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthCell(
    BuildContext context,
    int m,
    TextTheme text,
    ColorScheme scheme,
    DateTime now,
  ) {
    final isSelected = year == widget.initial.year && m == widget.initial.month;
    final isThisMonth = year == now.year && m == now.month;
    return Material(
      color: isSelected ? scheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(SetflowRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
        onTap: () => Navigator.pop(context, DateTime(year, m)),
        child: Container(
          alignment: Alignment.center,
          decoration: isThisMonth && !isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(SetflowRadii.sm),
                  border: Border.all(color: scheme.primary, width: 1.4),
                )
              : null,
          child: Text(
            '$m월',
            style: text.labelLarge?.copyWith(
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              color: isSelected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.date,
    required this.session,
    required this.inMonth,
    required this.isToday,
    required this.onTap,
    required this.onLongPress,
  });
  final DateTime date;
  final WorkoutSession? session;
  final bool inMonth;
  final bool isToday;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final completion = session?.completion ?? 0;
    final hasSession = (session?.totalSets ?? 0) > 0;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Heatmap cell: quiet date numeral plus one 8px intensity dot —
    // outlined = planned, dim volt = partial, solid volt = fully done.
    final BoxDecoration? dot = !hasSession
        ? null
        : completion >= 1
        ? BoxDecoration(shape: BoxShape.circle, color: scheme.primary)
        : completion > 0
        ? BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary.withValues(alpha: .45),
          )
        : BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.onSurfaceVariant, width: 1.4),
          );
    final Color dayColor = date.weekday == DateTime.sunday
        ? scheme.error
        : date.weekday == DateTime.saturday
        ? context.setflowColors.blue
        : scheme.onSurface;

    return Opacity(
      opacity: inMonth ? 1 : .28,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: SetflowSpacing.xs,
              horizontal: SetflowSpacing.xxs,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: DecoratedBox(
                    // Today: a thin volt ring around the numeral only.
                    decoration: isToday
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.primary,
                              width: 1.6,
                            ),
                          )
                        : const BoxDecoration(),
                    child: Center(
                      child: Text(
                        '${date.day}',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: dayColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                SizedBox(
                  width: 8,
                  height: 8,
                  child: dot == null ? null : DecoratedBox(decoration: dot),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero stat block above the grid: the week's numbers are the screen's
/// protagonist — streak pill, volt sets numeral · tonnage, 7-day sparkline.
class _WeekHero extends StatelessWidget {
  const _WeekHero({required this.weeks});

  final List<List<DateTime>> weeks;

  static const _dayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  /// Consecutive weeks (ending at [weekStart]'s week) with at least one
  /// completed set.
  static int _weekStreak(AppState state, DateTime weekStart) {
    var streak = 0;
    var start = state.dateOnly(weekStart);
    for (var i = 0; i < 52; i++) {
      var worked = false;
      for (var d = 0; d < 7; d++) {
        final session =
            state.sessions[state.dateOnly(start.add(Duration(days: d)))];
        if ((session?.completedSets ?? 0) > 0) {
          worked = true;
          break;
        }
      }
      if (!worked) break;
      streak++;
      start = start.subtract(const Duration(days: 7));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final week = weeks.firstWhere(
      (week) => week.any((day) => DateUtils.isSameDay(day, DateTime.now())),
      orElse: () => weeks.first,
    );
    final daySessions = [
      for (final day in week) state.sessions[state.dateOnly(day)],
    ];
    final sets = daySessions.fold(
      0,
      (sum, item) => sum + (item?.completedSets ?? 0),
    );
    final volume = daySessions.fold<double>(
      0,
      (sum, item) => sum + (item?.volume ?? 0),
    );
    final dayVolumes = [for (final s in daySessions) s?.volume ?? 0.0];
    final maxVolume = dayVolumes.fold<double>(0, (a, b) => a > b ? a : b);
    final streak = _weekStreak(state, week.first);
    final (volumeValue, volumeUnit) = volume > 1000
        ? ((volume / 1000).toStringAsFixed(1), 't')
        : (volume.toStringAsFixed(0), 'kg');
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final dim = context.setflowColors.disabled;

    Color barColor(WorkoutSession? session) {
      final completion = session?.completion ?? 0;
      if ((session?.totalSets ?? 0) == 0 || completion == 0) {
        return context.setflowColors.surfaceContainerHigh;
      }
      if (completion >= 1) return scheme.primary;
      return scheme.primary.withValues(alpha: .45);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.xl,
        SetflowSpacing.lg,
        SetflowSpacing.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '이번 주',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (streak > 0) ...[
                const SizedBox(width: SetflowSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SetflowSpacing.sm,
                    vertical: SetflowSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(SetflowRadii.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 13,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$streak주 연속',
                        style: text.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$sets',
                style: text.displayLarge?.copyWith(color: scheme.primary),
              ),
              const SizedBox(width: SetflowSpacing.xs),
              Text(
                '세트',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: dim,
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dim),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Text(volumeValue, style: text.displayLarge),
              const SizedBox(width: SetflowSpacing.xs),
              Text(
                volumeUnit,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: dim,
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.lg),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: maxVolume <= 0
                            ? .12
                            : (dayVolumes[i] / maxVolume).clamp(.12, 1.0),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: barColor(daySessions[i]),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xs),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: Center(
                    child: Text(
                      _dayLabels[i],
                      style: text.bodySmall?.copyWith(
                        color: dim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Hairline between calendar weeks carrying that week's totals —
/// aggregates live on the divider, not in a boxed side column.
class _WeekHairline extends StatelessWidget {
  const _WeekHairline({required this.week});

  final List<DateTime> week;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sessions = week
        .map((date) => state.sessions[state.dateOnly(date)])
        .whereType<WorkoutSession>();
    final sets = sessions.fold(0, (sum, item) => sum + item.completedSets);
    final volume = sessions.fold<double>(0, (sum, item) => sum + item.volume);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final dim = context.setflowColors.disabled;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
          const SizedBox(width: SetflowSpacing.sm),
          if (sets > 0)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$sets세트',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' · ${volume > 1000 ? '${(volume / 1000).toStringAsFixed(1)}t' : '${volume.toStringAsFixed(0)}kg'}',
                    style: text.bodySmall?.copyWith(
                      color: dim,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              '—',
              style: text.bodySmall?.copyWith(
                color: dim,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  static const _filters = ['전체', '초급', '중급', '상급'];
  int filterIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final filter = _filters[filterIndex];
    final routines = filter == '전체'
        ? state.routines
        : state.routines.where((item) => item.level == filter).toList();
    return Scaffold(
      body: SafeArea(
        child: _CenteredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      '루틴',
                      style: text.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: Icons.add_rounded,
                      tooltip: '새 루틴 만들기',
                      onTap: () => _createRoutine(context),
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
                child: SegPills(
                  items: _filters,
                  selectedIndex: filterIndex,
                  onChanged: (index) => setState(() => filterIndex = index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SetflowSpacing.xl,
                  SetflowSpacing.md,
                  SetflowSpacing.xl,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '저장된 루틴 ${state.routines.length}/4',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusChip(
                      label: '무료 플랜',
                      color: context.setflowColors.warning,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    SetflowSpacing.xl,
                    SetflowSpacing.md,
                    SetflowSpacing.xl,
                    SetflowSpacing.section,
                  ),
                  children: [
                    if (state.routines.isEmpty)
                      EmptyState(
                        icon: Icons.playlist_add_rounded,
                        title: '저장된 루틴이 없어요',
                        message: '새 루틴을 만들거나 전문가 루틴을 저장해보세요.',
                        actionLabel: '새 루틴 만들기',
                        onAction: () => _createRoutine(context),
                      )
                    else if (routines.isEmpty)
                      const EmptyState(
                        icon: Icons.filter_list_off_rounded,
                        title: '조건에 맞는 루틴이 없어요',
                        message: '다른 난이도 필터를 선택해보세요.',
                      ),
                    for (final routine in routines)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.md,
                        ),
                        child: _RoutineCard(routine: routine),
                      ),
                    _GhostCreateCard(onTap: () => _createRoutine(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createRoutine(BuildContext context) async {
    final state = AppScope.of(context);
    if (state.routines.length >= 4) {
      AppSnackbar.error(context, '무료 플랜은 루틴을 4개까지 저장할 수 있어요.');
      return;
    }
    final draft = await showModalBottomSheet<RoutineDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const RoutineCreateSheet(),
    );
    if (draft == null || !context.mounted) return;
    final created = state.createRoutine(draft.name, draft.description);
    if (created) {
      AppSnackbar.success(context, '새 루틴을 저장했어요.');
    } else {
      AppSnackbar.error(context, '무료 플랜 저장 한도에 도달했어요.');
    }
  }
}

/// Rich action card: what the routine contains and a "start now" action,
/// visible without opening anything.
class _RoutineCard extends StatelessWidget {
  const _RoutineCard({required this.routine});

  final RoutineData routine;

  /// Sets created per exercise when a routine is applied (see
  /// AppState.addExercise) and a rough per-set pace for the time estimate.
  static const _setsPerExercise = 3;
  static const _minutesPerSet = 3.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final dim = context.setflowColors.disabled;
    final exerciseCount = routine.exercises.length;
    final setCount = exerciseCount * _setsPerExercise;
    final minutes = (setCount * _minutesPerSet).round();
    final chipNames = routine.exercises.take(3).toList();
    final overflow = exerciseCount - chipNames.length;

    TextSpan metaItem(String value, String label) => TextSpan(
      children: [
        TextSpan(
          text: value,
          style: text.bodyMedium?.copyWith(
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        TextSpan(
          text: label,
          style: text.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return SetflowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  routine.name,
                  style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                routine.level,
                style: text.bodySmall?.copyWith(
                  color: dim,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: SetflowSpacing.xs),
              InkWell(
                borderRadius: BorderRadius.circular(SetflowRadii.full),
                onTap: () => _showMenu(context),
                child: Padding(
                  padding: const EdgeInsets.all(SetflowSpacing.xs),
                  child: Icon(Icons.more_horiz_rounded, size: 20, color: dim),
                ),
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.sm),
          Text.rich(
            TextSpan(
              children: [
                metaItem('$exerciseCount', ' 운동'),
                const TextSpan(text: '   '),
                metaItem('$setCount', ' 세트'),
                const TextSpan(text: '   '),
                TextSpan(
                  text: '약 ',
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                metaItem('$minutes', '분'),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Wrap(
            spacing: SetflowSpacing.xs + SetflowSpacing.xxs,
            runSpacing: SetflowSpacing.xs + SetflowSpacing.xxs,
            children: [
              for (final exercise in chipNames)
                _ExerciseChip(label: exercise.name),
              if (overflow > 0)
                _ExerciseChip(label: '+$overflow', dimmed: true),
            ],
          ),
          const SizedBox(height: SetflowSpacing.lg),
          Material(
            color: scheme.primary.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(SetflowRadii.sm),
              onTap: () => _startNow(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: SetflowSpacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Text(
                      '바로 시작',
                      style: text.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
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

  void _startNow(BuildContext context) {
    final state = AppScope.of(context);
    final today = DateTime.now();
    state.applyRoutine(routine, today);
    AppSnackbar.success(context, '오늘 캘린더에 루틴을 적용했어요.');
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DailyWorkoutScreen(date: today)));
  }

  Future<void> _showMenu(BuildContext context) async {
    final state = AppScope.of(context);
    final action = await showAppActionSheet<String>(
      context,
      title: routine.name,
      actions: const [
        SheetAction(icon: Icons.today_rounded, label: '오늘 적용', value: 'apply'),
        SheetAction(icon: Icons.edit_rounded, label: '수정', value: 'edit'),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: '삭제',
          value: 'delete',
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'apply':
        state.applyRoutine(routine, DateTime.now());
        AppSnackbar.success(context, '오늘 캘린더에 루틴을 적용했어요.');
      case 'edit':
        AppSnackbar.info(context, '루틴 편집 화면은 운동 순서 편집 단계에서 연결됩니다.');
      case 'delete':
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                final dialogScheme = Theme.of(dialogContext).colorScheme;
                return AlertDialog(
                  title: const Text('루틴을 삭제할까요?'),
                  content: Text('${routine.name} 루틴은 삭제 후 복구할 수 없습니다.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('취소'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: dialogScheme.error,
                        foregroundColor: dialogScheme.onError,
                      ),
                      child: const Text('삭제'),
                    ),
                  ],
                );
              },
            ) ??
            false;
        if (confirmed && context.mounted) {
          state.removeRoutine(routine);
          AppSnackbar.success(context, '루틴을 삭제했어요.');
        }
    }
  }
}

/// Small bordered chip for a routine's exercise contents.
class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({required this.label, this.dimmed = false});

  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.sm + SetflowSpacing.xxs,
        vertical: SetflowSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainer,
        borderRadius: BorderRadius.circular(SetflowRadii.xs),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: dimmed
              ? context.setflowColors.disabled
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Dashed-feel ghost card that creates a new routine.
class _GhostCreateCard extends StatelessWidget {
  const _GhostCreateCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = context.setflowColors.disabled;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SetflowRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(SetflowRadii.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xl),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SetflowRadii.lg),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: dim),
              const SizedBox(width: SetflowSpacing.sm),
              Text(
                '새 루틴 만들기',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: dim,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  static const _filters = ['전체', '체중 감량', '근육 증가', '초급', '중급'];

  final searchController = TextEditingController();
  String filter = '전체';
  String sort = '인기순';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> _pickSort() async {
    final selected = await showAppActionSheet<String>(
      context,
      title: '정렬',
      actions: const [
        SheetAction(
          icon: Icons.local_fire_department_outlined,
          label: '인기순',
          value: '인기순',
        ),
        SheetAction(icon: Icons.schedule_rounded, label: '최신순', value: '최신순'),
        SheetAction(
          icon: Icons.sort_by_alpha_rounded,
          label: '이름순',
          value: '이름순',
        ),
      ],
    );
    if (selected != null && mounted) setState(() => sort = selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final query = searchController.text.trim().toLowerCase();
    final routines = state.marketRoutines.where((routine) {
      final matchesQuery =
          query.isEmpty ||
          routine.name.toLowerCase().contains(query) ||
          routine.author.toLowerCase().contains(query) ||
          routine.description.toLowerCase().contains(query);
      final matchesFilter =
          filter == '전체' ||
          routine.level == filter ||
          (filter == '근육 증가' &&
              routine.exercises.any((exercise) => exercise.muscle != '유산소')) ||
          (filter == '체중 감량' &&
              routine.exercises.any((exercise) => exercise.id == 'run'));
      return matchesQuery && matchesFilter;
    }).toList();
    if (sort == '이름순') {
      routines.sort((a, b) => a.name.compareTo(b.name));
    } else if (sort == '최신순') {
      routines.sort((a, b) => b.id.compareTo(a.id));
    }
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: _CenteredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      '전문가 루틴',
                      style: text.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: Icons.swap_vert_rounded,
                      tooltip: '정렬',
                      onTap: _pickSort,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    SetflowSpacing.xl,
                    SetflowSpacing.lg,
                    SetflowSpacing.xl,
                    SetflowSpacing.section,
                  ),
                  children: [
                    AppTextField(
                      controller: searchController,
                      onChanged: (_) => setState(() {}),
                      prefixIcon: const Icon(Icons.search),
                      hint: '목표, 운동, 트레이너 검색',
                    ),
                    const SizedBox(height: SetflowSpacing.lg),
                    SegPills(
                      items: _filters,
                      selectedIndex: _filters.indexOf(filter),
                      onChanged: (index) =>
                          setState(() => filter = _filters[index]),
                    ),
                    const SizedBox(height: SetflowSpacing.xxl),
                    SectionTitle(
                      query.isEmpty && filter == '전체'
                          ? '지금 인기 있는 루틴'
                          : '검색 결과 ${routines.length}개',
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                    if (routines.isEmpty)
                      EmptyState(
                        icon: Icons.search_off_rounded,
                        title: '조건에 맞는 루틴이 없어요',
                        message: '검색어나 필터를 바꿔 다시 찾아보세요.',
                        actionLabel: '검색 초기화',
                        onAction: () => setState(() {
                          searchController.clear();
                          filter = '전체';
                        }),
                      ),
                    for (final routine in routines)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.md,
                        ),
                        child: SetflowCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ExpertRoutineDetailScreen(routine: routine),
                            ),
                          ),
                          padding: EdgeInsets.zero,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 118,
                                decoration: BoxDecoration(
                                  color: routine.color.withValues(alpha: .14),
                                ),
                                child: Stack(
                                  children: [
                                    Positioned(
                                      right: 18,
                                      bottom: 12,
                                      child: Icon(
                                        Icons.fitness_center_rounded,
                                        size: 72,
                                        color: routine.color.withValues(
                                          alpha: .38,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 16,
                                      top: 14,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: SetflowSpacing.sm,
                                          vertical: SetflowSpacing.xs,
                                        ),
                                        decoration: BoxDecoration(
                                          color: routine.color,
                                          borderRadius: BorderRadius.circular(
                                            SetflowRadii.xs,
                                          ),
                                        ),
                                        child: Text(
                                          routine.level,
                                          style: text.bodySmall?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(
                                  SetflowSpacing.lg,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      routine.name,
                                      style: text.titleLarge?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: SetflowSpacing.xs),
                                    Text(
                                      routine.description,
                                      style: text.labelMedium?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: SetflowSpacing.md),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.verified_rounded,
                                          color: context.setflowColors.blue,
                                          size: 17,
                                        ),
                                        const SizedBox(
                                          width: SetflowSpacing.xs,
                                        ),
                                        Expanded(
                                          child: Text(
                                            routine.author,
                                            style: text.labelMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String sort = '최신순';

  Future<void> _compose() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SocialPostComposerScreen()),
    );
    if (created == true && mounted) {
      AppSnackbar.success(context, '게시물을 등록했어요.');
    }
  }

  Future<void> _pickSort() async {
    final selected = await showAppActionSheet<String>(
      context,
      title: '게시물 정렬',
      actions: const [
        SheetAction(icon: Icons.schedule_rounded, label: '최신순', value: '최신순'),
        SheetAction(
          icon: Icons.favorite_outline_rounded,
          label: '좋아요순',
          value: '좋아요순',
        ),
        SheetAction(
          icon: Icons.chat_bubble_outline_rounded,
          label: '댓글순',
          value: '댓글순',
        ),
      ],
    );
    if (selected != null && mounted) setState(() => sort = selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final posts = [...state.communityPosts];
    switch (sort) {
      case '좋아요순':
        posts.sort((a, b) => b.likes.compareTo(a.likes));
      case '댓글순':
        posts.sort((a, b) => b.comments.length.compareTo(a.comments.length));
      default:
        posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.xl,
                SetflowSpacing.md,
                SetflowSpacing.xl,
                SetflowSpacing.md,
              ),
              child: Row(
                children: [
                  Text(
                    '동기부여',
                    style: text.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  AppIconButton(
                    icon: Icons.swap_vert_rounded,
                    tooltip: '게시물 정렬',
                    onTap: _pickSort,
                  ),
                ],
              ),
            ),
            Expanded(
              child: posts.isEmpty
                  ? EmptyState(
                      icon: Icons.photo_library_outlined,
                      title: '아직 게시물이 없어요',
                      message: '첫 운동 기록을 공유하고 서로 응원해보세요.',
                      actionLabel: '첫 게시물 작성',
                      onAction: _compose,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        SetflowSpacing.xxs,
                        SetflowSpacing.xs,
                        SetflowSpacing.xxs,
                        100,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 2,
                            mainAxisSpacing: 2,
                          ),
                      itemCount: posts.length,
                      itemBuilder: (_, index) {
                        final post = posts[index];
                        return Semantics(
                          button: true,
                          label: '${post.author}의 게시물, ${post.content}',
                          child: Material(
                            color: post.color.withValues(alpha: .18),
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CommunityPostDetailScreen(post: post),
                                ),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Center(
                                    child: Icon(
                                      post.icon,
                                      size: 50,
                                      color: post.color,
                                    ),
                                  ),
                                  Positioned(
                                    left: 7,
                                    right: 7,
                                    bottom: 6,
                                    child: Text(
                                      post.metric,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (post.isMine)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Icon(
                                        Icons.person_rounded,
                                        size: 15,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class CoachingScreen extends StatelessWidget {
  const CoachingScreen({super.key});

  Future<void> _newConsult(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConsultationCreateScreen()),
    );
    if (created == true && context.mounted) {
      AppSnackbar.success(context, '상담이 접수되었습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.xl,
                SetflowSpacing.md,
                SetflowSpacing.xl,
                0,
              ),
              child: Text(
                '코칭',
                style: text.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: SetflowInsets.pageList,
                children: [
                  Container(
                    padding: const EdgeInsets.all(SetflowSpacing.xl),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(SetflowRadii.xl),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: scheme.primary,
                          child: Icon(
                            Icons.support_agent_rounded,
                            color: scheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: SetflowSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '내 기록을 전문가와 연결하세요',
                                style: text.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: SetflowSpacing.xs),
                              Text(
                                '상담 답변을 확인하고 1:1 코칭까지 이어갈 수 있어요.',
                                style: text.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xxl),
                  SectionTitle('내 상담 ${state.consultations.length}건'),
                  const SizedBox(height: SetflowSpacing.md),
                  if (state.consultations.isEmpty)
                    EmptyState(
                      icon: Icons.support_agent_rounded,
                      title: '진행 중인 상담이 없어요',
                      message: '운동 목표와 고민을 전문가에게 질문해보세요.',
                      actionLabel: '새 상담 신청',
                      onAction: () => _newConsult(context),
                    )
                  else
                    for (final consultation in state.consultations)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: SetflowSpacing.md,
                        ),
                        child: SetflowCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ConsultationDetailScreen(
                                consultation: consultation,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  TintedIconBadge(
                                    icon: Icons.person_rounded,
                                    color: context.setflowColors.blue,
                                  ),
                                  const SizedBox(width: SetflowSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          consultation.trainerName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        Text(
                                          consultation.specialty,
                                          style: text.labelMedium?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _ConsultationBadge(
                                    status: consultation.status,
                                  ),
                                ],
                              ),
                              const Divider(height: 28),
                              Text(
                                consultation.question,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(height: 1.45),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: SetflowSpacing.xs),
                  AppButton(
                    variant: AppButtonVariant.outlined,
                    icon: Icons.edit_note_rounded,
                    label: '새 상담 신청',
                    onPressed: () => _newConsult(context),
                  ),
                  const SizedBox(height: SetflowSpacing.xxl),
                  const SectionTitle('코칭 보호 정책'),
                  const SizedBox(height: SetflowSpacing.sm),
                  InfoBanner(
                    message: '운동 일지 작성 후 72시간 안에 피드백을 받지 못하면 중도 해지 요청이 활성화됩니다.',
                    icon: Icons.shield_outlined,
                    color: context.setflowColors.success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsultationBadge extends StatelessWidget {
  const _ConsultationBadge({required this.status});

  final ConsultationStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConsultationStatus.waiting => ('답변 대기', context.setflowColors.orange),
      ConsultationStatus.answered => ('상담 완료', context.setflowColors.success),
      ConsultationStatus.coaching => ('코칭 중', context.setflowColors.blue),
    };
    return StatusChip(label: label, color: color);
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('운동 대시보드')),
      body: ListView(
        padding: SetflowInsets.pageListTight,
        children: Reveal.list([
          // Hero: this week's training summary as a data-viz card.
          const TrainingHeroCard(
            kicker: '이번 주 트레이닝',
            value: '12.8',
            unit: 't',
            delta: '12%',
            deltaUp: true,
            streak: '7일 연속',
            spark: [7.2, 6.5, 8.1, 7.8, 9.4, 8.9, 10.2, 9.6, 11.1, 12.8],
            weekValues: [1.8, 0, 1.5, 2.2, 0, 1.3, 0.9],
            weekLabels: ['월', '화', '수', '목', '금', '토', '일'],
            weekHighlight: 5,
            ringValue: 0.86,
            ringTop: '86%',
            ringBottom: '완료율',
          ),
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              MetricCard(
                label: '이번 달 운동',
                value: '18',
                suffix: '회',
                icon: Icons.event_available_rounded,
                tint: scheme.primary,
              ),
              const SizedBox(width: SetflowSpacing.md),
              MetricCard(
                label: '평균 세션',
                value: '58',
                suffix: '분',
                icon: Icons.timer_outlined,
                tint: context.setflowColors.teal,
              ),
            ],
          ),
          const SizedBox(height: SetflowSpacing.section),
          const KineticLabel('훈련 기록 · 최근 10주', tick: true),
          const SizedBox(height: SetflowSpacing.md),
          SetflowCard(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ContributionGrid(
                color: scheme.primary,
                emptyColor: context.setflowColors.surfaceContainerHigh,
                intensities: const [
                  [0.4, 0, 0.8, 0, 0.6, 0.3, 0],
                  [0.7, 0.5, 0, 0.9, 0, 0.4, 0.2],
                  [0, 0.6, 0.5, 0.7, 0.3, 0, 0.8],
                  [0.5, 0, 0.9, 0.4, 0.6, 0.7, 0],
                  [0.8, 0.3, 0, 0.5, 0.9, 0, 0.4],
                  [0.6, 0.7, 0.4, 0, 0.5, 0.8, 0.3],
                  [0, 0.9, 0.6, 0.7, 0, 0.4, 0.5],
                  [0.7, 0.5, 0.8, 0.3, 0.6, 0, 0.9],
                  [0.4, 0, 0.6, 0.9, 0.5, 0.7, 0],
                  [0.9, 0.6, 0.4, 0.5, 0.8, 0.3, 0.7],
                ],
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          SetflowCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BodyCompositionScreen()),
            ),
            child: Row(
              children: [
                TintedIconBadge(
                  icon: Icons.accessibility_new,
                  color: context.setflowColors.teal,
                ),
                const SizedBox(width: SetflowSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '체성분 변화',
                        style: text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '체중 70.9kg · 골격근량 32.5kg',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('주간 볼륨'),
          const SizedBox(height: SetflowSpacing.md),
          SetflowCard(
            child: SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SetflowSpacing.xs,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: [
                                    .35,
                                    .65,
                                    .2,
                                    .85,
                                    .55,
                                    .9,
                                    .45,
                                  ][i],
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: i == 5
                                          ? scheme.primary
                                          : context.setflowColors.teal
                                                .withValues(alpha: .7),
                                      borderRadius: BorderRadius.circular(
                                        SetflowRadii.xs,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: SetflowSpacing.sm),
                            Text(
                              ['월', '화', '수', '목', '금', '토', '일'][i],
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SetflowSpacing.xxl),
          const SectionTitle('1RM 성장'),
          const SizedBox(height: SetflowSpacing.md),
          SetflowCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: TintedIconBadge(
                icon: Icons.trending_up,
                color: context.setflowColors.orange,
              ),
              title: const Text(
                '바벨 벤치 프레스',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: const Text('최근 4주 +7.5kg'),
              trailing: Text(
                '72.5kg',
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: SetflowInsets.pageListTight,
        children: [
          ListTile(
            title: Text(
              '계정 & 개인화',
              style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('계정 & 프로필'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingDetailScreen(section: SettingSection.account),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('알림 설정'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingDetailScreen(
                  section: SettingSection.notifications,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('데이터 & 개인정보'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingDetailScreen(section: SettingSection.privacy),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('디스플레이'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingDetailScreen(section: SettingSection.display),
              ),
            ),
          ),
          const Divider(height: 30),
          ListTile(
            title: Text(
              '운동 기록',
              style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.scale_outlined),
            title: const Text('무게 단위'),
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'kg', label: Text('kg')),
                ButtonSegment(value: 'lb', label: Text('lb')),
              ],
              selected: {state.weightUnit},
              onSelectionChanged: (value) => state.setWeightUnit(value.first),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('기본 휴식 타이머'),
            subtitle: Text('${state.restDefaultSeconds}초'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const SettingDetailScreen(section: SettingSection.workout),
              ),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('다크 모드'),
            value: state.isDarkMode,
            onChanged: (_) => state.toggleTheme(),
          ),
          const Divider(height: 30),
          ListTile(
            title: Text(
              '데모 워크스페이스',
              style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('트레이너 화면 보기'),
            onTap: () {
              Navigator.pop(context);
              state.chooseRole(UserRole.trainer);
            },
          ),
          ListTile(
            leading: const Icon(Icons.apartment),
            title: const Text('헬스장 화면 보기'),
            onTap: () {
              Navigator.pop(context);
              state.chooseRole(UserRole.gym);
            },
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text('운영 관리자 화면 보기'),
            onTap: () {
              Navigator.pop(context);
              state.chooseRole(UserRole.admin);
            },
          ),
          const Divider(height: 30),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('로그아웃', style: TextStyle(color: scheme.error)),
            onTap: () {
              Navigator.pop(context);
              state.logout();
            },
          ),
        ],
      ),
    );
  }
}
