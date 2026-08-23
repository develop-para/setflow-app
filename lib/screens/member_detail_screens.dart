import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
          .loadBusinessMemberDetail(widget.member.id)
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
            ),
            _LiveMemberFeedbackTab(member: widget.member, detail: detail),
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
            _MemberLibraryTab(exercises: state.exercises),
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: _MemberSummaryHeader(
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

class _LiveMemberRecordTab extends StatelessWidget {
  const _LiveMemberRecordTab({
    required this.member,
    required this.detail,
    required this.loading,
    required this.error,
  });

  final BusinessMember member;
  final BusinessMemberDetail? detail;
  final bool loading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
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
    if (detail!.sessions.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => state.loadBusinessMemberDetail(member.id, force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: SetflowInsets.pageListTight,
          children: const [
            EmptyState(
              icon: Icons.event_busy_outlined,
              title: '공유할 운동 기록이 없어요',
              message: '회원이 운동을 저장하면 이곳에 자동으로 표시됩니다.',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => state.loadBusinessMemberDetail(member.id, force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SetflowInsets.pageListTight,
        children: [
          Container(
            padding: const EdgeInsets.all(SetflowSpacing.md),
            decoration: BoxDecoration(
              color: context.setflowColors.success.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(SetflowRadii.md),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: context.setflowColors.success,
                ),
                const SizedBox(width: SetflowSpacing.sm),
                const Expanded(
                  child: Text(
                    '회원이 공유에 동의한 운동 기록만 표시됩니다.',
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
          for (final session in detail!.sessions) ...[
            _LiveSessionCard(memberId: member.id, session: session),
            const SizedBox(height: SetflowSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _LiveSessionCard extends StatefulWidget {
  const _LiveSessionCard({required this.memberId, required this.session});

  final String memberId;
  final BusinessWorkoutSession session;

  @override
  State<_LiveSessionCard> createState() => _LiveSessionCardState();
}

class _LiveSessionCardState extends State<_LiveSessionCard> {
  final _feedbackController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _expanded = false;

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
              '${DateFormat('MM.dd').format(session.date)} (${_weekdayLabel(session.date)})',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${session.exercises.length}개 종목 · '
              '${session.completedSets}/${session.totalSets}$sessionUnit · '
              '${_businessSessionActivityText(session)}',
            ),
            trailing: Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
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
                  const Divider(),
                  Form(
                    key: _formKey,
                    child: AppTextField(
                      key: ValueKey('session-feedback-field-${session.id}'),
                      controller: _feedbackController,
                      maxLines: 3,
                      label: '세션 피드백',
                      hint: '회원에게 전달할 피드백을 작성하세요.',
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return '피드백 내용을 입력해주세요.';
                        if (text.length < 5) return '피드백을 5자 이상 입력해주세요.';
                        if (text.length > 2000) {
                          return '피드백은 2,000자 이하로 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.sm),
                  AppButton(
                    key: ValueKey('session-feedback-submit-${session.id}'),
                    label: sending ? '전송 중...' : '피드백 보내기',
                    icon: Icons.send_rounded,
                    onPressed: sending
                        ? null
                        : () async {
                            if (!(_formKey.currentState?.validate() ?? false)) {
                              return;
                            }
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
                                AppSnackbar.error(
                                  this.context,
                                  '피드백을 전송하지 못했어요.',
                                );
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveMemberFeedbackTab extends StatelessWidget {
  const _LiveMemberFeedbackTab({required this.member, required this.detail});

  final BusinessMember member;
  final BusinessMemberDetail? detail;

  @override
  Widget build(BuildContext context) {
    final feedbacks = <BusinessSessionFeedback>[
      ...?detail?.sessions.expand((session) => session.feedbacks),
    ];
    feedbacks.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    if (detail == null || !detail!.canReadWorkouts) {
      return const EmptyState(
        icon: Icons.lock_person_outlined,
        title: '표시할 피드백이 없어요',
        message: '운동 기록 공유가 켜지면 세션별 피드백을 확인할 수 있어요.',
      );
    }
    if (feedbacks.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: '아직 보낸 피드백이 없어요',
        message: '운동 기록 탭에서 세션을 열어 피드백을 작성해보세요.',
      );
    }
    return ListView.separated(
      padding: SetflowInsets.pageListTight,
      itemCount: feedbacks.length,
      separatorBuilder: (_, _) => const SizedBox(height: SetflowSpacing.sm),
      itemBuilder: (_, index) {
        final feedback = feedbacks[index];
        return SetflowCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              feedback.authorName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(feedback.text),
            trailing: Text(DateFormat('MM.dd').format(feedback.createdAt)),
          ),
        );
      },
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
            const SizedBox(width: 14),
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
                    style: const TextStyle(
                      fontSize: SetflowFontSize.caption,
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
              value: '${member.completionRate.round().clamp(0, 100)}',
              suffix: '%',
              icon: Icons.check_circle_outline,
              tint: member.completionRate >= 80
                  ? SetflowColors.green
                  : SetflowColors.orange,
            ),
            const SizedBox(width: 10),
            MetricCard(
              label: recentMetricLabel,
              value: recentMetricValue,
              suffix: recentMetricSuffix,
              icon: hasRecentCardio && !hasRecentResistance
                  ? Icons.directions_run_rounded
                  : Icons.monitor_weight_outlined,
              tint: SetflowColors.blue,
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
                            '${session.exercises.length}개 종목 · '
                            '${session.completedSets}/${session.totalSets}'
                            '${session.hasCardio ? '항목' : '세트'} · '
                            '${_workoutSessionActivityText(session)}',
                            style: const TextStyle(
                              fontSize: SetflowFontSize.caption,
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
            Text(
              '${date.day}',
              style: const TextStyle(fontSize: SetflowFontSize.caption),
            ),
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
                          fontSize: SetflowFontSize.bodyLarge,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        routine.description,
                        style: const TextStyle(
                          fontSize: SetflowFontSize.caption,
                          color: SetflowColors.secondaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
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
                const SizedBox(height: 3),
                Text(
                  post.$2,
                  style: const TextStyle(
                    fontSize: SetflowFontSize.caption,
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
                    Text(
                      '${post.$3}',
                      style: const TextStyle(fontSize: SetflowFontSize.caption),
                    ),
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.mode_comment_outlined,
                      size: 16,
                      color: SetflowColors.secondaryText,
                    ),
                    const SizedBox(width: 4),
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
                        fontSize: SetflowFontSize.caption,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      exercise.muscle,
                      style: const TextStyle(
                        fontSize: SetflowFontSize.tiny,
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
