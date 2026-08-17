import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'detail_screens.dart';
import 'evidence_library_screen.dart';
import 'member_goal_screen.dart';
import 'member_membership_screen.dart';
import 'member_social_detail_screens.dart';
import 'routine_editor_screen.dart';
import 'workout_screens.dart';
import 'welcome_screen.dart';

String _formatMinuteValue(double minutes) {
  final wholeMinutes = minutes.round();
  if ((minutes - wholeMinutes).abs() < .05) return '$wholeMinutes';
  return minutes.toStringAsFixed(1);
}

class MemberShell extends StatefulWidget {
  const MemberShell({super.key});

  @override
  State<MemberShell> createState() => _MemberShellState();
}

class _MemberShellState extends State<MemberShell> {
  int index = 0;
  String? _handledRoutineShareToken;

  static const destinations = [
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, '캘린더'),
    (Icons.playlist_add_outlined, Icons.playlist_add_rounded, '루틴'),
    (Icons.fitness_center_outlined, Icons.fitness_center_rounded, '전문가 루틴'),
    (Icons.group_outlined, Icons.group_rounded, '동기부여'),
    (Icons.chat_bubble_outline, Icons.chat_bubble_rounded, '코칭'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = AppScope.of(context).pendingRoutineShareToken;
    if (token == null) {
      _handledRoutineShareToken = null;
      return;
    }
    if (token == _handledRoutineShareToken) return;
    _handledRoutineShareToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && index != 1) setState(() => index = 1);
    });
  }

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
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          for (var i = 0; i < destinations.length; i++)
            NavigationDestination(
              icon: Icon(destinations[i].$1),
              selectedIcon: Icon(destinations[i].$2),
              label: destinations[i].$3,
            ),
        ],
      ),
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
  DateTime? dragSource;

  void _changeMonth(int offset) {
    setState(() => month = DateTime(month.year, month.month + offset));
  }

  void _openDashboard(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  void _openSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final days = _calendarDays(month);
    final weeks = List.generate(
      6,
      (index) => days.sublist(index * 7, index * 7 + 7),
    );
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final performance = state.featuredPerformance;
    final recommendation = state.hasTrainingGoal
        ? state.featuredRecommendation
        : null;

    return SafeArea(
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: LayoutBuilder(
                  builder: (context, headerConstraints) {
                    final compactHeader = headerConstraints.maxWidth < 360;
                    return Row(
                      children: [
                        SizedBox(
                          width: compactHeader ? 104 : null,
                          child: PopupMenuButton<int>(
                            tooltip: '월 선택',
                            onSelected: (value) => setState(
                              () => month = DateTime(month.year, value),
                            ),
                            itemBuilder: (_) => List.generate(
                              12,
                              (i) => PopupMenuItem(
                                value: i + 1,
                                child: Text('${i + 1}월'),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat('yyyy.MM').format(month),
                                      style: theme.textTheme.headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 20,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          decoration: BoxDecoration(
                            color: context.setflowColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(
                              SetflowRadii.full,
                            ),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MonthArrowButton(
                                tooltip: '이전 달',
                                icon: Icons.chevron_left_rounded,
                                onPressed: () => _changeMonth(-1),
                              ),
                              Container(
                                width: 1,
                                height: 18,
                                color: theme.colorScheme.outlineVariant,
                              ),
                              _MonthArrowButton(
                                tooltip: '다음 달',
                                icon: Icons.chevron_right_rounded,
                                onPressed: () => _changeMonth(1),
                              ),
                            ],
                          ),
                        ),
                        if (compactHeader)
                          PopupMenuButton<int>(
                            tooltip: '더 보기',
                            onSelected: (value) => value == 0
                                ? _openDashboard(context)
                                : _openSettings(context),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 0,
                                child: ListTile(
                                  leading: Icon(Icons.bar_chart_rounded),
                                  title: Text('운동 통계'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 1,
                                child: ListTile(
                                  leading: Icon(Icons.settings_outlined),
                                  title: Text('설정'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                            icon: const Icon(Icons.more_horiz_rounded),
                          )
                        else ...[
                          IconButton(
                            tooltip: '운동 통계',
                            onPressed: () => _openDashboard(context),
                            icon: const Icon(Icons.bar_chart_rounded),
                          ),
                          IconButton(
                            tooltip: '설정',
                            onPressed: () => _openSettings(context),
                            icon: const Icon(Icons.menu_rounded),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const horizontalPadding = 12.0;
                const summaryWidth = 54.0;
                final contentWidth = constraints.maxWidth.clamp(0.0, 640.0);
                final dayWidth =
                    (contentWidth - horizontalPadding * 2 - summaryWidth) / 7;
                final rowHeight = (dayWidth * 1.38).clamp(66.0, 80.0);
                return GestureDetector(
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity.abs() < 120) return;
                    _changeMonth(velocity < 0 ? 1 : -1);
                  },
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: AnimatedSwitcher(
                          duration: SetflowMotion.standard,
                          switchInCurve: SetflowMotion.standardCurve,
                          switchOutCurve: SetflowMotion.standardCurve,
                          child: Padding(
                            key: ValueKey('${month.year}-${month.month}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: horizontalPadding,
                            ),
                            child: Column(
                              children: [
                                _CalendarWeekdayHeader(
                                  summaryWidth: summaryWidth,
                                ),
                                const SizedBox(height: 6),
                                for (final week in weeks)
                                  SizedBox(
                                    height: rowHeight,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        for (final day in week)
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.all(2),
                                              child: _CalendarCell(
                                                date: day,
                                                session:
                                                    state.sessions[state
                                                        .dateOnly(day)],
                                                unit: state.weightUnit,
                                                feedbackCount: state
                                                    .memberSessionFeedbackForDate(
                                                      day,
                                                    )
                                                    .length,
                                                inMonth:
                                                    day.month == month.month,
                                                isToday: DateUtils.isSameDay(
                                                  day,
                                                  DateTime.now(),
                                                ),
                                                onTap: () =>
                                                    _handleDayTap(context, day),
                                                onWorkoutDropped: (source) =>
                                                    _handleWorkoutDrop(
                                                      context,
                                                      source,
                                                      day,
                                                    ),
                                                onDragStarted: () {
                                                  HapticFeedback.mediumImpact();
                                                  setState(
                                                    () => dragSource = day,
                                                  );
                                                },
                                                onDragEnded: () {
                                                  if (mounted) {
                                                    setState(
                                                      () => dragSource = null,
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                        SizedBox(
                                          width: summaryWidth,
                                          child: _WeeklySummary(week: week),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                _CalendarKpiSection(
                                  summary: performance,
                                  recommendation: recommendation,
                                  unit: state.weightUnit,
                                  hasGoal: state.hasTrainingGoal,
                                  onViewDashboard: () =>
                                      _openDashboard(context),
                                  onApply: () =>
                                      _handleKpiAction(context, recommendation),
                                ),
                                _MemberCoachingScheduleSection(
                                  schedules: state.coachingSchedules,
                                  memberUserId: state.businessAccess?.userId,
                                  loading: state.coachingSchedulesLoading,
                                  error: state.coachingSchedulesError,
                                  onRetry: () async {
                                    try {
                                      await state.refreshCoachingSchedules();
                                    } catch (_) {
                                      // The compact section keeps the retry state visible.
                                    }
                                  },
                                ),
                                if (dragSource != null)
                                  Container(
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: dark
                                          ? Colors.white12
                                          : SetflowColors.ink,
                                      borderRadius: BorderRadius.circular(
                                        SetflowRadii.md,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.drag_indicator_rounded,
                                          color: SetflowColors.primary,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${dragSource!.month}월 ${dragSource!.day}일 운동을 다른 날짜 위에 놓아주세요',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
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
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleDayTap(BuildContext context, DateTime day) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DailyWorkoutScreen(date: day)));
  }

  void _handleWorkoutDrop(
    BuildContext context,
    DateTime source,
    DateTime target,
  ) {
    final state = AppScope.of(context);
    final copied = state.copySession(source, target);
    if (copied == 0) {
      AppSnackbar.info(context, '대상 날짜에 같은 운동이 이미 있어요.');
      return;
    }
    HapticFeedback.selectionClick();
    AppSnackbar.success(
      context,
      '${target.month}월 ${target.day}일에 운동 $copied개를 복사했어요.',
    );
  }

  Future<void> _applyRecommendation(
    BuildContext context,
    WorkoutRecommendation recommendation,
  ) async {
    final state = AppScope.of(context);
    final hasGoals = await ensureMemberTrainingGoals(context);
    if (!hasGoals || !context.mounted) return;
    final today = state.dateOnly(DateTime.now());
    final refreshed = state.recommendationForDate(today);
    if (refreshed == null) return;
    state.applyRecommendation(today, refreshed);
    AppSnackbar.success(
      context,
      '${refreshed.template.name} 추천 세트를 오늘 운동에 적용했어요.',
    );
    _handleDayTap(context, today);
  }

  Future<void> _handleKpiAction(
    BuildContext context,
    WorkoutRecommendation? recommendation,
  ) async {
    final state = AppScope.of(context);
    if (state.featuredPerformance == null) {
      _handleDayTap(context, DateTime.now());
      return;
    }
    if (!state.hasTrainingGoal) {
      final hasGoals = await ensureMemberTrainingGoals(context);
      if (!hasGoals || !context.mounted) return;
      final refreshed = state.featuredRecommendation;
      if (refreshed != null) {
        await _applyRecommendation(context, refreshed);
      }
      return;
    }
    if (recommendation == null) {
      _handleDayTap(context, DateTime.now());
      return;
    }
    await _applyRecommendation(context, recommendation);
  }

  List<DateTime> _calendarDays(DateTime target) {
    final first = DateTime(target.year, target.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (index) => start.add(Duration(days: index)));
  }
}

class _MemberCoachingScheduleSection extends StatelessWidget {
  const _MemberCoachingScheduleSection({
    required this.schedules,
    required this.memberUserId,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<BusinessCoachingSchedule> schedules;
  final String? memberUserId;
  final bool loading;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final userId = memberUserId;
    if (userId == null) return const SizedBox.shrink();
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final upcoming = schedules
        .where(
          (schedule) =>
              schedule.memberUserId == userId && !schedule.date.isBefore(start),
        )
        .take(3)
        .toList(growable: false);
    if (upcoming.isEmpty && !loading && error == null) {
      return const SizedBox.shrink();
    }
    if (upcoming.isEmpty && loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (upcoming.isEmpty && error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          key: const Key('member-coaching-schedule-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('코칭 일정을 다시 불러오기'),
        ),
      );
    }

    return Padding(
      key: const Key('member-coaching-schedules'),
      padding: const EdgeInsets.only(top: 12),
      child: SetflowCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.event_note_rounded,
                  size: 19,
                  color: SetflowColors.blue,
                ),
                const SizedBox(width: 8),
                Text(
                  '예정된 코칭',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                const Text(
                  '읽기 전용',
                  style: TextStyle(
                    fontSize: 10,
                    color: SetflowColors.secondaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < upcoming.length; index++) ...[
              if (index > 0) const Divider(height: 16),
              _MemberScheduleRow(schedule: upcoming[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberScheduleRow extends StatelessWidget {
  const _MemberScheduleRow({required this.schedule});

  final BusinessCoachingSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final startHour = (schedule.startMinutes ~/ 60).toString().padLeft(2, '0');
    final startMinute = (schedule.startMinutes % 60).toString().padLeft(2, '0');
    return Row(
      children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: SetflowColors.blue.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
          ),
          child: Column(
            children: [
              Text(
                '${schedule.date.month}/${schedule.date.day}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$startHour:$startMinute',
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                schedule.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                schedule.trainerName ?? schedule.gymName ?? '담당 트레이너',
                style: const TextStyle(
                  fontSize: 11,
                  color: SetflowColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        Icon(
          schedule.isCompleted
              ? Icons.check_circle_rounded
              : Icons.chevron_right_rounded,
          size: 18,
          color: schedule.isCompleted
              ? SetflowColors.green
              : SetflowColors.secondaryText,
        ),
      ],
    );
  }
}

class _CalendarKpiSection extends StatelessWidget {
  const _CalendarKpiSection({
    required this.summary,
    required this.recommendation,
    required this.unit,
    required this.hasGoal,
    required this.onViewDashboard,
    required this.onApply,
  });

  final ExercisePerformanceSummary? summary;
  final WorkoutRecommendation? recommendation;
  final String unit;
  final bool hasGoal;
  final VoidCallback onViewDashboard;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final recommendation = this.recommendation;
    final change = summary?.changeFromPrevious;
    final changeIcon = change == null || change == 0
        ? Icons.trending_flat_rounded
        : change > 0
        ? Icons.trending_up_rounded
        : Icons.trending_down_rounded;
    final changeColor = change == null || change == 0
        ? SetflowColors.secondaryText
        : change > 0
        ? SetflowColors.green
        : SetflowColors.red;
    final changeValue = change == null
        ? '—'
        : '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}$unit';
    final nextValue = recommendation == null
        ? hasGoal
              ? '—'
              : '목표 설정'
        : recommendation.template.name;

    return Column(
      key: const Key('calendar-kpi-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '운동 KPI',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary == null
                          ? '기록이 쌓이면 자동으로 분석해요'
                          : '${summary.template.name} · 최근 기록 기준',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SetflowColors.secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: summary == null ? null : onViewDashboard,
                icon: const Icon(Icons.arrow_outward_rounded, size: 16),
                label: const Text('전체 보기'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 4 : 2;
            return GridView.builder(
              key: const Key('calendar-kpi-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 104,
              ),
              itemBuilder: (context, index) => switch (index) {
                0 => _CalendarKpiTile(
                  key: const Key('calendar-kpi-e1rm'),
                  label: '예상 1RM',
                  value: summary == null
                      ? '—'
                      : '${summary.currentE1rm.toStringAsFixed(1)}$unit',
                  caption: summary == null
                      ? '완료 세트 필요'
                      : '${summary.quality.label} 신뢰도 · ${summary.sessionCount}회',
                  icon: Icons.speed_rounded,
                  accent: SetflowColors.orange,
                ),
                1 => _CalendarKpiTile(
                  key: const Key('calendar-kpi-change'),
                  label: '최근 변화',
                  value: changeValue,
                  caption: change == null ? '비교 기록 필요' : '직전 운동 대비',
                  icon: changeIcon,
                  accent: changeColor,
                  valueColor: changeColor,
                ),
                2 => _CalendarKpiTile(
                  key: const Key('calendar-kpi-pr'),
                  label: '중량 PR',
                  value: summary == null
                      ? '—'
                      : '${PerformanceEngine.formatWeight(summary.weightPr.set.weight)}$unit',
                  caption: summary == null
                      ? '완료 세트 필요'
                      : '${summary.weightPr.set.reps}회 성공',
                  icon: Icons.emoji_events_outlined,
                  accent: SetflowColors.purple,
                ),
                _ => _CalendarKpiTile(
                  key: const Key('calendar-kpi-next'),
                  label: '다음 운동',
                  value: nextValue,
                  caption: recommendation == null
                      ? hasGoal
                            ? '추천 기록 필요'
                            : '맞춤 추천 받기'
                      : '${recommendation.goal.label} · '
                            '${recommendation.prescriptionSummary(unit)}',
                  icon: Icons.flag_outlined,
                  accent: SetflowColors.blue,
                ),
              },
            );
          },
        ),
        const SizedBox(height: 10),
        _KpiActionCard(
          summary: summary,
          recommendation: recommendation,
          unit: unit,
          hasGoal: hasGoal,
          onTap: onApply,
        ),
      ],
    );
  }
}

class _CalendarKpiTile extends StatelessWidget {
  const _CalendarKpiTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label $value, $caption',
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: context.setflowColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(SetflowRadii.xs),
                  ),
                  child: Icon(icon, size: 14, color: accent),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: SetflowColors.secondaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                height: 1.1,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                color: SetflowColors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiActionCard extends StatelessWidget {
  const _KpiActionCard({
    required this.summary,
    required this.recommendation,
    required this.unit,
    required this.hasGoal,
    required this.onTap,
  });

  final ExercisePerformanceSummary? summary;
  final WorkoutRecommendation? recommendation;
  final String unit;
  final bool hasGoal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final currentRecommendation = recommendation;
    final title = !hasGoal
        ? '목표 설정하기'
        : currentRecommendation != null
        ? summary == null
              ? '오늘 운동 이어가기'
              : '오늘 운동에 적용'
        : summary == null
        ? '오늘 운동 기록하기'
        : '오늘 운동 기록하기';
    final description = !hasGoal
        ? '내 목표에 맞는 운동 구성을 추천해요'
        : currentRecommendation != null
        ? '${currentRecommendation.goal.label} · '
              '${currentRecommendation.template.name} · '
              '${currentRecommendation.prescriptionSummary(unit)}'
        : summary == null
        ? '첫 기록부터 KPI를 자동으로 만들어요'
        : '운동을 완료하면 다음 구성을 추천해요';

    return SetflowCard(
      key: const Key('calendar-kpi-action'),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      color: SetflowColors.primary.withValues(alpha: .10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SetflowColors.primary.withValues(alpha: .28),
              borderRadius: BorderRadius.circular(SetflowRadii.sm),
            ),
            child: const Icon(
              Icons.track_changes_rounded,
              size: 19,
              color: SetflowColors.orange,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
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
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward_rounded, size: 19),
        ],
      ),
    );
  }
}

class _MonthArrowButton extends StatelessWidget {
  const _MonthArrowButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: EdgeInsets.zero,
      iconSize: 20,
      icon: Icon(icon),
    );
  }
}

class _CalendarWeekdayHeader extends StatelessWidget {
  const _CalendarWeekdayHeader({required this.summaryWidth});

  final double summaryWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Row(
        children: [
          for (var index = 0; index < 7; index++)
            Expanded(
              child: Center(
                child: Text(
                  ['일', '월', '화', '수', '목', '금', '토'][index],
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: index == 0
                        ? SetflowColors.red
                        : index == 6
                        ? context.setflowColors.blue
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: summaryWidth,
            child: Center(
              child: Text(
                '합계',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    required this.date,
    required this.session,
    required this.unit,
    required this.feedbackCount,
    required this.inMonth,
    required this.isToday,
    required this.onTap,
    required this.onWorkoutDropped,
    required this.onDragStarted,
    required this.onDragEnded,
  });
  final DateTime date;
  final WorkoutSession? session;
  final String unit;
  final int feedbackCount;
  final bool inMonth;
  final bool isToday;
  final VoidCallback onTap;
  final ValueChanged<DateTime> onWorkoutDropped;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completion = session?.completion ?? 0;
    final hasSession = (session?.totalSets ?? 0) > 0;
    final accent = completion >= 1
        ? context.setflowColors.teal
        : completion > 0
        ? context.setflowColors.orange
        : theme.colorScheme.onSurfaceVariant;
    final muscles =
        session?.exercises
            .map((item) => item.template.muscle.characters.first)
            .toSet()
            .take(2)
            .join() ??
        '';
    final resistanceVolumeLabel = session == null || session!.volume <= 0
        ? ''
        : session!.volume > 1000
        ? '${(session!.volume / 1000).toStringAsFixed(1)}t'
        : '${session!.volume.toStringAsFixed(0)}$unit';
    final cardioSeconds = session?.cardioDurationSeconds ?? 0;
    final cardioMinutes = _formatMinuteValue(cardioSeconds / 60);
    final activityLabel = [
      if (resistanceVolumeLabel.isNotEmpty) resistanceVolumeLabel,
      if (cardioSeconds > 0) '$cardioMinutes분',
    ].join(' · ');
    final semanticLabel = StringBuffer(
      '${date.year}년 ${date.month}월 ${date.day}일',
    );
    if (hasSession) {
      final resistanceSets = session!.exercises
          .where((exercise) => !exercise.template.isCardio)
          .fold<int>(
            0,
            (sum, exercise) =>
                sum + exercise.sets.where((set) => set.completed).length,
          );
      final cardioSegments = session!.exercises
          .where((exercise) => exercise.template.isCardio)
          .fold<int>(
            0,
            (sum, exercise) =>
                sum + exercise.sets.where((set) => set.completed).length,
          );
      if (resistanceSets > 0) semanticLabel.write(', $resistanceSets세트 완료');
      if (resistanceVolumeLabel.isNotEmpty) {
        semanticLabel.write(', 근력 볼륨 $resistanceVolumeLabel');
      }
      if (cardioSegments > 0) {
        semanticLabel.write(', 유산소 $cardioSegments구간 $cardioMinutes분 완료');
      }
    } else {
      semanticLabel.write(', 운동 기록 없음');
    }
    if (feedbackCount > 0) {
      semanticLabel.write(', 코치 피드백 $feedbackCount개');
    }

    return DragTarget<DateTime>(
      onWillAcceptWithDetails: (details) =>
          !DateUtils.isSameDay(details.data, date),
      onAcceptWithDetails: (details) => onWorkoutDropped(details.data),
      builder: (context, candidates, rejected) {
        final isDropTarget = candidates.isNotEmpty;
        final cell = Opacity(
          opacity: inMonth ? 1 : .32,
          child: Semantics(
            button: true,
            label: semanticLabel.toString(),
            hint: hasSession ? '길게 눌러 다른 날짜로 운동 복사' : null,
            excludeSemantics: true,
            child: AnimatedContainer(
              duration: SetflowMotion.micro,
              decoration: BoxDecoration(
                color: isDropTarget
                    ? theme.colorScheme.primary.withValues(alpha: .15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(SetflowRadii.sm),
                boxShadow: isDropTarget
                    ? [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: .24,
                          ),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: isDropTarget
                    ? theme.colorScheme.primaryContainer
                    : context.setflowColors.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SetflowRadii.sm),
                  side: BorderSide(
                    color: isDropTarget || isToday
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: isDropTarget ? 2 : (isToday ? 1.5 : 1),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              alignment: Alignment.center,
                              decoration: isToday
                                  ? BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                    )
                                  : null,
                              child: Text(
                                '${date.day}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: isToday
                                      ? theme.colorScheme.onPrimary
                                      : date.weekday == DateTime.sunday
                                      ? SetflowColors.red
                                      : date.weekday == DateTime.saturday
                                      ? context.setflowColors.blue
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (feedbackCount > 0)
                              Positioned(
                                right: 0,
                                child: Icon(
                                  Icons.mark_chat_unread_rounded,
                                  key: ValueKey(
                                    'calendar-feedback-${date.year}-'
                                    '${date.month}-${date.day}',
                                  ),
                                  size: 13,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),
                        if (hasSession) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(
                                SetflowRadii.xs,
                              ),
                            ),
                            child: Text(
                              muscles,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              style: TextStyle(
                                color: accent,
                                fontSize: 9,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activityLabel,
                            maxLines: 1,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 8,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else
                          const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (!hasSession) return cell;
        return LongPressDraggable<DateTime>(
          data: date,
          onDragStarted: onDragStarted,
          onDragEnd: (_) => onDragEnded(),
          feedback: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(SetflowRadii.md),
            color: theme.colorScheme.inverseSurface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fitness_center_rounded,
                    size: 18,
                    color: theme.colorScheme.onInverseSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${date.month}월 ${date.day}일 · 운동 ${session!.exercises.length}개',
                    style: TextStyle(
                      color: theme.colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .25, child: cell),
          child: cell,
        );
      },
    );
  }
}

class _WeeklySummary extends StatelessWidget {
  const _WeeklySummary({required this.week});
  final List<DateTime> week;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sessions = week
        .map((date) => state.sessions[state.dateOnly(date)])
        .whereType<WorkoutSession>();
    final sets = sessions.fold<int>(
      0,
      (sum, session) =>
          sum +
          session.exercises
              .where((exercise) => !exercise.template.isCardio)
              .fold<int>(
                0,
                (setSum, exercise) =>
                    setSum + exercise.sets.where((set) => set.completed).length,
              ),
    );
    final volume = sessions.fold<double>(0, (sum, item) => sum + item.volume);
    final cardioSeconds = sessions.fold<int>(
      0,
      (sum, session) => sum + session.cardioDurationSeconds,
    );
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 2, 2, 2),
      decoration: BoxDecoration(
        color: context.setflowColors.surfaceContainer,
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (sets > 0)
            RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                children: [
                  TextSpan(
                    text: '$sets',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const TextSpan(
                    text: ' 세트',
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          if (cardioSeconds > 0)
            Text(
              '${_formatMinuteValue(cardioSeconds / 60)}분 유산소',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (volume > 0)
            Text(
              volume > 1000
                  ? '${(volume / 1000).toStringAsFixed(1)}t'
                  : '${volume.toStringAsFixed(0)}${state.weightUnit}',
              style: TextStyle(
                fontSize: 8,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class RoutinesScreen extends StatelessWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 루틴'),
        actions: [
          IconButton(
            onPressed: () => _createRoutine(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          _IncomingRoutineSharesSection(state: state),
          if (state.pendingRoutineShareToken != null ||
              state.incomingRoutineShares.any(
                (share) => share.status == RoutineShareStatus.pending,
              ))
            const SizedBox(height: SetflowSpacing.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  '저장된 루틴 ${state.routines.length}/4',
                  style: const TextStyle(
                    color: SetflowColors.secondaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                '무료 플랜',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: SetflowColors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final routine in state.routines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SetflowCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 42,
                          decoration: BoxDecoration(
                            color: routine.color,
                            borderRadius: BorderRadius.circular(6),
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
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '${routine.exercises.length}개 운동 · ${routine.level}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SetflowColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'apply', child: Text('오늘 적용')),
                            PopupMenuItem(value: 'edit', child: Text('수정')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                '삭제',
                                style: TextStyle(color: SetflowColors.red),
                              ),
                            ),
                          ],
                          onSelected: (value) async {
                            if (value == 'apply') {
                              final added = state.applyRoutine(
                                routine,
                                DateTime.now(),
                              );
                              if (added == 0) {
                                AppSnackbar.info(
                                  context,
                                  '오늘 기록에 루틴 운동이 이미 모두 있어요.',
                                );
                              } else {
                                AppSnackbar.success(
                                  context,
                                  '오늘 캘린더에 운동 $added개를 적용했어요.',
                                );
                              }
                            } else if (value == 'edit') {
                              await _editRoutine(context, routine);
                            } else if (value == 'delete') {
                              final confirmed =
                                  await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('루틴을 삭제할까요?'),
                                      content: Text(
                                        '${routine.name} 루틴은 삭제 후 복구할 수 없습니다.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            false,
                                          ),
                                          child: const Text('취소'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            true,
                                          ),
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
                              if (confirmed && context.mounted) {
                                try {
                                  final removed = await state.removeRoutine(
                                    routine,
                                  );
                                  if (!context.mounted) return;
                                  if (removed) {
                                    AppSnackbar.success(context, '루틴을 삭제했어요.');
                                  } else {
                                    AppSnackbar.error(
                                      context,
                                      '삭제할 루틴을 찾지 못했어요.',
                                    );
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    AppSnackbar.error(
                                      context,
                                      '루틴을 서버에서 삭제하지 못했어요. 다시 시도해주세요.',
                                    );
                                  }
                                }
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      routine.description,
                      style: const TextStyle(
                        color: SetflowColors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: routine.exercises
                          .map(
                            (item) => Chip(
                              label: Text(
                                item.name,
                                style: const TextStyle(fontSize: 11),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                    AppButton(
                      label: '루틴 편집',
                      icon: Icons.edit_rounded,
                      variant: AppButtonVariant.outlined,
                      onPressed: () => _editRoutine(context, routine),
                    ),
                  ],
                ),
              ),
            ),
          if (state.routines.isEmpty)
            EmptyState(
              icon: Icons.playlist_add_rounded,
              title: '저장된 루틴이 없어요',
              message: '새 루틴을 만들거나 전문가 루틴을 저장해보세요.',
              actionLabel: '새 루틴 만들기',
              onAction: () => _createRoutine(context),
            ),
          OutlinedButton.icon(
            onPressed: state.routines.length >= 4
                ? () => AppSnackbar.info(context, '무료 플랜은 루틴을 4개까지 저장할 수 있어요.')
                : () => _createRoutine(context),
            icon: const Icon(Icons.add),
            label: const Text('새 루틴 만들기'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
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
    bool created;
    try {
      created = await state.createPersonalRoutine(
        draft.name,
        draft.description,
      );
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '루틴을 서버에 저장하지 못했어요. 다시 시도해주세요.');
      }
      return;
    }
    if (!context.mounted) return;
    if (created) {
      AppSnackbar.success(context, '새 루틴을 저장했어요.');
    } else {
      AppSnackbar.error(context, '무료 플랜 저장 한도에 도달했어요.');
    }
  }

  Future<void> _editRoutine(BuildContext context, RoutineData routine) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RoutineEditorScreen(routine: routine)),
    );
    if (updated == true && context.mounted) {
      AppSnackbar.success(context, '루틴 변경사항을 저장했어요.');
    }
  }
}

class _IncomingRoutineSharesSection extends StatelessWidget {
  const _IncomingRoutineSharesSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final pendingShares = state.incomingRoutineShares
        .where((share) => share.status == RoutineShareStatus.pending)
        .toList(growable: false);
    final pendingToken = state.pendingRoutineShareToken;
    if (pendingShares.isEmpty && pendingToken == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => _showRoutineShareCodeSheet(context),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: const Text('공유 코드 받기'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '트레이너가 보낸 루틴',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton(
              onPressed: () => _showRoutineShareCodeSheet(context),
              child: const Text('코드 입력'),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.sm),
        if (pendingToken != null)
          Padding(
            padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
            child: SetflowCard(
              color: SetflowColors.primary.withValues(alpha: .07),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.mark_email_unread_rounded,
                        color: SetflowColors.primary,
                      ),
                      SizedBox(width: SetflowSpacing.sm),
                      Expanded(
                        child: Text(
                          '공유받은 루틴이 있어요',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  const Text(
                    '링크의 루틴을 확인하고 내 루틴으로 안전하게 가져옵니다.',
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: '나중에',
                          variant: AppButtonVariant.outlined,
                          onPressed: state.clearPendingRoutineShareToken,
                        ),
                      ),
                      const SizedBox(width: SetflowSpacing.sm),
                      Expanded(
                        child: AppButton(
                          label: '루틴 받기',
                          icon: Icons.download_done_rounded,
                          onPressed: () =>
                              _acceptRoutineShareToken(context, pendingToken),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        for (final share in pendingShares)
          Padding(
            padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
            child: _IncomingRoutineShareCard(state: state, share: share),
          ),
      ],
    );
  }
}

class _IncomingRoutineShareCard extends StatelessWidget {
  const _IncomingRoutineShareCard({required this.state, required this.share});

  final AppState state;
  final RoutineShareRecord share;

  @override
  Widget build(BuildContext context) {
    final isSaving = state.isRespondingRoutineShare(share.id);
    final expiresAt = share.expiresAt;
    return SetflowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: SetflowColors.orange.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(SetflowRadii.md),
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: SetflowColors.orange,
                ),
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      share.routineTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${share.senderName} · ${share.routine?.exercises.length ?? 0}개 운동',
                      style: const TextStyle(
                        color: SetflowColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: SetflowColors.green.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '새 루틴',
                  style: TextStyle(
                    color: SetflowColors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (share.message case final String message
              when message.isNotEmpty) ...[
            const SizedBox(height: SetflowSpacing.md),
            Text(message, style: const TextStyle(height: 1.45)),
          ],
          if (expiresAt != null) ...[
            const SizedBox(height: SetflowSpacing.sm),
            Text(
              '${DateFormat('yyyy.MM.dd HH:mm').format(expiresAt.toLocal())}까지 수락 가능',
              style: const TextStyle(
                color: SetflowColors.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: SetflowSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '거절',
                  variant: AppButtonVariant.outlined,
                  onPressed: isSaving
                      ? null
                      : () => _declineRoutineShare(context, share),
                ),
              ),
              const SizedBox(width: SetflowSpacing.sm),
              Expanded(
                child: AppButton(
                  label: '수락',
                  icon: Icons.check_rounded,
                  isLoading: isSaving,
                  onPressed: isSaving
                      ? null
                      : () => _acceptRoutineShare(context, share),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoutineAcceptDecision {
  const _RoutineAcceptDecision({this.applyDate});

  final DateTime? applyDate;
}

Future<_RoutineAcceptDecision?> _askRoutineAcceptDecision(
  BuildContext context,
) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('루틴을 받을까요?'),
      content: const Text(
        '원본 운동 순서와 저항운동의 중량·횟수·휴식, '
        '유산소의 시간·거리·RPE를 그대로 저장합니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'save'),
          child: const Text('저장만'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'apply'),
          child: const Text('날짜에 적용'),
        ),
      ],
    ),
  );
  if (!context.mounted || choice == null) return null;
  if (choice == 'save') return const _RoutineAcceptDecision();
  final date = await showDatePicker(
    context: context,
    initialDate: DateTime.now(),
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
    helpText: '루틴을 적용할 날짜',
    cancelText: '취소',
    confirmText: '적용',
  );
  return date == null ? null : _RoutineAcceptDecision(applyDate: date);
}

Future<void> _acceptRoutineShare(
  BuildContext context,
  RoutineShareRecord share,
) async {
  final decision = await _askRoutineAcceptDecision(context);
  if (decision == null || !context.mounted) return;
  final state = AppScope.of(context);
  try {
    await state.respondToRoutineShare(
      share.id,
      accept: true,
      applyDate: decision.applyDate,
    );
    if (!context.mounted) return;
    AppSnackbar.success(
      context,
      decision.applyDate == null
          ? '루틴을 내 루틴에 저장했어요.'
          : '${DateFormat('M월 d일').format(decision.applyDate!)} 캘린더에 루틴을 적용했어요.',
    );
  } catch (_) {
    if (context.mounted) {
      AppSnackbar.error(context, '루틴을 받지 못했어요. 만료 여부를 확인해주세요.');
    }
  }
}

Future<void> _declineRoutineShare(
  BuildContext context,
  RoutineShareRecord share,
) async {
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('공유를 거절할까요?'),
          content: Text('${share.routineTitle} 루틴은 받은 목록에서 사라집니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('거절'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return;
  try {
    await AppScope.of(context).respondToRoutineShare(share.id, accept: false);
    if (context.mounted) AppSnackbar.info(context, '루틴 공유를 거절했어요.');
  } catch (_) {
    if (context.mounted) AppSnackbar.error(context, '요청을 처리하지 못했어요.');
  }
}

Future<void> _acceptRoutineShareToken(
  BuildContext context,
  String token,
) async {
  final decision = await _askRoutineAcceptDecision(context);
  if (decision == null || !context.mounted) return;
  try {
    await AppScope.of(
      context,
    ).acceptRoutineShareToken(token, applyDate: decision.applyDate);
    if (!context.mounted) return;
    AppSnackbar.success(
      context,
      decision.applyDate == null
          ? '공유 루틴을 내 루틴에 저장했어요.'
          : '${DateFormat('M월 d일').format(decision.applyDate!)} 캘린더에 루틴을 적용했어요.',
    );
  } catch (_) {
    if (context.mounted) {
      AppSnackbar.error(context, '공유 링크가 만료됐거나 이미 사용할 수 없어요.');
    }
  }
}

Future<void> _showRoutineShareCodeSheet(BuildContext context) async {
  final controller = TextEditingController();
  final token = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        SetflowSpacing.lg,
        SetflowSpacing.sm,
        SetflowSpacing.lg,
        MediaQuery.viewInsetsOf(sheetContext).bottom + SetflowSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '공유 루틴 받기',
            style: Theme.of(sheetContext).textTheme.headlineSmall,
          ),
          const SizedBox(height: SetflowSpacing.sm),
          const Text(
            '트레이너에게 받은 링크 또는 공유 코드를 붙여넣어 주세요.',
            style: TextStyle(color: SetflowColors.secondaryText),
          ),
          const SizedBox(height: SetflowSpacing.lg),
          TextField(
            controller: controller,
            autofocus: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '공유 링크 또는 코드',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) Navigator.pop(sheetContext, value);
            },
          ),
          const SizedBox(height: SetflowSpacing.lg),
          AppButton(
            label: '확인',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(sheetContext, value);
            },
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  if (token == null || token.trim().isEmpty || !context.mounted) return;
  await _acceptRoutineShareToken(context, token);
}

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final searchController = TextEditingController();
  String filter = '전체';
  String sort = '인기순';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
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
          routine.description.toLowerCase().contains(query) ||
          routine.exercises.any(
            (exercise) => exercise.name.toLowerCase().contains(query),
          );
      final matchesFilter =
          filter == '전체' ||
          routine.level == filter ||
          (filter == '근육 증가' &&
              routine.exercises.any((exercise) => !exercise.isCardio)) ||
          (filter == '체중 감량' &&
              routine.exercises.any((exercise) => exercise.isCardio));
      return matchesQuery && matchesFilter;
    }).toList();
    if (sort == '이름순') {
      routines.sort((a, b) => a.name.compareTo(b.name));
    } else if (sort == '최신순') {
      routines.sort((a, b) => b.id.compareTo(a.id));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('전문가 루틴'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '정렬',
            initialValue: sort,
            onSelected: (value) => setState(() => sort = value),
            itemBuilder: (_) => ['인기순', '최신순', '이름순']
                .map((item) => PopupMenuItem(value: item, child: Text(item)))
                .toList(),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          AppTextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            prefixIcon: const Icon(Icons.search),
            hint: '목표, 운동, 트레이너 검색',
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['전체', '체중 감량', '근육 증가', '초급', '중급']
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item),
                        selected: filter == item,
                        onSelected: (_) => setState(() => filter = item),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 22),
          SectionTitle(
            query.isEmpty && filter == '전체'
                ? '지금 인기 있는 루틴'
                : '검색 결과 ${routines.length}개',
          ),
          const SizedBox(height: 10),
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
              padding: const EdgeInsets.only(bottom: 13),
              child: SetflowCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExpertRoutineDetailScreen(routine: routine),
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
                              color: routine.color.withValues(alpha: .38),
                            ),
                          ),
                          Positioned(
                            left: 16,
                            top: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: routine.color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                routine.level,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 16,
                            top: 14,
                            child: _RoutineAccessBadge(
                              accessTier: routine.accessTier,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            routine.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            routine.description,
                            style: const TextStyle(
                              color: SetflowColors.secondaryText,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                color: SetflowColors.blue,
                                size: 17,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  routine.author,
                                  style: const TextStyle(
                                    fontSize: 12,
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
    );
  }
}

class _RoutineAccessBadge extends StatelessWidget {
  const _RoutineAccessBadge({required this.accessTier});

  final RoutineAccessTier accessTier;

  @override
  Widget build(BuildContext context) {
    final isPaid = accessTier == RoutineAccessTier.paid;
    final color = isPaid ? SetflowColors.purple : SetflowColors.green;
    return Semantics(
      label: '${accessTier.label} 루틴',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPaid
                  ? Icons.workspace_premium_rounded
                  : Icons.lock_open_rounded,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              accessTier.label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('동기부여'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '게시물 정렬',
            initialValue: sort,
            onSelected: (value) => setState(() => sort = value),
            itemBuilder: (_) => ['최신순', '좋아요순', '댓글순']
                .map((item) => PopupMenuItem(value: item, child: Text(item)))
                .toList(),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
        ],
      ),
      body: posts.isEmpty
          ? EmptyState(
              icon: Icons.photo_library_outlined,
              title: '아직 게시물이 없어요',
              message: '첫 운동 기록을 공유하고 서로 응원해보세요.',
              actionLabel: '첫 게시물 작성',
              onAction: _compose,
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 100),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CommunityPostDetailScreen(post: post),
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (post.imageUrl == null)
                            Center(
                              child: Icon(
                                post.icon,
                                size: 50,
                                color: post.color,
                              ),
                            )
                          else
                            Image.network(
                              post.imageUrl!,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null
                                  ? child
                                  : const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                              errorBuilder: (_, _, _) => Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 42,
                                  color: post.color,
                                ),
                              ),
                            ),
                          Positioned(
                            left: 7,
                            right: 7,
                            bottom: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: post.imageUrl == null
                                    ? Colors.transparent
                                    : Colors.black54,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                child: Text(
                                  post.metric,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: post.imageUrl == null
                                        ? null
                                        : Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (post.isMine)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(
                                Icons.person_rounded,
                                size: 15,
                                color: SetflowColors.ink,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _compose,
        backgroundColor: SetflowColors.ink,
        foregroundColor: Colors.white,
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
    return Scaffold(
      appBar: AppBar(title: const Text('코칭')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: SetflowColors.primary.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: SetflowColors.primary,
                  child: Icon(
                    Icons.support_agent_rounded,
                    color: SetflowColors.ink,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '내 기록을 전문가와 연결하세요',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '상담 답변을 확인하고 1:1 코칭까지 이어갈 수 있어요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: SetflowColors.secondaryText,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionTitle('내 상담 ${state.consultations.length}건'),
          const SizedBox(height: 10),
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
                padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                child: SetflowCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ConsultationDetailScreen(consultation: consultation),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFE8F0FF),
                            child: Icon(
                              Icons.person_rounded,
                              color: SetflowColors.blue,
                            ),
                          ),
                          const SizedBox(width: SetflowSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  consultation.trainerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  consultation.specialty,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: SetflowColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _ConsultationBadge(status: consultation.status),
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
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _newConsult(context),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('새 상담 신청'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(height: 26),
          const SectionTitle('코칭 보호 정책'),
          const SizedBox(height: 8),
          const SetflowCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: SetflowColors.green),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '운동 일지 작성 후 72시간 안에 피드백을 받지 못하면 중도 해지 요청이 활성화됩니다.',
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      height: 1.5,
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
}

class _ConsultationBadge extends StatelessWidget {
  const _ConsultationBadge({required this.status});

  final ConsultationStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConsultationStatus.waiting => ('답변 대기', SetflowColors.orange),
      ConsultationStatus.answered => ('상담 완료', SetflowColors.green),
      ConsultationStatus.coaching => ('코칭 중', SetflowColors.blue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(SetflowRadii.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final today = state.dateOnly(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final week = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    );
    final weeklySessions = week
        .map((day) => state.sessions[state.dateOnly(day)])
        .toList();
    final weeklyVolumes = weeklySessions
        .map((session) => session?.volume ?? 0)
        .toList();
    final weeklyCardioMinutes = weeklySessions
        .map((session) => (session?.cardioDurationSeconds ?? 0) / 60)
        .toList(growable: false);
    final totalVolume = weeklyVolumes.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final totalCardioMinutes = weeklyCardioMinutes.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final chartShowsResistance = totalVolume > 0;
    final chartValues = chartShowsResistance
        ? weeklyVolumes
        : weeklyCardioMinutes;
    final maxChartValue = chartValues.fold<double>(
      0,
      (best, value) => value > best ? value : best,
    );
    final totalSets = weeklySessions.fold<int>(
      0,
      (sum, session) => sum + (session?.totalSets ?? 0),
    );
    final completedSets = weeklySessions.fold<int>(
      0,
      (sum, session) => sum + (session?.completedSets ?? 0),
    );
    final workoutDays = weeklySessions
        .where((session) => (session?.completedSets ?? 0) > 0)
        .length;
    final summary = state.featuredPerformance;
    final recommendation = state.hasTrainingGoal
        ? state.featuredRecommendation
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('운동 대시보드')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Row(
            children: [
              MetricCard(
                label: '이번 주',
                value: '$workoutDays',
                suffix: '회',
                icon: Icons.calendar_today,
                tint: SetflowColors.teal,
              ),
              const SizedBox(width: 10),
              MetricCard(
                label: chartShowsResistance ? '근력 볼륨' : '유산소 시간',
                value: chartShowsResistance
                    ? totalVolume >= 1000
                          ? (totalVolume / 1000).toStringAsFixed(1)
                          : totalVolume.toStringAsFixed(0)
                    : _formatMinuteValue(totalCardioMinutes),
                suffix: chartShowsResistance
                    ? totalVolume >= 1000
                          ? 't'
                          : state.weightUnit
                    : '분',
                icon: chartShowsResistance
                    ? Icons.monitor_weight_outlined
                    : Icons.directions_run_rounded,
                tint: SetflowColors.orange,
              ),
            ],
          ),
          if (chartShowsResistance && totalCardioMinutes > 0) ...[
            const SizedBox(height: 12),
            SetflowCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.directions_run_rounded,
                    color: SetflowColors.teal,
                  ),
                  const SizedBox(width: SetflowSpacing.md),
                  Expanded(
                    child: Text(
                      '이번 주 유산소 '
                      '${_formatMinuteValue(totalCardioMinutes)}분',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const Text(
                    '시간·거리·RPE 기록',
                    style: TextStyle(
                      color: SetflowColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              MetricCard(
                label: '연속 기록',
                value: '${_currentStreak(state, today)}',
                suffix: '일',
                icon: Icons.local_fire_department,
                tint: SetflowColors.red,
              ),
              const SizedBox(width: 10),
              MetricCard(
                label: '완료율',
                value: totalSets == 0
                    ? '0'
                    : '${(completedSets / totalSets * 100).round()}',
                suffix: '%',
                icon: Icons.check_circle_outline,
                tint: SetflowColors.blue,
              ),
            ],
          ),
          const SizedBox(height: 26),
          SectionTitle(chartShowsResistance ? '주간 근력 볼륨' : '주간 유산소 시간'),
          const SizedBox(height: 10),
          SetflowCard(
            child: SizedBox(
              height: 170,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maxChartValue == 0
                                      ? .04
                                      : (chartValues[i] / maxChartValue).clamp(
                                          .04,
                                          1.0,
                                        ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: i == today.weekday - 1
                                          ? SetflowColors.primary
                                          : SetflowColors.teal.withValues(
                                              alpha: .7,
                                            ),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ['월', '화', '수', '목', '금', '토', '일'][i],
                              style: const TextStyle(
                                fontSize: 10,
                                color: SetflowColors.secondaryText,
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
          const SizedBox(height: 22),
          const SectionTitle('MY PERFORMANCE'),
          const SizedBox(height: 10),
          if (summary == null)
            const SetflowCard(
              child: Text(
                '완료한 근력 운동 세트가 쌓이면 e1RM과 PR 변화가 표시됩니다.',
                style: TextStyle(
                  height: 1.5,
                  color: SetflowColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else ...[
            SetflowCard(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFFF4CB),
                      child: Icon(
                        Icons.trending_up,
                        color: SetflowColors.orange,
                      ),
                    ),
                    title: Text(
                      summary.template.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      summary.changeFromPrevious == null
                          ? '${summary.sessionCount}회 기록 · 추정 품질 ${summary.quality.label}'
                          : '직전 대비 '
                                '${summary.changeFromPrevious! >= 0 ? '+' : ''}'
                                '${summary.changeFromPrevious!.toStringAsFixed(1)}${state.weightUnit}',
                    ),
                    trailing: Text(
                      '${summary.currentE1rm.toStringAsFixed(1)}${state.weightUnit}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Divider(),
                  _PerformancePrRow(
                    label: '중량 PR',
                    value:
                        '${PerformanceEngine.formatWeight(summary.weightPr.set.weight)}${state.weightUnit}',
                  ),
                  _PerformancePrRow(
                    label: '반복 PR',
                    value:
                        '${PerformanceEngine.formatWeight(summary.repPr.set.weight)}${state.weightUnit} × '
                        '${summary.repPr.set.reps}회',
                  ),
                  _PerformancePrRow(
                    label: 'e1RM PR',
                    value:
                        '${summary.e1rmPr.estimate.value.toStringAsFixed(1)}${state.weightUnit}',
                  ),
                ],
              ),
            ),
            if (recommendation != null) ...[
              const SizedBox(height: 22),
              const SectionTitle('NEXT SESSION'),
              const SizedBox(height: 10),
              SetflowCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.track_changes_rounded,
                      color: SetflowColors.teal,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recommendation.template.name,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            recommendation.prescriptionSummary(
                              state.weightUnit,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: SetflowColors.secondaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      recommendation.goal.label,
                      style: const TextStyle(
                        color: SetflowColors.teal,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static int _currentStreak(AppState state, DateTime today) {
    var streak = 0;
    var day = today;
    while ((state.sessions[state.dateOnly(day)]?.completedSets ?? 0) > 0) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

class _PerformancePrRow extends StatelessWidget {
  const _PerformancePrRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SetflowColors.secondaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
        children: [
          const ListTile(
            title: Text(
              '계정 & 개인화',
              style: TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
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
          const ListTile(
            title: Text(
              '운동 기록',
              style: TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
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
              state.usesLiveBusinessData ? '전문가 계정' : '데모 워크스페이스',
              style: const TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (state.usesLiveBusinessData) ...[
            ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: const Text('연결 센터 관리'),
              subtitle: Text(
                state.memberMembershipsError != null
                    ? '센터 연결 정보를 불러오지 못했어요.'
                    : state.memberMemberships.isEmpty
                    ? '연결된 센터 없음'
                    : state.memberMemberships
                          .map((item) => item.gymName ?? '연결 센터')
                          .join(', '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MemberMembershipScreen(),
                ),
              ),
            ),
            _BusinessRoleEntry(
              role: UserRole.trainer,
              icon: Icons.fitness_center,
              title: '트레이너',
              hasAccess:
                  state.businessAccess?.canUse(UserRole.trainer) ?? false,
              application: state.businessAccess?.trainerApplication,
            ),
            _BusinessRoleEntry(
              role: UserRole.gym,
              icon: Icons.apartment,
              title: '헬스장 / 센터장',
              hasAccess: state.businessAccess?.canUse(UserRole.gym) ?? false,
              application: state.businessAccess?.gymApplication,
            ),
          ] else ...[
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
          ],
          if (state.isAdmin)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('운영 관리자 화면 보기'),
              onTap: () {
                Navigator.pop(context);
                state.chooseRole(UserRole.admin);
              },
            ),
          const Divider(height: 30),
          const ListTile(
            title: Text(
              '참고자료',
              style: TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('settings-evidence-library'),
            leading: const Icon(Icons.science_outlined),
            title: const Text('관련 논문'),
            subtitle: const Text('추천 계산과 운동 구성에 참고한 근거'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EvidenceLibraryScreen()),
            ),
          ),
          const Divider(height: 30),
          ListTile(
            leading: const Icon(Icons.logout, color: SetflowColors.red),
            title: const Text(
              '로그아웃',
              style: TextStyle(color: SetflowColors.red),
            ),
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

class _BusinessRoleEntry extends StatelessWidget {
  const _BusinessRoleEntry({
    required this.role,
    required this.icon,
    required this.title,
    required this.hasAccess,
    this.application,
  });

  final UserRole role;
  final IconData icon;
  final String title;
  final bool hasAccess;
  final BusinessApplication? application;

  @override
  Widget build(BuildContext context) {
    final status = application?.status;
    final pending = status == BusinessApplicationStatus.pending;
    final rejected = status == BusinessApplicationStatus.rejected;
    final subtitle = hasAccess
        ? '승인 완료 · 운영 화면 열기'
        : pending
        ? '관리자 심사 중'
        : rejected
        ? '반려됨 · ${application?.rejectReason ?? '정보를 보완해 다시 신청해주세요.'}'
        : '등록 정보를 제출하고 관리자 승인을 요청하세요.';
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: pending
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: pending
          ? null
          : () async {
              final state = AppScope.of(context);
              if (hasAccess) {
                Navigator.pop(context);
                state.chooseRole(role);
                return;
              }
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => BusinessSetupScreen(role: role),
                ),
              );
            },
    );
  }
}
