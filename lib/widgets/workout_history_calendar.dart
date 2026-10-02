import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../data/business_repository.dart';
import '../korean_holidays.dart';
import '../theme.dart';
import '../theme/icons.dart';

/// 회원 기록의 조회용 캘린더. 기록 수정과 피드백은 각 화면이 제공한다.
class WorkoutHistoryDay {
  const WorkoutHistoryDay({
    required this.date,
    required this.muscles,
    required this.completedSets,
    required this.totalSets,
    required this.volumeKg,
    required this.cardioSeconds,
  });

  factory WorkoutHistoryDay.business(BusinessWorkoutSession session) =>
      WorkoutHistoryDay(
        date: session.date,
        muscles: [
          for (final exercise in session.exercises)
            if (exercise.targetMuscle != null) exercise.targetMuscle!,
        ],
        completedSets: session.completedSets,
        totalSets: session.totalSets,
        volumeKg: session.totalVolumeKg,
        cardioSeconds: session.cardioDurationSeconds,
      );

  factory WorkoutHistoryDay.workout(WorkoutSession session) =>
      WorkoutHistoryDay(
        date: session.date,
        muscles: [
          for (final exercise in session.exercises) exercise.template.muscle,
        ],
        completedSets: session.completedSets,
        totalSets: session.totalSets,
        volumeKg: session.volume,
        cardioSeconds: session.cardioDurationSeconds,
      );

  final DateTime date;
  final List<String> muscles;
  final int completedSets;
  final int totalSets;
  final double volumeKg;
  final int cardioSeconds;
}

class WorkoutHistoryCalendar extends StatefulWidget {
  const WorkoutHistoryCalendar({
    required this.days,
    required this.recordBuilder,
    this.onMonthChanged,
    this.initialDate,
    this.onDateSelected,
    this.loading = false,
    super.key,
  });

  final List<WorkoutHistoryDay> days;
  final Widget Function(DateTime date) recordBuilder;
  final Future<void> Function(DateTime month)? onMonthChanged;
  final DateTime? initialDate;
  final ValueChanged<DateTime>? onDateSelected;
  final bool loading;

  @override
  State<WorkoutHistoryCalendar> createState() => _WorkoutHistoryCalendarState();
}

class _WorkoutHistoryCalendarState extends State<WorkoutHistoryCalendar> {
  DateTime? _selected;
  bool _loadingMonth = false;

  @override
  void didUpdateWidget(WorkoutHistoryCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDate != oldWidget.initialDate) {
      _selected = widget.initialDate;
    }
  }

  DateTime get _selectedDate {
    if (_selected != null) return _selected!;
    if (widget.initialDate != null) {
      return DateUtils.dateOnly(widget.initialDate!);
    }
    final dates = widget.days.map((day) => day.date).toList()..sort();
    return DateUtils.dateOnly(dates.isEmpty ? DateTime.now() : dates.last);
  }

  Future<void> _select(DateTime date) async {
    final previous = _selectedDate;
    final changesMonth =
        previous.year != date.year || previous.month != date.month;
    setState(() => _selected = DateUtils.dateOnly(date));
    widget.onDateSelected?.call(_selected!);
    if (!changesMonth || widget.onMonthChanged == null) return;
    setState(() => _loadingMonth = true);
    try {
      await widget.onMonthChanged!(DateTime(date.year, date.month));
    } finally {
      if (mounted) setState(() => _loadingMonth = false);
    }
  }

  Future<void> _pickDate() async {
    final dates = widget.days.map((day) => day.date).toList()..sort();
    final first = dates.isNotEmpty && dates.first.year < 2000
        ? DateTime(dates.first.year)
        : DateTime(2000);
    final lastYear =
        dates.isNotEmpty && dates.last.year > DateTime.now().year + 5
        ? dates.last.year
        : DateTime.now().year + 5;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: first,
      lastDate: DateTime(lastYear, 12, 31),
      helpText: '기록 날짜 선택',
    );
    if (picked != null && mounted) await _select(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedDate;
    final month = DateTime(selected.year, selected.month);
    final first = month.subtract(Duration(days: month.weekday % 7));
    final count =
        ((month.weekday % 7 + DateTime(month.year, month.month + 1, 0).day) / 7)
            .ceil() *
        7;
    final byDate = <DateTime, List<WorkoutHistoryDay>>{};
    for (final day in widget.days) {
      byDate.putIfAbsent(DateUtils.dateOnly(day.date), () => []).add(day);
    }
    final monthDays = byDate.entries.where(
      (entry) => entry.key.year == month.year && entry.key.month == month.month,
    );
    final busy = widget.loading || _loadingMonth;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy ? null : _pickDate,
                  child: Text(
                    DateFormat('yyyy.MM').format(month),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '이전 달',
              onPressed: busy
                  ? null
                  : () => _select(DateTime(month.year, month.month - 1)),
              icon: const Icon(SetflowIcons.back),
            ),
            IconButton(
              tooltip: '다음 달',
              onPressed: busy
                  ? null
                  : () => _select(DateTime(month.year, month.month + 1)),
              icon: const Icon(SetflowIcons.forward),
            ),
          ],
        ),
        Text(
          '운동 ${monthDays.where((entry) => entry.value.any((day) => day.totalSets > 0)).length}일 · 날짜를 누르면 상세 기록을 볼 수 있어요.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: SetflowSpacing.md),
        Row(
          children: [
            for (var index = 0; index < 7; index++)
              Expanded(
                child: Center(
                  child: Text(
                    ['일', '월', '화', '수', '목', '금', '토'][index],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: index == 0
                          ? context.setflowColors.error
                          : index == 6
                          ? context.setflowColors.blue
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: SetflowSpacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: SetflowSpacing.xs,
            crossAxisSpacing: SetflowSpacing.xs,
            mainAxisExtent: 88,
          ),
          itemCount: count,
          itemBuilder: (context, index) {
            final date = first.add(Duration(days: index));
            return _HistoryCalendarCell(
              date: date,
              days: byDate[date] ?? const [],
              inMonth: date.month == month.month,
              selected: DateUtils.isSameDay(date, selected),
              onTap: busy ? null : () => _select(date),
            );
          },
        ),
        const SizedBox(height: SetflowSpacing.lg),
        Text(
          '${DateFormat('M월 d일').format(selected)} 운동 기록',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: SetflowSpacing.sm),
        if (busy)
          const Center(child: CircularProgressIndicator())
        else if (!byDate.containsKey(selected))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SetflowSpacing.lg),
            child: Text('이 날짜에는 저장된 운동 기록이 없어요.'),
          )
        else
          widget.recordBuilder(selected),
      ],
    );
  }
}

class _HistoryCalendarCell extends StatelessWidget {
  const _HistoryCalendarCell({
    required this.date,
    required this.days,
    required this.inMonth,
    required this.selected,
    required this.onTap,
  });
  final DateTime date;
  final List<WorkoutHistoryDay> days;
  final bool inMonth;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = days.fold<int>(0, (sum, day) => sum + day.totalSets);
    final completed = days.fold<int>(0, (sum, day) => sum + day.completedSets);
    final muscles = days.expand((day) => day.muscles).toSet().toList();
    final volume = days.fold<double>(0, (sum, day) => sum + day.volumeKg);
    final cardio = days.fold<int>(0, (sum, day) => sum + day.cardioSeconds);
    final hasRecord = total > 0;
    final alpha = .45 + .55 * (total == 0 ? 0 : completed / total).clamp(0, 1);
    final colors = [
      for (final muscle in muscles)
        Color.alphaBlend(
          _fill(muscle).withValues(alpha: alpha),
          SetflowColors.surface,
        ),
    ];
    if (colors.length == 1) colors.add(colors.first);
    final today = DateUtils.isSameDay(date, DateTime.now());
    final ink = hasRecord && inMonth && colors.isNotEmpty
        ? SetflowColors.ink
        : theme.colorScheme.onSurface;
    final activity = [
      if (volume > 0)
        volume >= 1000
            ? '${(volume / 1000).toStringAsFixed(1)}t'
            : '${volume.round()}kg',
      if (cardio > 0) '${(cardio / 60).round()}분',
    ].join(' · ');
    return Semantics(
      label:
          '${date.year}년 ${date.month}월 ${date.day}일, ${days.isEmpty ? '운동 기록 없음' : '${muscles.join(', ')} $completed/$total 완료 $activity'}',
      selected: selected,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: inMonth
            ? context.setflowColors.surfaceContainerLow
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.secondary
                : hasRecord
                ? theme.colorScheme.outlineVariant
                : Colors.transparent,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          key: ValueKey(
            'history-calendar-fill-${DateFormat('yyyy-MM-dd').format(date)}',
          ),
          decoration: hasRecord && colors.isNotEmpty && inMonth
              ? BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                )
              : null,
          child: InkWell(
            key: ValueKey(
              'history-calendar-day-${DateFormat('yyyy-MM-dd').format(date)}',
            ),
            onTap: onTap,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Padding(
                padding: const EdgeInsets.all(SetflowSpacing.xs),
                child: Column(
                  children: [
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      alignment: Alignment.center,
                      decoration: today
                          ? BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(
                        '${date.day}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: today
                              ? theme.colorScheme.onPrimary
                              : isRestDay(date)
                              ? context.setflowColors.error
                              : date.weekday == DateTime.saturday
                              ? context.setflowColors.blue
                              : ink,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (hasRecord) ...[
                      Text(
                        muscles.isEmpty ? '운동' : muscles.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: SetflowFontSize.micro,
                          color: ink,
                        ),
                      ),
                      Text(
                        activity.isEmpty ? '$completed/$total' : activity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: SetflowFontSize.micro,
                          color: ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _fill(String muscle) => switch (muscle) {
  '가슴' => SetflowMuscleFill.chest,
  '등' => SetflowMuscleFill.back,
  '어깨' => SetflowMuscleFill.shoulders,
  '하체' => SetflowMuscleFill.legs,
  '팔' => SetflowMuscleFill.arms,
  '복근' => SetflowMuscleFill.core,
  _ => SetflowMuscleFill.cardio,
};
