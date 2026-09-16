import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../theme.dart';
import '../theme/icons.dart';
import '../widgets/common.dart';
import 'workout_screens.dart';

enum _ExerciseOrder {
  recent('최근 운동순'),
  frequent('많이 한 순'),
  name('이름순');

  const _ExerciseOrder(this.label);
  final String label;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _search = TextEditingController();
  WorkoutStatsPeriod _period = WorkoutStatsPeriod.all;
  _ExerciseOrder _order = _ExerciseOrder.recent;
  String? _muscle;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _search.clear();
    _period = WorkoutStatsPeriod.all;
    _muscle = null;
  });

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final today = state.dateOnly(DateTime.now());
    final all = state.workoutAnalytics;
    final data = all.inPeriod(_period, today);
    final muscles =
        all.exercises.map((item) => item.template.muscle).toSet().toList()
          ..sort();
    final visible =
        data.exercises
            .where(
              (item) =>
                  (_muscle == null || item.template.muscle == _muscle) &&
                  item.template.matchesCatalogQuery(_search.text),
            )
            .toList()
          ..sort((a, b) {
            final primary = switch (_order) {
              _ExerciseOrder.recent => b.lastDate.compareTo(a.lastDate),
              _ExerciseOrder.frequent => b.workoutDays.compareTo(a.workoutDays),
              _ExerciseOrder.name => a.template.name.compareTo(b.template.name),
            };
            return primary != 0
                ? primary
                : a.template.name.compareTo(b.template.name);
          });

    return Scaffold(
      appBar: AppBar(title: const Text('운동 대시보드')),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          key: const PageStorageKey('workout-dashboard'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: SetflowInsets.pageHeader,
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PeriodPicker(
                      value: _period,
                      onChanged: (value) => setState(() => _period = value),
                    ),
                    const SizedBox(height: SetflowSpacing.lg),
                    _DashboardOverview(data: data, unit: state.weightUnit),
                    const SizedBox(height: SetflowSpacing.section),
                    const SectionTitle('운동별 성과'),
                    const SizedBox(height: SetflowSpacing.xs),
                    const _Hint('완료한 모든 종목을 모았어요. 운동을 누르면 변화와 기록을 볼 수 있어요.'),
                    if (all.exercises.isNotEmpty) ...[
                      const SizedBox(height: SetflowSpacing.lg),
                      TextField(
                        key: const ValueKey('dashboard-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '운동 이름, 부위, 기구 검색',
                          prefixIcon: const Icon(SetflowIcons.exerciseSearch),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '검색어 지우기',
                                  onPressed: () =>
                                      setState(() => _search.clear()),
                                  icon: const Icon(SetflowIcons.close),
                                ),
                        ),
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('전체 부위'),
                              selected: _muscle == null,
                              onSelected: (_) => setState(() => _muscle = null),
                            ),
                            for (final muscle in muscles) ...[
                              const SizedBox(width: SetflowSpacing.sm),
                              ChoiceChip(
                                label: Text(muscle),
                                selected: _muscle == muscle,
                                onSelected: (_) =>
                                    setState(() => _muscle = muscle),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: SetflowSpacing.md,
                        children: [
                          Text(
                            '${visible.length}개 종목',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          PopupMenuButton<_ExerciseOrder>(
                            tooltip: '운동 정렬',
                            initialValue: _order,
                            onSelected: (value) =>
                                setState(() => _order = value),
                            itemBuilder: (_) => [
                              for (final order in _ExerciseOrder.values)
                                PopupMenuItem(
                                  value: order,
                                  child: Text(order.label),
                                ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: SetflowSpacing.md,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_order.label),
                                  const Icon(SetflowIcons.expand),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (visible.isEmpty)
              SliverPadding(
                padding: SetflowInsets.pageForm,
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        all.exercises.isEmpty
                            ? '아직 완료한 운동이 없어요'
                            : '이 조건에 맞는 기록이 없어요',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: SetflowSpacing.sm),
                      _Hint(
                        all.exercises.isEmpty
                            ? '세트를 완료하면 중량·횟수·시간이 여기에 쌓여요.'
                            : '기간이나 검색 조건을 바꾸면 다른 기록을 볼 수 있어요.',
                      ),
                      const SizedBox(height: SetflowSpacing.lg),
                      if (all.exercises.isEmpty)
                        FilledButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DailyWorkoutScreen(date: today),
                            ),
                          ),
                          child: const Text('운동 기록하기'),
                        )
                      else
                        OutlinedButton(
                          onPressed: _reset,
                          child: const Text('전체 기록 보기'),
                        ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SetflowSpacing.gutter,
                ),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final item = visible[index];
                    return _ExerciseKpiRow(
                      key: ValueKey('exercise-kpi-${item.template.id}'),
                      summary: item,
                      unit: state.weightUnit,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExerciseKpiScreen(
                              template: item.template,
                              initialPeriod: _period,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: SetflowSpacing.xxl2),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({required this.data, required this.unit});
  final WorkoutAnalytics data;
  final String unit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _KpiGrid(
        items: [
          ('운동한 날', '${data.workoutDays}일'),
          ('기록한 종목', '${data.exercises.length}개'),
          ('완료 세트', '${data.completedSets}세트'),
          if (data.exercises.any((item) => item.template.usesWeight))
            ('근력 볼륨', '${_number(data.volume)} $unit·회')
          else if (data.cardioSeconds > 0)
            ('유산소 시간', _duration(data.cardioSeconds)),
        ],
      ),
      if (data.cardioSeconds > 0 &&
          data.exercises.any((item) => item.template.usesWeight)) ...[
        const SizedBox(height: SetflowSpacing.md),
        Text(
          '유산소 ${_duration(data.cardioSeconds)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
      const SizedBox(height: SetflowSpacing.sm),
      const _Hint('선택한 기간의 완료 기록 기준'),
    ],
  );
}

class _ExerciseKpiRow extends StatelessWidget {
  const _ExerciseKpiRow({
    required this.summary,
    required this.unit,
    required this.onTap,
    super.key,
  });
  final ExerciseKpiSummary summary;
  final String unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final template = summary.template;
    final metric = summary.metrics.first;
    final headline = template.isCardio
        ? _duration(summary.durationSeconds)
        : _metricValue(summary.best(metric), metric, unit);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: SetflowSpacing.sm),
                  const Icon(SetflowIcons.forward),
                ],
              ),
              const SizedBox(height: SetflowSpacing.xs),
              _Hint(
                '${template.muscle} · 최근 ${DateFormat('yyyy.MM.dd').format(summary.lastDate)}',
              ),
              const SizedBox(height: SetflowSpacing.md),
              Wrap(
                spacing: SetflowSpacing.xl,
                runSpacing: SetflowSpacing.sm,
                children: [
                  _InlineKpi(
                    label: template.isCardio
                        ? '누적 시간'
                        : _metricLabel(metric, template),
                    value: headline,
                  ),
                  _InlineKpi(
                    label: template.isCardio ? '거리' : '완료 세트',
                    value: template.isCardio
                        ? (summary.distanceKm > 0
                              ? '${_number(summary.distanceKm)} km'
                              : '미기록')
                        : '${summary.completedSets}세트',
                  ),
                  _InlineKpi(label: '운동한 날', value: '${summary.workoutDays}일'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every recorded exercise has a detail page, even if 1RM cannot be estimated.
class ExerciseKpiScreen extends StatefulWidget {
  const ExerciseKpiScreen({
    required this.template,
    this.initialPeriod = WorkoutStatsPeriod.all,
    super.key,
  });
  final ExerciseTemplate template;
  final WorkoutStatsPeriod initialPeriod;

  @override
  State<ExerciseKpiScreen> createState() => _ExerciseKpiScreenState();
}

class _ExerciseKpiScreenState extends State<ExerciseKpiScreen> {
  late WorkoutStatsPeriod _period = widget.initialPeriod;
  ExerciseKpi? _metric;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final data = state.workoutAnalytics.inPeriod(_period, DateTime.now());
    final summary = data.exercises
        .where((item) => item.template.id == widget.template.id)
        .firstOrNull;
    final template = summary?.template ?? widget.template;
    final metrics = summary?.metrics ?? [];
    final selectedMetric = metrics.contains(_metric)
        ? _metric!
        : metrics.firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(template.name)),
      body: SafeArea(
        top: false,
        child: ListView(
          key: PageStorageKey('exercise-kpi-detail-${template.id}'),
          padding: SetflowInsets.pageList,
          children: [
            _PeriodPicker(
              value: _period,
              onChanged: (value) => setState(() => _period = value),
            ),
            const SizedBox(height: SetflowSpacing.lg),
            if (summary == null) ...[
              const SectionTitle('이 기간에는 기록이 없어요'),
              const SizedBox(height: SetflowSpacing.sm),
              TextButton(
                onPressed: () =>
                    setState(() => _period = WorkoutStatsPeriod.all),
                child: const Text('전체 기간 보기'),
              ),
            ] else ...[
              _Hint(
                '${template.muscle} · ${summary.workoutDays}일 운동 · ${summary.completedSets}세트 완료',
              ),
              const SizedBox(height: SetflowSpacing.md),
              _KpiGrid(items: _detailKpis(summary, state.weightUnit)),
              const SizedBox(height: SetflowSpacing.sm),
              const _Hint('최고 기록과 합계는 선택한 기간 기준이에요.'),
              const SizedBox(height: SetflowSpacing.section),
              const SectionTitle('기록 변화'),
              const SizedBox(height: SetflowSpacing.sm),
              Wrap(
                spacing: SetflowSpacing.sm,
                runSpacing: SetflowSpacing.xs,
                children: [
                  for (final metric in metrics)
                    ChoiceChip(
                      key: ValueKey('kpi-metric-${metric.name}'),
                      label: Text(_metricLabel(metric, template)),
                      selected: selectedMetric == metric,
                      onSelected: (_) => setState(() => _metric = metric),
                    ),
                ],
              ),
              if (selectedMetric != null)
                _KpiTrend(
                  key: ValueKey('${_period.name}-${selectedMetric.name}'),
                  days: summary.days,
                  metric: selectedMetric,
                  unit: state.weightUnit,
                ),
              if (selectedMetric == ExerciseKpi.estimatedMax)
                _Hint(
                  '추정 1RM은 ${state.oneRepMaxFormula.label} 공식으로 계산한 참고값이에요. '
                  '10회 이하의 일반 세트만 사용하며 실제 최대 중량과 다를 수 있어요.',
                ),
              if (selectedMetric == ExerciseKpi.volume)
                const _Hint('완료한 세트의 중량 × 횟수를 더한 값이에요. 같은 종목 안에서 비교하세요.'),
              if (selectedMetric == ExerciseKpi.reps && template.usesWeight)
                const _Hint('반복 횟수는 중량에 따라 달라져요. 날짜별 세트의 중량도 함께 확인하세요.'),
              const SizedBox(height: SetflowSpacing.section),
              const SectionTitle('날짜별 기록'),
              const SizedBox(height: SetflowSpacing.xs),
              const _Hint('날짜를 누르면 완료한 세트가 펼쳐져요.'),
              for (final day in summary.days.reversed)
                _DayRecord(day: day, unit: state.weightUnit),
            ],
          ],
        ),
      ),
    );
  }
}

List<(String, String)> _detailKpis(ExerciseKpiSummary summary, String unit) {
  final template = summary.template;
  if (template.isCardio) {
    final pace = summary.secondsPerKm;
    return [
      ('누적 시간', _duration(summary.durationSeconds)),
      (
        '누적 거리',
        summary.distanceKm > 0 ? '${_number(summary.distanceKm)} km' : '미기록',
      ),
      ('평균 페이스', pace == null ? '미기록' : '${_clock(pace.round())} /km'),
      (
        '평균 운동 강도',
        summary.averageRpe == null
            ? '미기록'
            : 'RPE ${_number(summary.averageRpe!)}',
      ),
    ];
  }
  if (template.isDurationHold) {
    return [
      (
        '최장 버티기',
        _metricValue(
          summary.best(ExerciseKpi.duration),
          ExerciseKpi.duration,
          unit,
        ),
      ),
      ('누적 시간', _duration(summary.durationSeconds)),
      ('완료 세트', '${summary.completedSets}세트'),
      ('운동한 날', '${summary.workoutDays}일'),
    ];
  }
  return [
    if (template.usesWeight) ...[
      (
        '최고 중량',
        _metricValue(
          summary.best(ExerciseKpi.weight),
          ExerciseKpi.weight,
          unit,
        ),
      ),
      (
        '최고 추정 1RM',
        _metricValue(
          summary.best(ExerciseKpi.estimatedMax),
          ExerciseKpi.estimatedMax,
          unit,
        ),
      ),
      ('누적 볼륨', '${_number(summary.totalVolume)} $unit·회'),
    ],
    ('최고 반복', '${_number(summary.best(ExerciseKpi.reps) ?? 0)}회'),
    ('누적 반복', '${_number(summary.totalReps)}회'),
    ('완료 세트', '${summary.completedSets}세트'),
  ];
}

class _KpiTrend extends StatefulWidget {
  const _KpiTrend({
    required this.days,
    required this.metric,
    required this.unit,
    super.key,
  });
  final List<ExerciseDayStats> days;
  final ExerciseKpi metric;
  final String unit;

  @override
  State<_KpiTrend> createState() => _KpiTrendState();
}

class _KpiTrendState extends State<_KpiTrend> {
  int? _selection;

  @override
  Widget build(BuildContext context) {
    final points = widget.days
        .where((day) => day.value(widget.metric) != null)
        .toList();
    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: SetflowSpacing.xxl),
        child: Text('이 지표를 계산할 기록이 없어요.'),
      );
    }
    final index = (_selection ?? points.length - 1).clamp(0, points.length - 1);
    final selected = points[index];
    final value = selected.value(widget.metric)!;
    final change = index == 0
        ? null
        : value - points[index - 1].value(widget.metric)!;
    final theme = Theme.of(context);
    final offsets = _pointPositions(points);
    void select(int next) =>
        setState(() => _selection = next.clamp(0, points.length - 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: SetflowSpacing.md),
        Text(
          _metricValue(value, widget.metric, widget.unit),
          style: theme.textTheme.headlineMedium,
        ),
        _Hint(
          change == null
              ? (points.length == 1
                    ? '첫 기록이에요. 다음 기록부터 변화를 비교할 수 있어요.'
                    : '선택 기간의 첫 기록')
              : '직전 기록 대비 ${change > 0
                    ? '+'
                    : change < 0
                    ? '−'
                    : ''}${_metricValue(change.abs(), widget.metric, widget.unit)}',
        ),
        const SizedBox(height: SetflowSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) => Semantics(
            container: true,
            label: '${widget.metric.label} 변화',
            value:
                '${DateFormat('yyyy년 M월 d일').format(selected.date)}, '
                '${_metricValue(value, widget.metric, widget.unit)}',
            increasedValue: index < points.length - 1
                ? '${DateFormat('yyyy년 M월 d일').format(points[index + 1].date)}, '
                      '${_metricValue(points[index + 1].value(widget.metric), widget.metric, widget.unit)}'
                : null,
            decreasedValue: index > 0
                ? '${DateFormat('yyyy년 M월 d일').format(points[index - 1].date)}, '
                      '${_metricValue(points[index - 1].value(widget.metric), widget.metric, widget.unit)}'
                : null,
            slider: points.length > 1,
            onIncrease: index < points.length - 1
                ? () => select(index + 1)
                : null,
            onDecrease: index > 0 ? () => select(index - 1) : null,
            child: GestureDetector(
              key: const ValueKey('exercise-kpi-chart'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final fraction =
                    ((details.localPosition.dx - SetflowSpacing.sm) /
                            (constraints.maxWidth - SetflowSpacing.lg))
                        .clamp(0.0, 1.0);
                var nearest = 0;
                for (var i = 1; i < offsets.length; i++) {
                  if ((offsets[i] - fraction).abs() <
                      (offsets[nearest] - fraction).abs()) {
                    nearest = i;
                  }
                }
                select(nearest);
              },
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                    values: points
                        .map((day) => day.value(widget.metric)!)
                        .toList(),
                    positions: offsets,
                    selected: index,
                    line: context.setflowColors.brandDeep,
                    fill: context.setflowColors.brandSoft,
                    grid: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: SetflowSpacing.md,
          runSpacing: SetflowSpacing.xs,
          children: [
            Text(
              DateFormat('yy.MM.dd').format(points.first.date),
              style: theme.textTheme.labelSmall,
            ),
            if (points.length > 1)
              Text(
                DateFormat('yy.MM.dd').format(points.last.date),
                style: theme.textTheme.labelSmall,
              ),
          ],
        ),
        Row(
          children: [
            IconButton(
              tooltip: '이전 기록',
              onPressed: index > 0 ? () => select(index - 1) : null,
              icon: const Icon(SetflowIcons.back),
            ),
            Expanded(
              child: Text(
                DateFormat('yyyy.MM.dd').format(selected.date),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: '다음 기록',
              onPressed: index < points.length - 1
                  ? () => select(index + 1)
                  : null,
              icon: const Icon(SetflowIcons.forward),
            ),
          ],
        ),
      ],
    );
  }
}

List<double> _pointPositions(List<ExerciseDayStats> days) {
  if (days.length == 1) return [.5];
  final first = days.first.date.millisecondsSinceEpoch;
  final span = days.last.date.millisecondsSinceEpoch - first;
  return days
      .map((day) => (day.date.millisecondsSinceEpoch - first) / span)
      .toList();
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.positions,
    required this.selected,
    required this.line,
    required this.fill,
    required this.grid,
  });
  final List<double> values;
  final List<double> positions;
  final int selected;
  final Color line;
  final Color fill;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final top = SetflowSpacing.sm;
    final bottom = size.height - SetflowSpacing.sm;
    final maximum = math.max(1.0, values.reduce(math.max) * 1.12);
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          SetflowSpacing.sm + positions[i] * (size.width - SetflowSpacing.lg),
          bottom - values[i] / maximum * (bottom - top),
        ),
    ];
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = top + (bottom - top) * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (points.length > 1) {
      final area = Path.from(path)
        ..lineTo(points.last.dx, bottom)
        ..lineTo(points.first.dx, bottom)
        ..close();
      canvas.drawPath(area, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawLine(
      Offset(points[selected].dx, top),
      Offset(points[selected].dx, bottom),
      gridPaint,
    );
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        points[i],
        i == selected ? 5 : 3,
        Paint()..color = line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}

class _DayRecord extends StatelessWidget {
  const _DayRecord({required this.day, required this.unit});
  final ExerciseDayStats day;
  final String unit;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey(
      'kpi-day-${day.template.id}-${day.date.toIso8601String()}',
    ),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(bottom: SetflowSpacing.md),
    title: Text(DateFormat('yyyy.MM.dd').format(day.date)),
    subtitle: Text(
      day.template.isCardio || day.template.isDurationHold
          ? '${day.completedSets}세트 · ${_duration(day.durationSeconds)}'
          : '${day.completedSets}세트 · ${day.reps}회${day.template.usesWeight ? ' · ${_number(day.volume)} $unit·회' : ''}',
    ),
    children: [
      for (var i = 0; i < day.sets.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SetflowSpacing.xs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${i + 1}세트 · ${_setDescription(day.sets[i], day.template, unit)}'
              '${workoutSetTypeLabel(day.sets[i].type) == '일반' ? '' : ' · ${workoutSetTypeLabel(day.sets[i].type)}'}',
            ),
          ),
        ),
    ],
  );
}

String _setDescription(
  WorkoutSetEntry set,
  ExerciseTemplate template,
  String unit,
) {
  if (template.isCardio) {
    return '${_duration(set.durationSeconds)}'
        '${set.distanceKm > 0 ? ' · ${_number(set.distanceKm)} km' : ''}'
        '${set.intensityRpe > 0 ? ' · RPE ${_number(set.intensityRpe)}' : ''}';
  }
  if (template.isDurationHold) return _duration(set.durationSeconds);
  if (template.isRepsOnly) return '${set.reps}회';
  return '${_number(set.weight)} $unit × ${set.reps}회';
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});
  final WorkoutStatsPeriod value;
  final ValueChanged<WorkoutStatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final period in WorkoutStatsPeriod.values)
          Padding(
            padding: const EdgeInsets.only(right: SetflowSpacing.sm),
            child: ChoiceChip(
              key: ValueKey('stats-period-${period.name}'),
              label: Text(period.label),
              selected: value == period,
              onSelected: (_) => onChanged(period),
            ),
          ),
      ],
    ),
  );
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaled = MediaQuery.textScalerOf(
        context,
      ).scale(SetflowFontSize.body);
      final columns =
          constraints.maxWidth >= 320 && scaled < SetflowFontSize.body * 1.5
          ? 2
          : 1;
      final width =
          (constraints.maxWidth - SetflowSpacing.md * (columns - 1)) / columns;
      return Wrap(
        spacing: SetflowSpacing.md,
        runSpacing: SetflowSpacing.md,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.setflowColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(SetflowRadii.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(SetflowSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Hint(item.$1),
                      const SizedBox(height: SetflowSpacing.xs),
                      Text(
                        item.$2,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _InlineKpi extends StatelessWidget {
  const _InlineKpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Text(value, style: Theme.of(context).textTheme.titleSmall),
    ],
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

String _number(num value) => NumberFormat('#,##0.#').format(value);
String _clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
String _duration(int seconds) =>
    seconds < 60 ? '$seconds초' : '${_number(seconds / 60)}분';
String _metricLabel(ExerciseKpi metric, ExerciseTemplate template) =>
    metric == ExerciseKpi.duration && template.isDurationHold
    ? '최장 버티기'
    : metric.label;
String _metricValue(double? value, ExerciseKpi metric, String unit) =>
    value == null
    ? '계산할 기록 없음'
    : switch (metric) {
        ExerciseKpi.weight ||
        ExerciseKpi.estimatedMax => '${_number(value)} $unit',
        ExerciseKpi.volume => '${_number(value)} $unit·회',
        ExerciseKpi.reps => '${_number(value)}회',
        ExerciseKpi.duration => _duration(value.round()),
        ExerciseKpi.distance => '${_number(value)} km',
      };
