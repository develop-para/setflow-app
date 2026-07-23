import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

String _weekdayLabel(DateTime date) => _weekdayLabels[date.weekday - 1];

/// 사업자(트레이너/헬스장)가 담당 회원의 상세 정보를 열람하는 화면.
/// [PeoplePage._showMember] 바텀시트에서 진입한다.
class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({
    required this.person,
    required this.role,
    super.key,
  });

  final (String, String, String, int) person;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final recentSessions = state.sessions.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final latestVolume = recentSessions.isEmpty
        ? 0.0
        : recentSessions.first.volume;
    final routines = [...state.routines, ...state.marketRoutines];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${person.$1} 상세'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '캘린더'),
              Tab(text: '루틴'),
              Tab(text: '커뮤니티'),
              Tab(text: '라이브러리'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: _MemberSummaryHeader(
                person: person,
                latestVolume: latestVolume,
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _MemberCalendarTab(sessions: state.sessions),
                  _MemberRoutineTab(routines: routines),
                  const _MemberCommunityTab(),
                  _MemberLibraryTab(exercises: state.exercises),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberSummaryHeader extends StatelessWidget {
  const _MemberSummaryHeader({
    required this.person,
    required this.latestVolume,
  });

  final (String, String, String, int) person;
  final double latestVolume;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: SetflowColors.primary.withValues(alpha: .2),
              child: Text(
                person.$1.characters.first,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.$1,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${person.$2} · 마지막 기록 ${person.$3}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: SetflowColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            MetricCard(
              label: '완료율',
              value: '${person.$4}',
              suffix: '%',
              icon: Icons.check_circle_outline,
              tint: person.$4 >= 80
                  ? SetflowColors.green
                  : SetflowColors.orange,
            ),
            const SizedBox(width: 10),
            MetricCard(
              label: '최근 볼륨',
              value: latestVolume.toStringAsFixed(1),
              suffix: 't',
              icon: Icons.monitor_weight_outlined,
              tint: SetflowColors.blue,
            ),
          ],
        ),
      ],
    );
  }
}

class _MemberCalendarTab extends StatefulWidget {
  const _MemberCalendarTab({required this.sessions});

  final Map<DateTime, WorkoutSession> sessions;

  @override
  State<_MemberCalendarTab> createState() => _MemberCalendarTabState();
}

class _MemberCalendarTabState extends State<_MemberCalendarTab> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = <DateTime?>[
      ...List.filled(firstWeekday, null),
      for (var day = 1; day <= daysInMonth; day++)
        DateTime(month.year, month.month, day),
    ];
    final recent = widget.sessions.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: SetflowInsets.pageListTight,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat('yyyy.MM').format(month),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month + 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final day in cells)
              if (day == null)
                const SizedBox.shrink()
              else
                _MemberCalendarCell(
                  date: day,
                  session:
                      widget.sessions[DateTime(day.year, day.month, day.day)],
                ),
          ],
        ),
        const SizedBox(height: 16),
        const SectionTitle('최근 운동 기록'),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const EmptyState(
            icon: Icons.event_busy,
            title: '운동 기록 없음',
            message: '이 회원의 최근 운동 기록이 없습니다.',
          )
        else
          for (final session in recent.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SetflowCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateFormat('MM.dd').format(session.date)} (${_weekdayLabel(session.date)})',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${session.exercises.length}개 종목 · ${session.totalSets}세트 · ${session.volume.toStringAsFixed(1)}t',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SetflowColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${(session.completion * 100).round()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: session.completion >= .8
                            ? SetflowColors.green
                            : SetflowColors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _MemberCalendarCell extends StatelessWidget {
  const _MemberCalendarCell({required this.date, required this.session});

  final DateTime date;
  final WorkoutSession? session;

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: SetflowColors.primary, width: 1.4)
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${date.day}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            if (session != null)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session!.completion >= .8
                      ? SetflowColors.green
                      : SetflowColors.orange,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberRoutineTab extends StatelessWidget {
  const _MemberRoutineTab({required this.routines});

  final List<RoutineData> routines;

  @override
  Widget build(BuildContext context) {
    if (routines.isEmpty) {
      return const EmptyState(
        icon: Icons.list_alt_outlined,
        title: '루틴 없음',
        message: '이 회원에게 배정된 루틴이 없습니다.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      itemCount: routines.length,
      itemBuilder: (_, index) {
        final routine = routines[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SetflowCard(
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 44,
                  decoration: BoxDecoration(
                    color: routine.color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routine.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        routine.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SetflowColors.secondaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${routine.level} · ${routine.exercises.length}개 종목',
                        style: const TextStyle(
                          fontSize: 11,
                          color: SetflowColors.disabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MemberCommunityTab extends StatelessWidget {
  const _MemberCommunityTab();

  static const _posts = [
    ('오늘 상체 운동 완료!', '3시간 전', 12, 3),
    ('식단 기록 공유합니다', '어제', 8, 1),
    ('3주차 인바디 결과 인증', '3일 전', 24, 6),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      itemCount: _posts.length,
      itemBuilder: (_, index) {
        final post = _posts[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.$1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  post.$2,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SetflowColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.favorite_border,
                      size: 16,
                      color: SetflowColors.secondaryText,
                    ),
                    const SizedBox(width: 4),
                    Text('${post.$3}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.mode_comment_outlined,
                      size: 16,
                      color: SetflowColors.secondaryText,
                    ),
                    const SizedBox(width: 4),
                    Text('${post.$4}', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MemberLibraryTab extends StatelessWidget {
  const _MemberLibraryTab({required this.exercises});

  final List<ExerciseTemplate> exercises;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemCount: exercises.length,
      itemBuilder: (_, index) {
        final exercise = exercises[index];
        return SetflowCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(exercise.icon, color: SetflowColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      exercise.muscle,
                      style: const TextStyle(
                        fontSize: 10,
                        color: SetflowColors.secondaryText,
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
}
