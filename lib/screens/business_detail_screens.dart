import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum BusinessTool {
  calendar,
  refunds,
  badges,
  contentReports,
  sanctions,
  minorAlerts,
  ranking,
  ocr,
  plans,
  keywords,
  logs,
}

class BusinessToolScreen extends StatefulWidget {
  const BusinessToolScreen({required this.tool, required this.role, super.key});
  final BusinessTool tool;
  final UserRole role;

  @override
  State<BusinessToolScreen> createState() => _BusinessToolScreenState();
}

class _BusinessToolScreenState extends State<BusinessToolScreen> {
  bool first = true;
  double slider = 72;
  final keywords = <String>['무조건', '기적', '100% 보장', '한 달 완성'];

  @override
  void initState() {
    super.initState();
    if (widget.tool == BusinessTool.calendar) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          await AppScope.of(context).refreshCoachingSchedules();
        } catch (_) {
          // The calendar renders the repository error and retry action.
        }
      });
    }
  }

  String get title => switch (widget.tool) {
    BusinessTool.calendar => '코칭 캘린더',
    BusinessTool.refunds => '환불 및 미정산 내역',
    BusinessTool.badges => '배지 발급 관리',
    BusinessTool.contentReports => '커뮤니티 신고 큐',
    BusinessTool.sanctions => '제재 이력',
    BusinessTool.minorAlerts => '미성년자 위험 신호',
    BusinessTool.ranking => '랭킹 알고리즘 설정',
    BusinessTool.ocr => 'OCR 모델 및 한도',
    BusinessTool.plans => '구독 플랜 정책',
    BusinessTool.keywords => '금지 키워드 관리',
    BusinessTool.logs => '시스템 로그',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: _content(context),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    return switch (widget.tool) {
      BusinessTool.calendar => _calendar(context),
      BusinessTool.refunds => _refunds(context),
      BusinessTool.badges => _badges(context),
      BusinessTool.contentReports => _reports(context),
      BusinessTool.sanctions => _sanctions(),
      BusinessTool.minorAlerts => _minorAlerts(context),
      BusinessTool.ranking => _ranking(context),
      BusinessTool.ocr => _ocr(context),
      BusinessTool.plans => _plans(context),
      BusinessTool.keywords => _keywords(context),
      BusinessTool.logs => _logs(),
    };
  }

  List<Widget> _calendar(BuildContext context) {
    final state = AppScope.of(context);
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day - now.weekday + 1,
    );
    final schedules = state.coachingSchedules;
    final canCreate = widget.role == UserRole.trainer;
    final widgets = <Widget>[
      SetflowCard(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (index) {
            final day = startOfWeek.add(Duration(days: index));
            final count = schedules
                .where((item) => DateUtils.isSameDay(item.date, day))
                .length;
            return _Day(label: '월화수목금토일'[index], count: count);
          }),
        ),
      ),
      const SizedBox(height: SetflowSpacing.xl),
      Row(
        children: [
          const Expanded(child: SectionTitle('코칭 일정')),
          IconButton(
            key: const Key('coaching-schedule-refresh'),
            tooltip: '일정 새로고침',
            onPressed: state.coachingSchedulesLoading
                ? null
                : () => _refreshCalendar(context),
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (canCreate)
            FilledButton.icon(
              key: const Key('coaching-schedule-create'),
              onPressed: state.isCreatingCoachingSchedule
                  ? null
                  : () => _showCreateScheduleDialog(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('일정 추가'),
            ),
        ],
      ),
      const SizedBox(height: SetflowSpacing.sm),
    ];

    if (state.coachingSchedulesLoading && schedules.isEmpty) {
      widgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return widgets;
    }
    if (state.coachingSchedulesError != null && schedules.isEmpty) {
      widgets.add(
        _ScheduleMessageCard(
          icon: Icons.cloud_off_outlined,
          title: '일정을 불러오지 못했어요',
          subtitle: '서버 연결을 확인하고 다시 시도해주세요.',
          actionLabel: '다시 시도',
          onAction: () => _refreshCalendar(context),
        ),
      );
      return widgets;
    }
    if (schedules.isEmpty) {
      widgets.add(
        _ScheduleMessageCard(
          icon: Icons.event_available_outlined,
          title: '등록된 코칭 일정이 없어요',
          subtitle: canCreate
              ? '회원과의 다음 코칭 일정을 추가해보세요.'
              : '트레이너가 등록한 일정이 여기에 표시됩니다.',
          actionLabel: canCreate ? '첫 일정 추가' : null,
          onAction: canCreate ? () => _showCreateScheduleDialog(context) : null,
        ),
      );
      return widgets;
    }

    DateTime? previousDate;
    for (final schedule in schedules) {
      if (previousDate == null ||
          !DateUtils.isSameDay(previousDate, schedule.date)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              _scheduleDateLabel(schedule.date),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        );
        previousDate = schedule.date;
      }
      widgets.add(_scheduleTile(context, schedule));
    }
    return widgets;
  }

  Widget _scheduleTile(
    BuildContext context,
    BusinessCoachingSchedule schedule,
  ) {
    final state = AppScope.of(context);
    final profile = state.businessWorkspace?.profile;
    final canManage =
        widget.role == UserRole.trainer &&
        profile is TrainerBusinessProfile &&
        profile.id == schedule.trainerId;
    final pending =
        state.isUpdatingCoachingSchedule(schedule.id) ||
        state.isDeletingCoachingSchedule(schedule.id);
    final counterpart =
        schedule.memberName ??
        schedule.gymName ??
        (widget.role == UserRole.trainer
            ? '개인 일정'
            : schedule.trainerName ?? '담당 트레이너');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SetflowCard(
        child: Row(
          children: [
            Icon(
              schedule.isCompleted
                  ? Icons.check_rounded
                  : Icons.schedule_rounded,
              color: schedule.isCompleted
                  ? context.setflowColors.success
                  : SetflowColors.ink,
            ),
            const SizedBox(width: SetflowSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      decoration: schedule.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.xs),
                  Text(
                    '${_scheduleTime(schedule.startMinutes)}–${_scheduleTime(schedule.endMinutes)} · $counterpart',
                    style: TextStyle(
                      fontSize: SetflowFontSize.caption,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (pending)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (canManage) ...[
              Checkbox(
                key: Key('coaching-schedule-complete-${schedule.id}'),
                value: schedule.isCompleted,
                onChanged: (value) =>
                    _toggleSchedule(context, schedule, value ?? false),
              ),
              IconButton(
                key: Key('coaching-schedule-delete-${schedule.id}'),
                tooltip: '일정 삭제',
                onPressed: () => _deleteSchedule(context, schedule),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ] else
              Icon(
                schedule.isCompleted
                    ? Icons.check_circle_rounded
                    : Icons.lock_outline_rounded,
                color: schedule.isCompleted
                    ? context.setflowColors.success
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshCalendar(BuildContext context) async {
    try {
      await AppScope.of(context).refreshCoachingSchedules();
    } catch (_) {
      if (context.mounted) showMessage(context, '일정을 불러오지 못했습니다.');
    }
  }

  Future<void> _toggleSchedule(
    BuildContext context,
    BusinessCoachingSchedule schedule,
    bool completed,
  ) async {
    try {
      await AppScope.of(
        context,
      ).setCoachingScheduleCompleted(schedule.id, completed: completed);
      if (context.mounted) {
        showMessage(context, completed ? '일정을 완료했습니다.' : '완료를 취소했습니다.');
      }
    } catch (_) {
      if (context.mounted) showMessage(context, '완료 상태를 저장하지 못했습니다.');
    }
  }

  Future<void> _deleteSchedule(
    BuildContext context,
    BusinessCoachingSchedule schedule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text('‘${schedule.title}’ 일정을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await AppScope.of(context).deleteCoachingSchedule(schedule.id);
      if (context.mounted) showMessage(context, '일정을 삭제했습니다.');
    } catch (_) {
      if (context.mounted) showMessage(context, '일정을 삭제하지 못했습니다.');
    }
  }

  Future<void> _showCreateScheduleDialog(BuildContext context) async {
    final state = AppScope.of(context);
    final titleController = TextEditingController();
    var date = DateTime.now();
    var start = const TimeOfDay(hour: 10, minute: 0);
    var end = const TimeOfDay(hour: 11, minute: 0);
    String? memberId;
    final linkedMembers = state.businessMembers
        .where((member) => member.userId != null)
        .toList(growable: false);
    Future<void>? dialogCompleted;

    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        dialogCompleted ??= ModalRoute.of(dialogContext)?.completed;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('코칭 일정 추가'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('coaching-schedule-title'),
                    controller: titleController,
                    autofocus: true,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: '일정 제목',
                      hintText: '예: 하체 PT · 4주차',
                    ),
                  ),
                  const SizedBox(height: SetflowSpacing.sm2),
                  DropdownButtonFormField<String?>(
                    key: const Key('coaching-schedule-member'),
                    initialValue: memberId,
                    decoration: const InputDecoration(labelText: '회원'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('개인 일정'),
                      ),
                      for (final member in linkedMembers)
                        DropdownMenuItem<String?>(
                          value: member.id,
                          child: Text(member.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => memberId = value),
                  ),
                  const SizedBox(height: SetflowSpacing.sm2),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('날짜'),
                    subtitle: Text(_scheduleDateLabel(date)),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: date,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 365),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setDialogState(() => date = picked);
                      }
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('시작'),
                          subtitle: Text(start.format(dialogContext)),
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: dialogContext,
                              initialTime: start,
                            );
                            if (picked != null) {
                              setDialogState(() => start = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: SetflowSpacing.md),
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('종료'),
                          subtitle: Text(end.format(dialogContext)),
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: dialogContext,
                              initialTime: end,
                            );
                            if (picked != null) {
                              setDialogState(() => end = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                key: const Key('coaching-schedule-save'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('저장'),
              ),
            ],
          ),
        );
      },
    );
    final title = titleController.text;
    await dialogCompleted;
    titleController.dispose();
    if (shouldCreate != true || !context.mounted) return;
    try {
      await AppScope.of(context).createCoachingSchedule(
        title: title,
        date: date,
        startMinutes: start.hour * 60 + start.minute,
        endMinutes: end.hour * 60 + end.minute,
        memberId: memberId,
      );
      if (context.mounted) showMessage(context, '코칭 일정을 추가했습니다.');
    } catch (error) {
      if (context.mounted) {
        showMessage(context, switch (error) {
          CoachingScheduleConflictException() => error.toString(),
          ArgumentError() => error.message?.toString() ?? '입력값을 확인해주세요.',
          _ => '일정을 저장하지 못했습니다. 잠시 후 다시 시도해주세요.',
        });
      }
    }
  }

  List<Widget> _refunds(BuildContext context) => [
    Row(
      children: [
        MetricCard(
          label: '미정산',
          value: '1.28',
          suffix: '백만원',
          icon: Icons.hourglass_bottom,
          tint: context.setflowColors.orange,
        ),
        SizedBox(width: SetflowSpacing.sm2),
        MetricCard(
          label: '환불 처리',
          value: '3',
          suffix: '건',
          icon: Icons.replay,
          tint: context.setflowColors.error,
        ),
      ],
    ),
    const SizedBox(height: SetflowSpacing.xxl),
    for (final item in const [
      ('박민지', '중도 해지', '검토 중'),
      ('이준호', '결제 오류', '환불 완료'),
      ('최서연', '서비스 불만족', '분쟁 중'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SetflowCard(
          child: Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: context.setflowColors.error,
              ),
              const SizedBox(width: SetflowSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: SetflowFontSize.small,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                item.$3,
                style: TextStyle(
                  fontSize: SetflowFontSize.small,
                  fontWeight: SetflowWeight.medium,
                  color: context.setflowColors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _badges(BuildContext context) => [
    const TextField(
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: '사용자 검색',
      ),
    ),
    const SizedBox(height: SetflowSpacing.xl),
    for (final item in const [
      ('김코치', '국가공인 · 사업자', true),
      ('박트레이너', '민간자격', true),
      ('이코치', '갱신 필요', false),
    ])
      SwitchListTile(
        secondary: CircleAvatar(child: Text(item.$1.characters.first)),
        title: Text(
          item.$1,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(item.$2),
        value: item.$3,
        onChanged: (_) => showMessage(context, '${item.$1} 배지 상태를 변경했습니다.'),
      ),
  ];

  List<Widget> _reports(BuildContext context) => [
    for (final item in const [
      ('Red', '불법 약물 판매 의심', '38분 남음'),
      ('Orange', '과도한 비방 표현', '8시간 남음'),
      ('Yellow', '부적절한 홍보', '2일 남음'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SetflowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _reportColor(item.$1).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(SetflowRadii.xs),
                    ),
                    child: Text(
                      item.$1,
                      style: TextStyle(
                        color: _reportColor(item.$1),
                        fontSize: SetflowFontSize.tiny,
                        fontWeight: SetflowWeight.medium,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    item.$3,
                    style: TextStyle(
                      fontSize: SetflowFontSize.tiny,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SetflowSpacing.md),
              Text(
                item.$2,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: SetflowSpacing.md),
              OutlinedButton(
                onPressed: () => showMessage(context, '신고 상세 검토를 시작했습니다.'),
                child: const Text('검토하기'),
              ),
            ],
          ),
        ),
      ),
  ];

  Color _reportColor(String grade) => grade == 'Red'
      ? context.setflowColors.error
      : grade == 'Orange'
      ? context.setflowColors.orange
      : SetflowColors.primary;

  List<Widget> _sanctions() => [
    for (final item in const [
      ('운동초보', '경고', '부적절한 댓글'),
      ('다이어터', '7일 정지', '반복 신고'),
      ('헬스왕', '30일 정지', '금지 콘텐츠'),
    ])
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.gavel_outlined, color: context.setflowColors.error),
        title: Text(
          item.$1,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(item.$3),
        trailing: Text(
          item.$2,
          style: TextStyle(
            fontSize: SetflowFontSize.small,
            color: context.setflowColors.error,
            fontWeight: SetflowWeight.medium,
          ),
        ),
      ),
  ];

  List<Widget> _minorAlerts(BuildContext context) => [
    SetflowCard(
      child: Row(
        children: [
          Icon(Icons.child_care, color: context.setflowColors.orange),
          SizedBox(width: SetflowSpacing.md),
          Expanded(
            child: Text(
              '위험 행동 패턴은 최소 수집 원칙으로 탐지하며 운영자 검토 전 자동 제재하지 않습니다.',
              style: TextStyle(fontSize: SetflowFontSize.caption, height: 1.45),
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: SetflowSpacing.lg),
    for (final item in const [
      ('user_2481', '과도한 체중 감량 목표 반복'),
      ('user_5130', '심야 운동 7일 연속'),
    ])
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          item.$1,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(item.$2),
        trailing: OutlinedButton(
          onPressed: () => showMessage(context, '계정 안전 검토를 시작했습니다.'),
          child: const Text('검토'),
        ),
      ),
  ];

  List<Widget> _ranking(BuildContext context) => [
    const SetflowCard(
      child: Text(
        'Final Score = Base Score × Time Decay − Penalty',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    const SizedBox(height: SetflowSpacing.xl),
    Text('조회 가중치 ${slider.toInt()}'),
    Slider(
      value: slider,
      min: 0,
      max: 100,
      onChanged: (value) => setState(() => slider = value),
    ),
    const ListTile(title: Text('상담 가중치'), trailing: Text('40')),
    const ListTile(title: Text('구매 가중치'), trailing: Text('80')),
    const ListTile(title: Text('72시간 미응답 패널티'), trailing: Text('-100')),
    const SizedBox(height: SetflowSpacing.xl),
    PrimaryButton(
      label: '파라미터 저장',
      onPressed: () => showMessage(context, '변경 이력을 남기고 랭킹 재계산을 예약했습니다.'),
    ),
  ];

  List<Widget> _ocr(BuildContext context) => [
    const ListTile(
      title: Text('현재 비전 모델'),
      subtitle: Text('Gemini Flash'),
      trailing: Icon(Icons.chevron_right),
    ),
    ListTile(
      title: const Text('월간 OCR 한도'),
      subtitle: Slider(
        value: slider.clamp(10, 100),
        min: 10,
        max: 100,
        divisions: 9,
        onChanged: (value) => setState(() => slider = value),
      ),
      trailing: Text('${slider.clamp(10, 100).toInt()}건'),
    ),
    SwitchListTile(
      title: const Text('낮은 신뢰도 필드 경고'),
      value: first,
      onChanged: (value) => setState(() => first = value),
    ),
    const SizedBox(height: SetflowSpacing.xl),
    PrimaryButton(
      label: 'OCR 설정 저장',
      onPressed: () => showMessage(context, '(데모) OCR 설정은 아직 저장되지 않아요.'),
    ),
  ];

  List<Widget> _plans(BuildContext context) => [
    for (final item in const [
      ('일반 무료', r'$0', '루틴 4개'),
      ('일반 프리미엄', r'$3.99', '루틴 무제한 · OCR'),
      ('트레이너 프로', r'$39', '회원 4~50명'),
      ('엔터프라이즈', '구간제', '회원 51~500명+'),
    ])
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
                      item.$1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.$3,
                      style: TextStyle(
                        fontSize: SetflowFontSize.small,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                item.$2,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              IconButton(
                onPressed: () =>
                    showMessage(context, '${item.$1} 정책 편집을 열었습니다.'),
                tooltip: '수정',
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _keywords(BuildContext context) => [
    TextField(
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) setState(() => keywords.add(value.trim()));
      },
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.add),
        hintText: '키워드 입력 후 Enter',
      ),
    ),
    const SizedBox(height: SetflowSpacing.xl),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keywords
          .map(
            (item) => InputChip(
              label: Text(item),
              onDeleted: () => setState(() => keywords.remove(item)),
            ),
          )
          .toList(),
    ),
  ];

  List<Widget> _logs() => [
    Row(
      children: [
        MetricCard(
          label: '업타임',
          value: '99.98',
          suffix: '%',
          icon: Icons.cloud_done_outlined,
          tint: context.setflowColors.success,
        ),
        SizedBox(width: SetflowSpacing.sm2),
        MetricCard(
          label: '오류율',
          value: '0.02',
          suffix: '%',
          icon: Icons.error_outline,
          tint: context.setflowColors.error,
        ),
      ],
    ),
    const SizedBox(height: SetflowSpacing.xxl),
    for (final item in const [
      ('08:21:32', 'INFO', '정산 배치 완료 · 284건'),
      ('08:18:05', 'WARN', 'OCR 응답 지연 · 1.8초'),
      ('08:02:44', 'INFO', '랭킹 재계산 완료'),
    ])
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Text(
          item.$1,
          style: const TextStyle(
            fontSize: SetflowFontSize.tiny,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        title: Text(
          item.$3,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        trailing: Text(
          item.$2,
          style: TextStyle(
            fontSize: SetflowFontSize.tiny,
            fontWeight: SetflowWeight.medium,
            color: item.$2 == 'WARN'
                ? context.setflowColors.orange
                : context.setflowColors.success,
          ),
        ),
      ),
  ];
}

class _ScheduleMessageCard extends StatelessWidget {
  const _ScheduleMessageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SetflowCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            icon,
            size: 34,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: SetflowSpacing.sm2),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: SetflowSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: SetflowFontSize.caption,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: SetflowSpacing.md),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

String _scheduleDateLabel(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
}

String _scheduleTime(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _Day extends StatelessWidget {
  const _Day({required this.label, required this.count});
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: SetflowFontSize.tiny,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: SetflowSpacing.sm),
      CircleAvatar(
        radius: 18,
        backgroundColor: count > 3 ? SetflowColors.primary : SetflowColors.soft,
        // The loud state is a black fill now, so the digit has to invert.
        foregroundColor: count > 3 ? Colors.white : SetflowColors.ink,
        child: Text(
          '$count',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    ],
  );
}
