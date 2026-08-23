import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../korean_holidays.dart';
import '../data/business_repository.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/auth_gate.dart';
import '../widgets/bottom_bar.dart';
import '../widgets/portal.dart';
import 'detail_screens.dart';
import 'evidence_library_screen.dart';
import 'member_membership_screen.dart';
import 'member_mypage_screen.dart';
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
  /// Index into the page list, where 2 is the center destination.
  int index = 0;
  bool _recordSheetOpen = false;
  String? _handledRoutineShareToken;

  /// Page index the center disc owns.
  static const _recordPage = 2;

  /// 홈. The only page that carries the 일반인/트레이너 switch.
  static const _homePage = 0;

  /// Bar slots left of the center action, then right of it.
  static const destinations = [
    SetflowNavItem(
      icon: SetflowIcons.home,
      selectedIcon: SetflowIcons.homeActive,
      label: '홈',
    ),
    SetflowNavItem(
      icon: SetflowIcons.stats,
      selectedIcon: SetflowIcons.statsActive,
      label: '통계',
    ),
    SetflowNavItem(
      icon: SetflowIcons.community,
      selectedIcon: SetflowIcons.communityActive,
      label: '커뮤니티',
    ),
    SetflowNavItem(
      icon: SetflowIcons.my,
      selectedIcon: SetflowIcons.myActive,
      label: '마이',
    ),
  ];

  /// Bar slot -> page. Slots 0/1 sit before the center page, 2/3 after it.
  static const _slotToPage = [0, 1, 3, 4];

  int? get _selectedSlot {
    final slot = _slotToPage.indexOf(index);
    return slot == -1 ? null : slot;
  }

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
      // 루틴 no longer owns a tab, so surface the record page instead.
      if (mounted && index != _recordPage) {
        setState(() => index = _recordPage);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pages = [
      const CalendarScreen(),
      const DashboardScreen(),
      DailyWorkoutScreen(date: today),
      const CommunityScreen(),
      const MyPageScreen(),
    ];

    return PopScope(
      // Back closes the sheet before it ever reaches "leave the app".
      canPop: !_recordSheetOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeRecordSheet();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                PortalHeaderBar(switcher: index == _homePage),
                // The header already ate the status-bar inset, so the per-page
                // SafeArea below must not add it a second time.
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: MediaQuery.removeViewInsets(
                      context: context,
                      removeBottom: true,
                      child: IndexedStack(index: index, children: pages),
                    ),
                  ),
                ),
              ],
            ),
            // The sheet lives inside the shell body rather than in a modal
            // route, so the bar below it — and its close button — stay live.
            // A showModalBottomSheet barrier would swallow every disc tap.
            if (_recordSheetOpen) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeRecordSheet,
                  child: const ColoredBox(color: Color(0x59000000)),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _RecordActionSheet(
                  onSelected: (action) {
                    _closeRecordSheet();
                    _runRecordAction(action, today);
                  },
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: SetflowActionNavBar(
          items: destinations,
          selectedIndex: _selectedSlot,
          onSelected: (slot) {
            _closeRecordSheet();
            setState(() => index = _slotToPage[slot]);
          },
          centerLabel: '기록',
          centerIcon: _recordSheetOpen
              ? SetflowIcons.close
              : SetflowIcons.record,
          centerSelected: index == _recordPage,
          onCenterTap: _handleCenterTap,
        ),
      ),
    );
  }

  /// The OKX Trade contract: the first tap opens the core surface, a second tap
  /// while already there opens its action sheet, and a third closes it.
  void _handleCenterTap() {
    if (_recordSheetOpen) {
      _closeRecordSheet();
      return;
    }
    setState(() {
      if (index != _recordPage) {
        index = _recordPage;
      } else {
        _recordSheetOpen = true;
      }
    });
  }

  void _closeRecordSheet() {
    if (!_recordSheetOpen) return;
    setState(() => _recordSheetOpen = false);
  }

  void _runRecordAction(_RecordAction action, DateTime today) {
    switch (action) {
      case _RecordAction.routines:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const RoutinesScreen()));
      case _RecordAction.market:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MarketScreen()));
      case _RecordAction.library:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ExerciseLibraryScreen(date: today)),
        );
      case _RecordAction.pastDays:
        setState(() => index = 0);
    }
  }
}

enum _RecordAction { routines, market, library, pastDays }

/// The center disc's action sheet — the ways to fill today's log, the way OKX
/// puts its trade modes behind the Trade button.
class _RecordActionSheet extends StatelessWidget {
  const _RecordActionSheet({required this.onSelected});

  final ValueChanged<_RecordAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: SetflowMotion.standard,
      curve: SetflowMotion.standardCurve,
      builder: (context, value, child) =>
          FractionalTranslation(translation: Offset(0, value), child: child),
      child: Material(
        color: theme.scaffoldBackgroundColor,
        // Flat on purpose: a monochrome sheet separates with a hairline, and a
        // drop shadow here would smear onto the bar's transparent riser.
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: SetflowSpacing.md),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                SetflowSpacing.xxl,
                0,
                SetflowSpacing.xxl,
                SetflowSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '무엇으로 기록할까요?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            _RecordActionTile(
              actionKey: 'record-action-routines',
              icon: SetflowIcons.routine,
              title: '내 루틴',
              subtitle: '저장한 루틴을 불러와 오늘에 적용',
              onTap: () => onSelected(_RecordAction.routines),
            ),
            _RecordActionTile(
              actionKey: 'record-action-market',
              icon: SetflowIcons.market,
              title: '전문가 루틴',
              subtitle: '트레이너가 만든 루틴 둘러보기',
              onTap: () => onSelected(_RecordAction.market),
            ),
            _RecordActionTile(
              actionKey: 'record-action-library',
              icon: SetflowIcons.exerciseSearch,
              title: '운동 찾기',
              subtitle: '운동을 직접 골라 오늘에 추가',
              onTap: () => onSelected(_RecordAction.library),
            ),
            _RecordActionTile(
              actionKey: 'record-action-past',
              icon: SetflowIcons.pastDays,
              title: '지난 날짜 기록',
              subtitle: '캘린더에서 다른 날짜 열기',
              onTap: () => onSelected(_RecordAction.pastDays),
            ),
            const SizedBox(height: SetflowSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _RecordActionTile extends StatelessWidget {
  const _RecordActionTile({
    required this.actionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String actionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey(actionKey),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SetflowSpacing.xxl,
      ),
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
      onTap: onTap,
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

  /// 월간이 기본이다. 접으면 [anchor]가 든 한 주만 남는다.
  bool expanded = true;

  /// 접었을 때 남는 주를 정하는 날짜. 달을 바꿀 때마다 같이 옮겨서
  /// **항상 현재 격자 안에 있다** — 그래야 접는 순간 보여줄 주가 확실하다.
  DateTime anchor = DateUtils.dateOnly(DateTime.now());

  /// 펼쳤을 땐 한 달, 접었을 땐 한 주씩 넘어간다. 보이는 만큼 움직여야
  /// 화살표와 스와이프가 같은 뜻으로 읽힌다.
  void _step(int offset) {
    setState(() {
      if (expanded) {
        _goToMonth(DateTime(month.year, month.month + offset));
      } else {
        anchor = DateTime(anchor.year, anchor.month, anchor.day + 7 * offset);
        month = DateTime(anchor.year, anchor.month);
      }
    });
  }

  void _goToMonth(DateTime target) {
    month = DateTime(target.year, target.month);
    final today = DateUtils.dateOnly(DateTime.now());
    anchor = today.year == month.year && today.month == month.month
        ? today
        : DateTime(month.year, month.month, 1);
  }

  void _toggleExpanded() {
    setState(() => expanded = !expanded);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final days = _calendarDays(month);
    final weeks = List.generate(
      6,
      (index) => days.sublist(index * 7, index * 7 + 7),
    );
    // 접었을 때 남는 한 주. anchor는 항상 이 격자 안에 있지만,
    // 못 찾으면 첫 주로 떨어뜨려서 화면이 통째로 비는 일은 없게 한다.
    final foldedWeek = weeks.firstWhere(
      (week) => week.any((day) => DateUtils.isSameDay(day, anchor)),
      orElse: () => weeks.first,
    );
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

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
                        // 제목이 남는 폭을 다 먹고 필요하면 스스로 줄어든다 —
                        // 고정 폭 + Spacer 조합은 버튼이 하나만 늘어도 넘친다.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: compactHeader ? 104 : null,
                              child: PopupMenuButton<int>(
                                tooltip: '월 선택',
                                onSelected: (value) => setState(
                                  () => _goToMonth(DateTime(month.year, value)),
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
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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
                                tooltip: expanded ? '이전 달' : '이전 주',
                                icon: Icons.chevron_left_rounded,
                                onPressed: () => _step(-1),
                              ),
                              Container(
                                width: 1,
                                height: 18,
                                color: theme.colorScheme.outlineVariant,
                              ),
                              _MonthArrowButton(
                                tooltip: expanded ? '다음 달' : '다음 주',
                                icon: Icons.chevron_right_rounded,
                                onPressed: () => _step(1),
                              ),
                            ],
                          ),
                        ),
                        // 통계와 설정은 여기 없다. 통계는 바텀바의 "통계" 탭이고
                        // 설정은 "마이"에 있다 — 여기서 push하면 셸 위에 바텀바 없는
                        // 사본이 하나 더 열려서 돌아갈 길이 사라진다.
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
                    _step(velocity < 0 ? 1 : -1);
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
                                  _CollapsibleWeek(
                                    visible:
                                        expanded || identical(week, foldedWeek),
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
                                _CalendarFoldHandle(
                                  key: const Key('calendar-fold-handle'),
                                  expanded: expanded,
                                  onPressed: _toggleExpanded,
                                ),
                                const SizedBox(height: 12),
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

  List<DateTime> _calendarDays(DateTime target) {
    final first = DateTime(target.year, target.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));
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

/// 한 주 행. 접히면 높이가 0으로 줄면서 사라진다.
///
/// 높이를 직접 0으로 주면 안의 셀들이 찌그러지며 오버플로가 난다 —
/// 그래서 자식은 늘 제 높이를 갖고, 잘라내는 건 [Align.heightFactor] 쪽이다.
class _CollapsibleWeek extends StatelessWidget {
  const _CollapsibleWeek({
    required this.visible,
    required this.height,
    required this.child,
  });

  final bool visible;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: visible ? 1 : 0, end: visible ? 1 : 0),
      duration: SetflowMotion.standard,
      curve: SetflowMotion.standardCurve,
      builder: (context, factor, child) {
        if (factor <= 0) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: factor,
            // 접히는 중인 주는 눈에만 남는다 — 탭이나 드롭을 받으면 안 된다.
            child: IgnorePointer(
              ignoring: !visible,
              child: Opacity(opacity: factor, child: child),
            ),
          ),
        );
      },
      child: SizedBox(height: height, child: child),
    );
  }
}

/// 월간 ↔ 주간을 바꾸는 손잡이. 화살표가 가리키는 쪽이 결과다.
class _CalendarFoldHandle extends StatelessWidget {
  const _CalendarFoldHandle({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = expanded ? '이번 주만 보기' : '한 달 전체 보기';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(SetflowRadii.full),
              child: Container(
                width: 76,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.setflowColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(SetflowRadii.full),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Icon(
                  expanded ? SetflowIcons.collapse : SetflowIcons.expand,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
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
                  ['월', '화', '수', '목', '금', '토', '일'][index],
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    // 달력은 한국 사람이 평생 봐 온 규칙이 있다 — 일요일과 공휴일은
                    // 빨강, 토요일은 파랑. 농도로 대신하면 그냥 흐린 글자일 뿐이다.
                    color: switch (index) {
                      6 => context.setflowColors.error,
                      5 => context.setflowColors.blue,
                      _ => theme.colorScheme.onSurface,
                    },
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
                // 빈 날은 비워 둔다. 42칸을 전부 같은 회색 상자로 칠하면 달이
                // 한 덩어리로 보여서, 운동한 날이 어디였는지가 사라진다.
                color: isDropTarget
                    ? theme.colorScheme.primaryContainer
                    : hasSession
                    ? context.setflowColors.surfaceContainerLow
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SetflowRadii.sm),
                  side: BorderSide(
                    color: isDropTarget
                        ? theme.colorScheme.primary
                        : hasSession
                        ? theme.colorScheme.outlineVariant
                        : Colors.transparent,
                    width: isDropTarget ? 2 : 1,
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
                                      : isRestDay(date)
                                      ? context.setflowColors.error
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
                          // 부위와 볼륨은 글자로만. 예전엔 완료율에 따라 teal/orange
                          // 틴트를 깔았는데, 바로 위 오늘 표시가 라임이라 한 칸에
                          // 색이 셋이었고 어느 것도 의미로 읽히지 않았다.
                          Text(
                            muscles,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 9,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            activityLabel,
                            maxLines: 1,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 8,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          // 한 칸에서 색을 쓰는 곳은 여기 하나다. 다 끝낸 날은
                          // 성공색으로 꽉 차고, 하다 만 날은 브랜드가 그만큼만 찬다.
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: completion.clamp(0, 1).toDouble(),
                              minHeight: 3,
                              backgroundColor: theme.colorScheme.outlineVariant,
                              valueColor: AlwaysStoppedAnimation(
                                completion >= 1
                                    ? context.setflowColors.success
                                    : theme.colorScheme.primary,
                              ),
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
          // 전문가 루틴 lost its own tab to the center action; same domain, so
          // it lives here rather than in a menu nobody opens.
          IconButton(
            key: const ValueKey('routines-open-market'),
            tooltip: '전문가 루틴',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MarketScreen())),
            icon: const Icon(SetflowIcons.market),
          ),
          IconButton(
            tooltip: '루틴 만들기',
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
    final draft = await showSetflowSheet<RoutineDraft>(
      context,
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
  Future<void>? sheetCompleted;
  final token = await showSetflowSheet<String>(
    context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      sheetCompleted ??= ModalRoute.of(sheetContext)?.completed;
      return Padding(
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
      );
    },
  );
  await sheetCompleted;
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
    // Posts leave this device and carry an author, so this is where the account
    // is asked for — not at launch.
    if (!await requireSignIn(context, reason: AuthReason.community)) return;
    if (!mounted) return;
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
        key: const ValueKey('community-compose'),
        onPressed: _compose,
        backgroundColor: SetflowColors.ink,
        foregroundColor: Colors.white,
        child: const Icon(SetflowIcons.addExercise),
      ),
    );
  }
}

class CoachingScreen extends StatelessWidget {
  const CoachingScreen({super.key});

  Future<void> _newConsult(BuildContext context) async {
    if (!await requireSignIn(context, reason: AuthReason.coaching)) return;
    if (!context.mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConsultationCreateScreen()),
    );
    if (created == true && context.mounted) {
      AppSnackbar.success(context, '상담이 접수되었습니다.');
    }
  }

  Future<void> _refresh(BuildContext context) async {
    final state = AppScope.of(context);
    try {
      if (state.usesLiveBusinessData) {
        await state.refreshMemberConsultations();
      } else {
        await state.refreshBusinessDashboard(state.role);
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, '상담 내역을 불러오지 못했어요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final activeConsultations = _activeMemberConsultations(state);
    final unknownStatusCount = state.usesLiveBusinessData
        ? state.memberConsultations
              .where(
                (item) => item.status == BusinessConsultationStatus.unknown,
              )
              .length
        : 0;
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
                Icon(Icons.support_agent_rounded, color: SetflowColors.ink),
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
          const SizedBox(height: SetflowSpacing.lg),
          AppButton(
            key: const ValueKey('coaching-new-consultation-primary'),
            label: '새 상담 신청',
            icon: Icons.edit_note_rounded,
            onPressed: () => _newConsult(context),
          ),
          const SizedBox(height: 24),
          SectionTitle('진행 중 상담 ${activeConsultations.length}건'),
          const SizedBox(height: 10),
          if (state.usesLiveBusinessData &&
              state.memberConsultationsLoading &&
              state.memberConsultations.isEmpty)
            const LoadingState(
              key: ValueKey('coaching-active-loading'),
              message: '진행 중인 상담을 불러오고 있어요',
              itemCount: 2,
              compact: true,
            )
          else if (state.usesLiveBusinessData &&
              state.memberConsultationsError != null &&
              state.memberConsultations.isEmpty)
            ErrorState(
              key: const ValueKey('coaching-active-error'),
              message: '진행 중인 상담을 확인하지 못했어요.',
              onRetry: () => _refresh(context),
            )
          else if (activeConsultations.isEmpty)
            const EmptyState(
              key: ValueKey('coaching-active-empty'),
              icon: Icons.support_agent_rounded,
              title: '진행 중인 상담이 없어요',
              message: '운동 목표와 고민을 전문가에게 질문해보세요.',
            )
          else
            for (final entry in activeConsultations)
              Padding(
                key: ValueKey(
                  'coaching-active-consultation-${entry.consultation.id}',
                ),
                padding: const EdgeInsets.only(bottom: SetflowSpacing.md),
                child: SetflowCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConsultationDetailScreen(
                        consultation: entry.consultation,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            color: SetflowColors.blue,
                          ),
                          const SizedBox(width: SetflowSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.consultation.trainerName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  entry.consultation.specialty,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: SetflowColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _MemberConsultationBadge(entry: entry),
                        ],
                      ),
                      const Divider(height: 28),
                      Text(
                        entry.consultation.question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
          if (state.usesLiveBusinessData &&
              state.memberConsultationsError != null &&
              state.memberConsultations.isNotEmpty) ...[
            const SizedBox(height: SetflowSpacing.sm),
            SetflowCard(
              key: const ValueKey('coaching-active-stale-warning'),
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(SetflowSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.sync_problem_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  Expanded(
                    child: Text(
                      '최신 상담 상태를 확인하지 못했어요. 표시된 내용은 이전 동기화 결과입니다.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: state.memberConsultationsLoading
                        ? null
                        : () => _refresh(context),
                    child: const Text('재시도'),
                  ),
                ],
              ),
            ),
          ],
          if (unknownStatusCount > 0) ...[
            const SizedBox(height: SetflowSpacing.sm),
            SetflowCard(
              key: const ValueKey('coaching-unknown-status-notice'),
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(SetflowSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  Expanded(
                    child: Text(
                      '상태 확인이 필요한 상담이 $unknownStatusCount건 있어요. '
                      '새로고침 후에도 계속되면 고객센터에 문의해주세요.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          OutlinedButton.icon(
            key: const ValueKey('coaching-consultation-history'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ConsultationHistoryScreen(),
              ),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('과거 상담 이력'),
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

class ConsultationHistoryScreen extends StatefulWidget {
  const ConsultationHistoryScreen({super.key});

  @override
  State<ConsultationHistoryScreen> createState() =>
      _ConsultationHistoryScreenState();
}

class _ConsultationHistoryScreenState extends State<ConsultationHistoryScreen> {
  Future<void> _refresh() async {
    final state = AppScope.of(context);
    try {
      if (state.usesLiveBusinessData) {
        await state.refreshMemberConsultations();
      } else {
        await state.refreshBusinessDashboard(state.role);
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, '과거 상담 이력을 새로고침하지 못했어요.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final history = _historicalMemberConsultations(state);
    final initialLoadFailed =
        state.usesLiveBusinessData &&
        state.memberConsultationsError != null &&
        history.isEmpty;
    final isLoading =
        state.usesLiveBusinessData &&
        state.memberConsultationsLoading &&
        state.memberConsultations.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('과거 상담 이력'),
        actions: [
          IconButton(
            key: const ValueKey('consultation-history-refresh'),
            tooltip: '새로고침',
            onPressed: state.memberConsultationsLoading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        key: const ValueKey('consultation-history-refresh-indicator'),
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LoadingState(
                  key: ValueKey('consultation-history-loading'),
                  message: '과거 상담 이력을 불러오고 있어요',
                ),
              )
            else if (initialLoadFailed && history.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: ErrorState(
                  key: const ValueKey('consultation-history-error'),
                  message: '과거 상담 이력을 불러오지 못했어요.',
                  onRetry: _refresh,
                ),
              )
            else if (history.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  key: ValueKey('consultation-history-empty'),
                  icon: Icons.history_rounded,
                  title: '아직 과거 상담 이력이 없어요',
                  message: '답변이 완료된 상담이 여기에 모여요.',
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  SetflowSpacing.md,
                  18,
                  SetflowSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    '답변이 완료된 상담 ${history.length}건',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (state.usesLiveBusinessData &&
                  state.memberConsultationsError != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    SetflowSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: SetflowCard(
                      key: const ValueKey('consultation-history-stale-warning'),
                      color: Theme.of(context).colorScheme.errorContainer,
                      padding: const EdgeInsets.all(SetflowSpacing.md),
                      child: Text(
                        '최신 이력을 확인하지 못해 이전 동기화 결과를 표시하고 있어요.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                sliver: SliverList.separated(
                  key: const ValueKey('consultation-history-list'),
                  itemCount: history.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: SetflowSpacing.md),
                  itemBuilder: (context, index) =>
                      _ConsultationHistoryCard(entry: history[index]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConsultationHistoryCard extends StatelessWidget {
  const _ConsultationHistoryCard({required this.entry});

  final _MemberConsultationEntry entry;

  @override
  Widget build(BuildContext context) {
    final consultation = entry.consultation;
    final answer = consultation.response?.trim();
    return SetflowCard(
      key: ValueKey('consultation-history-item-${consultation.id}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConsultationDetailScreen(consultation: consultation),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.support_agent_rounded,
                color: SetflowColors.green,
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      consultation.trainerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat(
                        'yyyy.MM.dd HH:mm',
                      ).format(consultation.createdAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _MemberConsultationBadge(entry: entry),
            ],
          ),
          const Divider(height: SetflowSpacing.xl),
          Text(
            consultation.question.trim().isEmpty
                ? '질문 내용이 저장되지 않았어요.'
                : consultation.question,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, height: 1.45),
          ),
          const SizedBox(height: SetflowSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(SetflowSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '전문가 답변',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  answer == null || answer.isEmpty
                      ? '답변 내용을 상세 화면에서 확인해주세요.'
                      : answer,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
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

class _MemberConsultationBadge extends StatelessWidget {
  const _MemberConsultationBadge({required this.entry});

  final _MemberConsultationEntry entry;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (entry.cloud?.status) {
      BusinessConsultationStatus.pending => ('답변 대기', SetflowColors.orange),
      BusinessConsultationStatus.assigned => ('담당 배정', SetflowColors.blue),
      BusinessConsultationStatus.answered => ('답변 완료', SetflowColors.green),
      BusinessConsultationStatus.replied => ('상담 완료', SetflowColors.green),
      BusinessConsultationStatus.unknown => ('상태 확인 필요', SetflowColors.red),
      null => switch (entry.consultation.status) {
        ConsultationStatus.waiting => ('답변 대기', SetflowColors.orange),
        ConsultationStatus.answered => ('상담 완료', SetflowColors.green),
        ConsultationStatus.coaching => ('코칭 중', SetflowColors.blue),
      },
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

class _MemberConsultationEntry {
  const _MemberConsultationEntry({required this.consultation, this.cloud});

  final ConsultationData consultation;
  final BusinessConsultation? cloud;
}

List<_MemberConsultationEntry> _activeMemberConsultations(AppState state) {
  if (!state.usesLiveBusinessData) {
    return state.consultations
        .where(
          (item) =>
              item.status == ConsultationStatus.waiting ||
              item.status == ConsultationStatus.coaching,
        )
        .map((item) => _MemberConsultationEntry(consultation: item))
        .toList(growable: false);
  }
  return state.memberConsultations
      .where(
        (item) =>
            item.status == BusinessConsultationStatus.pending ||
            item.status == BusinessConsultationStatus.assigned,
      )
      .map(_memberConsultationEntry)
      .toList(growable: false);
}

List<_MemberConsultationEntry> _historicalMemberConsultations(AppState state) {
  if (!state.usesLiveBusinessData) {
    return state.consultations
        .where((item) => item.status == ConsultationStatus.answered)
        .map((item) => _MemberConsultationEntry(consultation: item))
        .toList(growable: false);
  }
  return state.memberConsultations
      .where(
        (item) =>
            item.status == BusinessConsultationStatus.answered ||
            item.status == BusinessConsultationStatus.replied,
      )
      .map(_memberConsultationEntry)
      .toList(growable: false);
}

_MemberConsultationEntry _memberConsultationEntry(BusinessConsultation cloud) {
  return _MemberConsultationEntry(
    consultation: _consultationDataFromCloud(cloud),
    cloud: cloud,
  );
}

ConsultationData _consultationDataFromCloud(BusinessConsultation record) {
  final responseMessages =
      record.messages
          .where(
            (message) =>
                message.sender == BusinessMessageSender.trainer ||
                message.sender == BusinessMessageSender.gym,
          )
          .toList()
        ..sort(
          (left, right) =>
              (left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  ),
        );
  return ConsultationData(
    id: record.id,
    trainerName: record.trainerName ?? record.gymName ?? '담당 전문가',
    specialty: record.specialty ?? record.goal ?? '맞춤 운동 상담',
    goal: record.goal ?? '',
    level: record.level ?? '',
    question: record.question ?? '',
    createdAt: record.createdAt ?? DateTime.now(),
    status:
        record.status == BusinessConsultationStatus.answered ||
            record.status == BusinessConsultationStatus.replied
        ? ConsultationStatus.answered
        : ConsultationStatus.waiting,
    response: responseMessages.lastOrNull?.text,
    sharedRecommendationProfile: record.sharedRecommendationProfile,
    recommendationProfileShareRevokedAt:
        record.recommendationProfileShareRevokedAt,
  );
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
                    leading: const Icon(
                      Icons.trending_up,
                      color: SetflowColors.orange,
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

  Future<void> _logout(BuildContext context, AppState state) async {
    final route = ModalRoute.of(context);
    Navigator.of(context).pop();
    await route?.completed;
    await state.logout();
  }

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
          // Sign-in is only offered to a session that has nothing to sign out
          // of: no Supabase user *and* still a guest. A local member session
          // restored from a snapshot gets logout, not a login prompt.
          if (!Auth.instance.hasAuthenticatedUser &&
              state.role == UserRole.guest)
            ListTile(
              key: const ValueKey('settings-sign-in'),
              leading: const Icon(
                SetflowIcons.signIn,
                color: SetflowColors.primary,
              ),
              title: const Text('로그인 / 회원가입'),
              subtitle: const Text('기록을 클라우드에 백업하고 코칭을 사용하세요'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const WelcomeScreen())),
            )
          else
            ListTile(
              leading: const Icon(
                SetflowIcons.signOut,
                color: SetflowColors.red,
              ),
              title: const Text(
                '로그아웃',
                style: TextStyle(color: SetflowColors.red),
              ),
              // Waits for the sheet to finish closing before signing out, so the
              // teardown never races the route animation.
              onTap: () => _logout(context, state),
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
