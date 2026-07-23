import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
      AppSnackbar.success(context, '${day.month}월 ${day.day}일로 운동을 복사했습니다.');
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
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final confirmed = await _confirmDeleteDay(context, day);
                  if (!confirmed || !context.mounted) return;
                  state.deleteSession(day);
                  AppSnackbar.success(context, '운동 기록을 삭제했어요.');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteDay(BuildContext context, DateTime day) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: SetflowColors.red,
            ),
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
                              state.applyRoutine(routine, DateTime.now());
                              AppSnackbar.success(
                                context,
                                '오늘 캘린더에 루틴을 적용했어요.',
                              );
                            } else if (value == 'edit') {
                              AppSnackbar.info(
                                context,
                                '루틴 편집 화면은 운동 순서 편집 단계에서 연결됩니다.',
                              );
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
                                state.removeRoutine(routine);
                                AppSnackbar.success(context, '루틴을 삭제했어요.');
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
    final created = state.createRoutine(draft.name, draft.description);
    if (created) {
      AppSnackbar.success(context, '새 루틴을 저장했어요.');
    } else {
      AppSnackbar.error(context, '무료 플랜 저장 한도에 도달했어요.');
    }
  }
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
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CommunityPostDetailScreen(post: post),
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: Icon(post.icon, size: 50, color: post.color),
                          ),
                          Positioned(
                            left: 7,
                            right: 7,
                            bottom: 6,
                            child: Text(
                              post.metric,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
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
          SetflowCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BodyCompositionScreen()),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(0xFFE0FAF7),
                  child: Icon(
                    Icons.accessibility_new,
                    color: SetflowColors.teal,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '체성분 변화',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '체중 70.9kg · 골격근량 32.5kg',
                        style: TextStyle(
                          fontSize: 11,
                          color: SetflowColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right),
              ],
            ),
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
