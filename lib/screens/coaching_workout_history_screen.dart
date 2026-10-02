import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/workout_history_calendar.dart';

/// 수업 전 개인 운동까지 포함한 회원 기록. 페이지마다 서버가 권한을 확인한다.
class CoachingWorkoutHistoryScreen extends StatefulWidget {
  const CoachingWorkoutHistoryScreen({required this.schedule, super.key});
  final BusinessCoachingSchedule schedule;

  @override
  State<CoachingWorkoutHistoryScreen> createState() =>
      _CoachingWorkoutHistoryScreenState();
}

class _CoachingWorkoutHistoryScreenState
    extends State<CoachingWorkoutHistoryScreen>
    with WidgetsBindingObserver {
  final _sessions = <BusinessWorkoutSession>[];
  CoachingWorkoutCursor? _cursor;
  DateTime? _selectedHistoryDate;
  bool _requested = false;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(reset: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final state = AppScope.of(context);
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) {
        _sessions.clear();
        _cursor = null;
      }
    });
    try {
      final page = await state.loadCoachingWorkoutHistory(
        widget.schedule.id,
        before: _cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _sessions.map((s) => s.id).toSet();
        _sessions.addAll(page.sessions.where((s) => ids.add(s.id)));
        _cursor = page.nextCursor;
        _loading = false;
      });
      if (reset && _sessions.isNotEmpty) {
        final date = _selectedHistoryDate ?? _sessions.first.date;
        await _loadMonth(DateTime(date.year, date.month));
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        // 동의 철회/수업 종료일 수 있으므로 이전에 읽은 정보도 치운다.
        _sessions.clear();
        _cursor = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMonth(DateTime month) async {
    while (mounted && !_failed && !_loading && _cursor != null) {
      if (_cursor!.date.isBefore(month)) break;
      final previousCursor = _cursor;
      await _load();
      if (_cursor?.sessionId == previousCursor?.sessionId) break;
    }
  }

  Future<void> _loadOlder() async {
    final previousCount = _sessions.length;
    await _load();
    if (!mounted || _failed || _sessions.length <= previousCount) return;
    final date = _sessions[previousCount].date;
    setState(() => _selectedHistoryDate = date);
    await _loadMonth(DateTime(date.year, date.month));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.schedule.memberName} 운동 기록')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SetflowInsets.pageListTight,
        children: [
          Text(
            '수업 전 개인 운동을 포함한 전체 기록',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: SetflowSpacing.lg),
          if (_failed) ...[
            const Text('기록을 열 수 없어요. 회원의 공유 동의와 수업 상태를 확인해주세요.'),
            TextButton(
              onPressed: () => _load(reset: true),
              child: const Text('다시 확인'),
            ),
          ] else if (!_loading && _sessions.isEmpty)
            const Text('아직 저장된 운동 기록이 없습니다.'),
          if (!_failed)
            WorkoutHistoryCalendar(
              days: [
                for (final session in _sessions)
                  WorkoutHistoryDay.business(session),
              ],
              initialDate: _selectedHistoryDate,
              onDateSelected: (date) => _selectedHistoryDate = date,
              loading: _loading,
              onMonthChanged: _loadMonth,
              recordBuilder: (date) => Column(
                children: [
                  for (final session in _sessions.where(
                    (session) => DateUtils.isSameDay(session.date, date),
                  )) ...[
                    CoachingWorkoutSessionCard(
                      key: ValueKey(session.id),
                      session: session,
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                ],
              ),
            ),
          if (!_loading && _cursor != null)
            OutlinedButton(
              key: const ValueKey('coaching-history-more'),
              onPressed: _loadOlder,
              child: const Text('이전 기록 더 보기'),
            ),
        ],
      ),
    ),
  );
}

class CoachingWorkoutSessionCard extends StatelessWidget {
  const CoachingWorkoutSessionCard({required this.session, super.key});
  final BusinessWorkoutSession session;

  @override
  Widget build(BuildContext context) => SetflowCard(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      key: PageStorageKey('coaching-history-${session.id}'),
      title: Text(DateFormat('yyyy.MM.dd').format(session.date)),
      subtitle: Text(
        '${session.exercises.length}개 종목 · ${session.completedSets}/${session.totalSets}세트',
      ),
      childrenPadding: const EdgeInsets.all(SetflowSpacing.md),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session.category != null) Text('분류 · ${session.category}'),
        if (session.intensity != null) Text('운동 강도 · ${session.intensity}'),
        if (session.feedback?.isNotEmpty == true)
          Text('운동 메모 · ${session.feedback}'),
        for (final exercise in session.exercises) ...[
          Text(exercise.name, style: Theme.of(context).textTheme.titleSmall),
          for (final set in exercise.sets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xs),
              child: Text(
                [
                  '${set.setNumber}세트 · ${set.completed ? '완료' : '미완료'}',
                  if (set.durationSeconds == null)
                    '${set.weight}kg × ${set.reps}회',
                  if (set.durationSeconds != null) '${set.durationSeconds}초',
                  if (set.distanceMeters != null) '${set.distanceMeters}m',
                  if (set.intensityRpe != null) 'RPE ${set.intensityRpe}',
                  if (set.rir != null) 'RIR ${set.rir}',
                  '휴식 ${set.restSeconds}초',
                  if (set.memo?.isNotEmpty == true) set.memo!,
                ].join(' · '),
              ),
            ),
          const SizedBox(height: SetflowSpacing.sm),
        ],
        for (final feedback in session.feedbacks)
          Text('${feedback.authorName} · ${feedback.text}'),
      ],
    ),
  );
}
