import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
    final state = AppScope.of(context);
    final pages = [
      const CalendarScreen(),
      const RoutinesScreen(),
      const MarketScreen(),
      const CommunityScreen(),
      const CoachingScreen(),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: index, children: pages),
          if (state.restRemaining > 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: 10,
              child: _RestTimerBar(seconds: state.restRemaining),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 74,
        selectedIndex: index,
        indicatorColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.surface,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          for (var i = 0; i < destinations.length; i++)
            NavigationDestination(
              icon: Icon(destinations[i].$1, color: SetflowColors.disabled),
              selectedIcon: Icon(
                destinations[i].$2,
                color: SetflowColors.primary,
              ),
              label: destinations[i].$3,
            ),
        ],
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}

class _RestTimerBar extends StatelessWidget {
  const _RestTimerBar({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return Material(
      color: SetflowColors.ink,
      elevation: 10,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined, color: SetflowColors.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '휴식 중',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '$minutes:$remainder',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: AppScope.of(context).cancelRestTimer,
              icon: const Icon(Icons.close, color: Colors.white),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
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
  DateTime? copySource;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final days = _calendarDays(month);
    final weeks = List.generate(
      6,
      (index) => days.sublist(index * 7, index * 7 + 7),
    );
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 8),
            child: Row(
              children: [
                PopupMenuButton<int>(
                  onSelected: (value) =>
                      setState(() => month = DateTime(month.year, value)),
                  itemBuilder: (_) => List.generate(
                    12,
                    (i) =>
                        PopupMenuItem(value: i + 1, child: Text('${i + 1}월')),
                  ),
                  child: Row(
                    children: [
                      Text(
                        DateFormat('yyyy.MM').format(month),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: SetflowColors.secondaryText,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '운동 통계',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                  ),
                  icon: const Icon(Icons.bar_chart_rounded),
                ),
                IconButton(
                  tooltip: '설정',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        ['일', '월', '화', '수', '목', '금', '토'][i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: i == 0
                              ? Colors.redAccent
                              : i == 6
                              ? Colors.blueAccent
                              : SetflowColors.secondaryText,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(
                  width: 44,
                  child: Center(
                    child: Text(
                      '주간',
                      style: TextStyle(
                        fontSize: 10,
                        color: SetflowColors.disabled,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final height = (constraints.maxHeight - 46) / 6;
                return GestureDetector(
                  onVerticalDragEnd: (details) {
                    final forward = (details.primaryVelocity ?? 0) < 0;
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
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                      child: Column(
                        children: [
                          for (final week in weeks)
                            SizedBox(
                              height: height,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final day in week)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
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
                                  SizedBox(
                                    width: 44,
                                    child: _WeeklySummary(week: week),
                                  ),
                                ],
                              ),
                            ),
                          if (copySource != null)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: dark
                                    ? Colors.white12
                                    : SetflowColors.ink,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.copy_rounded,
                                    color: SetflowColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      '복사할 날짜를 선택해주세요',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        setState(() => copySource = null),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 18,
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
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleDayTap(BuildContext context, DateTime day) {
    if (copySource != null) {
      AppScope.of(context).copySession(copySource!, day);
      setState(() => copySource = null);
      showMessage(context, '${day.month}월 ${day.day}일로 운동을 복사했습니다.');
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DailyWorkoutScreen(date: day)));
  }

  void _showDayMenu(BuildContext context, DateTime day) {
    final state = AppScope.of(context);
    final session = state.sessions[state.dateOnly(day)];
    if (session == null || session.exercises.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  '${day.month}월 ${day.day}일 운동',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('루틴 복사'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => copySource = day);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: SetflowColors.red,
                ),
                title: const Text(
                  '기록 삭제',
                  style: TextStyle(color: SetflowColors.red),
                ),
                onTap: () {
                  state.deleteSession(day);
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DateTime> _calendarDays(DateTime target) {
    final first = DateTime(target.year, target.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    return List.generate(42, (index) => start.add(Duration(days: index)));
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
    final Color background = !hasSession
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF29272B)
              : SetflowColors.soft)
        : completion >= 1
        ? SetflowColors.teal
        : completion > 0
        ? SetflowColors.orange
        : const Color(0xFFE1E4E8);
    final textColor = hasSession
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final muscles =
        session?.exercises
            .map((item) => item.template.muscle.characters.first)
            .toSet()
            .take(2)
            .join() ??
        '';

    return Opacity(
      opacity: inMonth ? 1 : .28,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: isToday && !hasSession
              ? const BorderSide(color: SetflowColors.primary, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: Column(
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: date.weekday == DateTime.sunday
                        ? Colors.redAccent
                        : date.weekday == DateTime.saturday
                        ? Colors.blueAccent
                        : textColor,
                  ),
                ),
                const Spacer(),
                if (hasSession) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      muscles,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    session!.volume > 1000
                        ? '${(session!.volume / 1000).toStringAsFixed(1)}t'
                        : session!.volume.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
    final sets = sessions.fold(0, (sum, item) => sum + item.completedSets);
    final volume = sessions.fold<double>(0, (sum, item) => sum + item.volume);
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF29272B)
            : SetflowColors.elevated,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$sets',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const Text(
            '세트',
            style: TextStyle(fontSize: 8, color: SetflowColors.secondaryText),
          ),
          if (volume > 0)
            Text(
              volume > 1000
                  ? '${(volume / 1000).toStringAsFixed(1)}t'
                  : volume.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 8,
                color: SetflowColors.secondaryText,
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
                          ],
                          onSelected: (value) {
                            if (value == 'apply') {
                              state.applyRoutine(routine, DateTime.now());
                              showMessage(context, '오늘 캘린더에 루틴을 적용했습니다.');
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
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => _createRoutine(context),
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

  void _createRoutine(BuildContext context) {
    final name = TextEditingController();
    final description = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '새 루틴 만들기',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '루틴 이름'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: '설명'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: '저장',
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                AppScope.of(
                  context,
                ).createRoutine(name.text.trim(), description.text.trim());
                Navigator.pop(sheetContext);
              },
            ),
          ],
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
  String filter = '전체';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('전문가 루틴')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '목표, 운동, 트레이너 검색',
            ),
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
          const SectionTitle('지금 인기 있는 루틴'),
          const SizedBox(height: 10),
          for (final routine in state.marketRoutines)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: SetflowCard(
                onTap: () => _showRoutine(context, routine),
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

  void _showRoutine(BuildContext context, RoutineData routine) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .78,
        maxChildSize: .92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Container(
              height: 170,
              decoration: BoxDecoration(
                color: routine.color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.fitness_center_rounded,
                size: 86,
                color: routine.color,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              routine.name,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: SetflowColors.blue,
                  size: 18,
                ),
                const SizedBox(width: 5),
                Text(
                  routine.author,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              routine.description,
              style: const TextStyle(
                color: SetflowColors.secondaryText,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            const SectionTitle('포함된 운동'),
            for (final exercise in routine.exercises)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: routine.color.withValues(alpha: .12),
                  child: Icon(exercise.icon, color: routine.color),
                ),
                title: Text(
                  exercise.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(exercise.muscle),
              ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: '내 루틴으로 가져오기',
              icon: Icons.download_rounded,
              onPressed: () {
                AppScope.of(context).importRoutine(routine);
                Navigator.pop(sheetContext);
                showMessage(context, '내 루틴에 추가했습니다.');
              },
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
  final liked = <int>{};

  @override
  Widget build(BuildContext context) {
    const posts = [
      ('오운완 민지', '오늘 하체 루틴 100% 완료! 지난주보다 스쿼트 5kg 올렸어요.', '하체 · 12세트 · 4.2t'),
      ('꾸준한 준호', '30일 연속 운동 달성. 짧게라도 기록하니 습관이 되네요.', '전신 · 8세트 · 2.8t'),
      ('세트플로우 코치', '이번 주는 무게보다 정확한 가동범위에 집중해보세요.', '코칭 팁'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('동기부여'),
        actions: [
          IconButton(
            onPressed: () =>
                showMessage(context, '게시물 작성 화면은 다음 단계에서 사진 업로드와 연결됩니다.'),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        itemCount: posts.length,
        itemBuilder: (_, index) {
          final post = posts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SetflowCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: [
                        SetflowColors.primary,
                        SetflowColors.teal,
                        SetflowColors.blue,
                      ][index],
                      child: Text(
                        post.$1.characters.first,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(
                      post.$1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: const Text('오늘', style: TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.more_horiz),
                  ),
                  Container(
                    height: 160,
                    color: [
                      const Color(0xFFFFF4CB),
                      const Color(0xFFE0FAF7),
                      const Color(0xFFE8F0FF),
                    ][index],
                    child: Center(
                      child: Icon(
                        [
                          Icons.emoji_events_rounded,
                          Icons.local_fire_department_rounded,
                          Icons.lightbulb_rounded,
                        ][index],
                        size: 72,
                        color: [
                          SetflowColors.orange,
                          SetflowColors.red,
                          SetflowColors.blue,
                        ][index],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.$2,
                          style: const TextStyle(
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          post.$3,
                          style: const TextStyle(
                            color: SetflowColors.secondaryText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => setState(
                                () => liked.contains(index)
                                    ? liked.remove(index)
                                    : liked.add(index),
                              ),
                              icon: Icon(
                                liked.contains(index)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: liked.contains(index)
                                    ? SetflowColors.red
                                    : null,
                              ),
                            ),
                            Text(
                              '${24 + index * 13 + (liked.contains(index) ? 1 : 0)}',
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.chat_bubble_outline, size: 21),
                            const SizedBox(width: 5),
                            Text('${5 + index}'),
                            const Spacer(),
                            const Icon(Icons.ios_share_outlined),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CoachingScreen extends StatelessWidget {
  const CoachingScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                        '비동기 상담 후 1:1 코칭을 시작할 수 있어요.',
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
          const SectionTitle('진행 중인 상담'),
          const SizedBox(height: 10),
          SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE8F0FF),
                      child: Icon(Icons.person, color: SetflowColors.blue),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '김코치',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            '초보자 4주 근력 스타트',
                            style: TextStyle(
                              fontSize: 12,
                              color: SetflowColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: SetflowColors.orange.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '답변 대기',
                        style: TextStyle(
                          color: SetflowColors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                const Text(
                  '주 3회 운동이 가능한데 무릎이 불편해도 진행할 수 있을까요?',
                  style: TextStyle(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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

  void _newConsult(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '상담 신청',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              '운동 목표와 현재 고민을 구체적으로 적어주세요.',
              style: TextStyle(color: SetflowColors.secondaryText),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: controller,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '예: 주 3회 근육 증가가 목표예요.',
              ),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: '상담 보내기',
              onPressed: () {
                Navigator.pop(sheetContext);
                showMessage(context, '상담이 접수되었습니다.');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운동 대시보드')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          Row(
            children: const [
              MetricCard(
                label: '이번 주',
                value: '4',
                suffix: '회',
                icon: Icons.calendar_today,
                tint: SetflowColors.teal,
              ),
              SizedBox(width: 10),
              MetricCard(
                label: '총 볼륨',
                value: '12.8',
                suffix: 't',
                icon: Icons.monitor_weight_outlined,
                tint: SetflowColors.orange,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              MetricCard(
                label: '연속 기록',
                value: '7',
                suffix: '일',
                icon: Icons.local_fire_department,
                tint: SetflowColors.red,
              ),
              SizedBox(width: 10),
              MetricCard(
                label: '완료율',
                value: '86',
                suffix: '%',
                icon: Icons.check_circle_outline,
                tint: SetflowColors.blue,
              ),
            ],
          ),
          const SizedBox(height: 26),
          const SectionTitle('주간 볼륨'),
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
          const SectionTitle('1RM 성장'),
          const SizedBox(height: 10),
          const SetflowCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(0xFFFFF4CB),
                child: Icon(Icons.trending_up, color: SetflowColors.orange),
              ),
              title: Text(
                '바벨 벤치 프레스',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('최근 4주 +7.5kg'),
              trailing: Text(
                '72.5kg',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ),
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
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('다크 모드'),
            value: state.isDarkMode,
            onChanged: (_) => state.toggleTheme(),
          ),
          const Divider(height: 30),
          const ListTile(
            title: Text(
              '데모 워크스페이스',
              style: TextStyle(
                fontSize: 13,
                color: SetflowColors.secondaryText,
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
