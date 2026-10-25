import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../data/coaching_management_repository.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import '../widgets/exercise_muscle_map.dart';
import '../widgets/pro_access_gate.dart';
import '../widgets/workout_history_calendar.dart';
import 'coaching_management_screen.dart';
import 'coaching_workout_screens.dart';
import 'consultation_chat_screen.dart';

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

String _weekdayLabel(DateTime date) => _weekdayLabels[date.weekday - 1];

String _businessCardioSetText(BusinessWorkoutSet set) {
  final minutes = ((set.durationSeconds ?? 0) / 60).round();
  final distance = set.distanceMeters;
  final distanceText = distance != null && distance > 0
      ? ' · ${(distance / 1000).toStringAsFixed(1)}km'
      : '';
  final rpe = set.intensityRpe;
  final rpeText = rpe != null && rpe > 0
      ? ' · RPE ${rpe.toStringAsFixed(rpe % 1 == 0 ? 0 : 1)}'
      : '';
  return '$minutes분$distanceText$rpeText';
}

String _businessSessionActivityText(BusinessWorkoutSession session) {
  final hasResistance = session.exercises.any(
    (exercise) => exercise.targetMuscle != '유산소',
  );
  final hasCardio = session.exercises.any(
    (exercise) => exercise.targetMuscle == '유산소',
  );
  return [
    if (hasResistance) '${(session.totalVolumeKg / 1000).toStringAsFixed(1)}t',
    if (hasCardio) '${(session.cardioDurationSeconds / 60).round()}분 유산소',
  ].join(' · ');
}

String _workoutSessionActivityText(WorkoutSession session) => [
  if (session.hasResistance) '${(session.volume / 1000).toStringAsFixed(1)}t',
  if (session.hasCardio) '${(session.cardioDurationSeconds / 60).round()}분 유산소',
].join(' · ');

/// 사업자(트레이너/헬스장)가 담당 회원의 상세 정보를 열람하는 화면.
/// [PeoplePage._showMember] 바텀시트에서 진입한다.
class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({
    required this.member,
    required this.role,
    super.key,
  });

  final BusinessMember member;
  final UserRole role;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen>
    with WidgetsBindingObserver {
  var _requested = false;
  late final DateTime _recentTo;
  late final DateTime _recentFrom;
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    _recentTo = DateUtils.dateOnly(DateTime.now());
    _recentFrom = _recentTo.subtract(const Duration(days: 90));
    _from = _recentFrom;
    _to = _recentTo;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final appState = AppScope.of(context);
    if (!appState.usesLiveBusinessData) return;
    appState
        .loadBusinessMemberDetail(widget.member.id, force: true)
        .then<void>((_) {}, onError: (_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (_requested || !state.usesLiveBusinessData) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      state
          .loadBusinessMemberDetail(
            widget.member.id,
            force: true,
            from: _from,
            to: _to,
          )
          .then<void>((_) {}, onError: (_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final liveBusinessData = state.usesLiveBusinessData;
    final detail = state.businessMemberDetail(widget.member.id);
    final visibleSessions = liveBusinessData
        ? <DateTime, WorkoutSession>{}
        : state.sessions;
    final recentSessions = visibleSessions.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final latestSession = recentSessions.isEmpty ? null : recentSessions.first;
    final routines = liveBusinessData
        ? <RoutineData>[]
        : [...state.routines, ...state.marketRoutines];
    final isGym = widget.role == UserRole.gym;
    final tabs = liveBusinessData
        ? const [Tab(text: '운동 기록'), Tab(text: '피드백')]
        : isGym
        ? const [Tab(text: '기록'), Tab(text: '루틴'), Tab(text: '피드백')]
        : const [
            Tab(text: '캘린더'),
            Tab(text: '루틴'),
            Tab(text: '커뮤니티'),
            Tab(text: '라이브러리'),
          ];
    final tabViews = liveBusinessData
        ? <Widget>[
            _LiveMemberRecordTab(
              member: widget.member,
              detail: detail,
              loading: state.isBusinessMemberDetailLoading(widget.member.id),
              error: state.businessMemberDetailError(widget.member.id),
              from: _from,
              to: _to,
              recentFrom: _recentFrom,
              recentTo: _recentTo,
              onRangeChanged: (from, to) => setState(() {
                _from = from;
                _to = to;
              }),
            ),
            _LiveMemberFeedbackTab(
              member: widget.member,
              detail: detail,
              from: _from,
              to: _to,
              loading: state.isBusinessMemberDetailLoading(widget.member.id),
              error: state.businessMemberDetailError(widget.member.id),
            ),
          ]
        : isGym
        ? <Widget>[
            _MemberCalendarTab(sessions: visibleSessions),
            _MemberRoutineTab(routines: routines),
            _MemberFeedbackTab(memberName: widget.member.name),
          ]
        : <Widget>[
            _MemberCalendarTab(sessions: visibleSessions),
            _MemberRoutineTab(routines: routines),
            const _MemberCommunityTab(),
            _MemberLibraryTab(
              exercises: <String, ExerciseTemplate>{
                for (final exercise in state.selectableExercises)
                  exercise.id: exercise,
                for (final routine in routines)
                  for (final exercise in routine.exercises)
                    exercise.id: exercise,
                for (final session in visibleSessions.values)
                  for (final exercise in session.exercises)
                    exercise.template.id: exercise.template,
              }.values.toList(growable: false),
            ),
          ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.member.name} 상세'),
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SetflowSpacing.gutter,
                SetflowSpacing.md,
                SetflowSpacing.gutter,
                SetflowSpacing.sm2,
              ),
              child: liveBusinessData
                  ? _LiveMemberHeader(
                      member: widget.member,
                      role: widget.role,
                      from: _from,
                      to: _to,
                    )
                  : _MemberSummaryHeader(
                      member: widget.member,
                      latestSession: latestSession,
                      liveDetail: detail,
                    ),
            ),
            Expanded(child: TabBarView(children: tabViews)),
          ],
        ),
      ),
    );
  }
}

class _LiveMemberHeader extends StatelessWidget {
  const _LiveMemberHeader({
    required this.member,
    required this.role,
    required this.from,
    required this.to,
  });

  final BusinessMember member;
  final UserRole role;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final consultations =
        state.businessConsultations
            .where((consultation) => consultation.userId == member.userId)
            .toList()
          ..sort(
            (left, right) => (right.createdAt ?? DateTime(0)).compareTo(
              left.createdAt ?? DateTime(0),
            ),
          );
    final consultation = consultations.firstOrNull;
    final connectedTrainer = role == UserRole.trainer && member.userId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${member.goal ?? '목표 미등록'} · 마지막 기록 ${_relativeDate(member.lastActivityAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (connectedTrainer) ...[
          const SizedBox(height: SetflowSpacing.sm),
          Wrap(
            spacing: SetflowSpacing.sm,
            runSpacing: SetflowSpacing.xs,
            children: [
              if (state.coachingWorkoutRepository != null)
                OutlinedButton.icon(
                  key: const ValueKey('member-detail-assignments'),
                  icon: const Icon(SetflowIcons.routine),
                  label: const Text('운동 과제'),
                  onPressed: () async {
                    if (!await requireProAccess(context) || !context.mounted) {
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CoachingAssignmentsScreen(
                          memberUserId: member.userId,
                        ),
                      ),
                    );
                  },
                ),
              if (consultation != null &&
                  state.businessRepository is ConsultationChatRepository)
                OutlinedButton.icon(
                  key: const ValueKey('member-detail-chat'),
                  icon: const Icon(SetflowIcons.comment),
                  label: const Text('대화'),
                  onPressed: () async {
                    if (!await requireProAccess(context) || !context.mounted) {
                      return;
                    }
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ConsultationChatScreen(
                          consultationId: consultation.id,
                          role: role,
                          initialConsultation: consultation,
                        ),
                      ),
                    );
                  },
                ),
              if (state.businessRepository is CoachingManagementRepository)
                OutlinedButton.icon(
                  key: const ValueKey('member-detail-sharing'),
                  icon: const Icon(SetflowIcons.handOver),
                  label: const Text('기록 공유'),
                  onPressed: () async {
                    final accountId = state.businessAccess?.userId;
                    await openTrainerMemberRecords(
                      context,
                      memberUserId: member.userId,
                      memberName: member.name,
                      consultationId: consultation?.id,
                    );
                    if (!context.mounted ||
                        state.role != role ||
                        state.businessAccess?.userId != accountId) {
                      return;
                    }
                    try {
                      await state.loadBusinessMemberDetail(
                        member.id,
                        force: true,
                        from: from,
                        to: to,
                      );
                    } catch (_) {
                      // 기록 탭의 조회 실패와 다시 시도로 안내한다.
                    }
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LiveMemberRecordTab extends StatefulWidget {
  const _LiveMemberRecordTab({
    required this.member,
    required this.detail,
    required this.loading,
    required this.error,
    required this.from,
    required this.to,
    required this.recentFrom,
    required this.recentTo,
    required this.onRangeChanged,
  });

  final BusinessMember member;
  final BusinessMemberDetail? detail;
  final bool loading;
  final Object? error;
  final DateTime from;
  final DateTime to;
  final DateTime recentFrom;
  final DateTime recentTo;
  final void Function(DateTime from, DateTime to) onRangeChanged;

  @override
  State<_LiveMemberRecordTab> createState() => _LiveMemberRecordTabState();
}

class _LiveMemberRecordTabState extends State<_LiveMemberRecordTab>
    with AutomaticKeepAliveClientMixin<_LiveMemberRecordTab> {
  DateTime? _selectedHistoryDate;
  bool _showCalendar = false;
  BusinessMember get member => widget.member;
  BusinessMemberDetail? get detail => widget.detail;
  bool get loading => widget.loading;
  Object? get error => widget.error;

  @override
  bool get wantKeepAlive => true;

  Future<void> _loadMonth(DateTime month) async {
    final end = DateTime(month.year, month.month + 1, 0);
    widget.onRangeChanged(month, end);
    try {
      await AppScope.of(
        context,
      ).loadBusinessMemberDetail(member.id, force: true, from: month, to: end);
    } catch (_) {
      // 공유 권한 철회와 조회 실패는 기존 오류 화면으로 안내한다.
    }
  }

  Future<void> _showRecent() async {
    setState(() => _showCalendar = false);
    widget.onRangeChanged(widget.recentFrom, widget.recentTo);
    try {
      await AppScope.of(context).loadBusinessMemberDetail(
        member.id,
        force: true,
        from: widget.recentFrom,
        to: widget.recentTo,
      );
    } catch (_) {
      // 기존 조회 오류와 다시 시도로 안내한다.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = AppScope.of(context);
    if (detail == null && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (detail == null && error != null) {
      return RefreshIndicator(
        onRefresh: () => state.loadBusinessMemberDetail(member.id, force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: SetflowInsets.pageListTight,
          children: [
            EmptyState(
              icon: Icons.cloud_off_outlined,
              title: '회원 기록을 불러오지 못했어요',
              message: '서버 연결을 확인한 뒤 다시 시도해주세요.',
              actionLabel: '다시 시도',
              onAction: () {
                state
                    .loadBusinessMemberDetail(member.id, force: true)
                    .then<void>((_) {}, onError: (_) {});
              },
            ),
          ],
        ),
      );
    }
    if (member.userId == null) {
      return const EmptyState(
        icon: Icons.link_off_rounded,
        title: '앱 계정이 연결되지 않았어요',
        message: '회원이 센터 초대를 수락해 Setflow 계정과 연결되면 기록을 볼 수 있어요.',
      );
    }
    if (detail == null || !detail!.canReadWorkouts) {
      return const EmptyState(
        icon: Icons.lock_person_outlined,
        title: '운동 기록 공유가 꺼져 있어요',
        message: '회원이 개인정보 설정에서 운동 기록 공유에 동의하면 담당자에게만 표시됩니다.',
      );
    }
    final sessions = [...detail!.sessions]
      ..sort((left, right) => right.date.compareTo(left.date));
    return RefreshIndicator(
      onRefresh: () => state.loadBusinessMemberDetail(member.id, force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SetflowInsets.pageListTight,
        children: [
          Wrap(
            spacing: SetflowSpacing.sm,
            runSpacing: SetflowSpacing.xs,
            children: [
              TextButton.icon(
                key: const ValueKey('member-records-recent'),
                onPressed: loading ? null : _showRecent,
                icon: const Icon(SetflowIcons.pastDays),
                label: const Text('최근 운동'),
              ),
              TextButton.icon(
                key: const ValueKey('member-records-calendar'),
                onPressed: loading
                    ? null
                    : () => setState(() => _showCalendar = !_showCalendar),
                icon: const Icon(SetflowIcons.calendar),
                label: Text(_showCalendar ? '달력 접기' : '날짜로 찾기'),
              ),
            ],
          ),
          Text(
            '조회 기간 ${DateFormat('yyyy.MM.dd').format(widget.from)} ~ ${DateFormat('yyyy.MM.dd').format(widget.to)}',
            key: const ValueKey('member-records-period'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: SetflowSpacing.md),
          if (_showCalendar)
            WorkoutHistoryCalendar(
              days: [
                for (final session in sessions)
                  WorkoutHistoryDay.business(session),
              ],
              initialDate: _selectedHistoryDate,
              onDateSelected: (date) => _selectedHistoryDate = date,
              onMonthChanged: _loadMonth,
              recordBuilder: (date) => Column(
                children: [
                  for (final session in sessions.where(
                    (session) => DateUtils.isSameDay(session.date, date),
                  )) ...[
                    _LiveSessionCard(
                      key: ValueKey(session.id),
                      memberId: member.id,
                      session: session,
                    ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                ],
              ),
            )
          else if (sessions.isEmpty)
            const EmptyState(
              icon: SetflowIcons.pastDays,
              title: '이 기간의 운동 기록이 없어요',
              message: '날짜로 찾기에서 다른 달의 공유된 기록을 확인해보세요.',
            )
          else
            for (final session in sessions) ...[
              _LiveSessionCard(
                key: ValueKey(session.id),
                memberId: member.id,
                session: session,
              ),
              const SizedBox(height: SetflowSpacing.md),
            ],
        ],
      ),
    );
  }
}

class _LiveSessionCard extends StatefulWidget {
  const _LiveSessionCard({
    required this.memberId,
    required this.session,
    this.startWithFeedback = false,
    super.key,
  });

  final String memberId;
  final BusinessWorkoutSession session;
  final bool startWithFeedback;

  @override
  State<_LiveSessionCard> createState() => _LiveSessionCardState();
}

class _LiveSessionCardState extends State<_LiveSessionCard> {
  final _feedbackController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _expanded = false;
  late bool _writingFeedback;

  @override
  void initState() {
    super.initState();
    _writingFeedback = widget.startWithFeedback;
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final session = widget.session;
    final sending = state.isSendingSessionFeedback(session.id);
    final sessionUnit =
        session.exercises.any((exercise) => exercise.targetMuscle == '유산소')
        ? '항목'
        : '세트';
    return SetflowCard(
      key: ValueKey('member-session-${session.id}'),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => _expanded = !_expanded),
            title: Text(
              '${DateFormat('yyyy.MM.dd').format(session.date)} (${_weekdayLabel(session.date)})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(
              '${session.exercises.length}개 종목 · '
              '${session.completedSets}/${session.totalSets}$sessionUnit · '
              '${_businessSessionActivityText(session)}',
            ),
            trailing: Icon(
              _expanded ? SetflowIcons.collapse : SetflowIcons.expand,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_expanded)
                  Text(
                    session.exercises
                        .map((exercise) => exercise.name)
                        .join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                TextButton.icon(
                  key: ValueKey('session-feedback-open-${session.id}'),
                  icon: const Icon(SetflowIcons.comment),
                  label: Text(_writingFeedback ? '입력 접기' : '피드백 쓰기'),
                  onPressed: () =>
                      setState(() => _writingFeedback = !_writingFeedback),
                ),
              ],
            ),
          ),
          if (_writingFeedback)
            Padding(
              padding: const EdgeInsets.all(SetflowSpacing.md),
              child: _feedbackEditor(context, state, session, sending),
            ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(SetflowSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final exercise in session.exercises) ...[
                    Text(
                      exercise.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (exercise.targetMuscle != null)
                      Text(
                        exercise.targetMuscle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: SetflowSpacing.xs),
                    for (final set in exercise.sets)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '${set.setNumber}${exercise.targetMuscle == '유산소' ? '구간' : '세트'}',
                              ),
                            ),
                            Expanded(
                              child: Text(
                                exercise.targetMuscle == '유산소'
                                    ? _businessCardioSetText(set)
                                    : '${set.weight.toStringAsFixed(set.weight % 1 == 0 ? 0 : 1)}kg × ${set.reps}회',
                              ),
                            ),
                            if (exercise.targetMuscle != '유산소')
                              Text('${set.restSeconds}초'),
                            const SizedBox(width: SetflowSpacing.xs),
                            Icon(
                              set.completed
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: set.completed
                                  ? context.setflowColors.success
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: SetflowSpacing.md),
                  ],
                  if (session.feedbacks.isNotEmpty) ...[
                    const Divider(),
                    for (final feedback in session.feedbacks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                        title: Text(feedback.authorName),
                        subtitle: Text(feedback.text),
                        trailing: Text(
                          DateFormat('MM.dd').format(feedback.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _feedbackEditor(
    BuildContext context,
    AppState state,
    BusinessWorkoutSession session,
    bool sending,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${DateFormat('yyyy.MM.dd').format(session.date)} 운동에 보낼 피드백',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: SetflowSpacing.sm),
      Form(
        key: _formKey,
        child: AppTextField(
          key: ValueKey('session-feedback-field-${session.id}'),
          controller: _feedbackController,
          enabled: !sending,
          maxLines: 3,
          label: '세션 피드백',
          hint: '회원에게 전달할 피드백을 작성하세요.',
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return '피드백 내용을 입력해주세요.';
            if (text.length < 5) return '피드백을 5자 이상 입력해주세요.';
            if (text.length > 2000) return '피드백은 2,000자 이하로 입력해주세요.';
            return null;
          },
        ),
      ),
      const SizedBox(height: SetflowSpacing.sm),
      AppButton(
        key: ValueKey('session-feedback-submit-${session.id}'),
        label: sending ? '전송 중...' : '피드백 보내기',
        icon: SetflowIcons.sendComment,
        onPressed: sending
            ? null
            : () async {
                if (!(_formKey.currentState?.validate() ?? false)) return;
                try {
                  await state.sendBusinessSessionFeedback(
                    memberId: widget.memberId,
                    sessionId: session.id,
                    text: _feedbackController.text,
                  );
                  if (!mounted) return;
                  _feedbackController.clear();
                  AppSnackbar.success(this.context, '피드백을 전송했어요.');
                } catch (_) {
                  if (mounted) {
                    AppSnackbar.error(this.context, '피드백을 전송하지 못했어요.');
                  }
                }
              },
      ),
    ],
  );
}

class _LiveMemberFeedbackTab extends StatelessWidget {
  const _LiveMemberFeedbackTab({
    required this.member,
    required this.detail,
    required this.from,
    required this.to,
    required this.loading,
    required this.error,
  });

  final BusinessMember member;
  final BusinessMemberDetail? detail;
  final DateTime from;
  final DateTime to;
  final bool loading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return const EmptyState(
        icon: SetflowIcons.cloudUnavailable,
        title: '피드백을 불러오지 못했어요',
        message: '운동 기록 탭에서 다시 시도해주세요.',
      );
    }
    final feedbacks =
        <({BusinessWorkoutSession session, BusinessSessionFeedback feedback})>[
          for (final session in detail?.sessions ?? <BusinessWorkoutSession>[])
            for (final feedback in session.feedbacks)
              (session: session, feedback: feedback),
        ];
    feedbacks.sort(
      (left, right) =>
          right.feedback.createdAt.compareTo(left.feedback.createdAt),
    );
    if (detail == null || !detail!.canReadWorkouts) {
      return const EmptyState(
        icon: Icons.lock_person_outlined,
        title: '표시할 피드백이 없어요',
        message: '운동 기록 공유가 켜지면 세션별 피드백을 확인할 수 있어요.',
      );
    }
    return ListView(
      padding: SetflowInsets.pageListTight,
      children: [
        Text(
          '조회 기간 ${DateFormat('yyyy.MM.dd').format(from)} ~ ${DateFormat('yyyy.MM.dd').format(to)}',
          key: const ValueKey('member-feedback-period'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: SetflowSpacing.md),
        if (feedbacks.isEmpty)
          const EmptyState(
            icon: SetflowIcons.comment,
            title: '이 기간에 보낸 피드백이 없어요',
            message: '운동 기록의 피드백 쓰기에서 해당 운동에 바로 전달할 수 있어요.',
          ),
        for (final item in feedbacks) ...[
          SetflowCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _MemberSessionFeedbackScreen(
                    member: member,
                    sessionId: item.session.id,
                  ),
                ),
              ),
              title: Text(
                '${DateFormat('yyyy.MM.dd').format(item.session.date)} 운동',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.session.exercises
                        .map((exercise) => exercise.name)
                        .join(' · '),
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  Text(item.feedback.text),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    '${item.feedback.authorName} · ${DateFormat('MM.dd').format(item.feedback.createdAt)} 전송',
                  ),
                ],
              ),
              trailing: const Icon(SetflowIcons.forward),
            ),
          ),
          const SizedBox(height: SetflowSpacing.sm),
        ],
      ],
    );
  }
}

class _MemberSessionFeedbackScreen extends StatelessWidget {
  const _MemberSessionFeedbackScreen({
    required this.member,
    required this.sessionId,
  });

  final BusinessMember member;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final detail = state.businessMemberDetail(member.id);
    final session = detail?.canReadWorkouts == true
        ? detail!.sessions
              .where((session) => session.id == sessionId)
              .firstOrNull
        : null;
    return Scaffold(
      appBar: AppBar(title: Text('${member.name} 운동 피드백')),
      body: state.isBusinessMemberDetailLoading(member.id)
          ? const Center(child: CircularProgressIndicator())
          : session == null
          ? const EmptyState(
              icon: SetflowIcons.account,
              title: '운동 기록을 확인할 수 없어요',
              message: '공유 상태와 조회 기간을 다시 확인해주세요.',
            )
          : ListView(
              padding: SetflowInsets.pageList,
              children: [
                _LiveSessionCard(
                  memberId: member.id,
                  session: session,
                  startWithFeedback: true,
                ),
              ],
            ),
    );
  }
}

class _MemberFeedbackTab extends StatelessWidget {
  const _MemberFeedbackTab({required this.memberName});

  final String memberName;

  @override
  Widget build(BuildContext context) {
    final facts = AppScope.of(context).dashboardFor(UserRole.gym).facts;
    final feedback = facts['memberFeedback.$memberName'];
    final trainer = facts['memberAssignment.$memberName'] ?? '미배정';
    return ListView(
      padding: SetflowInsets.pageListTight,
      children: [
        Container(
          padding: const EdgeInsets.all(SetflowSpacing.md),
          decoration: BoxDecoration(
            color: context.setflowColors.purple.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(SetflowRadii.md),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, color: context.setflowColors.purple),
              const SizedBox(width: SetflowSpacing.sm),
              const Expanded(
                child: Text(
                  '센터에는 회원이 공유에 동의한 기록만 표시됩니다.',
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SetflowSpacing.lg),
        SetflowCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: const Text('담당자'),
                trailing: Text(
                  trainer,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: const Text('최근 피드백'),
                subtitle: Text(feedback ?? '아직 작성된 피드백이 없어요.'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberSummaryHeader extends StatelessWidget {
  const _MemberSummaryHeader({
    required this.member,
    required this.latestSession,
    this.liveDetail,
  });

  final BusinessMember member;
  final WorkoutSession? latestSession;
  final BusinessMemberDetail? liveDetail;

  @override
  Widget build(BuildContext context) {
    final liveLatestSession = liveDetail?.sessions.isNotEmpty == true
        ? liveDetail!.sessions.first
        : null;
    final hasRecentResistance = liveLatestSession != null
        ? liveLatestSession.exercises.any(
            (exercise) => exercise.targetMuscle != '유산소',
          )
        : latestSession?.hasResistance ?? false;
    final hasRecentCardio = liveLatestSession != null
        ? liveLatestSession.exercises.any(
            (exercise) => exercise.targetMuscle == '유산소',
          )
        : latestSession?.hasCardio ?? false;
    final recentVolumeKg =
        liveLatestSession?.totalVolumeKg ?? latestSession?.volume ?? 0;
    final recentCardioSeconds =
        liveLatestSession?.cardioDurationSeconds ??
        latestSession?.cardioDurationSeconds ??
        0;
    final recentMetricLabel = hasRecentResistance && hasRecentCardio
        ? '최근 근력·유산소'
        : hasRecentCardio
        ? '최근 유산소'
        : '최근 볼륨';
    final cardioOnly = hasRecentCardio && !hasRecentResistance;
    final recentMetricValue = cardioOnly
        ? (recentCardioSeconds / 60).round().toString()
        : (recentVolumeKg / 1000).toStringAsFixed(1);
    final recentMetricSuffix = cardioOnly
        ? '분'
        : hasRecentCardio
        ? 't · ${(recentCardioSeconds / 60).round()}분 유산소'
        : 't';
    return Column(
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: SetflowColors.primary.withValues(alpha: .2),
              child: Text(
                member.name.characters.first,
                style: const TextStyle(
                  fontSize: SetflowFontSize.headline,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: SetflowSpacing.md2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(
                      fontSize: SetflowFontSize.headline,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${member.goal ?? '목표 미등록'} · 마지막 기록 ${_relativeDate(member.lastActivityAt)}',
                    style: TextStyle(
                      fontSize: SetflowFontSize.caption,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.lg),
        Row(
          children: [
            MetricCard(
              label: '완료율',
              value: '${member.completionRate.round().clamp(0, 100)}',
              suffix: '%',
              icon: Icons.check_circle_outline,
              tint: member.completionRate >= 80
                  ? context.setflowColors.success
                  : context.setflowColors.orange,
            ),
            const SizedBox(width: SetflowSpacing.sm2),
            MetricCard(
              label: recentMetricLabel,
              value: recentMetricValue,
              suffix: recentMetricSuffix,
              icon: hasRecentCardio && !hasRecentResistance
                  ? Icons.directions_run_rounded
                  : Icons.monitor_weight_outlined,
              tint: context.setflowColors.blue,
            ),
          ],
        ),
      ],
    );
  }
}

String _relativeDate(DateTime? date) {
  if (date == null) return '없음';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = today.difference(target).inDays;
  if (days <= 0) return '오늘';
  if (days == 1) return '어제';
  return '$days일 전';
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
              tooltip: '이전',
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat('yyyy.MM').format(month),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: SetflowFontSize.title,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month + 1)),
              tooltip: '다음',
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
        const SizedBox(height: SetflowSpacing.lg),
        const SectionTitle('최근 운동 기록'),
        const SizedBox(height: SetflowSpacing.sm),
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
                          const SizedBox(height: SetflowSpacing.xs),
                          Text(
                            '${session.exercises.length}개 종목 · '
                            '${session.completedSets}/${session.totalSets}'
                            '${session.hasCardio ? '항목' : '세트'} · '
                            '${_workoutSessionActivityText(session)}',
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
                    Text(
                      '${(session.completion * 100).round()}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: session.completion >= .8
                            ? context.setflowColors.success
                            : context.setflowColors.orange,
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
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
          // 라임 테두리는 흰 칸 위에서 사라진다 — 읽는 브랜드(secondary).
          border: isToday
              ? Border.all(
                  color: Theme.of(context).colorScheme.secondary,
                  width: 1.4,
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: const TextStyle(fontSize: SetflowFontSize.caption),
            ),
            const SizedBox(height: SetflowSpacing.xxs),
            if (session != null)
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: session!.completion >= .8
                      ? context.setflowColors.success
                      : context.setflowColors.orange,
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
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        8,
        SetflowSpacing.gutter,
        28,
      ),
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
                    borderRadius: BorderRadius.circular(SetflowRadii.xs),
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
                          fontSize: SetflowFontSize.bodyLarge,
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.xxs),
                      Text(
                        routine.description,
                        style: TextStyle(
                          fontSize: SetflowFontSize.caption,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        '${routine.level} · ${routine.exercises.length}개 종목',
                        style: const TextStyle(
                          fontSize: SetflowFontSize.small,
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
      padding: const EdgeInsets.fromLTRB(
        SetflowSpacing.gutter,
        8,
        SetflowSpacing.gutter,
        28,
      ),
      itemCount: _posts.length,
      itemBuilder: (_, index) {
        final post = _posts[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SetflowCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.$1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: SetflowFontSize.bodyLarge,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.xs),
                Text(
                  post.$2,
                  style: TextStyle(
                    fontSize: SetflowFontSize.caption,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: SetflowSpacing.sm2),
                Row(
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Text(
                      '${post.$3}',
                      style: const TextStyle(fontSize: SetflowFontSize.caption),
                    ),
                    const SizedBox(width: SetflowSpacing.md2),
                    Icon(
                      Icons.mode_comment_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: SetflowSpacing.xs),
                    Text(
                      '${post.$4}',
                      style: const TextStyle(fontSize: SetflowFontSize.caption),
                    ),
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
    return ListView.separated(
      padding: SetflowInsets.pageListTight,
      itemCount: exercises.length,
      separatorBuilder: (_, _) => const SizedBox(height: SetflowSpacing.sm),
      itemBuilder: (_, index) {
        final exercise = exercises[index];
        return SetflowCard(
          padding: const EdgeInsets.all(SetflowSpacing.md),
          child: Row(
            children: [
              ExerciseMuscleMap.forExercise(
                exercise: exercise,
                size: 48,
                decorative: true,
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: SetflowFontSize.caption,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      exerciseMuscleSummaryKo(exercise),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: SetflowFontSize.tiny,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
